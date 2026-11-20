-- Focused contracts from the official API and ReaTeam's spk77 peak reader.
-- Standalone: lua5.4 tests/lua_api_contracts.lua
local checks = 0
local function check(ok, message)
  assert(ok, message)
  checks = checks + 1
end
local function environment()
  local env = setmetatable({reaper = {}, gfx = {mouse_x = 0, mouse_y = 0}}, {__index = _G})
  env._G = env
  env.reaper.ClearConsole = function() end
  env.reaper.ShowConsoleMsg = function() end
  env.gfx.showmenu = function() return 0 end
  return env
end
local function load_script(path, env)
  assert(loadfile(path, "t", env))()
end
local env = environment()
load_script("phase-alignment-tool.lua", env)
local api = env.reaper
local detector = env.SGMPhaseAlignment.findFirstTransient
local destroyed, status, accessor, channels = 0, 1, {}, 2
local read_start, requested
api.GetActiveTake = function() return {} end
api.GetMediaItemTake_Source = function() return {} end
api.GetMediaSourceSampleRate = function() return 1000 end
api.GetMediaSourceNumChannels = function() return channels end
api.CreateTakeAudioAccessor = function() return accessor end
api.GetMediaItemInfo_Value = function() return 12 end
api.GetAudioAccessorStartTime = function() return 0.025 end
api.GetAudioAccessorEndTime = function() return 0.125 end
api.new_array = function(n)
  local buffer = {}
  for i = 1, n do buffer[i] = 0 end
  return buffer
end
api.GetAudioAccessorSamples = function(_, rate, count, start, frames, buffer)
  read_start, requested = start, frames
  -- A transient at frame 40 in the LAST channel, not at frame zero.
  buffer[40 * count + count] = -0.8
  return status
end
api.DestroyAudioAccessor = function() destroyed = destroyed + 1 end
for _, count in ipairs({1, 2, 4}) do
  channels = count
  local time, peak = detector({})
  check(time and math.abs(time - 12.065) < 1e-9, "status 1 must include accessor_start and scan all requested frames/channels")
  check(peak == 0.8, "negative transient amplitude must be absolute")
end
check(read_start == 0.025 and requested == 100, "read must start at accessor boundary")
check(destroyed == 3, "successful reads must release accessors")
for _, result in ipairs({0, -1}) do
  status = result
  check(detector({}) == nil, "no audio/error must not inspect buffer")
end
check(destroyed == 5, "failed reads must release accessors")
accessor = nil
check(detector({}) == nil and destroyed == 5, "nil accessor must be guarded")
accessor = {}
api.GetAudioAccessorEndTime = function() return 0.025 end
check(detector({}) == nil and destroyed == 6, "empty accessor must be released without reading")

-- gfx.showmenu returns a one-based row index, not an action index that skips
-- a decorative title. Check all four menus across all OS identifiers and execute a real nudge row.
for _, os_id in ipairs({"Linux", "Win64", "Win32", "OSX64", "macOS-arm64"}) do
  for path, first in pairs({
    ["phase-alignment-tool.lua"] = "1. Auto-Align Selected Tracks (Quad-Track Guitar)",
    ["SGM_Professional_Session_Builder.lua"] = "Full Production (25 tracks)",
    ["plugin-wrapper.lua"] = "Scan All Plugins",
    ["Reaper AI Control Hub.lua"] = "Inspect Master FX / Export Routing Notes",
  }) do
    local menu_env = environment()
    menu_env.reaper.GetResourcePath = function() return "/unused-contract-fixture" end
    menu_env.reaper.GetOS = function() return os_id end
    menu_env.reaper.time_precise = function() return 0 end
    menu_env.gfx.showmenu = function(menu)
      check(menu:match("^[^|]+") == first, path .. " [" .. os_id .. "]: row 1 must be the first action")
      return 0
    end
    load_script(path, menu_env)
  end
end
local position, undo, refresh = 2, 0, 0
api.CountSelectedMediaItems = function() return 1 end
api.GetSelectedMediaItem = function() return {} end
api.GetMediaItemInfo_Value = function() return position end
api.SetMediaItemInfo_Value = function(_, key, value) position = value end
api.Undo_BeginBlock = function() undo = undo + 1 end
api.Undo_EndBlock = function() undo = undo - 1 end
api.PreventUIRefresh = function(d) refresh = refresh + d end
api.UpdateArrange = function() end
env.gfx.showmenu = function() return 6 end
load_script("phase-alignment-tool.lua", env)
check(math.abs(position - 2.0001) < 1e-9 and undo == 0 and refresh == 0,
  "row 6 must nudge right 0.1ms with balanced undo and PreventUIRefresh")

-- plugin-wrapper.lua: automateSelectedPlugin bitmask guard, confirmation, undo, and PreventUIRefresh
local pw_env = environment()
pw_env.reaper.GetResourcePath = function() return "/unused-contract-fixture" end
pw_env.reaper.GetOS = function() return "Linux" end
pw_env.reaper.ShowMessageBox = function() return 0 end
load_script("plugin-wrapper.lua", pw_env)
local pw_undo, pw_refresh, pw_points = 0, 0, 0
pw_env.reaper.Undo_BeginBlock = function() pw_undo = pw_undo + 1 end
pw_env.reaper.Undo_EndBlock = function() pw_undo = pw_undo - 1 end
pw_env.reaper.PreventUIRefresh = function(d) pw_refresh = pw_refresh + d end
pw_env.reaper.UpdateArrange = function() end
pw_env.reaper.GetTrack = function() return {} end
pw_env.reaper.TrackFX_GetFXName = function() return true, "ReaEQ" end
pw_env.reaper.TrackFX_GetParamName = function() return true, "Gain" end
pw_env.reaper.GetFXEnvelope = function() return {} end
pw_env.reaper.GetCursorPosition = function() return 0 end
pw_env.reaper.InsertEnvelopePoint = function() pw_points = pw_points + 1 end
pw_env.reaper.Envelope_SortPoints = function() end
pw_env.reaper.GetLastTouchedFX = function() return true, 1, 0x1000000, 0 end
check(pw_env.SGMPluginWrapper.automateSelectedPlugin() == false and pw_points == 0,
  "record-input FX bitmask must be rejected")
pw_env.reaper.GetLastTouchedFX = function() return true, (1 << 16) | 1, 0, 0 end
check(pw_env.SGMPluginWrapper.automateSelectedPlugin() == false and pw_points == 0,
  "take FX track_number bitmask ((1 << 16) | 1) must be rejected")
pw_env.reaper.GetLastTouchedFX = function() return true, 1, 0x2000000 | 1, 0 end
pw_env.reaper.ShowMessageBox = function() return 1 end
check(pw_env.SGMPluginWrapper.automateSelectedPlugin() == true and pw_undo == 0 and pw_refresh == 0 and pw_points == 21,
  "REAPER 7 FX container bitmask (0x2000000) must be allowed for track FX automation")
pw_points = 0
pw_env.reaper.GetLastTouchedFX = function() return true, 1, 0, 0 end
pw_env.reaper.ShowMessageBox = function() return 0 end
check(pw_env.SGMPluginWrapper.automateSelectedPlugin() == false and pw_undo == 0 and pw_points == 0,
  "declined automation must not mutate envelopes")
pw_env.reaper.ShowMessageBox = function() return 1 end
check(pw_env.SGMPluginWrapper.automateSelectedPlugin() == true and pw_undo == 0 and pw_refresh == 0 and pw_points == 21,
  "confirmed automation must insert 21 points with balanced undo and PreventUIRefresh")

-- plugin-wrapper.lua: GetFXEnvelope returning nil (e.g. non-automatable or locked)
pw_env.reaper.GetFXEnvelope = function() return nil end
pw_points = 0
local pw_null_env_res = pw_env.SGMPluginWrapper.automateSelectedPlugin()
check(pw_null_env_res == false and pw_undo == 0 and pw_refresh == 0 and pw_points == 0,
  "null envelope must fail cleanly without crashing and keep undo/refresh balanced")

-- SGM_Professional_Session_Builder.lua: rollback partially created tracks on error
local sb_env = environment()
load_script("SGM_Professional_Session_Builder.lua", sb_env)
local sb_tracks, sb_undo, sb_refresh = {}, 0, 0
sb_env.reaper.CountTracks = function() return #sb_tracks end
sb_env.reaper.InsertTrackAtIndex = function(idx)
  if #sb_tracks >= 2 then return end
  table.insert(sb_tracks, idx + 1, {id = idx + 1})
