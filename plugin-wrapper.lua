-- REAPER Plugin Wrapper & Manager
-- @description Wraps plugin chains for repeatable loading and manages a plugin database
-- @author Scott Mills
-- @version 1.0
-- Comprehensive VST/VST3/AU plugin scanning, management, and automation
-- Version 1.0

local PLUGIN_DB_FILE = reaper.GetResourcePath() .. "/plugin_database.json"

-- Platform-specific plugin paths
local function getScanPaths()
  local os_type = reaper.GetOS() or ""
  local paths
  if os_type == "Win32" or os_type == "Win64" then
    local prog_files = os.getenv("ProgramFiles") or "C:\\Program Files"
    local prog_files_x86 = os.getenv("ProgramFiles(x86)") or "C:\\Program Files (x86)"
    local common_files = os.getenv("CommonProgramFiles") or (prog_files .. "\\Common Files")
    paths = {
      prog_files .. "\\VSTPlugins",
      prog_files .. "\\Steinberg\\VSTPlugins",
      common_files .. "\\VST3",
      common_files .. "\\CLAP",
      prog_files_x86 .. "\\VSTPlugins"
    }
  elseif os_type:match("^OSX") or os_type:match("^macOS") then
    paths = {
      "/Library/Audio/Plug-Ins/VST",
      "/Library/Audio/Plug-Ins/VST3",
      "/Library/Audio/Plug-Ins/Components",
      "/Library/Audio/Plug-Ins/CLAP",
      "/Library/Audio/Plug-Ins/LV2"
    }
    -- Per-user paths only exist when HOME is set
    local home = os.getenv("HOME")
    if home then
      table.insert(paths, home .. "/Library/Audio/Plug-Ins/VST")
      table.insert(paths, home .. "/Library/Audio/Plug-Ins/VST3")
      table.insert(paths, home .. "/Library/Audio/Plug-Ins/Components")
      table.insert(paths, home .. "/Library/Audio/Plug-Ins/CLAP")
      table.insert(paths, home .. "/Library/Audio/Plug-Ins/LV2")
    end
  else
    -- Linux
    paths = {
      "/usr/lib/vst",
      "/usr/lib/lxvst",
      "/usr/lib/vst3",
      "/usr/local/lib/vst",
      "/usr/local/lib/lxvst",
      "/usr/local/lib/vst3",
      "/usr/lib/clap",
      "/usr/lib/lv2",
      "/usr/local/lib/clap",
      "/usr/local/lib/lv2"
    }
    local home = os.getenv("HOME")
    if home then
      table.insert(paths, home .. "/.vst")
      table.insert(paths, home .. "/.vst3")
      table.insert(paths, home .. "/.lxvst")
      table.insert(paths, home .. "/.clap")
      table.insert(paths, home .. "/.lv2")
    end
  end
  return paths
end

local SCAN_PATHS = getScanPaths()

-- ===================================
-- PLUGIN DATABASE
-- ===================================

