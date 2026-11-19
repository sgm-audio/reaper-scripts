-- harness.lua — run INSIDE a real REAPER 7.x process:
--   reaper -nosplash -cfgfile <dir>/reaper.ini -newinst -nonewinst tests/reaper_host/harness.lua
-- Environment:
--   SGM_REPO      repository root (required)
--   SGM_HOST_OUT  log file path (required); one line per event, ends with HOST_RESULT
--   SGM_CASES     optional comma list of case names (default: every file in cases/)
--
-- Every assertion runs against the real REAPER API (real project, real media
-- source decoding, real audio accessors, real FX). Nothing here is a stub except
-- the modal UI entry points (ShowMessageBox / gfx.showmenu), which would block a
-- headless host; both are recorded so tests can assert on them.

local REPO = assert(os.getenv("SGM_REPO"), "SGM_REPO not set")
local OUT = assert(os.getenv("SGM_HOST_OUT"), "SGM_HOST_OUT not set")

local T = {repo = REPO, pass = 0, fail = 0, console = {}, dialogs = {},
           dialog_answer = 1, menu_choice = 0}

-- ---------------------------------------------------------------- logging
do local h = io.open(OUT, "w"); if h then h:close() end end
local function log(...)
  local parts = {}
  for i, v in ipairs({...}) do parts[i] = tostring(v) end
  local h = io.open(OUT, "a")
  if h then h:write(table.concat(parts, " "), "\n"); h:close() end
end
T.log = log

log("HOST_VERSION", reaper.GetAppVersion(), _VERSION, reaper.GetOS())
log("RESOURCE_PATH", reaper.GetResourcePath())

