-- Live REAPER 7 tests for phase-alignment-tool.lua (real accessors, real undo, real media).
return function(T)
  local RATE = 48000
  local FRAMES = 24000 -- 0.5 s
  local TOL = 1.5 / RATE

  local function wav(name, nch, click_frame, amp, ch_for_click)
    local fns = {}
    for c = 1, nch do
      fns[c] = (c == (ch_for_click or 1)) and T.click(click_frame, amp or 0.8) or T.click(-1, 0)
    end
    return T.write_wav(T.tmpdir() .. "/" .. name .. ".wav", RATE, FRAMES, fns)
  end

  local function load_tool(choice)
    T.menu_choice = choice or 0
    T.load_script("phase-alignment-tool.lua")
  end

  local function pair(click_a, click_b, pos_a, pos_b)
    local a, b = T.add_track("A"), T.add_track("B")
    local ia = T.add_item(a, wav("pa_" .. click_a, 1, click_a), pos_a or 1.0)
    local ib = T.add_item(b, wav("pb_" .. click_b, 1, click_b), pos_b or 1.0)
    T.select_only_tracks({a, b})
    reaper.Undo_OnStateChange("fixture")
    return ia, ib
  end

  T.test("phase.live.findFirstTransient_exact_time_and_peak", function()
    load_tool(0)
    local tr = T.add_track("X")
    local item = T.add_item(tr, wav("ft", 1, 2400, 0.8), 2.0)
    local t, peak = _G.SGMPhaseAlignment.findFirstTransient(item)
    T.near(t, 2.05, TOL, "transient time")
    T.near(peak, 0.8, 0.01, "peak")
  end)

  T.test("phase.live.findFirstTransient_stereo_right_channel_only", function()
    load_tool(0)
    local tr = T.add_track("S")
    local item = T.add_item(tr, wav("st", 2, 1200, 0.9, 2), 0.0)
    local t = _G.SGMPhaseAlignment.findFirstTransient(item)
    T.near(t, 1200 / RATE, TOL, "right-channel transient time (frame index, not scalar index)")
  end)

  T.test("phase.live.findFirstTransient_below_threshold_returns_nil_with_peak", function()
    load_tool(0)
    local tr = T.add_track("Q")
    local item = T.add_item(tr, wav("quiet", 1, 1000, 0.2), 0.0)
    local t, peak = _G.SGMPhaseAlignment.findFirstTransient(item)
    T.eq(t, nil, "no transient below 0.3 threshold")
    T.near(peak, 0.2, 0.01, "peak reported")
  end)

  T.test("phase.live.findFirstTransient_honours_take_start_offset", function()
    load_tool(0)
    local tr = T.add_track("O")
    local item, take = T.add_item(tr, wav("off", 1, 1440, 0.8), 3.0) -- click at 30 ms
    reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0.02)
    local t = _G.SGMPhaseAlignment.findFirstTransient(item)
    T.near(t, 3.0 + 0.010, TOL, "offset take: transient is 10 ms into the item")
  end)

  T.test("phase.live.align_moves_late_item_and_new_transients_coincide", function()
    local ia, ib = pair(480, 1440) -- 10 ms vs 30 ms
    load_tool(0)
    _G.SGMPhaseAlignment.alignSelectedTracks()
    T.eq(#T.dialogs, 1, "exactly one confirmation dialog")
    T.near(T.item_pos(ia), 1.0, 1e-9, "earliest item untouched")
    T.near(T.item_pos(ib), 1.0 - 0.020, 1e-6, "late item moved earlier by 20 ms")
    local ta = _G.SGMPhaseAlignment.findFirstTransient(ia)
    local tb = _G.SGMPhaseAlignment.findFirstTransient(ib)
    T.near(ta, tb, TOL, "transients now sample-aligned (re-measured with a fresh accessor)")
  end)

  T.test("phase.live.align_is_one_undo_step_and_undo_restores_positions", function()
    pair(480, 1440)
    load_tool(0)
    _G.SGMPhaseAlignment.alignSelectedTracks()
    T.eq(reaper.Undo_CanUndo2(0), "Align Guitar Tracks (Phase)", "undo label")
    local moved = T.item_pos(reaper.GetTrackMediaItem(reaper.GetTrack(0, 1), 0))
    T.near(moved, 0.98, 1e-6, "moved before undo")
    reaper.Undo_DoUndo2(0)
    -- Undo may recreate item objects; always re-fetch handles.
    local restored = T.item_pos(reaper.GetTrackMediaItem(reaper.GetTrack(0, 1), 0))
    T.near(restored, 1.0, 1e-9, "undo restores original position in a single step")
    T.near(T.item_pos(reaper.GetTrackMediaItem(reaper.GetTrack(0, 0), 0)), 1.0, 1e-9, "other track too")
  end)


  T.test("phase.live.cancel_leaves_project_and_undo_stack_untouched", function()
    local _, ib = pair(480, 1440)
    local before = reaper.Undo_CanUndo2(0)
    T.dialog_answer = 2 -- Cancel
    load_tool(0)
    _G.SGMPhaseAlignment.alignSelectedTracks()
    T.near(T.item_pos(ib), 1.0, 1e-9, "no move on cancel")
    T.eq(reaper.Undo_CanUndo2(0), before, "no undo point on cancel")
  end)

  T.test("phase.live.already_aligned_prompts_nothing_and_moves_nothing", function()
    local ia, ib = pair(480, 480)
    load_tool(0)
    _G.SGMPhaseAlignment.alignSelectedTracks()
    T.eq(#T.dialogs, 0, "no dialog when already aligned")
    T.near(T.item_pos(ia), 1.0, 1e-9, "A")
    T.near(T.item_pos(ib), 1.0, 1e-9, "B")
    T.contains(T.console_text(), "already aligned", "console message")
  end)

  T.test("phase.live.fewer_than_two_tracks_warns_and_does_not_edit", function()
    local a = T.add_track("A")
    local ia = T.add_item(a, wav("solo", 1, 480), 1.0)
    T.select_only_tracks({a})
    load_tool(0)
    _G.SGMPhaseAlignment.alignSelectedTracks()
    T.eq(#T.dialogs, 1, "warning dialog")
    T.near(T.item_pos(ia), 1.0, 1e-9, "unmoved")
  end)

  T.test("phase.live.late_item_never_moves_before_project_start", function()
    -- B's transient is 40 ms later than A's but B sits at 0.0: clamping must hold.
    local a, b = T.add_track("A"), T.add_track("B")
    T.add_item(a, wav("clamp_a", 1, 0), 0.0)
    local ib = T.add_item(b, wav("clamp_b", 1, 1920), 0.0)
    T.select_only_tracks({a, b})
    load_tool(0)
    _G.SGMPhaseAlignment.alignSelectedTracks()
    T.ok(T.item_pos(ib) >= 0, "item position must never go negative")
  end)

  T.test("phase.live.menu_nudge_left_right_moves_selected_items_with_undo", function()
    local tr = T.add_track("N")
    local item = T.add_item(tr, wav("nudge", 1, 480), 1.0)
    reaper.SetMediaItemSelected(item, true)
    load_tool(4) -- Nudge Right 1ms
    T.near(T.item_pos(item), 1.001, 1e-9, "right 1 ms")
    T.eq(reaper.Undo_CanUndo2(0), "Nudge Items", "undo label")
    load_tool(3) -- Nudge Left 1 ms
    T.near(T.item_pos(item), 1.0, 1e-9, "left 1 ms")
    load_tool(6) -- fine right 0.1 ms
    T.near(T.item_pos(item), 1.0001, 1e-9, "fine right")
    load_tool(5)
    T.near(T.item_pos(item), 1.0, 1e-9, "fine left")
  end)

  T.test("phase.live.menu_nudge_clamps_at_zero", function()
    local tr = T.add_track("N")
    local item = T.add_item(tr, wav("nudge0", 1, 480), 0.0005)
    reaper.SetMediaItemSelected(item, true)
    load_tool(3)
    T.near(T.item_pos(item), 0.0, 1e-12, "clamped at 0")
  end)

  T.test("phase.live.menu_analyze_reports_position_difference_classes", function()
    pair(480, 480, 1.0, 1.0001)
    load_tool(2)
    T.contains(T.console_text(), "EXCELLENT", "<0.2ms")
    T.reset_ui(); T.clear_project()
    pair(480, 480, 1.0, 1.003)
    load_tool(2)
    T.contains(T.console_text(), "ACCEPTABLE", "<5ms")
    T.reset_ui(); T.clear_project()
    pair(480, 480, 1.0, 1.1)
    load_tool(2)
    T.contains(T.console_text(), "Significant misalignment", ">=5ms")
  end)

  T.test("phase.live.playrate_2x_and_late_120ms_and_minus30db_in_real_host", function()
    load_tool(0)
    local tr1 = T.add_track("Rate2x")
    local item1, take1 = T.add_item(tr1, wav("rate60", 1, 2880, 0.8), 1.0) -- click at 60ms
    reaper.SetMediaItemTakeInfo_Value(take1, "D_PLAYRATE", 2.0)
    local t_rate = _G.SGMPhaseAlignment.findFirstTransient(item1)
    T.near(t_rate, 1.030, 0.002, "2x playrate shifts 60ms click to ~30ms in real REAPER accessor")

    local tr2 = T.add_track("Late120")
    local item2 = T.add_item(tr2, wav("late120", 1, 5760, 0.9), 1.0) -- click at 120ms (>100ms window)
    local t_late = _G.SGMPhaseAlignment.findFirstTransient(item2)
    T.eq(t_late, nil, "120ms transient outside 100ms window returns nil in real host")

    local tr3 = T.add_track("Quiet30")
    local item3 = T.add_item(tr3, wav("quiet30", 1, 960, 0.0316), 1.0) -- -30dBFS
    local t_quiet, p_quiet = _G.SGMPhaseAlignment.findFirstTransient(item3)
    T.eq(t_quiet, nil, "-30dB transient below 0.3 threshold returns nil in real host")
    T.near(p_quiet, 0.0316, 0.005, "-30dB peak measured accurately in real host")
  end)

  T.test("phase.live.polarity_inverted_pair_aligns_and_surfaces_preflight_warnings", function()
    local a, b = T.add_track("Pos"), T.add_track("Neg")
    local ia = T.add_item(a, wav("pol_p", 1, 720, 0.8), 1.0) -- +0.8 at 15ms
    reaper.AddTakeToMediaItem(ia) -- second take to trigger multi-take pre-flight warning
    reaper.SetActiveTake(reaper.GetMediaItemTake(ia, 0))
    local ib = T.add_item(b, wav("pol_n", 1, 2880, -0.8), 1.0) -- -0.8 at 60ms
    T.select_only_tracks({a, b})
    load_tool(0)
    _G.SGMPhaseAlignment.alignSelectedTracks()
    T.eq(#T.dialogs, 1, "one confirmation dialog")
    T.contains(T.dialogs[1].text, "Opposite transient polarity", "polarity warning surfaced before confirm")
    T.contains(T.dialogs[1].text, "2 takes", "multi-take warning surfaced before confirm")
    T.contains(T.dialogs[1].text, "100ms", "100ms window disclosed before confirm")
    T.near(T.item_pos(ib), 0.955, 1e-4, "late inverted track moved by -45ms")
    local ta, _, pa = _G.SGMPhaseAlignment.findFirstTransient(ia)
    local tb, _, pb = _G.SGMPhaseAlignment.findFirstTransient(ib)
    T.near(ta, tb, TOL, "polarity-inverted pair transients coincide post-alignment")
    T.eq(pa, 1, "track A positive polarity")
    T.eq(pb, -1, "track B negative polarity")
  end)
end
