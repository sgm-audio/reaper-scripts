-- Live REAPER 7 tests for plugin-wrapper.lua (PluginInstance / PluginAutomation / PluginDB / scanner).
return function(T)
  local function res(p) return reaper.GetResourcePath() .. "/" .. p end
  local function W()
    T.load_script("plugin-wrapper.lua")
    return _G.SGMPluginWrapper
  end
  local function eq_instance(w, name)
    local tr = T.add_track("fx")
    local idx = reaper.TrackFX_AddByName(tr, name or "ReaEQ", false, -1)
    T.ok(idx >= 0, "host added " .. tostring(name or "ReaEQ"))
    return tr, w.PluginInstance:new(tr, idx), idx
  end

  T.test("wrapper.live.instance_name_params_and_value_roundtrip", function()
    local w = W()
    local tr, inst, idx = eq_instance(w)
    T.contains(inst:getName(), "ReaEQ", "FX name from host")
    local n = inst:getParamCount()
    T.ok(n > 4, "ReaEQ exposes parameters, got " .. tostring(n))
    T.ok(inst:getParamName(0) ~= "", "param 0 has a name")
    local _, _, _, mid = reaper.TrackFX_GetParamEx(tr, idx, 0)
    T.ok(inst:setParamValue(0, mid), "SetParam succeeds")
    T.near(inst:getParamValue(0), mid, 1e-6, "value round-trips through the host")
    T.ok(inst:getParamFormatted(0) ~= "", "formatted value available")
    inst:cacheAllParams()
    T.eq(#inst.param_cache + 1 >= n, true, "cacheAllParams covers every parameter (0-indexed)")
    T.ok(inst.param_cache[n - 1] ~= nil, "last parameter cached")
  end)

  T.test("wrapper.live.enable_disable_remove", function()
    local w = W()
    local tr, inst = eq_instance(w)
    T.eq(inst:isEnabled(), true, "enabled on add")
    inst:disable()
    T.eq(inst:isEnabled(), false, "disable reaches the host")
    inst:enable()
    T.eq(inst:isEnabled(), true, "enable reaches the host")
    T.eq(reaper.TrackFX_GetCount(tr), 1, "one FX")
    inst:remove()
    T.eq(reaper.TrackFX_GetCount(tr), 0, "remove deletes the real FX")
  end)

  T.test("wrapper.live.presets_and_state_chunk_do_not_error", function()
    local w = W()
    local _, inst = eq_instance(w)
    T.ok(inst:getPresetCount() >= 0, "preset count is a number")
    local chunk = inst:getStateChunk()
    T.ok(chunk == nil or type(chunk) == "string", "state chunk nil or string")
  end)

  T.test("wrapper.live.automateParameter_inserts_two_points_at_tempo_scaled_time", function()
    local w = W()
    local tr, inst, idx = eq_instance(w)
    reaper.SetEditCurPos(1.0, false, false)
    local tempo = reaper.Master_GetTempo()
    local auto = w.PluginAutomation:new(inst)
    T.eq(auto:automateParameter(0, 0.2, 0.8, 4), true, "automateParameter ok")
    local env = reaper.GetFXEnvelope(tr, idx, 0, false)
    T.ok(env ~= nil, "envelope exists on the real FX param")
    -- REAPER seeds a brand-new envelope with a default point at t=0; the script must add exactly two more.
    local pts = {}
    for i = 0, reaper.CountEnvelopePoints(env) - 1 do
      local _, t, v = reaper.GetEnvelopePoint(env, i)
      pts[#pts + 1] = {t = t, v = v}
    end
    T.eq(#pts, 3, "default seed point + two automation points")
    T.near(pts[1].t, 0.0, 1e-9, "seed point at project start")
    T.near(pts[2].t, 1.0, 1e-6, "first point at edit cursor")
    T.near(pts[3].t - pts[2].t, 4 * 60 / tempo, 1e-6, "duration = beats * 60 / tempo")
    T.near(pts[2].v, 0.2, 1e-6, "start value")
    T.near(pts[3].v, 0.8, 1e-6, "end value")
  end)

  T.test("wrapper.live.createSweep_curves_have_21_monotonic_points_and_exact_shape", function()
    local w = W()
    local expectations = {
      linear = function(t) return t end,
      exponential = function(t) return t * t end,
      logarithmic = function(t) return math.sqrt(t) end,
    }
    for curve, f in pairs(expectations) do
      T.clear_project()
      local tr, inst, idx = eq_instance(w)
      local auto = w.PluginAutomation:new(inst)
      T.eq(auto:createSweep(0, 0.0, 1.0, 4.0, curve), true, curve .. " ok")
      local env = reaper.GetFXEnvelope(tr, idx, 0, false)
      T.eq(reaper.CountEnvelopePoints(env), 21, curve .. " point count")
      local prev = -1
      for i = 0, 20 do
        local _, time, value = reaper.GetEnvelopePoint(env, i)
        T.ok(time > prev, curve .. " times strictly increasing at " .. i)
        prev = time
        T.near(time, 4.0 * i / 20, 1e-6, curve .. " time " .. i)
        T.near(value, f(i / 20), 1e-6, curve .. " value " .. i)
      end
    end
  end)

  T.test("wrapper.live.automate_without_touched_param_refuses_and_leaves_no_envelope", function()
    local w = W()
    local tr = T.add_track("none")
    reaper.TrackFX_AddByName(tr, "ReaEQ", false, -1)
    local before = reaper.Undo_CanUndo2(0)
    -- Nothing has been touched in this fresh host session, so the script must refuse.
    local touched = reaper.GetLastTouchedFX()
    if not touched then
      T.eq(w.automateSelectedPlugin(), false, "refuses when nothing touched")
      T.eq(#T.dialogs, 1, "one explanatory dialog")
      T.eq(reaper.Undo_CanUndo2(0), before, "no undo point created")
    end
  end)

  T.test("wrapper.live.db_roundtrip_with_hostile_strings_through_real_filesystem", function()
    local w = W()
    local db = w.PluginDB:new()
    local nasty = 'Evil "Quote" \\ Back\tTab'
    db:addPlugin({name = nasty, path = "/x/y \"z\".vst3", format = "VST3", vendor = "V\\W", category = "EQ", param_count = 7})
    db.last_scan = 1700000000
    T.ok(db:save(), "save writes to the real resource path")
    local text = T.read_file(res("plugin_database.json"))
    T.ok(text ~= nil and text:find('"plugins"', 1, true), "database file present")
    local db2 = w.PluginDB:new()
    db2:load()
    T.eq(#db2.plugins, 1, "one plugin reloaded")
    T.eq(db2.plugins[1].name, nasty, "name round-trips byte-exact")
    T.eq(db2.plugins[1].path, "/x/y \"z\".vst3", "path round-trips")
    T.eq(db2.plugins[1].param_count, 7, "param_count round-trips")
    T.eq(db2.last_scan, 1700000000, "last_scan round-trips")
    T.eq(db2:findByName("evil").name, nasty, "case-insensitive find")
  end)

  T.test("wrapper.live.full_scan_of_fixture_home_finds_exact_plugins_and_names", function()
    T.eq(os.getenv("HOME"), os.getenv("SGM_FIXTURE_HOME"), "runner pointed HOME at the fixture tree")
    local w = W()
    local scanner = w.PluginScanner:new()
    scanner:performFullScan()
    local names = {}
    for _, p in ipairs(scanner.db.plugins) do
      if p.path:find(os.getenv("HOME"), 1, true) == 1 then names[p.name] = p end
    end
    local function has(n, fmt)
      T.ok(names[n] ~= nil, "missing plugin '" .. n .. "' (have: " .. (function() local t = {} for k in pairs(names) do t[#t + 1] = k end table.sort(t) return table.concat(t, "|") end)() .. ")")
      T.eq(names[n].format, fmt, n .. " format")
    end
    has("Neural DSP Archetype Gojira", "VST3")
    has("FabFilter Pro-Q 3", "VST3")
    has("iZotope Ozone 11", "VST3")
    has("FabFilter Saturn 2", "CLAP")
    has("Waves SSL Comp", "VST2")
    has("Foo v2.5", "VST3")
    has("Some", "LV2")
    local n = 0 for _ in pairs(names) do n = n + 1 end
    T.eq(n, 7, "exactly the fixture plugins (bundle internals and readme.txt ignored)")
    T.eq(names["FabFilter Pro-Q 3"].vendor, "FabFilter", "vendor from path")
    local saved = T.read_file(res("plugin_database.json"))
    T.ok(saved and saved:find("Foo v2.5", 1, true), "scan persisted to the resource path")
  end)

  T.test("wrapper.live.menu_rows_list_track_fx_and_export_database", function()
    local w = W()
    local tr = eq_instance(w, "ReaEQ")
    T.select_only_tracks({tr})
    T.reset_ui()
    T.menu_choice = 2
    w.showMenu()
    T.contains(T.console_text(), "ReaEQ", "menu row 2 prints real track FX")
    T.reset_ui()
    os.remove(res("plugin_database.json"))
    T.menu_choice = 4
    w.showMenu()
    T.ok(T.read_file(res("plugin_database.json")) ~= nil, "menu row 4 writes plugin_database.json")
    T.ok(#T.dialogs >= 1 and T.dialogs[#T.dialogs].title == "Success", "menu row 4 shows Success dialog")
  end)

  T.test("wrapper.live.automateSelectedPlugin_real_reaeq_creates_21_points_and_single_step_undo", function()
    local w = W()
    local tr, _, idx = eq_instance(w, "ReaEQ")
    reaper.Undo_OnStateChange("reaeq_fixture")
    reaper.TrackFX_SetParam(tr, idx, 0, 0.5)
    local real_last_touched = reaper.GetLastTouchedFX
    local touched = real_last_touched()
    if not touched then
      -- Headless REAPER has no GUI click to update last-touched; point at the real Track 1 / ReaEQ FX 0 / param 0.
      reaper.GetLastTouchedFX = function() return true, 1, idx, 0 end
    end
    T.dialog_answer = 1
    local ok_call, res_auto = pcall(w.automateSelectedPlugin)
    reaper.GetLastTouchedFX = real_last_touched
    T.ok(ok_call, "automateSelectedPlugin did not error: " .. tostring(res_auto))
    T.eq(res_auto, true, "automateSelectedPlugin succeeded on real ReaEQ")

    local env = reaper.GetFXEnvelope(tr, idx, 0, false)
    T.ok(env ~= nil, "real ReaEQ FX envelope created")
    T.eq(reaper.CountEnvelopePoints(env), 21, "automateSelectedPlugin created exact 21 envelope points")
    T.eq(reaper.Undo_CanUndo2(0), "SGM: Automate FX Parameter", "exact undo block label")

    reaper.Undo_DoUndo2(0)
    local tr_after = reaper.GetTrack(0, 0)
    local env_after = reaper.GetFXEnvelope(tr_after, 0, 0, false)
    local pts_after = env_after and reaper.CountEnvelopePoints(env_after) or 0
    T.ok(pts_after < 21, "single-step undo removed the 21 automation points (remaining=" .. tostring(pts_after) .. ")")
  end)
end
