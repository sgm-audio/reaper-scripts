-- SGM Studio Session Builder
-- @description Adds full-production, mixing, mastering, or stem-session tracks and routing to the current project
-- @author Scott Mills
-- @version 3.0
-- Existing tracks and items are preserved. All changes are grouped in one undo block.

local function msg(message)
  reaper.ShowConsoleMsg(tostring(message) .. "\n")
end

local COLORS = {
  red = {220, 60, 60}, blue = {60, 110, 220}, green = {60, 170, 90},
  yellow = {220, 190, 60}, purple = {150, 80, 200}, orange = {230, 130, 40},
  white = {210, 210, 210}, gray = {120, 120, 120},
}

local STOCK_FX = {
  input = {"ReaEQ", "ReaComp"},
  instrument = {"ReaEQ", "ReaComp"},
  processing = {"ReaEQ", "ReaComp"},
  parallel = {"ReaComp"},
  mix_bus = {"ReaEQ", "ReaComp"},
  master = {"ReaEQ", "ReaLimit"},
}

local function track(name, track_type, color, bus, parallel)
  return {name = name, type = track_type, color = color, bus = bus, parallel = parallel}
end

local SESSION_BUILDERS = {}

function SESSION_BUILDERS.full_production()
  return {
    name = "SGM Full Production Session",
    tracks = {
      track("Drums Input", "input", "red", "Drum Bus", "Drums Parallel"),
      track("Bass Input", "input", "blue", "Bass Bus", "Bass Parallel"),
      track("Guitars Input", "input", "green", "Guitar Bus", "Guitars Parallel"),
      track("Keys Input", "input", "purple", "Keys Bus"),
      track("Vocals Input", "input", "yellow", "Vocal Bus"),
      track("FX Input", "input", "orange", "FX Bus"),
      track("Kick Drum", "instrument", "red", "Drum Bus", "Drums Parallel"),
      track("Snare Drum", "instrument", "red", "Drum Bus", "Drums Parallel"),
      track("Hi-Hats", "instrument", "red", "Drum Bus"),
      track("Overheads", "instrument", "red", "Drum Bus"),
      track("Bass Guitar", "instrument", "blue", "Bass Bus", "Bass Parallel"),
      track("Lead Guitar", "instrument", "green", "Guitar Bus", "Guitars Parallel"),
      track("Keys", "instrument", "purple", "Keys Bus"),
      track("Synths", "instrument", "orange", "Keys Bus"),
      track("Drum Bus", "processing", "red", "Mix Bus"),
      track("Bass Bus", "processing", "blue", "Mix Bus"),
      track("Guitar Bus", "processing", "green", "Mix Bus"),
      track("Keys Bus", "processing", "purple", "Mix Bus"),
      track("Vocal Bus", "processing", "yellow", "Mix Bus"),
      track("FX Bus", "processing", "orange", "Mix Bus"),
      track("Drums Parallel", "parallel", "red", "Mix Bus"),
      track("Bass Parallel", "parallel", "blue", "Mix Bus"),
      track("Guitars Parallel", "parallel", "green", "Mix Bus"),
      track("Mix Bus", "mix_bus", "white", "Master"),
      track("Master", "master", "gray"),
    },
  }
end

function SESSION_BUILDERS.mixing()
  return {
    name = "SGM Mixing Session",
    tracks = {
      track("Drum Bus", "processing", "red", "Mix Bus"),
      track("Bass Bus", "processing", "blue", "Mix Bus"),
      track("Guitar Bus", "processing", "green", "Mix Bus"),
      track("Vocal Bus", "processing", "yellow", "Mix Bus"),
      track("Reverb Return", "processing", "purple", "Mix Bus"),
      track("Delay Return", "processing", "orange", "Mix Bus"),
      track("Mix Bus", "mix_bus", "white"),
    },
  }
end

function SESSION_BUILDERS.mastering()
  return {
    name = "SGM Mastering Session",
    tracks = {
      {name = "Reference (Muted)", type = "reference", color = "blue", muted = true},
      {name = "Mastering Chain", type = "master", color = "gray"},
    },
  }
end

function SESSION_BUILDERS.stem_separation()
  return {
    name = "SGM Stem Separation Session",
    tracks = {
      track("Vocals", "input", "yellow", "Stem Bus"),
      track("Drums", "input", "red", "Stem Bus"),
      track("Bass", "input", "blue", "Stem Bus"),
      track("Other", "input", "green", "Stem Bus"),
      {name = "Original Mix (Muted Reference)", type = "reference", color = "white", muted = true},
      track("Stem Bus", "processing", "purple"),
    },
  }
end

local function createRouting(tracks)
  local routing = {sends = {}}
  for _, source in ipairs(tracks) do
    if source.bus then
      table.insert(routing.sends, {
        source = source.name, destination = source.bus,
        level_db = source.type == "mix_bus" and 0 or 0, pan = 0, mode = 0,
      })
    end
    if source.parallel then
      table.insert(routing.sends, {
        source = source.name, destination = source.parallel,
        level_db = -6, pan = 0, mode = 0,
      })
    end
  end
  return routing
end

local AdvancedSessionBuilder = {}
AdvancedSessionBuilder.__index = AdvancedSessionBuilder

function AdvancedSessionBuilder:new()
  return setmetatable({}, self)
end

function AdvancedSessionBuilder:buildSessionFromAnalysis(project_type, complexity)
  project_type = project_type or "full_production"
  complexity = complexity or "stock"
  local builder = SESSION_BUILDERS[project_type]
  if not builder then return nil, "Unknown session type: " .. tostring(project_type) end
  local session = builder()
  session.routing = createRouting(session.tracks)
  session.complexity = complexity
  return session
end

