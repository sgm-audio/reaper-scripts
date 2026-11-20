-- Live REAPER 7.x tests for session builder, signal chain presets, rule-of-30 presets,
-- template installer, and plugin development blueprint.

return function(T)
  T.test("session.live.mixing_builds_tracks_sends_fx_and_preserves_existing", function()
    local existing = T.add_track("Existing")
    T.menu_choice = 0 -- load without auto-running menu
    T.load_script("SGM_Professional_Session_Builder.lua")
    T.ok(_G.SGMSessionBuilder ~= nil, "SGMSessionBuilder exported")
    T.dialog_answer = 1
    local before = reaper.CountTracks(0)
    local session = _G.SGMSessionBuilder.buildProfessionalSession("mixing", "stock")
    T.ok(session ~= nil and session.implemented == true, "mixing session implemented")
    T.ok(reaper.CountTracks(0) > before, "tracks added to project")
    local _, ex_name = reaper.GetSetMediaTrackInfo_String(existing, "P_NAME", "", false)
    T.eq(ex_name, "Existing", "existing track preserved")
    T.ok(session.sends_created >= 1, "at least one routing send created")
  end)

  T.test("session.live.single_undo_removes_session_build", function()
    reaper.Undo_OnStateChange("fixture")
    T.menu_choice = 0
    T.load_script("SGM_Professional_Session_Builder.lua")
    T.dialog_answer = 1
    _G.SGMSessionBuilder.buildProfessionalSession("mastering", "stock")
    T.ok(reaper.CountTracks(0) >= 2, "mastering tracks created")
    reaper.Undo_DoUndo2(0)
    T.eq(reaper.CountTracks(0), 0, "single undo removes session tracks")
  end)

  T.test("presets.live.signal_chain_library_loads_with_valid_categories", function()
    local lib = T.load_script("signal-chain-presets.lua")
    T.ok(type(lib) == "table", "SIGNAL_CHAIN_LIBRARY returned")
    local count = 0
    for name, entry in pairs(lib) do
      count = count + 1
      T.ok(type(name) == "string" and name ~= "", "preset name")
      T.ok(type(entry) == "table", "preset entry is table")
    end
    T.ok(count >= 5, "at least 5 signal chain presets: " .. count)
  end)

  T.test("presets.live.rule_of_30_loads_and_matches_tracks", function()
    local r30 = T.load_script("rule-of-30-plugin-presets.lua")
    T.ok(type(r30) == "table", "rule-of-30 exports table")
    T.ok(type(r30.getChainForTrack) == "function", "getChainForTrack exported")
    local kick = r30.getChainForTrack("Kick In")
    T.ok(type(kick) == "table" and next(kick) ~= nil, "kick chain non-empty")
    local missing = r30.getChainForTrack("")
    T.ok(missing == nil, "empty track name returns nil")
  end)

  T.test("installer.live.copies_scripts_docs_plugin_and_writes_manifest", function()
    T.dialog_answer = 1
    T.load_script("reaper-template-installer.lua")
    local last = T.dialogs[#T.dialogs] and T.dialogs[#T.dialogs].text or ""
    T.contains(last, "Installed ", "installer completed: " .. last)
    local base = reaper.GetResourcePath() .. "/Scripts/ScottMills/"
    local manifest = io.open(base .. "installed-files.txt", "r")
    T.ok(manifest ~= nil, "installed-files.txt exists in resource path")
    if manifest then
      local content = manifest:read("*a")
      manifest:close()
      T.contains(content, "Reaper AI Control Hub.lua", "manifest lists installed script")
      T.contains(content, "plugin/", "manifest lists plugin source")
    end
  end)

  T.test("blueprint.live.creates_juce_project_in_saved_project", function()
    local tmp_dir = reaper.GetResourcePath() .. "/sgm_blueprint_proj"
    reaper.RecursiveCreateDirectory(tmp_dir, 0)
    local rpp = tmp_dir .. "/dev.rpp"
    local fh = assert(io.open(rpp, "w"))
    fh:write("<REAPER_PROJECT 0.1 \"7.0\"\n>\n")
    fh:close()
    reaper.Main_openProject("noprompt:" .. rpp)
    T.dialog_answer = 1
    local ok = T.load_script("SGM_plugin_development_blueprint.lua")
    local last = T.dialogs[#T.dialogs] and T.dialogs[#T.dialogs].text or ""
    T.ok(ok == true, "blueprint returned true (dialog: " .. last .. ")")
    local cmake = io.open(tmp_dir .. "/SGM_AI_Plugin_Suite/CMakeLists.txt", "r")
    T.ok(cmake ~= nil, "JUCE CMakeLists.txt created in saved project (dialog: " .. last .. ")")
    if cmake then cmake:close() end
  end)
end
