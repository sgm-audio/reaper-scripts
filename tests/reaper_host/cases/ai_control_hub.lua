-- Live REAPER 7 tests for Reaper AI Control Hub.lua against real FX names, real tracks and real files.
return function(T)
  local function res(p) return reaper.GetResourcePath() .. "/" .. p end
  local function load_hub(choice)
    T.menu_choice = choice or 0
    T.load_script("Reaper AI Control Hub.lua")
  end
  local function master_add(name)
    local m = reaper.GetMasterTrack(0)
    local idx = reaper.TrackFX_AddByName(m, name, false, -1)
    T.ok(idx >= 0, "host added " .. name .. " to master")
    return idx
  end
  local function clear_master()
    local m = reaper.GetMasterTrack(0)
    for i = reaper.TrackFX_GetCount(m) - 1, 0, -1 do reaper.TrackFX_Delete(m, i) end
  end

  T.test("hub.live.real_fx_names_with_ai_substrings_are_not_misclassified", function()
    load_hub(0)
    clear_master()
    -- "JS: Gain Reduction Scope (Cockos)" contains "ai" inside "Gain" but is not an AI tool.
    master_add("JS:analysis/gain_reduction_scope")
    local bridge = _G.AIPluginBridge:new()
    local found = bridge:discover_ai_plugins()
    T.eq(#found, 0, "Gain Reduction Scope must not be an 'AI plugin'")
    clear_master()
  end)

  T.test("hub.live.categorize_and_capabilities_use_word_boundaries", function()
    load_hub(0)
    local b = _G.AIPluginBridge:new()
    for _, n in ipairs({"Chain Gain", "Rain Gate", "Mainstage Pad", "HTML Viewer"}) do
      T.eq(b:_categorize_plugin(n), "General", n .. " category")
      T.eq(#b:_assess_capabilities(n), 0, n .. " capabilities")
    end
    T.eq(b:_categorize_plugin("Neural AI Processor"), "AI Processing", "real AI name")
    T.eq(b:_categorize_plugin("Stem Separator"), "Stem Separation", "stem")
    T.eq(b:_categorize_plugin("OmniBridge by AudioMovers"), "Routing/Host", "routing")
    local caps = b:_assess_capabilities("AI Stem Separate Master Analyze")
    local set = {}
    for _, c in ipairs(caps) do set[c] = true end
    for _, c in ipairs({"stem_separation", "mastering", "analysis", "ai_processing"}) do T.ok(set[c], "capability " .. c) end
  end)

  T.test("hub.live.plugin_type_detection_uses_real_host_fx_name_prefixes", function()
    load_hub(0)
    clear_master()
    local vst = master_add("ReaEQ")
    local js = master_add("JS:analysis/gain_reduction_scope")
    local b = _G.AIPluginBridge:new()
    local _, vst_name = reaper.TrackFX_GetFXName(reaper.GetMasterTrack(0), vst, "")
    T.ok(vst_name:match("^VST"), "host names VST FX with a 'VST:' prefix, got " .. vst_name)
    T.eq(b:_detect_plugin_type(vst), "VST2", "VST type from host name prefix")
    T.eq(b:_detect_plugin_type(js), "JSFX", "JSFX type from host name prefix")
    T.eq(b:_detect_plugin_type(99), "Unknown", "out-of-range index")
    clear_master()
  end)

  T.test("hub.live.discovery_finds_real_ai_named_master_fx", function()
    load_hub(0)
    clear_master()
    -- ReaFir is a real FX whose host name ("ReaFir (FFT EQ+Dynamics Processor)") matches no AI pattern.
    master_add("ReaFir")
    local b = _G.AIPluginBridge:new()
    T.eq(#b:discover_ai_plugins(), 0, "plain FX not discovered")
    clear_master()
    -- JS: "Stereo Channel Volume/Pan/Polarity Control" etc. do not match; a JS with 'Analysis' in its
    -- desc would. Use the host's own list to find one real match for the 'Analysis'/'Meter' families.
    local candidate
    for i = 0, 5000 do
      local ok, name, ident = reaper.EnumInstalledFX(i)
      if not ok then break end
      if name:find("[%s]Mastering") or name:find("Stem") then candidate = ident; break end
    end
    if candidate then
      master_add("JS:" .. candidate)
      T.ok(#b:discover_ai_plugins() >= 1, "real Mastering/Stem FX discovered")
      clear_master()
    end
  end)

  T.test("hub.live.routing_template_file_is_written_with_three_presets", function()
    os.remove(res("ai_routing_template.json"))
    load_hub(0)
    local b = _G.AIPluginBridge:new()
    local presets = b:create_ai_routing_template()
    T.eq(#presets, 3, "three presets returned")
    local text = T.read_file(res("ai_routing_template.json"))
    T.ok(text ~= nil, "template written under the real resource path")
    T.eq(select(2, text:gsub('"tracks": %[', "")), 3, "three tracks arrays")
    T.ok(text:find('"channel": "1"', 1, true) or text:find('"channel": 1', 1, true), "channel emitted")
  end)

  T.test("hub.live.menu_discovery_runs_end_to_end_and_exports_template", function()
    os.remove(res("ai_routing_template.json"))
    load_hub(1)
    T.contains(T.console_text(), "AI PLUGIN DISCOVERY MODE", "discovery mode ran")
    T.ok(T.read_file(res("ai_routing_template.json")) ~= nil, "template exported by menu action")
  end)

  T.test("hub.live.external_processing_without_selection_is_a_safe_noop", function()
    load_hub(0)
    local l = _G.ExternalToolLauncher:new()
    reaper.Main_OnCommand(40297, 0)
    local files = l:launch_external_processing(nil, "stem_separation")
    T.eq(#files, 0, "no files")
    T.contains(T.console_text(), "Select at least one track", "guidance message")
  end)

  T.test("hub.live.external_processing_requires_saved_project_and_sanitizes_names", function()
    load_hub(0)
    local tr = T.add_track('Gtr: L/R <DI>?')
    T.select_only_tracks({tr})
    local l = _G.ExternalToolLauncher:new()
    -- Unsaved project: safely refuses instead of writing into default REAPER Media.
    local unsaved_files = l:launch_external_processing(nil, "stem_separation")
    T.eq(#unsaved_files, 0, "no files on unsaved project")
    T.contains(T.console_text(), "Save the project", "unsaved project guidance")

    -- Saved project: reports sanitised manual render target without claiming audio was rendered.
    local tmp_dir = reaper.GetResourcePath() .. "/sgm_hub_test_proj"
    reaper.RecursiveCreateDirectory(tmp_dir, 0)
    local rpp = tmp_dir .. "/test.rpp"
    local fh = assert(io.open(rpp, "w"))
    fh:write("<REAPER_PROJECT 0.1 \"7.0\"\n>\n")
    fh:close()
    reaper.Main_openProject("noprompt:" .. rpp)
    tr = T.add_track('Gtr: L/R <DI>?')
    T.select_only_tracks({tr})
    T.reset_ui()
    local files = l:launch_external_processing(nil, "stem_separation")
    T.eq(#files, 0, "hub never claims files were rendered")
    local out = T.console_text()
    T.contains(out, "01_Gtr_ L_R _DI___export.wav", "sanitised manual render target")
    T.contains(out, "No audio was rendered automatically", "honest status")
  end)

  T.test("hub.live.tool_paths_are_portable_and_include_resource_path", function()
    load_hub(0)
    local l = _G.ExternalToolLauncher:new()
    local seen = false
    for _, p in ipairs(l.tool_paths) do
      T.ok(not p:find("C:\\", 1, true), "no hardcoded C:\\ path on this OS: " .. p)
      if p == reaper.GetResourcePath() .. "/UserPlugins/AI" then seen = true end
    end
    T.ok(seen, "resource-path based location present")
  end)
end