end
sb_env.reaper.GetTrack = function(_, idx) return sb_tracks[idx + 1] end
sb_env.reaper.DeleteTrack = function(tr)
  for i = #sb_tracks, 1, -1 do
    if sb_tracks[i] == tr then table.remove(sb_tracks, i) end
  end
end
sb_env.reaper.GetSetMediaTrackInfo_String = function() return true, "" end
sb_env.reaper.ColorToNative = function() return 0 end
sb_env.reaper.SetTrackColor = function() end
sb_env.reaper.SetMediaTrackInfo_Value = function() end
sb_env.reaper.Undo_BeginBlock = function() sb_undo = sb_undo + 1 end
sb_env.reaper.Undo_EndBlock = function() sb_undo = sb_undo - 1 end
sb_env.reaper.PreventUIRefresh = function(d) sb_refresh = sb_refresh + d end
sb_env.reaper.TrackList_AdjustWindows = function() end
sb_env.reaper.UpdateArrange = function() end
local sb_builder = sb_env.SGMSessionBuilder.AdvancedSessionBuilder:new()
local sb_engine = sb_env.SGMSessionBuilder.SessionImplementationEngine:new()
local sb_full = sb_builder:buildSessionFromAnalysis("full_production", "no_fx")
local sb_ok = sb_engine:implementSession(sb_full)
check(sb_ok == false and #sb_tracks == 0 and sb_undo == 0 and sb_refresh == 0,
  "failed session build must roll back partial tracks and balance undo/refresh")

-- phase-alignment-tool.lua: adversarial transient inputs (digital silence, DC offset, sample 0 edge)
local adv_env = environment()
load_script("phase-alignment-tool.lua", adv_env)
local adv_api = adv_env.reaper
local adv_detector = adv_env.SGMPhaseAlignment.findFirstTransient
local adv_destroyed, adv_accessor = 0, {}
adv_api.GetActiveTake = function() return {} end
adv_api.GetMediaItemTake_Source = function() return {} end
adv_api.GetMediaSourceSampleRate = function() return 1000 end
adv_api.GetMediaSourceNumChannels = function() return 2 end
adv_api.CreateTakeAudioAccessor = function() return adv_accessor end
adv_api.GetMediaItemInfo_Value = function() return 5.0 end
adv_api.GetAudioAccessorStartTime = function() return 0.0 end
adv_api.GetAudioAccessorEndTime = function() return 0.1 end
adv_api.new_array = function(n)
  local b = {}
  for i = 1, n do b[i] = 0 end
  return b
end
adv_api.DestroyAudioAccessor = function() adv_destroyed = adv_destroyed + 1 end

-- Case 1: Digital silence (all 0.0) -> must return nil and peak 0
adv_api.GetAudioAccessorSamples = function(_, rate, count, start, frames, buffer)
  for i = 1, #buffer do buffer[i] = 0.0 end
  return 1
end
local s_time, s_peak = adv_detector({})
check(s_time == nil and s_peak == 0, "digital silence must return nil transient and 0 peak")
check(adv_destroyed == 1, "silence read must destroy accessor")

-- Case 2: Constant DC offset below threshold (0.05, threshold is 0.3) -> must return nil and peak 0.05
adv_api.GetAudioAccessorSamples = function(_, rate, count, start, frames, buffer)
  for i = 1, #buffer do buffer[i] = 0.05 end
  return 1
end
local dc_time, dc_peak = adv_detector({})
check(dc_time == nil and math.abs(dc_peak - 0.05) < 1e-9, "DC offset below threshold must return nil transient")

-- Case 3: Immediate transient at frame 0 (edge boundary) -> transient_time must equal item start position
adv_api.GetAudioAccessorSamples = function(_, rate, count, start, frames, buffer)
  for i = 1, #buffer do buffer[i] = 0 end
  buffer[1] = 0.95  -- frame 0, channel 0
  return 1
end
local edge_time, edge_peak = adv_detector({})
check(edge_time and math.abs(edge_time - 5.0) < 1e-9, "frame 0 transient must align exactly to item start")
check(math.abs(edge_peak - 0.95) < 1e-9, "frame 0 peak must be captured")

-- phase-alignment-tool.lua: nudgeItems error branch balances Undo and PreventUIRefresh
local nudge_undo, nudge_refresh = 0, 0
adv_api.CountSelectedMediaItems = function() return 1 end
adv_api.GetSelectedMediaItem = function() return {} end
adv_api.GetMediaItemInfo_Value = function() return 2.0 end
adv_api.SetMediaItemInfo_Value = function() error("Simulated disk/API write fault during nudge") end
adv_api.Undo_BeginBlock = function() nudge_undo = nudge_undo + 1 end
adv_api.Undo_EndBlock = function() nudge_undo = nudge_undo - 1 end
adv_api.PreventUIRefresh = function(d) nudge_refresh = nudge_refresh + d end
adv_api.UpdateArrange = function() end
adv_api.ShowMessageBox = function() return 0 end
adv_env.gfx.showmenu = function() return 6 end  -- nudge right 0.1ms
load_script("phase-alignment-tool.lua", adv_env)
check(nudge_undo == 0 and nudge_refresh == 0,
  "nudgeItem failure inside pcall must maintain balanced Undo and PreventUIRefresh")

-- phase-alignment-tool.lua: verify undo/refresh balance on execution error with multiple items
local pa_env = environment()
pa_env.reaper.GetResourcePath = function() return "/unused-contract-fixture" end
pa_env.reaper.GetOS = function() return "Linux" end
load_script("phase-alignment-tool.lua", pa_env)
local pa_undo, pa_refresh = 0, 0
pa_env.reaper.Undo_BeginBlock = function() pa_undo = pa_undo + 1 end
pa_env.reaper.Undo_EndBlock = function() pa_undo = pa_undo - 1 end
pa_env.reaper.PreventUIRefresh = function(d) pa_refresh = pa_refresh + d end
pa_env.reaper.UpdateArrange = function() end
pa_env.reaper.ShowMessageBox = function() return 0 end
pa_env.reaper.CountSelectedMediaItems = function() return 2 end
pa_env.reaper.GetSelectedMediaItem = function(_, idx)
  if idx > 0 then error("Forced nudge error") end
  return {}
end
pa_env.reaper.GetMediaItemInfo_Value = function() return 1.0 end
pa_env.reaper.SetMediaItemInfo_Value = function() end
pa_env.gfx.showmenu = function() return 3 end -- Nudge Left 1ms
pcall(function()
  load_script("phase-alignment-tool.lua", pa_env)
end)
check(pa_undo == 0 and pa_refresh == 0,
  "phase-alignment-tool multi-item nudge error must balance undo and PreventUIRefresh")

-- phase-alignment-tool.lua: alignSelectedTracks() confirmation, alignment, and pcall undo/refresh balance
local al_env = environment()
load_script("phase-alignment-tool.lua", al_env)
local al_api = al_env.reaper
local al_tracks = {{name = "Gtr L"}, {name = "Gtr R"}}
local al_items = {{pos = 1.0}, {pos = 1.0}}
local al_undo, al_refresh = 0, 0
al_api.CountSelectedTracks = function() return #al_tracks end
al_api.GetSelectedTrack = function(_, idx) return al_tracks[idx + 1] end
al_api.GetTrackName = function(tr) return true, tr.name end
al_api.CountTrackMediaItems = function() return 1 end
al_api.GetTrackMediaItem = function(tr, _) return tr == al_tracks[1] and al_items[1] or al_items[2] end
al_api.GetActiveTake = function(item) return item end
al_api.GetMediaItemTake_Source = function() return {} end
al_api.GetMediaSourceSampleRate = function() return 1000 end
al_api.GetMediaSourceNumChannels = function() return 1 end
al_api.CreateTakeAudioAccessor = function(take) return take end
al_api.DestroyAudioAccessor = function() end
al_api.GetAudioAccessorStartTime = function() return 0.0 end
al_api.GetAudioAccessorEndTime = function() return 0.1 end
al_api.new_array = function(n)
  local b = {}
  for i = 1, n do b[i] = 0 end
  return b
