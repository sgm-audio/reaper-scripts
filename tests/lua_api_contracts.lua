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
  check(time and math.abs(time - 12.04) < 1e-9, "status 1 must scan all requested frames/channels")
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
-- a decorative title. Check all four menus and execute a real nudge row.
for path, first in pairs({
  ["phase-alignment-tool.lua"] = "1. Auto-Align Selected Tracks (Quad-Track Guitar)",
  ["SGM_Professional_Session_Builder.lua"] = "Full Production (25 tracks)",
  ["plugin-wrapper.lua"] = "Scan All Plugins",
  ["Reaper AI Control Hub.lua"] = "Inspect Master FX / Export Routing Notes",
}) do
  local menu_env = environment()
  menu_env.reaper.GetResourcePath = function() return "/unused-contract-fixture" end
  menu_env.reaper.GetOS = function() return "Linux" end
  menu_env.reaper.time_precise = function() return 0 end
  menu_env.gfx.showmenu = function(menu)
    check(menu:match("^[^|]+") == first, path .. ": row 1 must be the first action")
    return 0
  end
  load_script(path, menu_env)
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

-- Case 2: Constant DC offset below threshold (0.05, threshold is 0.1) -> must return nil and peak 0.05
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

-- Case C: SetMediaItemInfo_Value errors inside pcall -> undo/refresh stay balanced
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

-- reaper-template-installer.lua: main() decline vs accept in an isolated temp dir
local inst_temp = os.tmpname()
os.remove(inst_temp)
os.execute("mkdir -p '" .. inst_temp:gsub("'", "'\\''") .. "'")
local inst_env = environment()
inst_env.reaper.GetResourcePath = function() return inst_temp end
inst_env.reaper.ShowMessageBox = function() return 0 end
inst_env.reaper.RecursiveCreateDirectory = function(path, _)
  os.execute("mkdir -p '" .. tostring(path):gsub("'", "'\\''") .. "'")
  return 1
end
load_script("./reaper-template-installer.lua", inst_env)
check(inst_env.SGMScriptInstaller.main() == false,
  "declined installer main() must return false")
local manifest_before = io.open(inst_temp .. "/Scripts/ScottMills/installed-files.txt", "r")
check(manifest_before == nil, "declined installer must not write manifest")
if manifest_before then manifest_before:close() end
inst_env.reaper.ShowMessageBox = function() return 1 end
check(inst_env.SGMScriptInstaller.main() == true,
  "confirmed installer main() must return true")
local manifest_after = io.open(inst_temp .. "/Scripts/ScottMills/installed-files.txt", "r")
check(manifest_after ~= nil, "confirmed installer must write installed-files.txt manifest")
if manifest_after then manifest_after:close() end
os.execute("rm -rf '" .. inst_temp:gsub("'", "'\\''") .. "'")

print(string.format("All %d API contract checks passed", checks))
