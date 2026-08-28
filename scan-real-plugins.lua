-- REAL PLUGIN SCANNER
-- Scans actual VST paths from user's system
-- Uses REAL paths: Waves V16, Plugin Alliance, Audified, LANDR, etc.
-- Version 1.0

reaper.ClearConsole()
reaper.ShowConsoleMsg("=== SCANNING REAL VST PLUGINS ===\n\n")

-- ===================================
-- USER'S ACTUAL VST PATHS
-- ===================================

local VST_PATHS = {
  -- VST2 Paths
  "C:\\Program Files\\VSTPlugIns",
  "C:\\Program Files (x86)\\VSTPlugIns",
  "C:\\Program Files (x86)\\Steinberg\\VSTPlugins",
  "C:\\Program Files\\Steinberg\\VstPlugins",

  -- VST3 Paths
  "C:\\Program Files\\Common Files\\VST3",
  os.getenv("LOCALAPPDATA") .. "\\Programs\\Common\\VST3",

  -- Specific Plugin Vendors
  "C:\\Program Files (x86)\\Waves\\Plug-Ins V16",
  "C:\\Program Files\\LANDR\\Mastering Plugin PRO",
  "C:\\Program Files\\Plugin Alliance",
  "C:\\Program Files\\Audified\\GK Amplifikation 3 Pro"
}

-- ===================================
-- PLUGIN SCANNER
-- ===================================

local function scanDirectory(path, extension)
  local plugins = {}

  if not reaper.file_exists(path) then
    return plugins
  end

  local i = 0
  repeat
    local file = reaper.EnumerateFiles(path, i)
    if file then
      if file:match(extension .. "$") then
        table.insert(plugins, {
          name = file:gsub(extension .. "$", ""),
          path = path .. "\\" .. file,
          type = extension:gsub("%.", ""):upper()
        })
      end
    end
    i = i + 1
  until not file

  -- Scan subdirectories
  i = 0
  repeat
    local subdir = reaper.EnumerateSubdirectories(path, i)
    if subdir then
      local sub_plugins = scanDirectory(path .. "\\" .. subdir, extension)
      for _, plugin in ipairs(sub_plugins) do
        table.insert(plugins, plugin)
      end
    end
    i = i + 1
  until not subdir

  return plugins
end

local function scanAllPlugins()
  local all_plugins = {
    vst2 = {},
    vst3 = {},
    dll = {},
    total = 0
  }

  reaper.ShowConsoleMsg("Scanning VST directories...\n\n")

  for _, path in ipairs(VST_PATHS) do
    reaper.ShowConsoleMsg("Scanning: " .. path .. "\n")

    -- Scan for VST2 DLLs
    local vst2_plugins = scanDirectory(path, ".dll")
    for _, plugin in ipairs(vst2_plugins) do
      table.insert(all_plugins.vst2, plugin)
      all_plugins.total = all_plugins.total + 1
    end

    -- Scan for VST3
    local vst3_plugins = scanDirectory(path, ".vst3")
    for _, plugin in ipairs(vst3_plugins) do
      table.insert(all_plugins.vst3, plugin)
      all_plugins.total = all_plugins.total + 1
    end
  end

  return all_plugins
end

-- ===================================
-- PLUGIN CATEGORIZER
-- ===================================

local function categorizeProPlugin(plugin_name)
  local name_lower = plugin_name:lower()

  local categories = {
    waves_v16 = false,
    izotope = false,
    fabfilter = false,
    neural_dsp = false,
    soundtoys = false,
    plugin_alliance = false,
    landr = false,
    audified = false
  }

  -- Check vendor
  if plugin_name:find("Waves") or plugin_name:find("WV16") then
    categories.waves_v16 = true
  elseif name_lower:find("izotope") then
    categories.izotope = true
  elseif name_lower:find("fabfilter") then
    categories.fabfilter = true
  elseif name_lower:find("neural") or name_lower:find("archetype") or name_lower:find("fortin") then
    categories.neural_dsp = true
  elseif name_lower:find("soundtoys") then
    categories.soundtoys = true
  elseif name_lower:find("landr") then
    categories.landr = true
  elseif name_lower:find("audified") or name_lower:find("gk amplifikation") then
    categories.audified = true
  end

  return categories
end

-- ===================================
-- KEY PLUGIN FINDER (For Rule of 30)
-- ===================================