end
al_api.GetAudioAccessorSamples = function(acc, _, _, _, _, buf)
  for i = 1, #buf do buf[i] = 0 end
  if acc == al_items[1] then
    buf[11] = 0.8 -- frame 10 -> 0.010s
  else
    buf[31] = 0.8 -- frame 30 -> 0.030s (needs -0.020s nudge)
  end
  return 1
end
al_api.GetMediaItemInfo_Value = function(item, _) return item.pos end
al_api.SetMediaItemInfo_Value = function(item, _, val) item.pos = val end
al_api.Undo_BeginBlock = function() al_undo = al_undo + 1 end
al_api.Undo_EndBlock = function() al_undo = al_undo - 1 end
al_api.PreventUIRefresh = function(d) al_refresh = al_refresh + d end
al_api.UpdateArrange = function() end

-- Case A: user cancels confirmation -> no mutation, no undo opened
al_api.ShowMessageBox = function() return 0 end
al_env.SGMPhaseAlignment.alignSelectedTracks()
check(math.abs(al_items[2].pos - 1.0) < 1e-9 and al_undo == 0 and al_refresh == 0,
  "declined alignSelectedTracks must not mutate items or open undo")

-- Case B: user confirms -> item 2 nudged by -0.020s, balanced undo/refresh
al_api.ShowMessageBox = function() return 1 end
al_env.SGMPhaseAlignment.alignSelectedTracks()
check(math.abs(al_items[2].pos - 0.98) < 1e-9 and al_undo == 0 and al_refresh == 0,
  "confirmed alignSelectedTracks must align later item and balance undo/refresh")

-- Case C: items start at 0.0s -> shifting left would clamp, so align right to latest transient instead
al_items[1].pos = 0.0
al_items[2].pos = 0.0
al_env.SGMPhaseAlignment.alignSelectedTracks()
check(math.abs(al_items[1].pos - 0.02) < 1e-9 and math.abs(al_items[2].pos - 0.0) < 1e-9,
  "items at 0.0s must align right to latest transient without clamping")

-- Case D: SetMediaItemInfo_Value errors inside pcall -> undo/refresh stay balanced
al_items[1].pos = 1.0
al_items[2].pos = 1.0
al_api.SetMediaItemInfo_Value = function() error("Simulated align write fault") end
al_env.SGMPhaseAlignment.alignSelectedTracks()
check(al_undo == 0 and al_refresh == 0,
  "alignSelectedTracks failure inside pcall must maintain balanced Undo and PreventUIRefresh")

-- SGM_Professional_Session_Builder.lua: buildProfessionalSession confirmation decline vs accept
local bp_env = environment()
load_script("SGM_Professional_Session_Builder.lua", bp_env)
local bp_tracks = {}
bp_env.reaper.CountTracks = function() return #bp_tracks end
bp_env.reaper.InsertTrackAtIndex = function(idx) table.insert(bp_tracks, idx + 1, {name = ""}) end
bp_env.reaper.GetTrack = function(_, idx) return bp_tracks[idx + 1] end
bp_env.reaper.GetSetMediaTrackInfo_String = function(tr, _, val, set)
  if set then tr.name = val end
  return true, tr.name
end
bp_env.reaper.GetTrackName = function(tr) return true, tr.name end
bp_env.reaper.ColorToNative = function() return 0 end
bp_env.reaper.SetTrackColor = function() end
bp_env.reaper.SetMediaTrackInfo_Value = function() end
bp_env.reaper.CreateTrackSend = function() return 0 end
bp_env.reaper.SetTrackSendInfo_Value = function() end
bp_env.reaper.Undo_BeginBlock = function() end
bp_env.reaper.Undo_EndBlock = function() end
bp_env.reaper.PreventUIRefresh = function() end
bp_env.reaper.TrackList_AdjustWindows = function() end
bp_env.reaper.UpdateArrange = function() end
bp_env.reaper.ShowMessageBox = function() return 0 end
check(bp_env.SGMSessionBuilder.buildProfessionalSession("mixing", "no_fx") == nil and #bp_tracks == 0,
  "declined buildProfessionalSession must not create tracks")
bp_env.reaper.ShowMessageBox = function() return 1 end
local bp_session = bp_env.SGMSessionBuilder.buildProfessionalSession("mixing", "no_fx")
check(bp_session ~= nil and bp_session.implemented == true and #bp_tracks == 7,
  "confirmed buildProfessionalSession must create 7 mixing tracks")

-- Cross-platform temporary directory helpers
local is_win = package.config:sub(1, 1) == "\\"
local function make_dir(path)
  if is_win then
    os.execute('mkdir "' .. tostring(path):gsub("/", "\\") .. '"')
  else
    os.execute("mkdir -p '" .. tostring(path):gsub("'", "'\\''") .. "'")
  end
end
local function remove_dir(path)
  if is_win then
    os.execute('rmdir /s /q "' .. tostring(path):gsub("/", "\\") .. '"')
  else
    os.execute("rm -rf '" .. tostring(path):gsub("'", "'\\''") .. "'")
  end
end
local function file_exists(path)
  local fh = io.open(path, "rb")
  if fh then fh:close(); return true end
  return false
