-- lua_smoke.lua — run each ReaScript with a conservative stubbed REAPER API.
-- Usage: lua5.4 tests/lua_smoke.lua <script.lua> [more.lua ...]
-- Exit codes: 0 = all ran clean, 2 = at least one load/runtime error.

local temp_root = os.tmpname()
os.remove(temp_root)
os.execute("mkdir -p '" .. temp_root:gsub("'", "'\\''") .. "'")

reaper = {
  GetResourcePath = function() return temp_root end,
  GetProjectPath = function() return temp_root end,
  EnumProjects = function(_) return nil, temp_root .. "/smoke.rpp" end,
  GetMousePosition = function() return 0, 0 end,
  GetOS = function() return "Linux" end,
  EnumerateFiles = function(_, _) return nil end,
  EnumerateSubdirectories = function(_, _) return nil end,
  CountTracks = function(_) return 0 end,
  CountSelectedTracks = function(_) return 0 end,
  CountSelectedMediaItems = function(_) return 0 end,
  CountTrackMediaItems = function(_) return 0 end,
  TrackFX_GetCount = function(_) return 0 end,
  GetMasterTrack = function(_) return {id = "master"} end,
  GetTrack = function(_, _) return nil end,
  GetSelectedTrack = function(_, _) return nil end,
  GetLastTouchedFX = function() return false, 0, -1, -1 end,
  GetSetMediaTrackInfo_String = function(_, _, _, _) return false, "" end,
  GetTrackName = function(_) return false, "" end,
  ShowMessageBox = function(_, _, _) return 0 end,
  ShowConsoleMsg = function(_) end,
  ClearConsole = function() end,
  time_precise = function() return os.clock() end,
  ColorToNative = function(_, _, _) return 0 end,
  file_exists = function(path)
    local file = io.open(path, "r")
    if file then file:close() return true end
    return false
  end,
  RecursiveCreateDirectory = function(path, _)
    os.execute("mkdir -p '" .. tostring(path):gsub("'", "'\\''") .. "'")
    return 1
  end,
  Undo_BeginBlock = function() end,
  Undo_EndBlock = function(_, _) end,
  PreventUIRefresh = function(_) end,
  UpdateArrange = function() end,
  TrackList_AdjustWindows = function(_) end,
  SetTrackColor = function(_, _) end,
  SetMediaTrackInfo_Value = function(_, _, _) end,
  InsertTrackAtIndex = function(_, _) end,
  DeleteTrack = function(_) end,
  TrackFX_AddByName = function(_, _, _, _) return 0 end,
  TrackFX_GetFXName = function(_, _, _) return false, "" end,
  TrackFX_GetNumParams = function(_, _) return 0 end,
  TrackFX_GetParamName = function(_, _, _) return false, "" end,
  TrackFX_GetParam = function(_, _, _) return 0 end,
  TrackFX_GetFormattedParamValue = function(_, _, _, _) return false, "" end,
  TrackFX_GetNamedConfigParm = function(_, _, _, _) return false, "" end,
  TrackFX_GetPresetIndex = function(_, _) return 0, 0 end,
  TrackFX_SetPresetByIndex = function(_, _, _) return true end,
  TrackFX_SetPreset = function(_, _, _) return true end,
  TrackFX_SetParam = function(_, _, _, _) return true end,
  TrackFX_SetEnabled = function(_, _, _) end,
  TrackFX_GetEnabled = function(_, _) return true end,
  TrackFX_Delete = function(_, _) return true end,
  CreateTrackSend = function(_, _) return -1 end,
  SetTrackSendInfo_Value = function(_, _, _, _, _) end,
  GetActiveTake = function(_) return nil end,
  GetMediaItemTake_Source = function(_) return nil end,
  GetMediaSourceSampleRate = function(_) return 44100 end,
  GetMediaSourceNumChannels = function(_) return 2 end,
  CreateTakeAudioAccessor = function(_) return nil end,
  DestroyAudioAccessor = function(_) end,
  GetAudioAccessorStartTime = function(_) return 0 end,
  GetAudioAccessorEndTime = function(_) return 0 end,
  GetAudioAccessorSamples = function(_, _, _, _, _, _) return 0 end,
  new_array = function(n)
    local b = {}
    for i = 1, n do b[i] = 0 end
    return b
  end,
  GetMediaItemInfo_Value = function(_, _) return 0 end,
  SetMediaItemInfo_Value = function(_, _, _) end,
  GetSelectedMediaItem = function(_, _) return nil end,
  GetTrackMediaItem = function(_, _) return nil end,
  GetFXEnvelope = function(_, _, _, _) return nil end,
  GetCursorPosition = function() return 0 end,
  InsertEnvelopePoint = function(_, _, _, _, _, _, _) return true end,
  Envelope_SortPoints = function(_) end,
  Master_GetTempo = function() return 120 end,
}

setmetatable(reaper, {
  __index = function(_, k)
    error("STRICT MOCK: Attempted access to undefined reaper API: " .. tostring(k), 2)
  end,
})

gfx = {
  mouse_x = 0, mouse_y = 0, x = 0, y = 0,
  showmenu = function(_) return 0 end,
  init = function() end,
  quit = function() end,
}
setmetatable(gfx, {
  __index = function(_, k)
    error("STRICT MOCK: Attempted access to undefined gfx API: " .. tostring(k), 2)
  end,
})

ImGui = setmetatable({}, {
  __index = function(_, k)
    error("STRICT MOCK: Attempted access to undefined ImGui API: " .. tostring(k), 2)
  end,
})

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