local function json_string(value)
  local escaped = tostring(value or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
  escaped = escaped:gsub("%c", function(char)
    local replacements = {["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}
    return replacements[char] or string.format("\\u%04X", string.byte(char))
  end)
  return '"' .. escaped .. '"'
end

local function json_unescape(value)
  local escapes = {['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t"}
  local out = {}
  local pos = 1
  local len = #value
  while pos <= len do
    local bs = value:find("\\", pos, true)
    if not bs then
      table.insert(out, value:sub(pos))
      break
    end
    if bs > pos then
      table.insert(out, value:sub(pos, bs - 1))
    end
    if bs == len then
      table.insert(out, "\\")
      break
    end
    local next_char = value:sub(bs + 1, bs + 1)
    if next_char == "u" then
      local hex = value:sub(bs + 2, bs + 5)
      if hex:match("^%x%x%x%x$") then
        local cp = tonumber(hex, 16)
        if cp <= 0x7F then
          table.insert(out, string.char(cp))
        elseif utf8 and utf8.char then
          table.insert(out, utf8.char(cp))
        else
          table.insert(out, "\\u" .. hex)
        end
        pos = bs + 6
      else
        table.insert(out, "u")
        pos = bs + 2
      end
    else
      table.insert(out, escapes[next_char] or next_char)
      pos = bs + 2
    end
  end
  return table.concat(out)
end

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
    local ok = file:write(self:toJSON())
    file:close()
    return ok ~= nil
  end
  return false
end

function PluginDB:parseJSON(str)
  -- Parse the flat schema written by toJSON. Unknown/corrupt data is rejected
  -- rather than silently replacing a saved database with an empty one.
  if type(str) ~= "string" or not str:match('"plugins"%s*:%s*%[') then return nil end
  local db = {plugins = {}, last_scan = tonumber(str:match('"last_scan"%s*:%s*(%d+)')) or 0}
  for object in str:gmatch('{%s*\n%s*"name".-\n    }') do
    local fields = {}
    for line in object:gmatch("[^\r\n]+") do
      local key, value = line:match('^%s*"([^"]+)"%s*:%s*"(.*)"%s*,?%s*$')
      if key then fields[key] = json_unescape(value) end
    end
    if fields.name and fields.path and fields.format then
      fields.param_count = tonumber(object:match('"param_count"%s*:%s*(%d+)')) or 0
      table.insert(db.plugins, fields)
    end
  end
  return db
end

function PluginDB:toJSON()
  local plugin_entries = {}
  for _, plugin in ipairs(self.plugins) do
    local entry = table.concat({
      "    {",
      '      "name": ' .. json_string(plugin.name) .. ",",
      '      "path": ' .. json_string(plugin.path) .. ",",
      '      "format": ' .. json_string(plugin.format) .. ",",
      '      "vendor": ' .. json_string(plugin.vendor or "Unknown") .. ",",
      '      "category": ' .. json_string(plugin.category or "Effect") .. ",",
      '      "param_count": ' .. tostring(tonumber(plugin.param_count) or 0),
      "    }",
    }, "\n")
    table.insert(plugin_entries, entry)
  end
  return "{\n" ..
    '  "last_scan": ' .. tostring(tonumber(self.last_scan) or os.time()) .. ",\n" ..
    '  "plugins": [\n' .. table.concat(plugin_entries, ",\n") .. "\n  ]\n}"
end

function PluginDB:addPlugin(plugin_info)
  table.insert(self.plugins, plugin_info)
end

function PluginDB:findByName(name)
  for _, plugin in ipairs(self.plugins) do
    if plugin.name:lower():find(name:lower(), 1, true) then
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

  -- Enumerating a missing directory simply returns no files in REAPER.
  -- Recursively scan directory
  local files = self:getFilesInDirectory(path)
  self.total_files = self.total_files + #files

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

function PluginScanner:getFilesInDirectory(path, depth)
  depth = depth or 0
  if depth > 16 then return {} end
  local files = {}
  local formats = {[".dll"] = true, [".so"] = true, [".vst"] = true, [".vst3"] = true,
    [".component"] = true, [".clap"] = true, [".lv2"] = true}
  local bundles = {[".vst"] = true, [".vst3"] = true, [".component"] = true, [".clap"] = true, [".lv2"] = true}

  local i = 0
  while true do
    local filename = reaper.EnumerateFiles(path, i)
    if not filename then break end
    local ext = filename:lower():match("(%.[^%.]+)$")
    if ext and formats[ext] then table.insert(files, path .. "/" .. filename) end
    i = i + 1
  end

  i = 0
  while true do
    local dirname = reaper.EnumerateSubdirectories(path, i)
    if not dirname then break end
    local full_path = path .. "/" .. dirname
    local ext = dirname:lower():match("(%.[^%.]+)$")
    if ext and bundles[ext] then
      table.insert(files, full_path)
    else
      for _, file in ipairs(self:getFilesInDirectory(full_path, depth + 1)) do table.insert(files, file) end
    end
    i = i + 1
  end
  return files
end

function PluginScanner:analyzePlugin(file_path)
  if type(file_path) ~= "string" then return nil end
  local filename = file_path:match("([^/\\]+)$")
  if not filename then return nil end
  local ext = (filename:match("%.([^%.]+)$") or ""):lower()

  local format = "Unknown"
  if ext == "dll" or ext == "vst" or ext == "so" then
    format = "VST2"
  elseif ext == "vst3" then
    format = "VST3"
  elseif ext == "component" then
    format = "AU"
  elseif ext == "clap" then
    format = "CLAP"
  elseif ext == "lv2" then
    format = "LV2"
  end

  -- Extract plugin name (remove only the final extension and common prefixes)
  -- "Plugin v2.5.vst3" -> "Plugin v2.5", not "Plugin v2".
  local name = filename:match("^(.*)%.[^%.]+$") or filename
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
    if path:lower():find(vendor:lower(), 1, true) then
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
    if name_lower:find(cat.pattern, 1, true) then
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
  local _, preset_count = reaper.TrackFX_GetPresetIndex(self.track, self.fx_index)
  return preset_count or 0
end

function PluginInstance:loadPreset(preset_index)
  reaper.TrackFX_SetPresetByIndex(self.track, self.fx_index, preset_index)
end

function PluginInstance:loadPresetByName(preset_name)
  return reaper.TrackFX_SetPreset(self.track, self.fx_index, preset_name)
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
  -- VST state chunks are exposed under this named parameter by REAPER.
  local ok, chunk = reaper.TrackFX_GetNamedConfigParm(self.track, self.fx_index, "vst_chunk")
  return ok and chunk or nil
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
  reaper.ShowConsoleMsg("Plugin: " .. tostring(self:getName() or "") .. "\n")
  reaper.ShowConsoleMsg("Parameters: " .. tostring(self:getParamCount()) .. "\n")
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

-- NOTE: automateParameter/createSweep mutate envelopes but do NOT open an undo
-- block; callers must wrap them in Undo_BeginBlock/Undo_EndBlock (see
-- automateSelectedPlugin) so the edit is a single balanced undo step.
function PluginAutomation:automateParameter(param_index, start_value, end_value, duration_beats)
  local track = self.plugin.track
  local param_env = reaper.GetFXEnvelope(track, self.plugin.fx_index, param_index, true)

  if not param_env then
    return false
  end

  local current_time = reaper.GetCursorPosition()
  local tempo = reaper.Master_GetTempo()
  if not tempo or tempo <= 0 then
    return false
  end
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

local function scanAllPlugins()
  local scanner = PluginScanner:new()
  scanner:performFullScan()
end

local function listAllPluginsOnTrack()
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

local function automateSelectedPlugin()
  local touched, track_number, fx_index, param_index = reaper.GetLastTouchedFX()
  if not touched or fx_index < 0 or param_index < 0 then
    reaper.ShowMessageBox("No plugin parameter touched", "Error", 0)
    return false
  end
  -- In REAPER, Take FX sets high 16 bits of track_number ((track_number >> 16) ~= 0),
  -- record-input FX sets bit 0x1000000 on fx_index, while 0x2000000 is REAPER 7 FX Containers.
  if (track_number >> 16) ~= 0 or (fx_index & 0x1000000) ~= 0 then
    reaper.ShowMessageBox(
      "Record-input FX and take FX are not supported for track FX envelope automation.",
      "Unsupported FX Type", 0)
    return false
  end
  local track = track_number == 0 and reaper.GetMasterTrack(0) or reaper.GetTrack(0, track_number - 1)
  if not track then
    reaper.ShowMessageBox("The last touched track no longer exists", "Error", 0)
    return false
  end

  local plugin = PluginInstance:new(track, fx_index)
  local fx_name = plugin:getName()
  local param_name = plugin:getParamName(param_index)
  local answer = reaper.ShowMessageBox(
    string.format("Create a 4-second exponential automation sweep on:\n%s — %s?",
      tostring(fx_name ~= "" and fx_name or ("FX #" .. fx_index)),
      tostring(param_name ~= "" and param_name or ("Param #" .. param_index))),
    "Automate Parameter", 1)
  if answer ~= 1 then
    return false
  end

  local min_val, max_val = 0.0, 1.0
  if reaper.TrackFX_GetParam then
    local _, p_min, p_max = reaper.TrackFX_GetParam(track, fx_index, param_index)
    if type(p_min) == "number" and type(p_max) == "number" and p_min ~= p_max then
      min_val, max_val = p_min, p_max
    end
  end

  local automation = PluginAutomation:new(plugin)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local call_ok, sweep_ok = pcall(function()
    return automation:createSweep(param_index, min_val, max_val, 4.0, "exponential")
  end)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("SGM: Automate FX Parameter", -1)
  reaper.UpdateArrange()

  if not call_ok then
    reaper.ShowMessageBox("Automation failed:\n" .. tostring(sweep_ok), "Error", 0)
    return false
  end
  reaper.ShowMessageBox(
    sweep_ok and "Automation created!" or "Could not create the parameter envelope",
    sweep_ok and "Success" or "Error", 0)
  return sweep_ok
end

-- ===================================
-- MENU
-- ===================================

local function showMenu()
  local menu = ""
  menu = menu .. "Scan All Plugins|"
  menu = menu .. "List Plugins on Selected Track|"
  menu = menu .. "Automate Last Touched Parameter|"
  menu = menu .. "Export Plugin Database"

  if gfx.init then gfx.init("", 0, 0, 0, 0, 0) end
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local result = gfx.showmenu(menu)
  if gfx.quit then gfx.quit() end

  if result == 1 then
    scanAllPlugins()
  elseif result == 2 then
    listAllPluginsOnTrack()
  elseif result == 3 then
    automateSelectedPlugin()
  elseif result == 4 then
    local scanner = PluginScanner:new()
    local saved = scanner.db:save()
    if saved then
      reaper.ShowMessageBox("Database saved to:\n" .. PLUGIN_DB_FILE, "Success", 0)
    else
      reaper.ShowMessageBox("Could not save database to:\n" .. PLUGIN_DB_FILE, "Error", 0)
    end
  end
end

_G.SGMPluginWrapper = {
  PluginDB = PluginDB,
  PluginScanner = PluginScanner,
  PluginInstance = PluginInstance,
  PluginAutomation = PluginAutomation,
  automateSelectedPlugin = automateSelectedPlugin,
  getScanPaths = getScanPaths,
}

-- Run
showMenu()