end
local function read_all(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local data = fh:read("*a")
  fh:close()
  return data
end
local function write_all(path, content)
  local fh = assert(io.open(path, "wb"))
  fh:write(content)
  fh:close()
end

-- reaper-template-installer.lua: main() decline vs accept in an isolated temp dir
local inst_temp = os.tmpname()
os.remove(inst_temp)
make_dir(inst_temp)
local inst_env = environment()
inst_env.reaper.GetResourcePath = function() return inst_temp end
inst_env.reaper.ShowMessageBox = function() return 0 end
inst_env.reaper.RecursiveCreateDirectory = function(path, _)
  make_dir(path)
  return 1
end
load_script("./reaper-template-installer.lua", inst_env)
check(inst_env.SGMScriptInstaller.main() == false,
  "declined installer main() must return false")
check(not file_exists(inst_temp .. "/Scripts/ScottMills/installed-files.txt"),
  "declined installer must not write manifest")
inst_env.reaper.ShowMessageBox = function() return 1 end
check(inst_env.SGMScriptInstaller.main() == true,
  "confirmed installer main() must return true")
check(file_exists(inst_temp .. "/Scripts/ScottMills/installed-files.txt"),
  "confirmed installer must write installed-files.txt manifest")
remove_dir(inst_temp)

-- reaper-template-installer.lua: failure injection #1 (unwritable target + rollback + sentinel restoration)
local inst_fail_temp = os.tmpname()
os.remove(inst_fail_temp)
make_dir(inst_fail_temp .. "/Scripts/ScottMills")
local sentinel_path = inst_fail_temp .. "/Scripts/ScottMills/Reaper AI Control Hub.lua"
write_all(sentinel_path, "ORIGINAL_SENTINEL_CONTENT")
local inst_fail_env = environment()
local inst_fail_dialogs = {}
inst_fail_env.reaper.GetResourcePath = function() return inst_fail_temp end
inst_fail_env.reaper.RecursiveCreateDirectory = function(path, _) make_dir(path); return 1 end
inst_fail_env.reaper.ShowMessageBox = function(text, title, _)
  table.insert(inst_fail_dialogs, {text = text, title = title})
  return 1
end
local real_io_open = io.open
inst_fail_env.io = setmetatable({
  open = function(path, mode)
    if mode == "wb" and tostring(path):find("phase-alignment-tool.lua", 1, true) then
      return nil, "Permission denied (injected)"
    end
    return real_io_open(path, mode)
  end
}, {__index = io})
load_script("./reaper-template-installer.lua", inst_fail_env)
local last_inst_dialog = inst_fail_dialogs[#inst_fail_dialogs]
check(last_inst_dialog and last_inst_dialog.text:find("1 file(s) could not be installed", 1, true) ~= nil,
  "unwritable target must report exact failure count (1)")
check(not file_exists(inst_fail_temp .. "/Scripts/ScottMills/installed-files.txt"),
  "partial copy failure must not write installed-files.txt")
check(read_all(sentinel_path) == "ORIGINAL_SENTINEL_CONTENT",
  "partial copy failure must restore pre-existing overwritten file")
check(not file_exists(inst_fail_temp .. "/Scripts/ScottMills/SGM_Professional_Session_Builder.lua"),
  "partial copy failure must roll back newly copied files")
inst_fail_dialogs = {}
check(inst_fail_env.SGMScriptInstaller.main() == false,
  "installer main() must return false on unwritable target failure")
remove_dir(inst_fail_temp)

-- reaper-template-installer.lua: failure injection #2 (missing 2 source files)
local missing_src_root = os.tmpname()
os.remove(missing_src_root)
make_dir(missing_src_root .. "/plugin/Source")
make_dir(missing_src_root .. "/plugin/Tests")
local missing_dest_root = os.tmpname()
os.remove(missing_dest_root)
make_dir(missing_dest_root)
local skip_sources = {["CHANGELOG.md"] = true, ["plugin/Tests/PluginTests.cpp"] = true}
for _, f in ipairs(inst_env.SGMScriptInstaller.scripts) do
  write_all(missing_src_root .. "/" .. f, read_all(f))
end
for _, f in ipairs(inst_env.SGMScriptInstaller.documents) do
  if not skip_sources[f] then write_all(missing_src_root .. "/" .. f, read_all(f)) end
end
for _, f in ipairs(inst_env.SGMScriptInstaller.plugin_files) do
  if not skip_sources["plugin/" .. f] then write_all(missing_src_root .. "/plugin/" .. f, read_all("plugin/" .. f)) end
end
local miss_env = environment()
local miss_dialogs = {}
miss_env.reaper.GetResourcePath = function() return missing_dest_root end
miss_env.reaper.RecursiveCreateDirectory = function(path, _) make_dir(path); return 1 end
miss_env.reaper.ShowMessageBox = function(text, title, _)
  table.insert(miss_dialogs, {text = text, title = title})
  return 1
end
load_script(missing_src_root .. "/reaper-template-installer.lua", miss_env)
local miss_res = miss_env.SGMScriptInstaller.main()
check(miss_res == false, "missing source installer main() must return false")
local miss_last = miss_dialogs[#miss_dialogs]
check(miss_last and miss_last.text:find("2 file(s) could not be installed", 1, true) ~= nil,
  "missing source must report exact failure count (2), got: " .. tostring(miss_last and miss_last.text))
check(not file_exists(missing_dest_root .. "/Scripts/ScottMills/installed-files.txt"),
  "missing source failure must not write installed-files.txt")
check(not file_exists(missing_dest_root .. "/Scripts/ScottMills/Reaper AI Control Hub.lua"),
  "missing source failure must roll back copied scripts")
remove_dir(missing_src_root)
remove_dir(missing_dest_root)

-- SGM_plugin_development_blueprint.lua: unsaved project and partial write rollback contracts
local bp_unsaved_env = environment()
local bp_unsaved_dialogs = {}
bp_unsaved_env.reaper.GetProjectPath = function() return "" end
bp_unsaved_env.reaper.ShowMessageBox = function(text, title, _)
  table.insert(bp_unsaved_dialogs, {text = text, title = title})
  return 1
end
load_script("./SGM_plugin_development_blueprint.lua", bp_unsaved_env)
check(bp_unsaved_env.SGMPluginDevelopment.create_development_project() == false,
  "blueprint must return false when GetProjectPath() == ''")
check(bp_unsaved_dialogs[#bp_unsaved_dialogs].text:find("Save the REAPER project", 1, true) ~= nil,
  "blueprint must instruct user to save project when GetProjectPath() == ''")

-- Also verify EnumProjects(-1) returning empty filename rejects unsaved project
local bp_enum_env = environment()
local bp_enum_temp = os.tmpname()
os.remove(bp_enum_temp)
make_dir(bp_enum_temp)
bp_enum_env.reaper.GetProjectPath = function() return bp_enum_temp end
bp_enum_env.reaper.EnumProjects = function(_) return {}, "" end
bp_enum_env.reaper.ShowMessageBox = function() return 0 end
load_script("./SGM_plugin_development_blueprint.lua", bp_enum_env)
check(bp_enum_env.SGMPluginDevelopment.create_development_project() == false,
  "blueprint must return false when EnumProjects(-1) reports unsaved project")
check(not file_exists(bp_enum_temp .. "/SGM_AI_Plugin_Suite/CMakeLists.txt"),
  "unsaved project must not create blueprint files")
remove_dir(bp_enum_temp)

-- Partial write rollback #1: io.open(..., "wb") fails on 3rd file (.gitignore)
local bp_rb1_temp = os.tmpname()
os.remove(bp_rb1_temp)
make_dir(bp_rb1_temp)
local bp_rb1_env = environment()
local bp_rb1_dialogs, bp_rb1_removed = {}, {}
bp_rb1_env.reaper.GetProjectPath = function() return bp_rb1_temp end
bp_rb1_env.reaper.RecursiveCreateDirectory = function(path, _) make_dir(path); return 1 end
bp_rb1_env.reaper.ShowMessageBox = function(text, title, _)
  table.insert(bp_rb1_dialogs, {text = text, title = title})
  return 0
end
bp_rb1_env.io = setmetatable({
  open = function(path, mode)
    if mode == "wb" and tostring(path):find("%.gitignore$") then
      return nil, "Read-only file system (injected)"
    end
    return real_io_open(path, mode)
  end
}, {__index = io})
local real_os_remove = os.remove
bp_rb1_env.os = setmetatable({
  remove = function(path)
    table.insert(bp_rb1_removed, path)
    return real_os_remove(path)
  end
}, {__index = os})
load_script("./SGM_plugin_development_blueprint.lua", bp_rb1_env)
check(bp_rb1_env.SGMPluginDevelopment.create_development_project() == false,
  "blueprint open failure on 3rd file must return false")
check(#bp_rb1_removed == 2,
  "blueprint open rollback must call os.remove on the 2 already-written files, got " .. #bp_rb1_removed)
check(not file_exists(bp_rb1_temp .. "/SGM_AI_Plugin_Suite/CMakeLists.txt"),
  "blueprint rollback must remove CMakeLists.txt")
check(not file_exists(bp_rb1_temp .. "/SGM_AI_Plugin_Suite/README.md"),
  "blueprint rollback must remove README.md")
check(bp_rb1_dialogs[#bp_rb1_dialogs].text:find("rolled back", 1, true) ~= nil,
  "blueprint rollback dialog must report rollback")
remove_dir(bp_rb1_temp)

-- Partial write rollback #2: file:write() fails on 3rd file (.gitignore)
local bp_rb2_temp = os.tmpname()
os.remove(bp_rb2_temp)
make_dir(bp_rb2_temp)
local bp_rb2_env = environment()
local bp_rb2_removed = {}
bp_rb2_env.reaper.GetProjectPath = function() return bp_rb2_temp end
bp_rb2_env.reaper.RecursiveCreateDirectory = function(path, _) make_dir(path); return 1 end
bp_rb2_env.reaper.ShowMessageBox = function() return 0 end
bp_rb2_env.io = setmetatable({
  open = function(path, mode)
    local fh, err = real_io_open(path, mode)
    if fh and mode == "wb" and tostring(path):find("%.gitignore$") then
      return {
        write = function() return nil, "No space left on device (injected)" end,
        close = function() fh:close() end,
      }
    end
    return fh, err
  end
}, {__index = io})
bp_rb2_env.os = setmetatable({
  remove = function(path)
    table.insert(bp_rb2_removed, path)
    return real_os_remove(path)
  end
}, {__index = os})
load_script("./SGM_plugin_development_blueprint.lua", bp_rb2_env)
check(bp_rb2_env.SGMPluginDevelopment.create_development_project() == false,
  "blueprint write failure on 3rd file must return false")
check(#bp_rb2_removed == 3,
  "blueprint write rollback must remove partial 3rd file plus 2 prior files, got " .. #bp_rb2_removed)
check(not file_exists(bp_rb2_temp .. "/SGM_AI_Plugin_Suite/CMakeLists.txt") and
      not file_exists(bp_rb2_temp .. "/SGM_AI_Plugin_Suite/README.md") and
      not file_exists(bp_rb2_temp .. "/SGM_AI_Plugin_Suite/.gitignore"),
  "blueprint write rollback must leave zero generated files on disk")
remove_dir(bp_rb2_temp)

-- plugin-wrapper.lua: PluginAutomation:automateParameter(), PluginInstance:remove(), performFullScan(), showMenu rows 1, 2, 4
local pw2_temp = os.tmpname()
os.remove(pw2_temp)
make_dir(pw2_temp)
local pw2_env = environment()
local pw2_console, pw2_dialogs = {}, {}
pw2_env.reaper.GetResourcePath = function() return pw2_temp end
pw2_env.reaper.GetOS = function() return "Linux" end
pw2_env.reaper.ShowConsoleMsg = function(m) table.insert(pw2_console, tostring(m)) end
pw2_env.reaper.ShowMessageBox = function(text, title, _)
  table.insert(pw2_dialogs, {text = text, title = title})
  return 0
end
pw2_env.reaper.EnumerateFiles = function(path, idx)
  if path == "/usr/lib/vst3" and idx == 0 then return "FabFilter Pro-Q 3.vst3" end
  return nil
end
pw2_env.reaper.EnumerateSubdirectories = function() return nil end
load_script("plugin-wrapper.lua", pw2_env)
local PW = pw2_env.SGMPluginWrapper

-- 1) PluginAutomation:automateParameter() tempo <= 0, nil tempo, nil envelope, and beat-to-second math
local inserted_pts, sort_calls = {}, 0
local mock_track_obj = {id = "track-A"}
local mock_env_obj = {id = "env-0"}
pw2_env.reaper.GetFXEnvelope = function() return mock_env_obj end
pw2_env.reaper.GetCursorPosition = function() return 2.5 end
pw2_env.reaper.InsertEnvelopePoint = function(env_arg, time, val)
  table.insert(inserted_pts, {env = env_arg, time = time, val = val})
end
pw2_env.reaper.Envelope_SortPoints = function() sort_calls = sort_calls + 1 end
local inst_auto = PW.PluginInstance:new(mock_track_obj, 2)
local auto = PW.PluginAutomation:new(inst_auto)

for _, bad_tempo in ipairs({0, -120}) do
  inserted_pts, sort_calls = {}, 0
  pw2_env.reaper.Master_GetTempo = function() return bad_tempo end
  check(auto:automateParameter(1, 0.2, 0.8, 4) == false and #inserted_pts == 0 and sort_calls == 0,
    "automateParameter must reject tempo <= 0 (" .. tostring(bad_tempo) .. ")")
end
inserted_pts, sort_calls = {}, 0
pw2_env.reaper.Master_GetTempo = function() return nil end
check(auto:automateParameter(1, 0.2, 0.8, 4) == false and #inserted_pts == 0 and sort_calls == 0,
  "automateParameter must reject nil tempo")

inserted_pts, sort_calls = {}, 0
pw2_env.reaper.Master_GetTempo = function() return 120 end
pw2_env.reaper.GetFXEnvelope = function() return nil end
check(auto:automateParameter(1, 0.2, 0.8, 4) == false and #inserted_pts == 0 and sort_calls == 0,
  "automateParameter must return false when GetFXEnvelope returns nil")

inserted_pts, sort_calls = {}, 0
pw2_env.reaper.GetFXEnvelope = function() return mock_env_obj end
pw2_env.reaper.Master_GetTempo = function() return 120 end
pw2_env.reaper.GetCursorPosition = function() return 2.5 end
check(auto:automateParameter(1, 0.25, 0.75, 4) == true, "automateParameter 120 BPM 4 beats must succeed")
check(#inserted_pts == 2 and sort_calls == 1, "automateParameter must insert 2 points and sort once")
check(math.abs(inserted_pts[1].time - 2.5) < 1e-9 and math.abs(inserted_pts[1].val - 0.25) < 1e-9,
  "automateParameter start point must match cursor and start_value")
check(math.abs(inserted_pts[2].time - 4.5) < 1e-9 and math.abs(inserted_pts[2].val - 0.75) < 1e-9,
  "automateParameter end point must match cursor + (4 * 60 / 120) = 4.5s")

inserted_pts, sort_calls = {}, 0
pw2_env.reaper.Master_GetTempo = function() return 150 end
pw2_env.reaper.GetCursorPosition = function() return 1.0 end
check(auto:automateParameter(0, 0.1, 0.9, 2.5) == true, "automateParameter 150 BPM 2.5 beats must succeed")
check(math.abs(inserted_pts[2].time - 2.0) < 1e-9,
  "automateParameter beat-to-second math must compute 1.0 + (2.5 * 60 / 150) = 2.0s")

-- 2) PluginInstance:remove()
local deleted_track, deleted_fx = nil, nil
pw2_env.reaper.TrackFX_Delete = function(tr, idx)
  deleted_track, deleted_fx = tr, idx
  return true
end
check(inst_auto:remove() == true and deleted_track == mock_track_obj and deleted_fx == 2,
  "PluginInstance:remove() must call TrackFX_Delete with exact track and fx_index")

-- 3) performFullScan() success + db:save() failure
local scan_inst = PW.PluginScanner:new()
check(scan_inst:performFullScan() == true, "performFullScan() must return true on writable resource path")
check(#scan_inst.db.plugins == 1 and scan_inst.db.plugins[1].name == "FabFilter Pro-Q 3",
  "performFullScan() must populate db.plugins")
check(file_exists(pw2_temp .. "/plugin_database.json"),
  "performFullScan() must persist plugin_database.json")

local pw_fail_env = environment()
local pw_fail_console, pw_fail_dialogs = {}, {}
pw_fail_env.reaper.GetResourcePath = function() return pw2_temp .. "/nonexistent_dir/nested" end
pw_fail_env.reaper.GetOS = function() return "Linux" end
pw_fail_env.reaper.ShowConsoleMsg = function(m) table.insert(pw_fail_console, tostring(m)) end
pw_fail_env.reaper.ShowMessageBox = function(text, title, _)
  table.insert(pw_fail_dialogs, {text = text, title = title})
  return 0
end
pw_fail_env.reaper.EnumerateFiles = function() return nil end
pw_fail_env.reaper.EnumerateSubdirectories = function() return nil end
load_script("plugin-wrapper.lua", pw_fail_env)
local fail_scanner = pw_fail_env.SGMPluginWrapper.PluginScanner:new()
check(fail_scanner:performFullScan() == false,
  "performFullScan() must return false when db:save() fails")
check(table.concat(pw_fail_console):find("ERROR: Could not save plugin database", 1, true) ~= nil,
  "performFullScan() must log save failure to console")

-- 4) showMenu() rows 1, 2, 4
os.remove(pw2_temp .. "/plugin_database.json")
pw2_env.gfx.showmenu = function() return 1 end
PW.showMenu()
check(file_exists(pw2_temp .. "/plugin_database.json"),
  "plugin-wrapper showMenu row 1 must execute scanAllPlugins and write DB")

-- Row 2: no selected track
pw2_dialogs = {}
pw2_env.reaper.GetSelectedTrack = function() return nil end
pw2_env.gfx.showmenu = function() return 2 end
PW.showMenu()
check(pw2_dialogs[#pw2_dialogs] and pw2_dialogs[#pw2_dialogs].text == "No track selected",
  "plugin-wrapper showMenu row 2 with no track must show No track selected dialog")

-- Row 2: selected track with 2 FX
pw2_console = {}
local listed_fx = {
  {name = "VST3: ReaEQ", params = 12, enabled = true},
  {name = "VST3: ReaComp", params = 8, enabled = false},
}
pw2_env.reaper.GetSelectedTrack = function() return mock_track_obj end
pw2_env.reaper.TrackFX_GetCount = function() return #listed_fx end
pw2_env.reaper.TrackFX_GetFXName = function(_, idx) return true, listed_fx[idx + 1].name end
pw2_env.reaper.TrackFX_GetNumParams = function(_, idx) return listed_fx[idx + 1].params end
pw2_env.reaper.TrackFX_GetEnabled = function(_, idx) return listed_fx[idx + 1].enabled end
pw2_env.gfx.showmenu = function() return 2 end
PW.showMenu()
local row2_out = table.concat(pw2_console)
check(row2_out:find("Plugin: VST3: ReaEQ", 1, true) ~= nil and
      row2_out:find("Parameters: 12", 1, true) ~= nil and
      row2_out:find("Plugin: VST3: ReaComp", 1, true) ~= nil and
      row2_out:find("Enabled: false", 1, true) ~= nil,
  "plugin-wrapper showMenu row 2 must print every FX on selected track")

-- Row 4: export DB success + failure
pw2_dialogs = {}
pw2_env.gfx.showmenu = function() return 4 end
PW.showMenu()
check(pw2_dialogs[#pw2_dialogs] and pw2_dialogs[#pw2_dialogs].title == "Success" and
      pw2_dialogs[#pw2_dialogs].text:find("plugin_database.json", 1, true) ~= nil,
  "plugin-wrapper showMenu row 4 must report Success on writable path")

pw_fail_dialogs = {}
pw_fail_env.gfx.showmenu = function() return 4 end
pw_fail_env.SGMPluginWrapper.showMenu()
check(pw_fail_dialogs[#pw_fail_dialogs] and pw_fail_dialogs[#pw_fail_dialogs].title == "Error" and
      pw_fail_dialogs[#pw_fail_dialogs].text:find("Could not save database", 1, true) ~= nil,
  "plugin-wrapper showMenu row 4 must report Error when db:save() fails")
remove_dir(pw2_temp)

-- Reaper AI Control Hub.lua: _detect_plugin_type() and all 4 menu rows
local hub_temp = os.tmpname()
os.remove(hub_temp)
make_dir(hub_temp)
local hub_env = environment()
local hub_console = {}
local hub_master = {
  fx = {
    "VST3: FabFilter Pro-Q 3",
    "VST3i: Serum",
    "VST: ReaEQ",
    "VSTi: ReaSynth",
    "CLAP: Surge XT",
    "CLAPi: Surge XT Synth",
    "AU: Apple AUBandpass",
    "AUi: Apple DLSMusicDevice",
    "LV2: Calf Reverb",
    "LV2i: Helm",
    "JS: Analysis/gfxanalyzer",
    "AU: Bridge (.vst3)",
    "CLAP: Wrapper (.vst)",
    "Standalone.vst3",
    "Legacy.dll",
    "LinuxPlug.so",
    "Instrument.clap",
    "Unit.component",
    "Effect.lv2",
    "Plain Unrecognized FX",
  }
}
hub_env.reaper.GetResourcePath = function() return hub_temp end
hub_env.reaper.GetOS = function() return "Linux" end
hub_env.reaper.ShowConsoleMsg = function(m) table.insert(hub_console, tostring(m)) end
hub_env.reaper.GetMasterTrack = function() return hub_master end
hub_env.reaper.TrackFX_GetCount = function(tr) return tr and #tr.fx or 0 end
hub_env.reaper.TrackFX_GetFXName = function(tr, idx)
  local name = tr and tr.fx[idx + 1]
  if not name then return false, "" end
  return true, name
end
load_script("Reaper AI Control Hub.lua", hub_env)
local hub_bridge = hub_env.AIPluginBridge:new()
local expected_types = {
  "VST3", "VST3", "VST2", "VST2", "CLAP", "CLAP", "AU", "AU", "LV2", "LV2", "JSFX",
  "AU", "CLAP", "VST3", "VST2", "VST2", "CLAP", "AU", "LV2", "Unknown",
}
for i, want in ipairs(expected_types) do
  local got = hub_bridge:_detect_plugin_type(i - 1)
  check(got == want, "_detect_plugin_type(" .. hub_master.fx[i] .. ") expected " .. want .. ", got " .. tostring(got))
end
check(hub_bridge:_detect_plugin_type(999) == "Unknown", "_detect_plugin_type out-of-range must return Unknown")
hub_env.reaper.GetMasterTrack = function() return nil end
check(hub_bridge:_detect_plugin_type(0) == "Unknown", "_detect_plugin_type with nil master must return Unknown")

-- AI Hub Menu Row 1: Inspect Master FX / Export Routing Notes
hub_master.fx = {"JS: Gain Reduction Scope", "VST3: Neural AI Processor"}
hub_env.reaper.GetMasterTrack = function() return hub_master end
hub_console = {}
hub_env.gfx.showmenu = function() return 1 end
hub_env.run_ai_hub()
local row1_console = table.concat(hub_console)
check(row1_console:find("AI PLUGIN DISCOVERY MODE", 1, true) ~= nil, "AI Hub row 1 must run discovery mode")
check(row1_console:find("Neural AI Processor", 1, true) ~= nil, "AI Hub row 1 must discover AI plugin")
check(row1_console:find("Gain Reduction Scope", 1, true) == nil, "AI Hub row 1 must not misclassify Gain Reduction Scope")
check(file_exists(hub_temp .. "/ai_routing_template.json"), "AI Hub row 1 must write ai_routing_template.json")

-- AI Hub Menu Row 2: ReWire Setup Notes
hub_console = {}
hub_env.gfx.showmenu = function() return 2 end
hub_env.run_ai_hub()
local row2_hub = table.concat(hub_console)
check(row2_hub:find("REWIRE INTEGRATION MODE", 1, true) ~= nil and
      row2_hub:find("no settings were changed", 1, true) ~= nil,
  "AI Hub row 2 must print ReWire setup notes")

-- AI Hub Menu Row 3: OmniBridge Setup Notes
hub_console = {}
hub_env.gfx.showmenu = function() return 3 end
hub_env.run_ai_hub()
local row3_hub = table.concat(hub_console)
check(row3_hub:find("OMNIBRIDGE INTEGRATION MODE", 1, true) ~= nil and
      row3_hub:find("OmniBridge Setup Instructions:", 1, true) ~= nil,
  "AI Hub row 3 must print OmniBridge setup notes")

-- AI Hub Menu Row 4: External Processing Instructions (no track -> unsaved -> saved Linux & Win64)
hub_console = {}
hub_env.reaper.CountSelectedTracks = function() return 0 end
hub_env.gfx.showmenu = function() return 4 end
hub_env.run_ai_hub()
check(table.concat(hub_console):find("Select at least one track", 1, true) ~= nil,
  "AI Hub row 4 with no selected tracks must guide user to select tracks")

local sel_track = {name = 'Gtr: L/R <DI>?'}
hub_env.reaper.CountSelectedTracks = function() return 1 end
hub_env.reaper.GetSelectedTrack = function() return sel_track end
hub_env.reaper.GetSetMediaTrackInfo_String = function(tr) return true, tr.name end
hub_env.reaper.EnumProjects = function() return {}, "" end
hub_console = {}
hub_env.run_ai_hub()
check(table.concat(hub_console):find("Save the project", 1, true) ~= nil,
  "AI Hub row 4 on unsaved project must refuse and ask user to save project")

hub_env.reaper.EnumProjects = function() return {}, hub_temp .. "/song.rpp" end
hub_env.reaper.GetOS = function() return "Linux" end
hub_console = {}
hub_env.run_ai_hub()
local row4_linux = table.concat(hub_console)
check(row4_linux:find("01_Gtr_ L_R _DI___export.wav", 1, true) ~= nil and
      row4_linux:find("No audio was rendered automatically", 1, true) ~= nil and
      row4_linux:find("python3 -m demucs", 1, true) ~= nil,
  "AI Hub row 4 on Linux saved project must print sanitized target and python3 command")

hub_env.reaper.GetOS = function() return "Win64" end
hub_console = {}
hub_env.run_ai_hub()
local row4_win = table.concat(hub_console)
check(row4_win:find("python -m demucs", 1, true) ~= nil,
  "AI Hub row 4 on Win64 saved project must print python command")
remove_dir(hub_temp)

-- phase-alignment-tool.lua: deterministic synthetic WAV fixtures, D_STARTOFFS / D_PLAYRATE / multi-take / polarity / edge cases
local wav_temp = os.tmpname()
os.remove(wav_temp)
make_dir(wav_temp)

local WAV_RATE = 48000
local WAV_FRAMES = 9600 -- 200ms @ 48kHz
local WAV_TOL = 1.0 / WAV_RATE

local function write_pcm16_wav(path, rate, nframes, nch, click_frame, click_ch, amp, width)
  width = width or 24
  local parts = {}
  for f = 0, nframes - 1 do
    for c = 1, nch do
      local v = 0.0
      if c == click_ch and click_frame >= 0 and f >= click_frame and f < click_frame + width then
        v = amp
      end
      v = math.max(-1.0, math.min(1.0, v))
      parts[#parts + 1] = string.pack("<i2", math.floor(v * 32767 + (v >= 0 and 0.5 or -0.5)))
    end
  end
  local pcm = table.concat(parts)
  local header = "RIFF" .. string.pack("<I4", 36 + #pcm) .. "WAVEfmt " ..
    string.pack("<I4I2I2I4I4I2I2", 16, 1, nch, rate, rate * nch * 2, nch * 2, 16) ..
    "data" .. string.pack("<I4", #pcm)
  write_all(path, header .. pcm)
  return path
end

local function parse_pcm16_wav(path)
  local raw = assert(read_all(path), "missing WAV fixture: " .. path)
  assert(raw:sub(1, 4) == "RIFF" and raw:sub(9, 12) == "WAVE", "invalid RIFF/WAVE header")
  local _, nch, rate, _, _, bits = string.unpack("<I2I2I4I4I2I2", raw, 21)
  assert(bits == 16, "expected 16-bit PCM")
  local data_size = string.unpack("<I4", raw, 41)
  local total_samples = data_size // 2
  local total_frames = total_samples // nch
  local samples = {}
  local pos = 45
  for i = 1, total_samples do
    local s
    s, pos = string.unpack("<i2", raw, pos)
    samples[i] = s / 32767.0
  end
  return {rate = rate, channels = nch, frames = total_frames, samples = samples}
end

-- Generate deterministic synthetic WAV fixtures on disk
local wav_mono_15 = write_pcm16_wav(wav_temp .. "/mono_15ms.wav", WAV_RATE, WAV_FRAMES, 1, 720, 1, 0.80)
local wav_stereo_60 = write_pcm16_wav(wav_temp .. "/stereo_60ms_ch2.wav", WAV_RATE, WAV_FRAMES, 2, 2880, 2, 0.85)
local wav_quad_15 = write_pcm16_wav(wav_temp .. "/quad_15ms_ch4.wav", WAV_RATE, WAV_FRAMES, 4, 720, 4, -0.75)
local wav_late_120 = write_pcm16_wav(wav_temp .. "/mono_120ms_late.wav", WAV_RATE, WAV_FRAMES, 1, 5760, 1, 0.90)
local wav_pol_pos_15 = write_pcm16_wav(wav_temp .. "/pol_pos_15ms.wav", WAV_RATE, WAV_FRAMES, 1, 720, 1, 0.80)
local wav_pol_neg_60 = write_pcm16_wav(wav_temp .. "/pol_neg_60ms.wav", WAV_RATE, WAV_FRAMES, 1, 2880, 1, -0.80)
local minus_30db = 10 ^ (-30 / 20) -- ~0.0316228 (< 0.3 threshold)
local wav_quiet_30db = write_pcm16_wav(wav_temp .. "/quiet_minus30db.wav", WAV_RATE, WAV_FRAMES, 1, 960, 1, minus_30db)

local dsp_env = environment()
local dsp_console, dsp_dialogs = {}, {}
local dsp_undo, dsp_refresh = 0, 0
local dsp_selected_tracks = {}
local dsp_force_nil_accessor = false
local dsp_destroyed = 0

local function make_wav_item(wav_path, pos, opts)
  opts = opts or {}
  local parsed = parse_pcm16_wav(wav_path)
  local take = {
    source = parsed,
    start_offs = opts.start_offs or 0.0,
    playrate = opts.playrate ~= nil and opts.playrate or 1.0,
  }
  return {
    pos = pos or 0.0,
    active_take = opts.no_take and nil or take,
    take_count = opts.take_count or 1,
  }
end

dsp_env.reaper.ShowConsoleMsg = function(m) table.insert(dsp_console, tostring(m)) end
dsp_env.reaper.ShowMessageBox = function(text, title, _)
  table.insert(dsp_dialogs, {text = text, title = title})
  return 1
end
dsp_env.reaper.CountSelectedTracks = function() return #dsp_selected_tracks end
dsp_env.reaper.GetSelectedTrack = function(_, idx) return dsp_selected_tracks[idx + 1] end
dsp_env.reaper.GetTrackName = function(tr) return true, tr.name end
dsp_env.reaper.CountTrackMediaItems = function(tr) return #tr.items end
dsp_env.reaper.GetTrackMediaItem = function(tr, idx) return tr.items[idx + 1] end
dsp_env.reaper.CountTakes = function(item) return item.take_count or 1 end
dsp_env.reaper.GetActiveTake = function(item) return item.active_take end
dsp_env.reaper.GetMediaItemTakeInfo_Value = function(take, key)
  if key == "D_STARTOFFS" then return take.start_offs or 0.0 end
  if key == "D_PLAYRATE" then return take.playrate end
  return 0.0
end
dsp_env.reaper.GetMediaItemTake_Source = function(take) return take.source end
dsp_env.reaper.GetMediaSourceSampleRate = function(src) return src.rate end
dsp_env.reaper.GetMediaSourceNumChannels = function(src) return src.channels end
dsp_env.reaper.GetMediaItemInfo_Value = function(item, _) return item.pos end
dsp_env.reaper.SetMediaItemInfo_Value = function(item, _, val) item.pos = val end
dsp_env.reaper.CreateTakeAudioAccessor = function(take)
  if dsp_force_nil_accessor then return nil end
  return {take = take}
end
dsp_env.reaper.DestroyAudioAccessor = function() dsp_destroyed = dsp_destroyed + 1 end
dsp_env.reaper.GetAudioAccessorStartTime = function() return 0.0 end
dsp_env.reaper.GetAudioAccessorEndTime = function(acc)
  local src = acc.take.source
  local rem = (src.frames / src.rate) - (acc.take.start_offs or 0.0)
  local rate = acc.take.playrate or 1.0
  return math.max(0.0, rem / rate)
end
dsp_env.reaper.new_array = function(n)
  local b = {}
  for i = 1, n do b[i] = 0 end
  return b
end
dsp_env.reaper.GetAudioAccessorSamples = function(acc, rate, nch, start_sec, frames, buf)
  local take = acc.take
  local src = take.source
  local start_offs = take.start_offs or 0.0
  local playrate = take.playrate or 1.0
  for f = 0, frames - 1 do
    local t_item = start_sec + (f / rate)
    local t_src = start_offs + (t_item * playrate)
    local src_frame = math.floor(t_src * src.rate + 0.5)
    for c = 0, nch - 1 do
      local val = 0.0
      if src_frame >= 0 and src_frame < src.frames then
        val = src.samples[src_frame * src.channels + c + 1] or 0.0
      end
      buf[f * nch + c + 1] = val
    end
  end
  return 1
end
dsp_env.reaper.Undo_BeginBlock = function() dsp_undo = dsp_undo + 1 end
dsp_env.reaper.Undo_EndBlock = function() dsp_undo = dsp_undo - 1 end
dsp_env.reaper.PreventUIRefresh = function(d) dsp_refresh = dsp_refresh + d end
dsp_env.reaper.UpdateArrange = function() end

load_script("phase-alignment-tool.lua", dsp_env)
local PA = dsp_env.SGMPhaseAlignment

-- 1) Ground-truth synthetic WAV transient detection across mono, stereo ch2, 4ch ch4, >100ms, -30dB
local t_mono, p_mono, pol_mono = PA.findFirstTransient(make_wav_item(wav_mono_15, 2.0))
check(t_mono and math.abs(t_mono - 2.015) <= WAV_TOL and math.abs(p_mono - 0.80) < 0.002 and pol_mono == 1,
  "mono 15ms WAV fixture must detect 2.015s, peak ~0.80, polarity +1")

local t_st, p_st, pol_st = PA.findFirstTransient(make_wav_item(wav_stereo_60, 1.0))
check(t_st and math.abs(t_st - 1.060) <= WAV_TOL and math.abs(p_st - 0.85) < 0.002 and pol_st == 1,
  "stereo 60ms ch2 WAV fixture must detect 1.060s, peak ~0.85, polarity +1")

local t_q4, p_q4, pol_q4 = PA.findFirstTransient(make_wav_item(wav_quad_15, 0.5))
check(t_q4 and math.abs(t_q4 - 0.515) <= WAV_TOL and math.abs(p_q4 - 0.75) < 0.002 and pol_q4 == -1,
  "4-channel 15ms ch4 negative WAV fixture must detect 0.515s, peak ~0.75, polarity -1")

local t_late, p_late = PA.findFirstTransient(make_wav_item(wav_late_120, 1.0))
check(t_late == nil and p_late == 0,
  "WAV transient at 120ms (>100ms window) must return nil and peak 0")

local t_quiet, p_quiet = PA.findFirstTransient(make_wav_item(wav_quiet_30db, 1.0))
check(t_quiet == nil and math.abs(p_quiet - minus_30db) < 0.002,
  "quiet -30dB WAV transient must return nil with accurate ~0.0316 peak")

-- 2) D_STARTOFFS, D_PLAYRATE, combined offset+playrate, and invalid playrate <= 0 guard
local t_offs = PA.findFirstTransient(make_wav_item(wav_stereo_60, 3.0, {start_offs = 0.025}))
check(t_offs and math.abs(t_offs - 3.035) <= WAV_TOL,
  "D_STARTOFFS=0.025 on 60ms click must detect 3.035s")

local t_rate = PA.findFirstTransient(make_wav_item(wav_stereo_60, 1.0, {playrate = 2.0}))
check(t_rate and math.abs(t_rate - 1.030) <= WAV_TOL,
  "D_PLAYRATE=2.0 on 60ms click must detect 1.030s")

local t_both = PA.findFirstTransient(make_wav_item(wav_stereo_60, 4.0, {start_offs = 0.020, playrate = 2.0}))
check(t_both and math.abs(t_both - 4.020) <= WAV_TOL,
  "D_STARTOFFS=0.020 + D_PLAYRATE=2.0 on 60ms click must detect 4.020s")

for _, bad_rate in ipairs({0.0, -1.0}) do
  local cfg = PA.inspectTakeConfiguration({}, {playrate = bad_rate})
  check(cfg.valid == false, "inspectTakeConfiguration must reject D_PLAYRATE <= 0 (" .. tostring(bad_rate) .. ")")
  check(PA.findFirstTransient(make_wav_item(wav_mono_15, 1.0, {playrate = bad_rate})) == nil,
    "findFirstTransient must reject D_PLAYRATE <= 0 without reading")
end

-- 3) Polarity-inverted pair alignment math + pre-flight warnings & physical limitations disclosure
local item_pos = make_wav_item(wav_pol_pos_15, 1.0)
local item_neg = make_wav_item(wav_pol_neg_60, 1.0)
dsp_selected_tracks = {
  {name = "DI Pos", items = {item_pos}},
  {name = "DI Neg", items = {item_neg}},
}
dsp_console, dsp_dialogs = {}, {}
PA.alignSelectedTracks()
check(math.abs(item_pos.pos - 1.0) < 1e-9 and math.abs(item_neg.pos - 0.955) <= WAV_TOL,
  "polarity-inverted 15ms vs 60ms pair must move late item by exact -0.045s")
local aligned_t1 = PA.findFirstTransient(item_pos)
local aligned_t2 = PA.findFirstTransient(item_neg)
check(math.abs(aligned_t1 - aligned_t2) <= WAV_TOL,
  "post-alignment transients of polarity-inverted pair must coincide within 1 sample")
local pol_dialog = dsp_dialogs[#dsp_dialogs] and dsp_dialogs[#dsp_dialogs].text or ""
check(pol_dialog:find("Opposite transient polarity", 1, true) ~= nil,
  "confirmation dialog must warn about opposite transient polarity (+ vs -)")
check(pol_dialog:find("first item per track", 1, true) ~= nil and
      pol_dialog:find("100ms", 1, true) ~= nil and
      pol_dialog:find("not waveform cross-correlation", 1, true) ~= nil,
  "confirmation dialog must disclose physical limitations (first item, 100ms window, onset-only)")
check(dsp_undo == 0 and dsp_refresh == 0, "polarity pair alignment must balance undo and PreventUIRefresh")

-- 4) Pre-flight warnings for multi-take item, multi-item track, non-unity playrate, and 0-item track
local mt_a = make_wav_item(wav_mono_15, 1.0, {take_count = 3})
local mt_a_extra = make_wav_item(wav_mono_15, 5.0)
local mt_b = make_wav_item(wav_stereo_60, 1.0, {playrate = 2.0}) -- 30ms effective transient -> -15ms move
dsp_selected_tracks = {
  {name = "MultiTake", items = {mt_a, mt_a_extra}},
  {name = "Stretched", items = {mt_b}},
  {name = "EmptyTrack", items = {}},
}
dsp_console, dsp_dialogs = {}, {}
PA.alignSelectedTracks()
local pf_dialog = dsp_dialogs[#dsp_dialogs] and dsp_dialogs[#dsp_dialogs].text or ""
check(pf_dialog:find("3 takes", 1, true) ~= nil,
  "pre-flight confirmation must warn about multi-take item")
check(pf_dialog:find("has 2 items", 1, true) ~= nil,
  "pre-flight confirmation must warn about multi-item track (first item only)")
check(pf_dialog:find("playrate is 2.000x", 1, true) ~= nil,
  "pre-flight confirmation must warn about non-unity take playrate")
check(pf_dialog:find("no media items", 1, true) ~= nil,
  "pre-flight confirmation must warn about 0-item track")
check(math.abs(mt_b.pos - 0.985) <= WAV_TOL and math.abs(mt_a_extra.pos - 5.0) < 1e-9,
  "multi-take/playrate alignment must shift Stretched by exact -0.015s and leave 2nd item untouched")

-- 5) Required edge cases: 0 tracks, 1 track, 0 items, nil CreateTakeAudioAccessor, within CONFIG.alignment_precision
-- Edge A: 0 tracks selected
dsp_selected_tracks = {}
dsp_console, dsp_dialogs = {}, {}
PA.alignSelectedTracks()
check(#dsp_dialogs == 1 and dsp_dialogs[1].title:find("No Tracks Selected", 1, true) ~= nil and dsp_undo == 0,
  "0 selected tracks must warn and not open undo")

-- Edge B: 1 track selected
local solo_item = make_wav_item(wav_mono_15, 2.0)
dsp_selected_tracks = {{name = "Solo", items = {solo_item}}}
dsp_console, dsp_dialogs = {}, {}
PA.alignSelectedTracks()
check(#dsp_dialogs == 1 and math.abs(solo_item.pos - 2.0) < 1e-9 and dsp_undo == 0,
  "1 selected track must warn, not mutate item, and not open undo")

-- Edge C: 2 tracks where one has 0 items -> fewer than 2 detected transients, no mutation, no dialog
local one_audio = make_wav_item(wav_mono_15, 2.0)
dsp_selected_tracks = {
  {name = "HasAudio", items = {one_audio}},
  {name = "NoItems", items = {}},
}
dsp_console, dsp_dialogs = {}, {}
PA.alignSelectedTracks()
check(#dsp_dialogs == 0 and math.abs(one_audio.pos - 2.0) < 1e-9 and dsp_undo == 0,
  "track with 0 items leaving <2 transients must not prompt or mutate")
check(table.concat(dsp_console):find("No items found", 1, true) ~= nil,
  "0-item track must be reported to console")

-- Edge D: CreateTakeAudioAccessor returns nil -> safe nil return, no crash, no mutation
dsp_force_nil_accessor = true
local nil_acc_item = make_wav_item(wav_mono_15, 1.0)
local nil_acc_before = dsp_destroyed
check(PA.findFirstTransient(nil_acc_item) == nil and dsp_destroyed == nil_acc_before,
  "nil CreateTakeAudioAccessor must return nil without calling DestroyAudioAccessor")
dsp_selected_tracks = {
  {name = "NilA", items = {nil_acc_item}},
  {name = "NilB", items = {make_wav_item(wav_stereo_60, 1.0)}},
}
dsp_console, dsp_dialogs = {}, {}
PA.alignSelectedTracks()
check(#dsp_dialogs == 0 and math.abs(nil_acc_item.pos - 1.0) < 1e-9 and dsp_undo == 0,
  "nil accessor on all tracks must refuse alignment safely")
dsp_force_nil_accessor = false

-- Edge E: All transients within CONFIG.alignment_precision (0.05ms < 0.1ms) -> no dialog, no move, no undo
local prec_a = make_wav_item(wav_mono_15, 1.00000)
local prec_b = make_wav_item(wav_mono_15, 1.00005) -- 0.05ms difference < 0.0001s precision
dsp_selected_tracks = {
  {name = "PrecA", items = {prec_a}},
  {name = "PrecB", items = {prec_b}},
}
dsp_console, dsp_dialogs = {}, {}
PA.alignSelectedTracks()
check(#dsp_dialogs == 0 and math.abs(prec_a.pos - 1.0) < 1e-9 and math.abs(prec_b.pos - 1.00005) < 1e-9 and dsp_undo == 0,
  "transients within CONFIG.alignment_precision must not prompt, move, or open undo")
check(table.concat(dsp_console):find("already aligned", 1, true) ~= nil,
  "within-precision alignment must log already aligned")

remove_dir(wav_temp)

print(string.format("All %d API contract checks passed", checks))
