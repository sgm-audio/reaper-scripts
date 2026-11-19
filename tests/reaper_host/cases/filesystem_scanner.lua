-- Live REAPER 7 tests for scan-real-plugins.lua (Filesystem Scanner) against real directory enumeration.
return function(T)
  local function res(p) return reaper.GetResourcePath() .. "/" .. p end
  local function S()
    T.load_script("scan-real-plugins.lua") -- main() runs at load
    return _G.SGMRealPluginScanner
  end

  T.test("scanner.live.fixture_tree_exact_results_and_json_file", function()
    T.eq(os.getenv("HOME"), os.getenv("SGM_FIXTURE_HOME"), "HOME is the fixture tree")
    S()
    local text = T.read_file(res("rule-of-30-plugins.json"))
    T.ok(text ~= nil, "rule-of-30-plugins.json written")
    T.eq(tonumber(text:match('"total_plugins":%s*(%d+)')), 7, "exact plugin count from real EnumerateFiles/Subdirectories")
    for _, key in ipairs({"neural_gojira", "fabfilter_proq3", "fabfilter_saturn", "izotope_ozone", "waves_ssl_comp"}) do
      T.ok(text:find('"' .. key .. '"', 1, true), "key plugin detected: " .. key)
    end
    T.ok(not text:find('"waves_cla76"', 1, true), "absent plugin not reported")
  end)

  T.test("scanner.live.bundles_are_not_recursed_and_files_vs_dirs_typed_correctly", function()
    local s = S()
    local plugins = s.scanDirectory(os.getenv("HOME") .. "/.vst3")
    local by_name = {}
    for _, p in ipairs(plugins) do by_name[p.name] = p end
    T.ok(by_name["Neural DSP Archetype Gojira"], "bundle dir recognised as plugin")
    T.ok(by_name["iZotope Ozone 11"], "nested bundle found through plain subdirectory")
    T.ok(by_name["FabFilter Pro-Q 3"], "file plugin found")
    T.ok(not by_name["Gojira"], "bundle internals (.so) not double counted")
    T.ok(not by_name["readme"], "non-plugin file ignored")
    T.eq(#plugins, 4, "vst3 tree has exactly 4 plugins")
  end)

  T.test("scanner.live.missing_directory_returns_empty_not_error", function()
    local s = S()
    local plugins = s.scanDirectory(os.getenv("HOME") .. "/does/not/exist")
    T.eq(#plugins, 0, "missing dir -> empty")
  end)

  T.test("scanner.live.findKeyPlugins_patterns_on_real_scan", function()
    local s = S()
    local all = {}
    for _, p in ipairs(s.scanDirectory(os.getenv("HOME") .. "/.vst3")) do all[#all + 1] = p end
    for _, p in ipairs(s.scanDirectory(os.getenv("HOME") .. "/.clap")) do all[#all + 1] = p end
    local keys = s.findKeyPlugins(all)
    T.ok(keys.fabfilter_proq3 and keys.fabfilter_proq3.type == "vst3", "Pro-Q 3")
    T.ok(keys.fabfilter_saturn and keys.fabfilter_saturn.type == "clap", "Saturn is CLAP")
    T.ok(keys.neural_gojira, "gojira")
    T.ok(not keys.waves_ssl_comp, "SSL comp lives in .vst, not scanned here")
  end)
end
