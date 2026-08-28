-- List All Available Reaper Plugins
-- Scans and exports all VST, VST3, JS, and AU plugins available in Reaper
-- Version 1.0

local PluginScanner = {}

function PluginScanner:new()
  local obj = {}
  setmetatable(obj, self)
  self.__index = self
  return obj
end

function PluginScanner:scanAllPlugins()
  local ok, plugins = pcall(function() return self:scanFXBrowser() end)
  if not ok then
    reaper.ShowConsoleMsg("Error during plugin scan: " .. tostring(plugins) .. "\n")
    return {total_count = 0, by_type = {}, by_category = {}}
  end
  return plugins
end

function PluginScanner:scanFXBrowser()
  local plugins = {
    all = {},
    by_type = {
      vst = {},
      vst3 = {},
      js = {},
      clap = {},
      au = {},
      lv2 = {}
    },
    by_category = {},
    total_count = 0
  }

  -- Use REAPER's plugin enumeration
  -- Note: This requires SWS extension for full functionality
  -- Fallback method using track FX enumeration

  -- Scan JS plugins (ReaPlugs) from resource path
  local resource_path = reaper.GetResourcePath()
  local js_path = resource_path .. "/Effects"

  plugins.by_type.js = self:scanDirectory(js_path, "")

  -- For VST/VST3, we need to read from REAPER's FX cache
  -- Located at: reaper-vstplugins64.ini (Windows) or similar

  local ini_path = resource_path .. "/reaper-vstplugins64.ini"
  if reaper.file_exists(ini_path) then
    plugins.by_type.vst, plugins.by_type.vst3 = self:parseVSTIni(ini_path)
  end

  -- Count totals
  for ptype, plist in pairs(plugins.by_type) do
    plugins.total_count = plugins.total_count + #plist
  end

  return plugins
end

function PluginScanner:detectCategory(name)
  local n = name:lower()
  if n:find("eq") or n:find("equalizer") then return "EQ"
  elseif n:find("comp") or n:find("limit") or n:find("pressor") then return "Dynamics"
  elseif n:find("verb") or n:find("reverb") or n:find("echo") or n:find("delay") then return "Time"
  elseif n:find("dist") or n:find("sat") or n:find("drive") or n:find("fuzz") or n:find("amp") or n:find("neural dsp") then return "Drive/Amp"
  elseif n:find("synth") or n:find("instrument") or n:find("kontakt") or n:find("piano") then return "Instrument"
  elseif n:find("gate") or n:find("expander") then return "Gate"
  elseif n:find("pitch") or n:find("tune") or n:find("shift") then return "Pitch"
  else return "Utility" end
end

function PluginScanner:scanDirectory(dir_path, prefix)
  local plugins = {}

  local i = 0
  repeat
    local file = reaper.EnumerateFiles(dir_path, i)
    if file then
      if file:match("%.jsfx$") or file:match("%.jsfx%-inc$") then
        local plugin_name = prefix .. file:gsub("%.jsfx$", ""):gsub("%.jsfx%-inc$", "")
        table.insert(plugins, {
          name = plugin_name,
          path = dir_path .. "/" .. file,
          type = "JS"
        })
      end
    end
    i = i + 1
  until not file

  -- Scan subdirectories
  i = 0
  repeat
    local subdir = reaper.EnumerateSubdirectories(dir_path, i)
    if subdir then
      local subpath = dir_path .. "/" .. subdir
      local sub_prefix = prefix .. subdir .. "/"
      local sub_plugins = self:scanDirectory(subpath, sub_prefix)
      for _, plugin in ipairs(sub_plugins) do
        table.insert(plugins, plugin)
      end
    end
    i = i + 1
  until not subdir

  return plugins
end

function PluginScanner:parseVSTIni(ini_path)
  local vst_plugins = {}
  local vst3_plugins = {}

  local file = io.open(ini_path, "r")
  if not file then
    return vst_plugins, vst3_plugins
  end

  for line in file:lines() do
    -- Parse VST entries
    -- Format: <NAME>file=<path>
    if line:match("^[^=]+file=") then
      local name = line:match("^([^=]+)file=")
      local path = line:match("file=(.+)$")

      if name and path then
        name = name:gsub("<", ""):gsub(">", ""):gsub("%s+$", "")

        local plugin_type = "VST"
        if path:match("%.vst3") or path:match("%.vst3/") then
          plugin_type = "VST3"
        end

        local plugin_entry = {
          name = name,
          path = path,
          type = plugin_type,
          category = self:detectCategory(name)
        }

        if not plugins.by_category[plugin_entry.category] then
          plugins.by_category[plugin_entry.category] = {}
        end
        table.insert(plugins.by_category[plugin_entry.category], plugin_entry)

        if plugin_type == "VST3" then
          table.insert(vst3_plugins, plugin_entry)
        else
          table.insert(vst_plugins, plugin_entry)
        end
      end
    end
  end

  file:close()

  return vst_plugins, vst3_plugins
