-- REAPER Plugin Wrapper & Manager
-- Comprehensive VST/VST3/AU plugin scanning, management, and automation
-- Version 1.0

local PLUGIN_DB_FILE = reaper.GetResourcePath() .. "/plugin_database.json"
local SCAN_PATHS = {}

-- Platform-specific plugin paths
if reaper.GetOS() == "Win32" or reaper.GetOS() == "Win64" then
  SCAN_PATHS = {
    "C:\\Program Files\\VSTPlugins",
    "C:\\Program Files\\Steinberg\\VSTPlugins",
    "C:\\Program Files\\Common Files\\VST3",
    "C:\\Program Files (x86)\\VSTPlugins"
  }
else
  SCAN_PATHS = {
    "/Library/Audio/Plug-Ins/VST",
    "/Library/Audio/Plug-Ins/VST3",
    "/Library/Audio/Plug-Ins/Components",
    os.getenv("HOME") .. "/Library/Audio/Plug-Ins/VST",
    os.getenv("HOME") .. "/Library/Audio/Plug-Ins/VST3"
  }
end

-- ===================================
-- PLUGIN DATABASE
-- ===================================

local PluginDB = {}

function PluginDB:new()
  local obj = {
    plugins = {},
    last_scan = 0
  }
  setmetatable(obj, self)
  self.__index = self
  return obj
end

function PluginDB:load()
  local file = io.open(PLUGIN_DB_FILE, "r")
  if file then
    local content = file:read("*all")
    file:close()

    -- Simple JSON-like parsing (basic implementation)
    local db = self:parseJSON(content)
    if db then
      self.plugins = db.plugins or {}
      self.last_scan = db.last_scan or 0
    end
  end
end

function PluginDB:save()
  local file = io.open(PLUGIN_DB_FILE, "w")
  if file then
    file:write(self:toJSON())
    file:close()
    return true
  end
  return false
end

function PluginDB:parseJSON(str)
  -- Simplified JSON parser for plugin database
  -- In production, use a proper JSON library
  return {plugins = {}, last_scan = os.time()}
end

function PluginDB:toJSON()
  local json = "{\n"
  json = json .. '  "last_scan": ' .. os.time() .. ',\n'
  json = json .. '  "plugins": [\n'

  local plugin_entries = {}
  for _, plugin in ipairs(self.plugins) do
    local entry = string.format([[
    {
      "name": "%s",
      "path": "%s",
      "format": "%s",
      "vendor": "%s",
      "category": "%s",
      "param_count": %d
    }]],
      plugin.name,
      plugin.path:gsub("\\", "\\\\"),
      plugin.format,
      plugin.vendor or "Unknown",
      plugin.category or "Effect",
      plugin.param_count or 0
    )
    table.insert(plugin_entries, entry)
  end

  json = json .. table.concat(plugin_entries, ",\n")
  json = json .. "\n  ]\n}"
  return json
end

function PluginDB:addPlugin(plugin_info)
  table.insert(self.plugins, plugin_info)
end

function PluginDB:findByName(name)
  for _, plugin in ipairs(self.plugins) do
    if plugin.name:lower():find(name:lower()) then
      return plugin
    end
  end
  return nil
end

function PluginDB:getByCategory(category)
  local results = {}
  for _, plugin in ipairs(self.plugins) do
    if plugin.category == category then
      table.insert(results, plugin)
    end
  end
  return results
end

-- ===================================
-- PLUGIN SCANNER
-- ===================================

local PluginScanner = {}

function PluginScanner:new()
  local obj = {
    db = PluginDB:new(),
    scan_progress = 0,
    total_files = 0
  }
  setmetatable(obj, self)
  self.__index = self
  obj.db:load()
  return obj
end

function PluginScanner:scanDirectory(path)
  local plugins_found = {}

  if not reaper.file_exists(path) then
    return plugins_found
  end

  -- Recursively scan directory
  local files = self:getFilesInDirectory(path)

  for _, file in ipairs(files) do
    local plugin_info = self:analyzePlugin(file)
    if plugin_info then
      table.insert(plugins_found, plugin_info)
      self.db:addPlugin(plugin_info)
    end

    self.scan_progress = self.scan_progress + 1
  end

  return plugins_found
end

