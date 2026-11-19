-- Live REAPER 7 tests for list-all-available-plugins.lua (Plugin Inventory).
-- Ground truth comes from REAPER itself: EnumInstalledFX, reaper-jsfx.ini and
-- reaper-vstplugins64.ini as written by the real host, and TrackFX_AddByName.
return function(T)
  local function res(p) return reaper.GetResourcePath() .. "/" .. p end

  local function jsfx_idents_from_host()
    local idents, n = {}, 0
    for i = 0, 5000 do
      local ok, name, ident = reaper.EnumInstalledFX(i)
      if not ok then break end
      if name:sub(1, 3) == "JS:" then idents[ident] = name; n = n + 1 end
    end
    return idents, n
  end

  local function scan()
    T.load_script("list-all-available-plugins.lua")
    local scanner = _G.SGMPluginInventory:new()
    return scanner, scanner:scanAllPlugins()
  end

  T.test("inventory.live.main_writes_valid_json_matching_in_memory_scan", function()
    T.load_script("list-all-available-plugins.lua") -- main() runs at load
    local text = T.read_file(res("plugin_inventory.json"))
    T.ok(text and #text > 100, "plugin_inventory.json written to the real resource path")
    local declared = tonumber(text:match('"total_count":%s*(%d+)'))
    local _, plugins = scan()
    T.eq(declared, plugins.total_count, "JSON total_count == scanned total")
    local entries = select(2, text:gsub('"category":', ""))
    T.eq(entries, plugins.total_count, "one JSON entry per plugin")
    T.contains(T.console_text(), "Total Plugins: " .. plugins.total_count, "console summary")
  end)

  T.test("inventory.live.every_js_entry_instantiates_in_the_host", function()
    local _, plugins = scan()
    T.ok(#plugins.by_type.js >= 150, "expected >=150 JSFX in a stock install, got " .. #plugins.by_type.js)
    local tr = T.add_track("fx")
    local bad = {}
    for _, p in ipairs(plugins.by_type.js) do
      local idx = reaper.TrackFX_AddByName(tr, "JS:" .. p.name, false, -1)
      if idx < 0 then bad[#bad + 1] = p.name else reaper.TrackFX_Delete(tr, idx) end
    end
    T.eq(#bad, 0, "inventory entries REAPER cannot instantiate: " .. table.concat(bad, ", "):sub(1, 600))
  end)

  T.test("inventory.live.no_installed_host_jsfx_is_missing", function()
    local _, plugins = scan()
    local idents = jsfx_idents_from_host()
    local have = {}
    for _, p in ipairs(plugins.by_type.js) do have[p.name] = true end
    local missing = {}
    for ident in pairs(idents) do if not have[ident] then missing[#missing + 1] = ident end end
    table.sort(missing)
    T.eq(#missing, 0, "host JSFX missing from inventory: " .. table.concat(missing, ", "):sub(1, 400))
  end)

  T.test("inventory.live.sampled_entries_instantiate_via_TrackFX_AddByName", function()
    local _, plugins = scan()
    local tr = T.add_track("fx")
    local checked = 0
    for i = 1, #plugins.by_type.js, math.max(1, math.floor(#plugins.by_type.js / 25)) do
      local p = plugins.by_type.js[i]
      local idx = reaper.TrackFX_AddByName(tr, "JS:" .. p.name, false, -1)
      T.ok(idx >= 0, "REAPER cannot instantiate inventory entry " .. p.name)
      checked = checked + 1
    end
    T.ok(checked >= 20, "sampled enough entries: " .. checked)
  end)

  T.test("inventory.live.parseCache_reads_the_real_reaper_vst_cache", function()
    local scanner = _G.SGMPluginInventory and _G.SGMPluginInventory:new() or scan()
    local path = res("reaper-vstplugins64.ini")
    local raw = T.read_file(path)
    T.ok(raw and raw:find("ReaEQ", 1, true), "REAPER wrote its VST cache (ReaEQ present)")
    local raw_lines = 0
    for line in raw:gmatch("[^\r\n]+") do if line:match("^[^=]+=[^,]*,[^,]*,") then raw_lines = raw_lines + 1 end end
    local parsed = scanner:parseCache(path, "vst")
    local parsed_names = {}
    for _, p in ipairs(parsed) do parsed_names[p.path] = true end
    local lost = {}
    for line in raw:gmatch("[^\r\n]+") do
      local fname = line:match("^([^=]+)=[^,]*,[^,]*,")
      if fname and not parsed_names[fname] then lost[#lost + 1] = line end
    end
    T.eq(#parsed, raw_lines, "every real cache line parsed; lost: " .. table.concat(lost, " || "):sub(1, 500))
    local seen_eq, seen_instrument = false, false
    for _, p in ipairs(parsed) do
      T.ok(not p.name:find("!!!", 1, true), "cache marker leaked into plugin name: " .. p.name)
      T.ok(p.name ~= "", "empty name")
      if p.name == "ReaEQ (Cockos)" then seen_eq = true end
      if p.name:find("ReaSynth", 1, true) then
        seen_instrument = true
        T.eq(p.name, "ReaSynth (Cockos)", "VSTi marker stripped from name")
      end
    end
    T.ok(seen_eq, "ReaEQ parsed with its exact host name")
    T.ok(seen_instrument, "ReaSynth parsed")
  end)

  T.test("inventory.live.vst_entries_are_discoverable_by_the_host", function()
    local scanner = _G.SGMPluginInventory and _G.SGMPluginInventory:new() or scan()
    local parsed = scanner:parseCache(res("reaper-vstplugins64.ini"), "vst")
    local tr = T.add_track("vst")
    for _, p in ipairs(parsed) do
      local idx = reaper.TrackFX_AddByName(tr, p.name, false, -1)
      T.ok(idx >= 0, "host cannot instantiate parsed cache name: " .. p.name)
    end
  end)
end