end

function PluginScanner:exportToJSON(plugins, output_path)
  local json_lines = {}

  table.insert(json_lines, "{")
  table.insert(json_lines, '  "total_count": ' .. plugins.total_count .. ',')
  table.insert(json_lines, '  "scan_date": "' .. os.date("%Y-%m-%d %H:%M:%S") .. '",')
  table.insert(json_lines, '  "by_type": {')

  local type_count = 0
  local type_total = 0
  for _ in pairs(plugins.by_type) do type_total = type_total + 1 end

  for ptype, plist in pairs(plugins.by_type) do
    type_count = type_count + 1
    table.insert(json_lines, '    "' .. ptype .. '": [')

    for i, plugin in ipairs(plist) do
      local comma = i < #plist and "," or ""
      local name_escaped = plugin.name:gsub('"', '\\"'):gsub('\\', '\\\\')
      local path_escaped = plugin.path:gsub('"', '\\"'):gsub('\\', '\\\\')
      table.insert(json_lines, '      {"name": "' .. name_escaped .. '", "path": "' .. path_escaped .. '"}' .. comma)
    end

    local type_comma = type_count < type_total and "," or ""
    table.insert(json_lines, '    ]' .. type_comma)
  end

  table.insert(json_lines, '  },')
  table.insert(json_lines, '  "by_category": {')

  local cat_count = 0
  local cat_total = 0
  for _ in pairs(plugins.by_category) do cat_total = cat_total + 1 end

  for cat, plist in pairs(plugins.by_category) do
    cat_count = cat_count + 1
    table.insert(json_lines, '    "' .. cat .. '": [')
    for i, plugin in ipairs(plist) do
      local comma = i < #plist and "," or ""
      local name_escaped = plugin.name:gsub('"', '\\"'):gsub('\\', '\\\\')
      table.insert(json_lines, '      {"name": "' .. name_escaped .. '", "type": "' .. plugin.type .. '"}' .. comma)
    end
    local cat_comma = cat_count < cat_total and "," or ""
    table.insert(json_lines, '    ]' .. cat_comma)
  end

  table.insert(json_lines, '  }')
  table.insert(json_lines, "}")

  local json_content = table.concat(json_lines, "\n")

  local file = io.open(output_path, "w")
  if file then
    file:write(json_content)
    file:close()
    return true
  end

  return false
end

function PluginScanner:exportToConsole(plugins)
  reaper.ClearConsole()
  reaper.ShowConsoleMsg("=== REAPER PLUGIN INVENTORY ===\n\n")
  reaper.ShowConsoleMsg("Total Plugins: " .. plugins.total_count .. "\n")
  reaper.ShowConsoleMsg("Scan Date: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")

  for ptype, plist in pairs(plugins.by_type) do
    if #plist > 0 then
      reaper.ShowConsoleMsg("--- " .. ptype:upper() .. " Plugins (" .. #plist .. ") ---\n")
      for i, plugin in ipairs(plist) do
        reaper.ShowConsoleMsg(string.format("  %3d. %s\n", i, plugin.name))
      end
      reaper.ShowConsoleMsg("\n")
    end
  end

  reaper.ShowConsoleMsg("=== END INVENTORY ===\n")
end

-- Main execution
function main()
  local scanner = PluginScanner:new()

  reaper.ShowConsoleMsg("Scanning plugins...\n")
  local plugins = scanner:scanFXBrowser()

  -- Display in console
  scanner:exportToConsole(plugins)

  -- Export to JSON
  local resource_path = reaper.GetResourcePath()
  local output_path = resource_path .. "/plugin_inventory.json"

  if scanner:exportToJSON(plugins, output_path) then
    reaper.ShowConsoleMsg("\nInventory exported to: " .. output_path .. "\n")
  else
    reaper.ShowConsoleMsg("\nFailed to export inventory file\n")
  end
end

-- Run the scanner
main()