-- ---------------------------------------------------------------- UI stubs
local real_console = reaper.ShowConsoleMsg
reaper.ShowConsoleMsg = function(s)
  T.console[#T.console + 1] = tostring(s)
  return real_console(s)
end
reaper.ShowMessageBox = function(text, title, kind)
  T.dialogs[#T.dialogs + 1] = {text = text, title = title, kind = kind}
  return T.dialog_answer
end
gfx.showmenu = function() return T.menu_choice end

function T.console_text() return table.concat(T.console) end
function T.reset_ui()
  T.console, T.dialogs, T.dialog_answer, T.menu_choice = {}, {}, 1, 0
end

-- ---------------------------------------------------------------- asserts
local function fail(msg, level) error(msg, (level or 1) + 1) end
function T.ok(cond, msg) if not cond then fail("assertion failed: " .. tostring(msg), 2) end end
function T.eq(a, b, msg)
  if a ~= b then fail(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2) end
end
function T.near(a, b, tol, msg)
  if type(a) ~= "number" or math.abs(a - b) > tol then
    fail(string.format("%s: expected %.9g +/- %g, got %s", msg or "near", b, tol, tostring(a)), 2)
  end
end
function T.contains(s, needle, msg)
  if not tostring(s):find(needle, 1, true) then
    fail(string.format("%s: %q not found in output", msg or "contains", needle), 2)
  end
end

-- ---------------------------------------------------------------- fixtures
function T.tmpdir()
  if not T._tmp then
    T._tmp = reaper.GetResourcePath() .. "/sgm_host_tmp"
    reaper.RecursiveCreateDirectory(T._tmp, 0)
  end
  return T._tmp
end

-- Write a 16-bit PCM WAV. channels = array of functions(frame_index)->float
function T.write_wav(path, rate, nframes, channel_fns)
  local nch = #channel_fns
  local parts = {}
  for f = 0, nframes - 1 do
    for c = 1, nch do
      local v = channel_fns[c](f)
      v = math.max(-1, math.min(1, v))
      parts[#parts + 1] = string.pack("<i2", math.floor(v * 32767 + 0.5))
    end
  end
  local data = table.concat(parts)
  local h = assert(io.open(path, "wb"))
  h:write("RIFF", string.pack("<I4", 36 + #data), "WAVEfmt ",
    string.pack("<I4I2I2I4I4I2I2", 16, 1, nch, rate, rate * nch * 2, nch * 2, 16),
    "data", string.pack("<I4", #data), data)
  h:close()
  return path
end

-- A click: silence, then `amp` for `width` frames starting at `at` frames.
function T.click(at, amp, width)
  return function(f) if f >= at and f < at + (width or 48) then return amp end return 0 end
end

function T.clear_project()
  for i = reaper.CountTracks(0) - 1, 0, -1 do reaper.DeleteTrack(reaper.GetTrack(0, i)) end
  for i = reaper.CountMediaItems(0) - 1, 0, -1 do
    local it = reaper.GetMediaItem(0, i)
    reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(it), it)
  end
  reaper.SetEditCurPos(0, false, false)
end

function T.add_track(name)
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name or ("T" .. idx), true)
  return tr
end

function T.add_item(track, wavpath, pos)
  local item = reaper.AddMediaItemToTrack(track)
  local take = reaper.AddTakeToMediaItem(item)
  local src = reaper.PCM_Source_CreateFromFile(wavpath)
  T.ok(src ~= nil, "PCM_Source_CreateFromFile " .. wavpath)
  reaper.SetMediaItemTake_Source(take, src)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", reaper.GetMediaSourceLength(src))
  reaper.UpdateItemInProject(item)
  return item, take
end

function T.select_only_tracks(tracks)
  reaper.Main_OnCommand(40297, 0) -- unselect all tracks
  for _, tr in ipairs(tracks) do reaper.SetTrackSelected(tr, true) end
end

function T.item_pos(item) return reaper.GetMediaItemInfo_Value(item, "D_POSITION") end

function T.read_file(path)
  local h = io.open(path, "rb"); if not h then return nil end
  local s = h:read("a"); h:close(); return s
end

-- Load a repo script (runs its top-level code, with UI stubs active).
function T.load_script(name)
  local path = REPO .. "/" .. name
  local chunk, err = loadfile(path)
  if not chunk then error("loadfile " .. name .. ": " .. tostring(err), 0) end
  local real_ctx = reaper.get_action_context
  reaper.get_action_context = function() return true, path, 0, 0, 0, 0, 0 end
  local ok, res = xpcall(chunk, debug.traceback)
  reaper.get_action_context = real_ctx
  if not ok then error(res, 0) end
  return res
end

-- ---------------------------------------------------------------- runner
local registry = {}
function T.test(name, fn) registry[#registry + 1] = {name = name, fn = fn} end

local function list_cases()
  local env = os.getenv("SGM_CASES")
  local names = {}
  if env and env ~= "" then
    for n in env:gmatch("[^,]+") do names[#names + 1] = n end
  else
    local i = 0
    while true do
      local f = reaper.EnumerateFiles(REPO .. "/tests/reaper_host/cases", i)
      if not f then break end
      if f:match("%.lua$") then names[#names + 1] = (f:gsub("%.lua$", "")) end
      i = i + 1
    end
    table.sort(names)
  end
  return names
end

local function run_all()
  for _, case in ipairs(list_cases()) do
    local chunk, err = loadfile(REPO .. "/tests/reaper_host/cases/" .. case .. ".lua")
    if not chunk then
      T.fail = T.fail + 1; log("FAIL", case .. " (load)", err)
    else
      local ok, e = pcall(function()
        local register = chunk(T)
        if type(register) == "function" then register(T) end
      end)
      if not ok then T.fail = T.fail + 1; log("FAIL", case .. " (register)", e) end
    end
  end
  for _, t in ipairs(registry) do
    T.reset_ui()
    T.clear_project()
    local u_before = reaper.GetProjectStateChangeCount(0)
    local ok, e = xpcall(t.fn, function(m) return debug.traceback(tostring(m), 2) end)
    if ok then T.pass = T.pass + 1; log("PASS", t.name)
    else T.fail = T.fail + 1; log("FAIL", t.name, (tostring(e):gsub("\n", " | "))) end
    local _ = u_before
  end
  log("HOST_RESULT", "pass=" .. T.pass, "fail=" .. T.fail)
end

local ok, e = xpcall(run_all, debug.traceback)
if not ok then T.fail = T.fail + 1; log("HOST_ERROR", (tostring(e):gsub("\n", " | "))); log("HOST_RESULT", "pass=" .. T.pass, "fail=" .. T.fail) end

-- Shut down. A project touched by undo/redo can raise a modal "Save unsaved project?"
-- prompt that hangs a headless run, so exit the host process directly (all log writes
-- above are open-append-close, so nothing is lost).
T.clear_project()
log("HOST_EXIT")
os.exit(T.fail == 0 and 0 or 1)
