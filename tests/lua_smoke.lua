-- lua_smoke.lua — run each ReaScript with a conservative stubbed REAPER API.
-- Usage: lua5.4 tests/lua_smoke.lua <script.lua> [more.lua ...]
-- Exit codes: 0 = all ran clean, 2 = at least one load/runtime error.

local function make_stub(name)
  local t = {}
  setmetatable(t, {
    __index = function(_, k) return make_stub(name .. "." .. tostring(k)) end,
    __call = function(_, ...) return make_stub(name .. "()") end,
    __tostring = function() return name end,
    __concat = function(a, b) return tostring(a) .. tostring(b) end,
    __len = function() return 0 end,
    __unm = function() return 0 end,
    __add = function() return 0 end, __sub = function() return 0 end,
    __mul = function() return 0 end, __div = function() return 0 end,
    __mod = function() return 0 end, __pow = function() return 0 end,
    __idiv = function() return 0 end,
    __band = function() return 0 end, __bor = function() return 0 end,
    __bxor = function() return 0 end, __bnot = function() return 0 end,
    __shl = function() return 0 end, __shr = function() return 0 end,
    __eq = function() return false end,
    __lt = function() return false end, __le = function() return false end,
  })
  return t
end

reaper = make_stub("reaper")
gfx = make_stub("gfx")
ImGui = make_stub("ImGui")

-- Return real scalar values for APIs used in loop bounds, comparisons, paths,
-- and menus. A universal callable table masks bugs and never terminates enums.
local temp_root = os.tmpname()
os.remove(temp_root)
os.execute("mkdir -p '" .. temp_root:gsub("'", "'\\''") .. "'")

function reaper.GetResourcePath() return temp_root end
function reaper.GetProjectPath() return temp_root end
function reaper.GetOS() return "Linux" end
function reaper.EnumerateFiles(_, _) return nil end
function reaper.EnumerateSubdirectories(_, _) return nil end
function reaper.CountTracks(_) return 0 end
function reaper.CountSelectedTracks(_) return 0 end
function reaper.CountSelectedMediaItems(_) return 0 end
function reaper.TrackFX_GetCount(_) return 0 end
function reaper.GetMasterTrack(_) return make_stub("master") end
function reaper.GetTrack(_, _) return nil end
function reaper.GetSelectedTrack(_, _) return nil end
function reaper.GetLastTouchedFX() return false, 0, -1, -1 end
function reaper.GetSetMediaTrackInfo_String(_, _, _, _) return false, "" end
function reaper.GetTrackName(_) return false, "" end
function reaper.ShowMessageBox(_, _, _) return 0 end
function reaper.ShowConsoleMsg(_) end
function reaper.ClearConsole() end
function reaper.time_precise() return os.clock() end
function reaper.ColorToNative(_, _, _) return 0 end
function reaper.file_exists(path)
  local file = io.open(path, "r")
  if file then file:close() return true end
  return false
end
function reaper.RecursiveCreateDirectory(path, _)
  os.execute("mkdir -p '" .. tostring(path):gsub("'", "'\\''") .. "'")
  return 1
end
function gfx.showmenu(_) return 0 end
gfx.mouse_x, gfx.mouse_y = 0, 0

local fail = 0
for _, filename in ipairs(arg) do
  local file = assert(io.open(filename, "rb"))
  local source = file:read("*a")
  file:close()
  local chunk, load_error = load(source, "@" .. filename)
  if not chunk then
    print("LOAD-FAIL " .. filename .. ": " .. tostring(load_error))
    fail = 2
  else
    local ok, runtime_error = pcall(chunk)
    if ok then
      print("RUN-OK   " .. filename)
    else
      print("RUN-FAIL " .. filename .. ": " .. tostring(runtime_error))
      fail = 2
    end
  end
end

os.execute("rm -rf '" .. temp_root:gsub("'", "'\\''") .. "'")
os.exit(fail)