local SessionImplementationEngine = {}
SessionImplementationEngine.__index = SessionImplementationEngine

function SessionImplementationEngine:new()
  return setmetatable({fx_warnings = {}}, self)
end

function SessionImplementationEngine:createTracks(track_templates)
  for _, template in ipairs(track_templates) do
    local index = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(index, true)
    local media_track = reaper.GetTrack(0, index)
    if not media_track then error("Could not create track: " .. template.name) end
    template._track = media_track
    reaper.GetSetMediaTrackInfo_String(media_track, "P_NAME", template.name, true)
    local rgb = COLORS[template.color] or COLORS.white
    reaper.SetTrackColor(media_track, reaper.ColorToNative(rgb[1], rgb[2], rgb[3]) | 0x1000000)
    reaper.SetMediaTrackInfo_Value(media_track, "B_MAINSEND", (template.bus or template.parallel) and 0 or 1)
    if template.muted then reaper.SetMediaTrackInfo_Value(media_track, "B_MUTE", 1) end
  end
end

function SessionImplementationEngine:addPlugins(track_templates, complexity)
  if complexity == "no_fx" then return end
  for _, template in ipairs(track_templates) do
    for _, fx_name in ipairs(STOCK_FX[template.type] or {}) do
      -- TrackFX_AddByName(track, fxname, recFX, instantiate): 3rd arg is the
      -- record-input-FX flag (boolean), not an install flag; the 4th arg
      -- controls instantiation (negative = always add, 0 = query only,
      -- positive = add if missing). Passing recFX=true with instantiate
      -- omitted queries the record-FX chain and never installs stock FX.
      local fx_index = reaper.TrackFX_AddByName(template._track, fx_name, false, 1)
      if fx_index < 0 then
        table.insert(self.fx_warnings, template.name .. ": " .. fx_name)
      end
    end
  end
end

-- Search backward so newly appended tracks win over same-named existing tracks.
function SessionImplementationEngine:findTrackByName(name)
  for index = reaper.CountTracks(0) - 1, 0, -1 do
    local media_track = reaper.GetTrack(0, index)
    local _, track_name = reaper.GetTrackName(media_track)
    if track_name == name then return media_track end
  end
  return nil
end

function SessionImplementationEngine:implementRouting(routing)
  local created = 0
  for _, send in ipairs(routing.sends) do
    local source = self:findTrackByName(send.source)
    local destination = self:findTrackByName(send.destination)
    if source and destination then
      local send_index = reaper.CreateTrackSend(source, destination)
      if send_index >= 0 then
        created = created + 1
        -- REAPER expects linear gain, not the dB values used in the session data.
        reaper.SetTrackSendInfo_Value(source, 0, send_index, "D_VOL", 10 ^ (send.level_db / 20))
        reaper.SetTrackSendInfo_Value(source, 0, send_index, "D_PAN", send.pan or 0)
        reaper.SetTrackSendInfo_Value(source, 0, send_index, "I_SENDMODE", send.mode or 0)
      end
    end
  end
  return created
end

function SessionImplementationEngine:implementSession(session)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  session.sends_created = 0
  local ok, err = pcall(function()
    self:createTracks(session.tracks)
    self:addPlugins(session.tracks, session.complexity)
    session.sends_created = self:implementRouting(session.routing)
  end)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("SGM: " .. session.name, -1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  if not ok then return false, err end
  for _, warning in ipairs(self.fx_warnings) do msg("WARNING: stock FX unavailable on " .. warning) end
  return true
end

local function generateSessionReport(session, fx_warnings)
  msg("\n=== " .. session.name .. " ===")
  msg("Tracks added: " .. #session.tracks)
  msg("Sends created: " .. tostring(session.sends_created or 0))
  msg("Stock FX warnings: " .. #fx_warnings)
  msg("Existing tracks and items were preserved.")
end

function buildProfessionalSession(project_type, complexity)
  local builder = AdvancedSessionBuilder:new()
  local session, build_error = builder:buildSessionFromAnalysis(project_type, complexity)
  if not session then
    reaper.ShowMessageBox(build_error, "Session Builder", 0)
    return nil
  end
  local answer = reaper.ShowMessageBox(
    "Add " .. #session.tracks .. " tracks and " .. #session.routing.sends ..
      " sends to the current project?\n\nExisting tracks and items will be preserved.",
    session.name, 1)
  if answer ~= 1 then return nil end

  local engine = SessionImplementationEngine:new()
  local ok, implementation_error = engine:implementSession(session)
  if not ok then
    reaper.ShowMessageBox("Session creation failed:\n" .. tostring(implementation_error), "Session Builder", 0)
    return nil
  end
  session.implemented = true
  generateSessionReport(session, engine.fx_warnings)
  return session
end

local function showProfessionalBuilderMenu()
  local menu = "SGM Session Builder (adds to current project)|" ..
    "Full Production (25 tracks)|" ..
    "Mixing (7 tracks)|" ..
    "Mastering (2 tracks)|" ..
    "Stem Separation (6 tracks)|" ..
    "Full Production Without FX"
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local result = gfx.showmenu(menu)
  if result == 1 then buildProfessionalSession("full_production", "stock")
  elseif result == 2 then buildProfessionalSession("mixing", "stock")
  elseif result == 3 then buildProfessionalSession("mastering", "stock")
  elseif result == 4 then buildProfessionalSession("stem_separation", "stock")
  elseif result == 5 then buildProfessionalSession("full_production", "no_fx") end
end

_G.SGMSessionBuilder = {
  AdvancedSessionBuilder = AdvancedSessionBuilder,
  SessionImplementationEngine = SessionImplementationEngine,
  session_builders = SESSION_BUILDERS,
}
showProfessionalBuilderMenu()
