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
local position, undo = 2, 0
api.CountSelectedMediaItems = function() return 1 end
api.GetSelectedMediaItem = function() return {} end
api.GetMediaItemInfo_Value = function() return position end
api.SetMediaItemInfo_Value = function(_, key, value) position = value end
api.Undo_BeginBlock = function() undo = undo + 1 end
api.Undo_EndBlock = function() undo = undo - 1 end
api.UpdateArrange = function() end
env.gfx.showmenu = function() return 6 end
load_script("phase-alignment-tool.lua", env)
check(math.abs(position - 2.0001) < 1e-9 and undo == 0, "row 6 must nudge right 0.1ms with balanced undo")
print(string.format("All %d API contract checks passed", checks))