function PluginScanner:getFilesInDirectory(path)
  local files = {}
  local extensions = {".dll", ".vst", ".vst3", ".component"}

  -- Use REAPER's file enumeration
  local i = 0
  repeat
    local filename = reaper.EnumerateFiles(path, i)
    if filename then
      for _, ext in ipairs(extensions) do
        if filename:sub(-#ext) == ext then
          table.insert(files, path .. "/" .. filename)
        end
      end
    end
    i = i + 1
  until not filename

  -- Enumerate subdirectories
  i = 0
  repeat
    local dirname = reaper.EnumerateSubdirectories(path, i)
    if dirname then
      local subfiles = self:getFilesInDirectory(path .. "/" .. dirname)
      for _, file in ipairs(subfiles) do
        table.insert(files, file)
      end
    end
    i = i + 1
  until not dirname

  return files
end

function PluginScanner:analyzePlugin(file_path)
  local filename = file_path:match("([^/\\]+)$")
  local ext = filename:match("%.([^%.]+)$")

  local format = "Unknown"
  if ext == "dll" or ext == "vst" then
    format = "VST2"
  elseif ext == "vst3" then
    format = "VST3"
  elseif ext == "component" then
    format = "AU"
  end

  -- Extract plugin name (remove extension and common prefixes)
  local name = filename:gsub("%..-$", "")
  name = name:gsub("^VST_", ""):gsub("^AU_", "")

  return {
    name = name,
    path = file_path,
    format = format,
    vendor = self:detectVendor(file_path),
    category = self:categorizePlugin(name),
    param_count = 0,  -- Would need to load plugin to get actual count
    scanned_at = os.time()
  }
end

function PluginScanner:detectVendor(path)
  -- Try to detect vendor from path
  local vendors = {
    "FabFilter", "Waves", "Soundtoys", "UAD", "Native Instruments",
    "iZotope", "Slate Digital", "Plugin Alliance", "Softube"
  }

  for _, vendor in ipairs(vendors) do
    if path:lower():find(vendor:lower()) then
      return vendor
    end
  end

  return "Unknown"
end

function PluginScanner:categorizePlugin(name)
  local categories = {
    {pattern = "eq", category = "EQ"},
    {pattern = "comp", category = "Compressor"},
    {pattern = "reverb", category = "Reverb"},
    {pattern = "delay", category = "Delay"},
    {pattern = "synth", category = "Instrument"},
    {pattern = "verb", category = "Reverb"},
    {pattern = "chorus", category = "Modulation"},
    {pattern = "flanger", category = "Modulation"},
    {pattern = "phaser", category = "Modulation"},
    {pattern = "distortion", category = "Distortion"},
    {pattern = "saturator", category = "Saturation"}
  }

  local name_lower = name:lower()
  for _, cat in ipairs(categories) do
    if name_lower:find(cat.pattern) then
      return cat.category
    end
  end

  return "Effect"
end

function PluginScanner:performFullScan()
  reaper.ClearConsole()
  reaper.ShowConsoleMsg("Starting full plugin scan...\n")

  self.db.plugins = {}  -- Clear existing
  self.scan_progress = 0
  self.total_files = 0

  for _, path in ipairs(SCAN_PATHS) do
    reaper.ShowConsoleMsg("Scanning: " .. path .. "\n")
    local found = self:scanDirectory(path)
    reaper.ShowConsoleMsg("  Found " .. #found .. " plugins\n")
  end

  self.db.last_scan = os.time()
  self.db:save()

  reaper.ShowConsoleMsg("\nScan complete! Total plugins: " .. #self.db.plugins .. "\n")
end

-- ===================================
-- PLUGIN INSTANCE MANAGER
-- ===================================

local PluginInstance = {}

function PluginInstance:new(track, fx_index)
  local obj = {
    track = track,
    fx_index = fx_index,
    param_cache = {}
  }
  setmetatable(obj, self)
  self.__index = self
  return obj
end

function PluginInstance:getName()
  local _, name = reaper.TrackFX_GetFXName(self.track, self.fx_index, "")
  return name
end

function PluginInstance:getParamCount()
  return reaper.TrackFX_GetNumParams(self.track, self.fx_index)
end

function PluginInstance:getParamName(param_index)
  local _, name = reaper.TrackFX_GetParamName(self.track, self.fx_index, param_index, "")
  return name
end

function PluginInstance:getParamValue(param_index)
  return reaper.TrackFX_GetParam(self.track, self.fx_index, param_index)
end

function PluginInstance:setParamValue(param_index, value)
  return reaper.TrackFX_SetParam(self.track, self.fx_index, param_index, value)
end

function PluginInstance:getParamFormatted(param_index)
  local _, formatted = reaper.TrackFX_GetFormattedParamValue(self.track, self.fx_index, param_index, "")
  return formatted
end

function PluginInstance:getPresetCount()
  return reaper.TrackFX_GetPresetIndex(self.track, self.fx_index)
end

function PluginInstance:loadPreset(preset_index)
  reaper.TrackFX_SetPresetByIndex(self.track, self.fx_index, preset_index)
end

function PluginInstance:savePreset(preset_name)
  reaper.TrackFX_SetPreset(self.track, self.fx_index, preset_name)
end

function PluginInstance:enable()
  reaper.TrackFX_SetEnabled(self.track, self.fx_index, true)
end

function PluginInstance:disable()
  reaper.TrackFX_SetEnabled(self.track, self.fx_index, false)
end

function PluginInstance:isEnabled()
  return reaper.TrackFX_GetEnabled(self.track, self.fx_index)
end

function PluginInstance:remove()
  reaper.TrackFX_Delete(self.track, self.fx_index)
end

function PluginInstance:getStateChunk()
  local _, chunk = reaper.TrackFX_GetNamedConfigParm(self.track, self.fx_index, "")
  return chunk
end

function PluginInstance:cacheAllParams()
  self.param_cache = {}
  local count = self:getParamCount()

  for i = 0, count - 1 do
    self.param_cache[i] = {
      name = self:getParamName(i),
      value = self:getParamValue(i),
      formatted = self:getParamFormatted(i)
    }
  end
end

function PluginInstance:printInfo()
  reaper.ShowConsoleMsg("Plugin: " .. self:getName() .. "\n")
  reaper.ShowConsoleMsg("Parameters: " .. self:getParamCount() .. "\n")
  reaper.ShowConsoleMsg("Enabled: " .. tostring(self:isEnabled()) .. "\n")
end

-- ===================================
-- PLUGIN AUTOMATION
-- ===================================

local PluginAutomation = {}

function PluginAutomation:new(plugin_instance)
  local obj = {
    plugin = plugin_instance
  }
  setmetatable(obj, self)
  self.__index = self
  return obj
end

function PluginAutomation:automateParameter(param_index, start_value, end_value, duration_beats)
  local track = self.plugin.track
  local param_env = reaper.GetFXEnvelope(track, self.plugin.fx_index, param_index, true)

  if not param_env then
    return false
  end

  local current_time = reaper.GetCursorPosition()
  local tempo = reaper.Master_GetTempo()
  local duration_seconds = (duration_beats * 60) / tempo

  -- Add automation points
  reaper.InsertEnvelopePoint(param_env, current_time, start_value, 0, 0, false, true)
  reaper.InsertEnvelopePoint(param_env, current_time + duration_seconds, end_value, 0, 0, false, true)
  reaper.Envelope_SortPoints(param_env)

  return true
end

function PluginAutomation:createSweep(param_index, start_val, end_val, duration, curve_type)
  local track = self.plugin.track
  local param_env = reaper.GetFXEnvelope(track, self.plugin.fx_index, param_index, true)

  if not param_env then return false end

  local current_time = reaper.GetCursorPosition()
  local steps = 20  -- Resolution

  for i = 0, steps do
    local t = i / steps
    local value

    if curve_type == "linear" then
      value = start_val + (end_val - start_val) * t
    elseif curve_type == "exponential" then
      value = start_val + (end_val - start_val) * (t * t)
    elseif curve_type == "logarithmic" then
      value = start_val + (end_val - start_val) * math.sqrt(t)
    else
      value = start_val + (end_val - start_val) * t
    end

    local time = current_time + (duration * t)
    reaper.InsertEnvelopePoint(param_env, time, value, 0, 0, false, true)
  end

  reaper.Envelope_SortPoints(param_env)
  return true
end

-- ===================================
-- MAIN FUNCTIONS
-- ===================================

function scanAllPlugins()
  local scanner = PluginScanner:new()
  scanner:performFullScan()
end

function listAllPluginsOnTrack()
  local track = reaper.GetSelectedTrack(0, 0)
  if not track then
    reaper.ShowMessageBox("No track selected", "Error", 0)
    return
  end

  local fx_count = reaper.TrackFX_GetCount(track)
  reaper.ClearConsole()
  reaper.ShowConsoleMsg("FX Chain for track:\n")
  reaper.ShowConsoleMsg("==================\n\n")

  for i = 0, fx_count - 1 do
    local plugin = PluginInstance:new(track, i)
    plugin:printInfo()
    reaper.ShowConsoleMsg("\n")
  end
end

function automateSelectedPlugin()
  local track = reaper.GetSelectedTrack(0, 0)
  if not track then
    reaper.ShowMessageBox("No track selected", "Error", 0)
    return
  end

  -- Get last touched FX
  local _, _, fx_index = reaper.GetLastTouchedFX()
  if fx_index < 0 then
    reaper.ShowMessageBox("No plugin touched", "Error", 0)
    return
  end

  local plugin = PluginInstance:new(track, fx_index)
  local automation = PluginAutomation:new(plugin)

  -- Automate first parameter as example
  automation:createSweep(0, 0.0, 1.0, 4.0, "exponential")
  reaper.ShowMessageBox("Automation created!", "Success", 0)
end

-- ===================================
-- MENU
-- ===================================

function showMenu()
  local menu = "Plugin Manager|"
  menu = menu .. "#Scan All Plugins|"
  menu = menu .. "List Plugins on Selected Track|"
  menu = menu .. "Automate Last Touched Parameter|"
  menu = menu .. "|"
  menu = menu .. "Export Plugin Database"

  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local result = gfx.showmenu(menu)

  if result == 1 then
    scanAllPlugins()
  elseif result == 2 then
    listAllPluginsOnTrack()
  elseif result == 3 then
    automateSelectedPlugin()
  elseif result == 4 then
    local scanner = PluginScanner:new()
    scanner.db:save()
    reaper.ShowMessageBox("Database saved to:\n" .. PLUGIN_DB_FILE, "Success", 0)
  end
end

-- Run
showMenu()