local function findKeyPlugins(all_plugins)
  reaper.ShowConsoleMsg("\n=== FINDING KEY PLUGINS FOR RULE OF 30 ===\n\n")

  local key_plugins = {
    -- Waves V16 (Critical)
    waves_ssl_comp = nil,
    waves_cla76 = nil,
    waves_h_delay = nil,
    waves_h_eq = nil,
    waves_j37_tape = nil,
    waves_ovox = nil,
    waves_tune_realtime = nil,

    -- iZotope (Critical)
    izotope_neutron = nil,
    izotope_ozone = nil,
    izotope_trash = nil,
    izotope_nectar = nil,
    izotope_stutter_edit = nil,

    -- FabFilter (Critical)
    fabfilter_proq3 = nil,
    fabfilter_prol2 = nil,
    fabfilter_saturn = nil,

    -- Neural DSP (Guitar Amps)
    neural_gojira = nil,
    neural_fortin = nil,

    -- Others
    landr_mastering = nil,
    audified_gk = nil
  }

  local found_count = 0

  -- Search through all plugins
  for _, plugin in ipairs(all_plugins.vst2) do
    local name_lower = plugin.name:lower()

    -- Waves
    if name_lower:find("ssl") and name_lower:find("comp") then
      key_plugins.waves_ssl_comp = plugin.path
      found_count = found_count + 1
    elseif name_lower:find("cla") and name_lower:find("76") then
      key_plugins.waves_cla76 = plugin.path
      found_count = found_count + 1
    elseif name_lower:find("h%-delay") or name_lower:find("hdelay") then
      key_plugins.waves_h_delay = plugin.path
      found_count = found_count + 1
    elseif name_lower:find("h%-eq") or name_lower:find("heq") then
      key_plugins.waves_h_eq = plugin.path
      found_count = found_count + 1
    elseif name_lower:find("j37") then
      key_plugins.waves_j37_tape = plugin.path
      found_count = found_count + 1
    elseif name_lower:find("ovox") then
      key_plugins.waves_ovox = plugin.path
      found_count = found_count + 1
    elseif name_lower:find("tune") and name_lower:find("real") then
      key_plugins.waves_tune_realtime = plugin.path
      found_count = found_count + 1
    end

    -- iZotope
    if name_lower:find("neutron") then
      key_plugins.izotope_neutron = plugin.path
      found_count = found_count + 1
    elseif name_lower:find("ozone") then
      key_plugins.izotope_ozone = plugin.path
      found_count = found_count + 1
    elseif name_lower:find("trash") then
      key_plugins.izotope_trash = plugin.path
      found_count = found_count + 1
    elseif name_lower:find("nectar") then
      key_plugins.izotope_nectar = plugin.path
      found_count = found_count + 1
    elseif name_lower:find("stutter") then
      key_plugins.izotope_stutter_edit = plugin.path
      found_count = found_count + 1
    end

    -- FabFilter
    if name_lower:find("pro%-q") or name_lower:find("proq") then
      key_plugins.fabfilter_proq3 = plugin.path
      found_count = found_count + 1
    elseif name_lower:find("pro%-l") or name_lower:find("prol") then
      key_plugins.fabfilter_prol2 = plugin.path
      found_count = found_count + 1
    elseif name_lower:find("saturn") then
      key_plugins.fabfilter_saturn = plugin.path
      found_count = found_count + 1
    end

    -- Neural DSP
    if name_lower:find("gojira") then
      key_plugins.neural_gojira = plugin.path
      found_count = found_count + 1
    elseif name_lower:find("fortin") or name_lower:find("nameless") then
      key_plugins.neural_fortin = plugin.path
      found_count = found_count + 1
    end

    -- LANDR
    if name_lower:find("landr") then
      key_plugins.landr_mastering = plugin.path
      found_count = found_count + 1
    end

    -- Audified
    if name_lower:find("gk") and name_lower:find("amplifikation") then
      key_plugins.audified_gk = plugin.path
      found_count = found_count + 1
    end
  end

  -- Check VST3 as well
  for _, plugin in ipairs(all_plugins.vst3) do
    local name_lower = plugin.name:lower()

    if name_lower:find("ozone") and not key_plugins.izotope_ozone then
      key_plugins.izotope_ozone = plugin.path
      found_count = found_count + 1
    elseif name_lower:find("neutron") and not key_plugins.izotope_neutron then
      key_plugins.izotope_neutron = plugin.path
      found_count = found_count + 1
    end
  end

  -- Display results
  reaper.ShowConsoleMsg("CRITICAL PLUGINS FOUND: " .. found_count .. "\n\n")

  reaper.ShowConsoleMsg("=== WAVES V16 ===\n")
  reaper.ShowConsoleMsg("  SSL Comp: " .. (key_plugins.waves_ssl_comp or "NOT FOUND") .. "\n")
  reaper.ShowConsoleMsg("  CLA-76: " .. (key_plugins.waves_cla76 or "NOT FOUND") .. "\n")
  reaper.ShowConsoleMsg("  H-Delay: " .. (key_plugins.waves_h_delay or "NOT FOUND") .. "\n")
  reaper.ShowConsoleMsg("  H-EQ: " .. (key_plugins.waves_h_eq or "NOT FOUND") .. "\n")
  reaper.ShowConsoleMsg("  J37 Tape: " .. (key_plugins.waves_j37_tape or "NOT FOUND") .. "\n")
  reaper.ShowConsoleMsg("  OVox: " .. (key_plugins.waves_ovox or "NOT FOUND") .. "\n")

  reaper.ShowConsoleMsg("\n=== iZotope ===\n")
  reaper.ShowConsoleMsg("  Ozone 11: " .. (key_plugins.izotope_ozone or "NOT FOUND") .. "\n")
  reaper.ShowConsoleMsg("  Neutron 4: " .. (key_plugins.izotope_neutron or "NOT FOUND") .. "\n")
  reaper.ShowConsoleMsg("  Trash 2: " .. (key_plugins.izotope_trash or "NOT FOUND") .. "\n")
  reaper.ShowConsoleMsg("  Nectar 4: " .. (key_plugins.izotope_nectar or "NOT FOUND") .. "\n")
  reaper.ShowConsoleMsg("  Stutter Edit: " .. (key_plugins.izotope_stutter_edit or "NOT FOUND") .. "\n")

  reaper.ShowConsoleMsg("\n=== FabFilter ===\n")
  reaper.ShowConsoleMsg("  Pro-Q 3: " .. (key_plugins.fabfilter_proq3 or "NOT FOUND") .. "\n")
  reaper.ShowConsoleMsg("  Pro-L 2: " .. (key_plugins.fabfilter_prol2 or "NOT FOUND") .. "\n")
  reaper.ShowConsoleMsg("  Saturn 2: " .. (key_plugins.fabfilter_saturn or "NOT FOUND") .. "\n")

  reaper.ShowConsoleMsg("\n=== Neural DSP ===\n")
  reaper.ShowConsoleMsg("  Archetype Gojira: " .. (key_plugins.neural_gojira or "NOT FOUND") .. "\n")
  reaper.ShowConsoleMsg("  Fortin Nameless: " .. (key_plugins.neural_fortin or "NOT FOUND") .. "\n")

  reaper.ShowConsoleMsg("\n=== Others ===\n")
  reaper.ShowConsoleMsg("  LANDR Mastering: " .. (key_plugins.landr_mastering or "NOT FOUND") .. "\n")
  reaper.ShowConsoleMsg("  Audified GK Amp: " .. (key_plugins.audified_gk or "NOT FOUND") .. "\n")

  return key_plugins
