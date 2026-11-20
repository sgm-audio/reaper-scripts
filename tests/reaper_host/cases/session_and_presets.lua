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

  T.test("session.live.all_four_modes_in_populated_project_exact_counts_routing_fx_and_undo", function()
    local modes = {
      {mode = "full_production", tracks = 25, sends = 31},
      {mode = "mixing", tracks = 7, sends = 6},
      {mode = "mastering", tracks = 2, sends = 0},
      {mode = "stem_separation", tracks = 6, sends = 4},
    }
    for _, spec in ipairs(modes) do
      T.clear_project()
      T.reset_ui()
      T.add_track("PreExisting 1")
      T.add_track("PreExisting 2")
      reaper.Undo_OnStateChange("populated_fixture_" .. spec.mode)
      T.menu_choice = 0
      T.load_script("SGM_Professional_Session_Builder.lua")
      T.dialog_answer = 1

      local session = _G.SGMSessionBuilder.buildProfessionalSession(spec.mode, "stock")
      T.ok(session ~= nil and session.implemented == true, spec.mode .. " implemented")
      T.eq(reaper.CountTracks(0), 2 + spec.tracks, spec.mode .. " exact track count")
      T.eq(session.sends_created, spec.sends, spec.mode .. " exact sends_created")
      T.contains(T.console_text(), "Stock FX warnings: 0", spec.mode .. " zero stock FX warnings")

      local host_sends = 0
      local fx_verified = 0
      for i, tmpl in ipairs(session.tracks) do
        local tr = reaper.GetTrack(0, 2 + (i - 1))
        T.ok(tr ~= nil, spec.mode .. " created track " .. i)
        local expected_mainsend = tmpl.bus and 0.0 or 1.0
        T.eq(reaper.GetMediaTrackInfo_Value(tr, "B_MAINSEND"), expected_mainsend,
          spec.mode .. " B_MAINSEND on " .. tmpl.name)
        if tmpl.muted then
          T.eq(reaper.GetMediaTrackInfo_Value(tr, "B_MUTE"), 1.0, spec.mode .. " B_MUTE on " .. tmpl.name)
        end
        host_sends = host_sends + reaper.GetTrackNumSends(tr, 0)
        local fx_cnt = reaper.TrackFX_GetCount(tr)
        if tmpl.type ~= "reference" then
          T.ok(fx_cnt >= 1, spec.mode .. " stock FX instantiated on " .. tmpl.name)
          for fi = 0, fx_cnt - 1 do
            local _, fxn = reaper.TrackFX_GetFXName(tr, fi, "")
            T.ok(fxn:find("ReaEQ", 1, true) or fxn:find("ReaComp", 1, true) or fxn:find("ReaLimit", 1, true),
              spec.mode .. " real stock FX name on " .. tmpl.name .. ": " .. fxn)
            fx_verified = fx_verified + 1
          end
        end
      end
      T.eq(host_sends, spec.sends, spec.mode .. " host GetTrackNumSends sum matches")
      T.ok(fx_verified >= 2, spec.mode .. " real ReaEQ/ReaComp/ReaLimit FX verified: " .. fx_verified)

      -- Single-step undo must restore exact pre-run track count (2) and preserve existing tracks
      reaper.Undo_DoUndo2(0)
      T.eq(reaper.CountTracks(0), 2, spec.mode .. " single-step undo restored exact pre-run track count")
      local _, pre1 = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, 0), "P_NAME", "", false)
      local _, pre2 = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, 1), "P_NAME", "", false)
      T.eq(pre1, "PreExisting 1", spec.mode .. " preserved PreExisting 1")
      T.eq(pre2, "PreExisting 2", spec.mode .. " preserved PreExisting 2")
    end
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
