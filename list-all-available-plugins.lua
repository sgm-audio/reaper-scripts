-- REAPER Plugin Inventory
-- @description Lists cached VST/VST3/CLAP/AU/LV2 and resource-path JSFX plugins; exports plugin_inventory.json
-- @author Scott Mills
-- @version 2.0
-- Uses REAPER's plugin cache and JSFX resource directory; SWS is not required.

local PluginScanner = {}
PluginScanner.__index = PluginScanner

local FORMATS = {"vst", "vst3", "clap", "au", "lv2", "js"}

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function path_join(left, right)
  return left:gsub("[/\\]+$", "") .. "/" .. right
end

local function json_string(value)
  local escaped = tostring(value or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
  escaped = escaped:gsub("%c", function(char)
    local replacements = {["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}
    return replacements[char] or string.format("\\u%04X", string.byte(char))
  end)
  return '"' .. escaped .. '"'
end

local function plugin_type_from_path(path, fallback)
  local lower = path:lower()
  if lower:match("%.vst3$") then return "vst3" end
  if lower:match("%.clap$") then return "clap" end
  if lower:match("%.component$") then return "au" end
  if lower:match("%.lv2$") then return "lv2" end
  return fallback or "vst"
end

function PluginScanner:new()
  return setmetatable({}, self)
end

function PluginScanner:detectCategory(name)
  local n = name:lower()
  if n:find("equalizer", 1, true) or n:match("%f[%w]eq%f[%W]") or n:find("pro%-q") then return "EQ"
  elseif n:find("comp", 1, true) or n:find("limit", 1, true) or n:find("pressor", 1, true) then return "Dynamics"
  elseif n:find("verb", 1, true) or n:find("echo", 1, true) or n:find("delay", 1, true) then return "Time"
  elseif n:find("dist", 1, true) or n:find("sat", 1, true) or n:find("drive", 1, true) or n:find("fuzz", 1, true) or n:find("amp", 1, true) then return "Drive/Amp"
  elseif n:find("synth", 1, true) or n:find("instrument", 1, true) or n:find("kontakt", 1, true) or n:find("piano", 1, true) then return "Instrument"
  elseif n:find("gate", 1, true) or n:find("expander", 1, true) then return "Gate"
  elseif n:find("pitch", 1, true) or n:find("tune", 1, true) or n:find("shift", 1, true) then return "Pitch"
  else return "Utility" end
end

function PluginScanner:scanDirectory(dir_path, prefix)
  local plugins = {}
  local index = 0
  while true do
    local filename = reaper.EnumerateFiles(dir_path, index)
    if not filename then break end
    local lower = filename:lower()
    local is_include = lower:match("%.jsfx%-inc$") ~= nil
    local is_jsfx = lower:match("%.jsfx$") or lower:match("%.js$") or not filename:match("%.")
    if not is_include and is_jsfx and not filename:match("^%.") then
      table.insert(plugins, {
        name = prefix .. filename:gsub("%.[jJ][sS][fF]?[xX]?$", ""),
        path = path_join(dir_path, filename),
        type = "js",
      })
    end
    index = index + 1
  end

  index = 0
  while true do
    local subdir = reaper.EnumerateSubdirectories(dir_path, index)
    if not subdir then break end
    local nested = self:scanDirectory(path_join(dir_path, subdir), prefix .. subdir .. "/")
    for _, plugin in ipairs(nested) do table.insert(plugins, plugin) end
    index = index + 1
  end
  return plugins
end

function PluginScanner:parseCache(ini_path, fallback_type)
  local found = {}
  local file = io.open(ini_path, "r")
  if not file then return found end
  for line in file:lines() do
    line = trim(line)
    if line ~= "" and not line:match("^%[") then
      local filename, data = line:match("^(.-)=(.*)$")
      if filename and data then
        -- Current cache format: filename=UID,project_id,"Name (Developer)".
        local uid, _, remainder = data:match("^([^,]*),([^,]*),(.*)$")
        local name = remainder and trim(remainder) or nil
        if name then
          name = name:gsub('^"(.*)"$', "%1"):gsub('""', '"')
          local plugin_type = plugin_type_from_path(filename, fallback_type)
          table.insert(found, {
            name = name,
            path = filename,
            uid = trim(uid or ""),
            type = plugin_type,
          })
        end
      end
    end
  end
  file:close()
  return found
end

-- Backwards-compatible name for callers of the old VST-only parser.
function PluginScanner:parseVSTIni(ini_path)
  local entries = self:parseCache(ini_path, "vst")
  local vst, vst3 = {}, {}
  for _, plugin in ipairs(entries) do
    table.insert(plugin.type == "vst3" and vst3 or vst, plugin)
  end
  return vst, vst3
end

function PluginScanner:scanFXBrowser()
  local plugins = {all = {}, by_type = {}, by_category = {}, total_count = 0}
  for _, format in ipairs(FORMATS) do plugins.by_type[format] = {} end

  local resource_path = reaper.GetResourcePath()
  for _, plugin in ipairs(self:scanDirectory(path_join(resource_path, "Effects"), "")) do
    table.insert(plugins.by_type.js, plugin)
  end

  local caches = {
    {"reaper-vstplugins64.ini", "vst"},
    {"reaper-vstplugins.ini", "vst"},
    {"reaper-clap-plugins64.ini", "clap"},
    {"reaper-au-plugins64.ini", "au"},
    {"reaper-lv2-plugins64.ini", "lv2"},
  }
  local seen = {}
  for _, cache in ipairs(caches) do
    for _, plugin in ipairs(self:parseCache(path_join(resource_path, cache[1]), cache[2])) do
      local identity = plugin.type .. "\0" .. plugin.path:lower()
      if not seen[identity] then
        seen[identity] = true
        table.insert(plugins.by_type[plugin.type] or plugins.by_type.vst, plugin)
      end
    end
  end

  for _, format in ipairs(FORMATS) do
    table.sort(plugins.by_type[format], function(a, b) return a.name:lower() < b.name:lower() end)
    for _, plugin in ipairs(plugins.by_type[format]) do
      plugin.category = self:detectCategory(plugin.name)
      table.insert(plugins.all, plugin)
      plugins.by_category[plugin.category] = plugins.by_category[plugin.category] or {}
      table.insert(plugins.by_category[plugin.category], plugin)
      plugins.total_count = plugins.total_count + 1
    end
  end
  return plugins
end

function PluginScanner:scanAllPlugins()
  local ok, plugins = pcall(function() return self:scanFXBrowser() end)
  if not ok then
    reaper.ShowConsoleMsg("Error during plugin scan: " .. tostring(plugins) .. "\n")
    return nil, plugins
  end
  return plugins
end

function PluginScanner:exportToJSON(plugins, output_path)
  local lines = {"{", '  "total_count": ' .. plugins.total_count .. ",", '  "scan_date": ' .. json_string(os.date("%Y-%m-%d %H:%M:%S")) .. ",", '  "by_type": {'}
  for format_index, format in ipairs(FORMATS) do
    table.insert(lines, "    " .. json_string(format) .. ": [")
    local list = plugins.by_type[format] or {}
    for index, plugin in ipairs(list) do
      local entry = "      {" ..
        '"name": ' .. json_string(plugin.name) ..
        ', "path": ' .. json_string(plugin.path) ..
        ', "type": ' .. json_string(plugin.type) ..
        ', "category": ' .. json_string(plugin.category or self:detectCategory(plugin.name)) .. "}"
      table.insert(lines, entry .. (index < #list and "," or ""))
    end
    table.insert(lines, "    ]" .. (format_index < #FORMATS and "," or ""))
  end
  table.insert(lines, "  },")
  table.insert(lines, '  "by_category": {')

  local categories = {}
  for category in pairs(plugins.by_category) do table.insert(categories, category) end
  table.sort(categories)
  for category_index, category in ipairs(categories) do
    table.insert(lines, "    " .. json_string(category) .. ": [")
    local list = plugins.by_category[category]
    for index, plugin in ipairs(list) do
      table.insert(lines, "      " .. json_string(plugin.name) .. (index < #list and "," or ""))
    end
    table.insert(lines, "    ]" .. (category_index < #categories and "," or ""))
  end
  table.insert(lines, "  }")
  table.insert(lines, "}")

  local file, open_error = io.open(output_path, "w")
  if not file then return false, open_error end
  local ok, write_error = file:write(table.concat(lines, "\n") .. "\n")
  file:close()
  if not ok then return false, write_error end
  return true
end

function PluginScanner:exportToConsole(plugins)
  reaper.ClearConsole()
  reaper.ShowConsoleMsg("=== REAPER PLUGIN INVENTORY ===\n\n")
  reaper.ShowConsoleMsg("Total Plugins: " .. plugins.total_count .. "\n")
  reaper.ShowConsoleMsg("Scan Date: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
  for _, format in ipairs(FORMATS) do
    local list = plugins.by_type[format]
    if #list > 0 then
      reaper.ShowConsoleMsg("--- " .. format:upper() .. " Plugins (" .. #list .. ") ---\n")
      for index, plugin in ipairs(list) do
        reaper.ShowConsoleMsg(string.format("  %3d. %s\n", index, plugin.name))
      end
      reaper.ShowConsoleMsg("\n")
    end
  end
end

function main()
  local scanner = PluginScanner:new()
  local plugins, scan_error = scanner:scanAllPlugins()
  if not plugins then
    reaper.ShowMessageBox("Plugin scan failed:\n" .. tostring(scan_error), "Plugin Inventory", 0)
    return false
  end
  scanner:exportToConsole(plugins)
  local output_path = path_join(reaper.GetResourcePath(), "plugin_inventory.json")
  local ok, export_error = scanner:exportToJSON(plugins, output_path)
  if ok then
    reaper.ShowConsoleMsg("\nInventory exported to: " .. output_path .. "\n")
  else
    reaper.ShowConsoleMsg("\nFailed to export inventory: " .. tostring(export_error) .. "\n")
  end
  return ok
end

_G.SGMPluginInventory = PluginScanner
main()