end

-- ===================================
-- MAIN EXECUTION
-- ===================================

local function main()
  local start_time = reaper.time_precise()

  local all_plugins = scanAllPlugins()

  reaper.ShowConsoleMsg("\n=== SCAN COMPLETE ===\n")
  reaper.ShowConsoleMsg("Total VST2: " .. #all_plugins.vst2 .. "\n")
  reaper.ShowConsoleMsg("Total VST3: " .. #all_plugins.vst3 .. "\n")
  reaper.ShowConsoleMsg("Grand Total: " .. all_plugins.total .. "\n\n")

  -- Find key plugins for Rule of 30
  local key_plugins = findKeyPlugins(all_plugins)

  local end_time = reaper.time_precise()
  reaper.ShowConsoleMsg("\nScan completed in " .. string.format("%.2f", end_time - start_time) .. " seconds\n")

  -- Export to JSON
  local export_path = reaper.GetResourcePath() .. "\\rule-of-30-plugins.json"
  local file = io.open(export_path, "w")
  if file then
    file:write("{\n")
    file:write('  "scan_date": "' .. os.date() .. '",\n')
    file:write('  "total_plugins": ' .. all_plugins.total .. ',\n')
    file:write('  "key_plugins": {\n')

    local entries = {}
    for name, path in pairs(key_plugins) do
      if path then
        table.insert(entries, '    "' .. name .. '": "' .. path:gsub("\\", "\\\\") .. '"')
      end
    end

    file:write(table.concat(entries, ",\n"))
    file:write('\n  }\n')
    file:write("}\n")
    file:close()

    reaper.ShowConsoleMsg("\n✅ Plugin database exported to: " .. export_path .. "\n")
  end
end

main()
