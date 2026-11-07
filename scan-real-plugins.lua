-- Filesystem Plugin Scanner
-- @description Scans OS plugin paths and exports matching Rule of 30 plugins to rule-of-30-plugins.json
-- @author Scott Mills
-- @version 2.0

local FORMAT_BY_EXTENSION = {
  [".dll"] = "vst2", [".vst"] = "vst2", [".vst3"] = "vst3",
  [".component"] = "au", [".clap"] = "clap", [".lv2"] = "lv2",
}
local BUNDLE_EXTENSIONS = {[".vst"] = true, [".vst3"] = true, [".component"] = true, [".lv2"] = true}

local function join_path(left, right)
  return left:gsub("[/\\]+$", "") .. "/" .. right
end

local function extension(filename)
  return filename:lower():match("(%.[^%.]+)$") or ""
end

local function json_string(value)
  local escaped = tostring(value or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
  escaped = escaped:gsub("%c", function(char)
    local replacements = {["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}
    return replacements[char] or string.format("\\u%04X", string.byte(char))
  end)
  return '"' .. escaped .. '"'
end

local function get_scan_paths()
  local paths = {}
  local function add(path) if path and path ~= "" then table.insert(paths, path) end end
  local os_type = reaper.GetOS()
  if os_type == "Win32" or os_type == "Win64" then
    add("C:/Program Files/VSTPlugins")
    add("C:/Program Files (x86)/VSTPlugins")
    add("C:/Program Files/Steinberg/VSTPlugins")
    add("C:/Program Files (x86)/Steinberg/VSTPlugins")
    add("C:/Program Files/Common Files/VST3")
    add("C:/Program Files/Common Files/CLAP")
    add("C:/Program Files (x86)/Waves/Plug-Ins V16")
    add("C:/Program Files/Waves/Plug-Ins V16")
    local localappdata = os.getenv("LOCALAPPDATA")
    if localappdata then add(join_path(localappdata, "Programs/Common/VST3")) end
  elseif os_type:match("^OSX") then
    add("/Library/Audio/Plug-Ins/VST")
    add("/Library/Audio/Plug-Ins/VST3")
    add("/Library/Audio/Plug-Ins/Components")
    add("/Library/Audio/Plug-Ins/CLAP")
    add("/Library/Audio/Plug-Ins/LV2")
    local home = os.getenv("HOME")
    if home then
      for _, folder in ipairs({"VST", "VST3", "Components", "CLAP", "LV2"}) do
        add(join_path(home, "Library/Audio/Plug-Ins/" .. folder))
      end
    end
  else
    for _, path in ipairs({"/usr/lib/vst", "/usr/lib/lxvst", "/usr/lib/vst3", "/usr/lib/clap", "/usr/lib/lv2", "/usr/local/lib/vst", "/usr/local/lib/vst3", "/usr/local/lib/clap", "/usr/local/lib/lv2"}) do add(path) end
    local home = os.getenv("HOME")
    if home then
      for _, folder in ipairs({".vst", ".lxvst", ".vst3", ".clap", ".lv2"}) do add(join_path(home, folder)) end
    end
  end
  return paths
end

local function scanDirectory(path)
  local plugins = {}
  local index = 0
  while true do
    local filename = reaper.EnumerateFiles(path, index)
    if not filename then break end
    local ext = extension(filename)
    local plugin_format = FORMAT_BY_EXTENSION[ext]
    if plugin_format then
      table.insert(plugins, {
        name = filename:sub(1, #filename - #ext),
        path = join_path(path, filename),
        type = plugin_format,
      })
    end
    index = index + 1
  end

  index = 0
  while true do
    local dirname = reaper.EnumerateSubdirectories(path, index)
    if not dirname then break end
    local full_path = join_path(path, dirname)
    local ext = extension(dirname)
    local plugin_format = FORMAT_BY_EXTENSION[ext]
    if plugin_format and BUNDLE_EXTENSIONS[ext] then
      table.insert(plugins, {
        name = dirname:sub(1, #dirname - #ext),
        path = full_path,
        type = plugin_format,
      })
    else
      for _, plugin in ipairs(scanDirectory(full_path)) do table.insert(plugins, plugin) end
    end
    index = index + 1
  end
  return plugins
end

local KEY_PATTERNS = {
  waves_ssl_comp = {"ssl", "comp"},
  waves_cla76 = {"cla", "76"},
  waves_h_delay = {"h%-delay"},
  waves_h_eq = {"h%-eq"},
  waves_j37_tape = {"j37"},
  waves_ovox = {"ovox"},
  waves_tune_realtime = {"tune", "real"},
  izotope_neutron = {"neutron"},
  izotope_ozone = {"ozone"},
  izotope_trash = {"trash"},
  izotope_nectar = {"nectar"},
  izotope_stutter_edit = {"stutter"},
  fabfilter_proq3 = {"pro%-q"},
  fabfilter_prol2 = {"pro%-l"},
  fabfilter_saturn = {"saturn"},
  neural_gojira = {"gojira"},
  neural_fortin = {"fortin"},
  neural_nameless = {"nameless"},
  landr_mastering = {"landr"},
  audified_gk = {"gk", "amplifikation"},
}

local function matches(name, patterns)
  local lower = name:lower()
  for _, pattern in ipairs(patterns) do
    if not lower:find(pattern) then return false end
  end
  return true
end

local function findKeyPlugins(all_plugins)
  local key_plugins = {}
  for _, plugin in ipairs(all_plugins) do
    for key, patterns in pairs(KEY_PATTERNS) do
      if not key_plugins[key] and matches(plugin.name, patterns) then
        key_plugins[key] = {name = plugin.name, path = plugin.path, type = plugin.type}
      end
    end
  end
  return key_plugins
end

local function exportJSON(output_path, all_plugins, key_plugins, elapsed)
  local lines = {"{", '  "scan_date": ' .. json_string(os.date("%Y-%m-%d %H:%M:%S")) .. ",", '  "scan_seconds": ' .. string.format("%.3f", elapsed) .. ",", '  "total_plugins": ' .. #all_plugins .. ",", '  "key_plugins": {'}
  local keys = {}
  for key in pairs(key_plugins) do table.insert(keys, key) end
  table.sort(keys)
  for index, key in ipairs(keys) do
    local plugin = key_plugins[key]
    table.insert(lines, "    " .. json_string(key) .. ": {" ..
      '"name": ' .. json_string(plugin.name) ..
      ', "path": ' .. json_string(plugin.path) ..
      ', "type": ' .. json_string(plugin.type) .. "}" .. (index < #keys and "," or ""))
  end
  table.insert(lines, "  },")
  table.insert(lines, '  "plugins": [')
  for index, plugin in ipairs(all_plugins) do
    table.insert(lines, "    {" ..
      '"name": ' .. json_string(plugin.name) ..
      ', "path": ' .. json_string(plugin.path) ..
      ', "type": ' .. json_string(plugin.type) .. "}" .. (index < #all_plugins and "," or ""))
  end
  table.insert(lines, "  ]")
  table.insert(lines, "}")

  local file, open_error = io.open(output_path, "w")
  if not file then return false, open_error end
  local ok, write_error = file:write(table.concat(lines, "\n") .. "\n")
  file:close()
  return ok ~= nil, write_error
end

local function main()
  reaper.ClearConsole()
  reaper.ShowConsoleMsg("=== FILESYSTEM PLUGIN SCAN ===\n\n")
  local start_time = reaper.time_precise()
  local all_plugins, seen = {}, {}
  local paths = get_scan_paths()
  for _, path in ipairs(paths) do
    reaper.ShowConsoleMsg("Scanning: " .. path .. "\n")
    for _, plugin in ipairs(scanDirectory(path)) do
      local identity = plugin.path:lower()
      if not seen[identity] then
        seen[identity] = true
        table.insert(all_plugins, plugin)
      end
    end
  end
  table.sort(all_plugins, function(a, b) return a.path:lower() < b.path:lower() end)
  local key_plugins = findKeyPlugins(all_plugins)
  local key_count = 0
  for _ in pairs(key_plugins) do key_count = key_count + 1 end

  local elapsed = reaper.time_precise() - start_time
  reaper.ShowConsoleMsg(string.format("\nFound %d plugins (%d Rule of 30 matches) in %.2fs\n", #all_plugins, key_count, elapsed))
  if #all_plugins == 0 then
    reaper.ShowMessageBox(
      "No supported plugins were found in the standard paths.\n\n" ..
      "Use list-all-available-plugins.lua to inspect REAPER's configured plugin cache instead.",
      "Plugin Scan — Nothing Found", 0)
  end

  local output_path = join_path(reaper.GetResourcePath(), "rule-of-30-plugins.json")
  local ok, export_error = exportJSON(output_path, all_plugins, key_plugins, elapsed)
  if ok then
    reaper.ShowConsoleMsg("Plugin database exported to: " .. output_path .. "\n")
  else
    reaper.ShowConsoleMsg("ERROR: Could not export plugin database: " .. tostring(export_error) .. "\n")
  end
  return ok
end

_G.SGMRealPluginScanner = {
  scanDirectory = scanDirectory,
  findKeyPlugins = findKeyPlugins,
  exportJSON = exportJSON,
  json_string = json_string,
}
main()
