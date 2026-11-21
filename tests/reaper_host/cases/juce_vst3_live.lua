-- Live REAPER 7.x host validation for the compiled JUCE VST3 plugin (SGM Utility.vst3).
return function(T)
  if not os.getenv("SGM_VST3_BUNDLE") or os.getenv("SGM_VST3_BUNDLE") == "" then
    return
  end

  local RATE = 48000
  local FRAMES = 48000 -- 1.0s

  local function sine_wav(name, nch, amp)
    local fns = {}
    for c = 1, nch do
      fns[c] = function(f)
        return amp * math.sin(2.0 * math.pi * 440.0 * f / RATE)
      end
    end
    return T.write_wav(T.tmpdir() .. "/" .. name .. ".wav", RATE, FRAMES, fns)
  end

  local function measure_track_rms(track, nch, start_sec, dur_sec)
    local acc = reaper.CreateTrackAudioAccessor(track)
    T.ok(acc ~= nil, "CreateTrackAudioAccessor succeeded")
    local nframes = math.floor(dur_sec * RATE)
    local buf = reaper.new_array(nframes * nch)
    local status = reaper.GetAudioAccessorSamples(acc, RATE, nch, start_sec, nframes, buf)
    reaper.DestroyAudioAccessor(acc)
    T.eq(status, 1, "GetAudioAccessorSamples returned audio status 1")
    local sum_sq = 0.0
    local total = nframes * nch
    for i = 1, total do
      local v = buf[i]
      sum_sq = sum_sq + (v * v)
    end
    return math.sqrt(sum_sq / total)
  end

  local function add_sgm_utility(tr)
    local idx = reaper.TrackFX_AddByName(tr, "SGM Utility", false, -1)
    if idx < 0 then
      idx = reaper.TrackFX_AddByName(tr, "VST3: SGM Utility", false, -1)
    end
    T.ok(idx >= 0, "REAPER scanned and instantiated SGM Utility.vst3 (idx=" .. tostring(idx) .. ")")
    local _, fx_name = reaper.TrackFX_GetFXName(tr, idx, "")
    T.contains(fx_name, "SGM Utility", "loaded FX name")
    return idx, fx_name
  end

  T.test("juce.live.vst3_scan_instantiate_and_parameters", function()
    local tr = T.add_track("JUCE Scan")
    local idx, fx_name = add_sgm_utility(tr)
    T.contains(fx_name, "VST3", "FX reported as VST3: " .. fx_name)
    local nparams = reaper.TrackFX_GetNumParams(tr, idx)
    T.ok(nparams >= 2, "SGM Utility exposes Gain and Bypass parameters, got " .. tostring(nparams))
    local _, p0 = reaper.TrackFX_GetParamName(tr, idx, 0, "")
    local _, p1 = reaper.TrackFX_GetParamName(tr, idx, 1, "")
    T.contains(p0:lower(), "gain", "param 0 is Gain: " .. p0)
    T.contains(p1:lower(), "bypass", "param 1 is Bypass: " .. p1)
    T.log("JUCE_VST3_SCAN_OK", fx_name, "params=" .. nparams)
  end)

  T.test("juce.live.vst3_mono_and_stereo_passthrough_gain_and_bypass", function()
    local expected_unity = 0.5 / math.sqrt(2.0) -- ~0.35355
    local expected_minus6 = expected_unity * (10.0 ^ (-6.0 / 20.0)) -- ~0.17720
    local norm_0db = 60.0 / 72.0   -- 0.0 dB on [-60, +12]
    local norm_m6db = 54.0 / 72.0  -- -6.0 dB on [-60, +12]

    local function render_rms(mode, gain_norm, bypass_norm)
      T.clear_project()
      local tr = T.add_track("JUCE " .. mode.label)
      T.add_item(tr, sine_wav("juce_" .. mode.label, mode.nch, 0.5), 0.0)
      local idx = add_sgm_utility(tr)
      reaper.TrackFX_SetParamNormalized(tr, idx, 1, bypass_norm)
      reaper.TrackFX_SetParamNormalized(tr, idx, 0, gain_norm)
      return measure_track_rms(tr, mode.nch, 0.2, 0.2)
    end

    for _, mode in ipairs({{label = "mono", nch = 1}, {label = "stereo", nch = 2}}) do
      -- 1) 0.0 dB pass-through
      local rms_unity = render_rms(mode, norm_0db, 0.0)
      T.near(rms_unity, expected_unity, 0.015, mode.label .. " 0dB pass-through RMS")

      -- 2) -6.0 dB gain attenuation
      local rms_m6 = render_rms(mode, norm_m6db, 0.0)
      T.near(rms_m6, expected_minus6, 0.015, mode.label .. " -6dB gain RMS")
      T.near(rms_m6 / rms_unity, 10.0 ^ (-6.0 / 20.0), 0.03, mode.label .. " -6dB/0dB gain ratio")

      -- 3) Bypass ON restores unity pass-through while Gain stays at -6dB
      local rms_bypass = render_rms(mode, norm_m6db, 1.0)
      T.near(rms_bypass, expected_unity, 0.015, mode.label .. " bypass RMS")
      T.log("JUCE_VST3_AUDIO_OK", mode.label,
        string.format("unity=%.4f m6=%.4f bypass=%.4f", rms_unity, rms_m6, rms_bypass))
    end
  end)

  T.test("juce.live.vst3_parameter_automation_envelope", function()
    local tr = T.add_track("JUCE Auto")
    local idx = add_sgm_utility(tr)
    local env = reaper.GetFXEnvelope(tr, idx, 0, true)
    T.ok(env ~= nil, "Gain FX envelope created on SGM Utility")
    reaper.InsertEnvelopePoint(env, 0.0, 54.0 / 72.0, 0, 0, false, true)
    reaper.InsertEnvelopePoint(env, 1.0, 60.0 / 72.0, 0, 0, false, true)
    reaper.Envelope_SortPoints(env)
    local cnt = reaper.CountEnvelopePoints(env)
    T.ok(cnt >= 2, "Gain envelope holds inserted points, got " .. tostring(cnt))
  end)

  T.test("juce.live.vst3_state_save_and_reload_across_project_reopen", function()
    local tr = T.add_track("JUCE State")
    local idx = add_sgm_utility(tr)
    local target_gain = 54.0 / 72.0 -- -6.0 dB
    reaper.TrackFX_SetParamNormalized(tr, idx, 0, target_gain)
    reaper.TrackFX_SetParamNormalized(tr, idx, 1, 1.0) -- Bypass ON

    local rpp_path = T.tmpdir() .. "/juce_state_test.rpp"
    reaper.Main_SaveProjectEx(0, rpp_path, 0)
    local saved_txt = T.read_file(rpp_path)
    T.ok(saved_txt ~= nil and saved_txt:find("SGM Utility", 1, true) ~= nil,
      "saved .rpp contains SGM Utility VST3 state")

    -- Open a fresh blank project, then reopen the saved project to verify true reload
    local blank_rpp = T.tmpdir() .. "/blank_reset.rpp"
    local bfh = assert(io.open(blank_rpp, "w"))
    bfh:write('<REAPER_PROJECT 0.1 "7.0"\n>\n')
    bfh:close()
    reaper.Main_openProject("noprompt:" .. blank_rpp)
    T.eq(reaper.CountTracks(0), 0, "blank project cleared tracks")

    reaper.Main_openProject("noprompt:" .. rpp_path)
    T.eq(reaper.CountTracks(0), 1, "reopened project restored track")
    local tr2 = reaper.GetTrack(0, 0)
    T.eq(reaper.TrackFX_GetCount(tr2), 1, "reopened project restored SGM Utility FX")
    local _, fx_name2 = reaper.TrackFX_GetFXName(tr2, 0, "")
    T.contains(fx_name2, "SGM Utility", "reopened FX is SGM Utility")
    local reloaded_gain = reaper.TrackFX_GetParamNormalized(tr2, 0, 0)
    local reloaded_bypass = reaper.TrackFX_GetParamNormalized(tr2, 0, 1)
    T.near(reloaded_gain, target_gain, 0.005, "saved -6dB Gain state survived project reopen")
    T.ok(reloaded_bypass >= 0.5, "saved Bypass=ON state survived project reopen")
    T.log("JUCE_VST3_STATE_OK", string.format("gain=%.4f bypass=%.1f", reloaded_gain, reloaded_bypass))
  end)
end
