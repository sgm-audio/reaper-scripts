-- PHASE ALIGNMENT TOOL
-- @description Aligns quad-tracked DI guitars by transient onset
-- @author Scott Mills
-- @version 1.0
-- Auto-align quad-tracked guitars for tight metal production
-- Analyzes transients and aligns DI tracks before amp processing
-- Version 1.0

reaper.ClearConsole()
reaper.ShowConsoleMsg("=== PHASE ALIGNMENT TOOL ===\n\n")

-- ===================================
-- CONFIGURATION
-- ===================================

local CONFIG = {
  transient_threshold = 0.3,  -- Sensitivity for detecting pick attacks (0-1)
  analysis_window = 0.1,      -- Seconds to analyze for first transient
  alignment_precision = 0.0001, -- Sample-accurate alignment (0.1ms)
}

-- ===================================
-- UTILITY FUNCTIONS
-- ===================================

local function getSelectedTracks()
  local tracks = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    if track then
      table.insert(tracks, track)
    end
  end
  return tracks
end

local function getTrackItems(track)
  local items = {}
  local item_count = reaper.CountTrackMediaItems(track)
  for i = 0, item_count - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    if item then
      table.insert(items, item)
    end
  end
  return items
end

local function inspectTakeConfiguration(item, take)
  local take_count = (reaper.CountTakes and item) and reaper.CountTakes(item) or 1
  local start_offs = 0.0
  local playrate = 1.0
  if take and reaper.GetMediaItemTakeInfo_Value then
    local raw_offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
    if type(raw_offs) == "number" then
      start_offs = raw_offs
    end
    local raw_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    if type(raw_rate) == "number" then
      playrate = raw_rate
    end
  end
  if playrate <= 0 then
    return {
      valid = false,
      reason = string.format("unsupported take playrate (%.4f)", playrate),
      take_count = take_count,
      start_offs = start_offs,
      playrate = playrate,
    }
  end
  return {
    valid = true,
    take_count = take_count,
    start_offs = start_offs,
    playrate = playrate,
  }
end

local function findFirstTransient(item)
  local take = reaper.GetActiveTake(item)
  if not take then return nil end

  local take_cfg = inspectTakeConfiguration(item, take)
  if not take_cfg.valid then return nil end

  local source = reaper.GetMediaItemTake_Source(take)
  if not source then return nil end
  local sample_rate = reaper.GetMediaSourceSampleRate(source)
  local num_channels = reaper.GetMediaSourceNumChannels(source)

  if not sample_rate or sample_rate <= 0 or not num_channels or num_channels <= 0 then return nil end

  -- Get audio accessor (REAPER's take audio accessor applies D_STARTOFFS and D_PLAYRATE
  -- in item-timeline seconds relative to D_POSITION).
  local accessor = reaper.CreateTakeAudioAccessor(take)
  if not accessor then return nil end
  local start_time = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local accessor_start = reaper.GetAudioAccessorStartTime(accessor)
  local accessor_end = reaper.GetAudioAccessorEndTime(accessor)

  -- Analyze first 100ms for transient
  local samples_to_analyze = math.floor(math.min(CONFIG.analysis_window, accessor_end - accessor_start) * sample_rate)
  if samples_to_analyze <= 0 then
    reaper.DestroyAudioAccessor(accessor)
    return nil
  end
  local audio_buffer = reaper.new_array(samples_to_analyze * num_channels)

  -- Read audio data
  local status = reaper.GetAudioAccessorSamples(
    accessor,
    sample_rate,
    num_channels,
    accessor_start,  -- Take accessor time, not project position
    samples_to_analyze,
    audio_buffer
  )

  -- GetAudioAccessorSamples returns a status, NOT a frame count.
  if status ~= 1 then
    reaper.DestroyAudioAccessor(accessor)
    return nil
  end

  -- The requested frames are interleaved across channels.
  -- Record the first frame exceeding threshold (and its polarity) and scan the entire window for true peak.
  local transient_frame = nil
  local transient_polarity = nil
  local peak_value = 0
  for frame = 0, samples_to_analyze - 1 do
    local frame_best_abs = 0
    local frame_best_raw = nil
    for channel = 0, num_channels - 1 do
      local buffer_index = frame * num_channels + channel + 1
      local raw_sample = audio_buffer[buffer_index]
      local sample_value = math.abs(raw_sample)
      if sample_value > peak_value then
        peak_value = sample_value
      end
      if not transient_frame and sample_value > CONFIG.transient_threshold and sample_value > frame_best_abs then
        frame_best_abs = sample_value
        frame_best_raw = raw_sample
      end
    end
    if not transient_frame and frame_best_raw ~= nil then
      transient_frame = frame
      transient_polarity = frame_best_raw >= 0 and 1 or -1
    end
  end

  reaper.DestroyAudioAccessor(accessor)

  if transient_frame then
    local transient_time = start_time + accessor_start + (transient_frame / sample_rate)
    return transient_time, peak_value, transient_polarity
  else
    return nil, peak_value, nil
  end
end

local function nudgeItem(item, time_offset)
  local current_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local new_pos = math.max(0.0, current_pos + time_offset)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
  return new_pos - current_pos
end

-- ===================================
-- PHASE ALIGNMENT ENGINE
-- ===================================

local function alignSelectedTracks()
  local tracks = getSelectedTracks()

  if #tracks < 2 then
    reaper.ShowConsoleMsg("❌ Please select at least 2 tracks to align\n")
    reaper.ShowConsoleMsg("   (e.g., Rhythm L and Rhythm R guitar tracks)\n")
    reaper.ShowMessageBox(
      "Please select at least 2 tracks to align\n(e.g., Rhythm L and Rhythm R guitar tracks)",
      "Phase Alignment — No Tracks Selected", 0)
    return
  end

  reaper.ShowConsoleMsg("Analyzing " .. #tracks .. " selected tracks...\n\n")

  -- Step 1: Pre-flight validation and transient analysis across selected tracks
  local track_data = {}
  local preflight_warnings = {}
  local earliest_transient = nil
  local latest_transient = nil
  local detected_count = 0
  local seen_pos_polarity = false
  local seen_neg_polarity = false

  for i, track in ipairs(tracks) do
    local _, track_name = reaper.GetTrackName(track)
    track_name = (track_name and track_name ~= "") and track_name or ("Track " .. i)
    local items = getTrackItems(track)

    if #items > 0 then
      if #items > 1 then
        local multi_item_warn = string.format(
          "Track '%s' has %d items; only the first item is analyzed and moved",
          track_name, #items)
        table.insert(preflight_warnings, multi_item_warn)
        reaper.ShowConsoleMsg("  ⚠ " .. multi_item_warn .. "\n")
      end

      local first_item = items[1]
      local active_take = reaper.GetActiveTake(first_item)
      local take_cfg = active_take and inspectTakeConfiguration(first_item, active_take) or nil
      if not active_take then
        local no_take_warn = string.format("Track '%s': first item has no active take (skipped)", track_name)
        table.insert(preflight_warnings, no_take_warn)
        reaper.ShowConsoleMsg(string.format("  Track %d (%s): No active take (skipped)\n", i, track_name))
      elseif not take_cfg.valid then
        local bad_cfg_warn = string.format("Track '%s': %s (skipped)", track_name, take_cfg.reason)
        table.insert(preflight_warnings, bad_cfg_warn)
        reaper.ShowConsoleMsg(string.format("  Track %d (%s): Unsupported take configuration: %s\n",
          i, track_name, take_cfg.reason))
      else
        if take_cfg.take_count > 1 then
          local multi_take_warn = string.format(
            "Track '%s' first item has %d takes; only active take is analyzed (D_POSITION shifts all takes)",
            track_name, take_cfg.take_count)
          table.insert(preflight_warnings, multi_take_warn)
          reaper.ShowConsoleMsg("  ⚠ " .. multi_take_warn .. "\n")
        end
        if math.abs(take_cfg.playrate - 1.0) > 1e-6 then
          local rate_warn = string.format(
            "Track '%s' active take playrate is %.3fx (time-stretched; verify phase manually)",
            track_name, take_cfg.playrate)
          table.insert(preflight_warnings, rate_warn)
          reaper.ShowConsoleMsg("  ⚠ " .. rate_warn .. "\n")
        end
        if math.abs(take_cfg.start_offs) > 1e-9 then
          reaper.ShowConsoleMsg(string.format(
            "  ℹ Track %d (%s): take D_STARTOFFS %.4fs honored via audio accessor\n",
            i, track_name, take_cfg.start_offs))
        end

        local item_pos = reaper.GetMediaItemInfo_Value(first_item, "D_POSITION")
        local transient_time, peak, polarity = findFirstTransient(first_item)

        table.insert(track_data, {
          track = track,
          name = track_name,
          item = first_item,
          item_pos = item_pos,
          transient_time = transient_time,
          peak = peak,
          polarity = polarity,
        })

        if transient_time then
          detected_count = detected_count + 1
          if polarity == 1 then seen_pos_polarity = true
          elseif polarity == -1 then seen_neg_polarity = true end
          local pol_label = polarity == -1 and "-" or "+"
          reaper.ShowConsoleMsg(string.format("  Track %d (%s): Transient at %.4fs (peak: %.2f, polarity: %s)\n",
            i, track_name, transient_time, peak, pol_label))

          if not earliest_transient or transient_time < earliest_transient then
            earliest_transient = transient_time
          end
          if not latest_transient or transient_time > latest_transient then
            latest_transient = transient_time
          end
        else
          local no_tr_warn = string.format(
            "Track '%s': no transient > %.2f within first %.0fms window (peak: %.3f, skipped)",
            track_name, CONFIG.transient_threshold, CONFIG.analysis_window * 1000, peak or 0)
          table.insert(preflight_warnings, no_tr_warn)
          reaper.ShowConsoleMsg(string.format("  Track %d (%s): %s\n", i, track_name, no_tr_warn))
        end
      end
    else
      local no_item_warn = string.format("Track '%s': no media items (skipped)", track_name)
      table.insert(preflight_warnings, no_item_warn)
      reaper.ShowConsoleMsg(string.format("  Track %d (%s): No items found\n", i, track_name))
    end
  end

  if detected_count == 0 then
    reaper.ShowConsoleMsg("\n❌ No transients detected in any track\n")
    reaper.ShowConsoleMsg("   Try lowering the threshold or checking your audio\n")
    return
  end

  if detected_count < 2 then
    reaper.ShowConsoleMsg(string.format(
      "\n❌ Only %d track had a transient within the first %.0fms window; at least 2 tracks are required to align\n",
      detected_count, CONFIG.analysis_window * 1000))
    return
  end

  if seen_pos_polarity and seen_neg_polarity then
    local pol_warn = "Opposite transient polarity (+ vs -) detected: onset alignment adjusts timing only and does NOT invert polarity"
    table.insert(preflight_warnings, pol_warn)
    reaper.ShowConsoleMsg("\n⚠ " .. pol_warn .. "\n")
  end

  -- Avoid clamping items at 0.0s: if shifting left to earliest_transient would
  -- push any item before 0.0s, align right to latest_transient instead.
  local target_time = earliest_transient
  local target_label = "earliest"
  for _, data in ipairs(track_data) do
    if data.transient_time and (data.item_pos + (earliest_transient - data.transient_time)) < 0 then
      target_time = latest_transient
      target_label = "latest"
      break
    end
  end

  local planned_moves = {}
  for _, data in ipairs(track_data) do
    if data.transient_time then
      local offset = target_time - data.transient_time
      if math.abs(offset) > CONFIG.alignment_precision then
        table.insert(planned_moves, {data = data, offset = offset})
      end
    end
  end

  if #planned_moves == 0 then
    reaper.ShowConsoleMsg("\n✓ All analyzed items are already aligned within precision.\n")
    return
  end

  local confirm_lines = {
    string.format("Align %d track(s) (first item per track) to %s transient at %.4fs?",
      #planned_moves, target_label, target_time),
    "",
    string.format(
      "Scope: first item per track, first %.0fms analysis window, threshold-based onset alignment only (not waveform cross-correlation; does not invert polarity).",
      CONFIG.analysis_window * 1000),
  }
  if #preflight_warnings > 0 then
    table.insert(confirm_lines, "")
    table.insert(confirm_lines, "Pre-flight warnings:")
    for _, warning in ipairs(preflight_warnings) do
      table.insert(confirm_lines, "- " .. warning)
    end
  end

  local answer = reaper.ShowMessageBox(table.concat(confirm_lines, "\n"), "Phase Alignment", 1)
  if answer ~= 1 then
    reaper.ShowConsoleMsg("Phase alignment cancelled.\n")
    return
  end

  -- Step 2: Align all tracks to the chosen reference transient
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local ok, err = pcall(function()
    reaper.ShowConsoleMsg("\n=== ALIGNING TRACKS ===\n")
    reaper.ShowConsoleMsg("Reference time (" .. target_label .. "): " .. string.format("%.4fs", target_time) .. "\n\n")

    for _, data in ipairs(track_data) do
      if data.transient_time then
        local offset = target_time - data.transient_time
        if math.abs(offset) > CONFIG.alignment_precision then
          local actual_offset = nudgeItem(data.item, offset)
          if math.abs(actual_offset - offset) > CONFIG.alignment_precision then
            reaper.ShowConsoleMsg(string.format("  ⚠ %s: Requested %.4fs, applied %.4fs (clamped at 0.0s)\n",
              data.name, offset, actual_offset))
          else
            reaper.ShowConsoleMsg(string.format("  ✓ %s: Adjusted by %.4fs\n", data.name, actual_offset))
          end
        else
          reaper.ShowConsoleMsg(string.format("  ✓ %s: Already aligned\n", data.name))
        end
      end
    end
  end)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Align Guitar Tracks (Phase)", -1)
  reaper.UpdateArrange()

  if not ok then
    reaper.ShowMessageBox("Phase alignment failed:\n" .. tostring(err), "Phase Alignment", 0)
    return
  end

  reaper.ShowConsoleMsg("\n✅ Phase alignment complete!\n")
  reaper.ShowConsoleMsg("\nNEXT STEPS:\n")
  reaper.ShowConsoleMsg("  1. Check alignment: Play and listen for a tight 'wall'\n")
  reaper.ShowConsoleMsg("  2. Mono test: Click Mono on master - should sound louder, not thinner\n")
  reaper.ShowConsoleMsg("  3. Add amp sims to your DI tracks\n\n")
end

-- ===================================
-- CORRELATION ANALYZER
-- ===================================

local function analyzePhaseCorrelation()
  reaper.ShowConsoleMsg("=== ITEM TIMING ALIGNMENT ANALYZER ===\n\n")

  local tracks = getSelectedTracks()

  if #tracks ~= 2 then
    reaper.ShowConsoleMsg("❌ Please select exactly 2 tracks for item-position timing comparison\n")
    return
  end

  local track1, track2 = tracks[1], tracks[2]
  local _, name1 = reaper.GetTrackName(track1)
  local _, name2 = reaper.GetTrackName(track2)

  reaper.ShowConsoleMsg("Comparing item-position timing between:\n")
  reaper.ShowConsoleMsg("  Track 1: " .. name1 .. "\n")
  reaper.ShowConsoleMsg("  Track 2: " .. name2 .. "\n\n")

  -- Get first items
  local items1 = getTrackItems(track1)
  local items2 = getTrackItems(track2)

  if #items1 == 0 or #items2 == 0 then
    reaper.ShowConsoleMsg("❌ One or both tracks have no items\n")
    return
  end

  local item1, item2 = items1[1], items2[1]
  local take1 = reaper.GetActiveTake(item1)
  local take2 = reaper.GetActiveTake(item2)

  if not take1 or not take2 then
    reaper.ShowConsoleMsg("❌ Could not access takes\n")
    return
  end

  local function hasAudio(take)
    local source = reaper.GetMediaItemTake_Source(take)
    if not source then return false end
    local channels = reaper.GetMediaSourceNumChannels(source)
    return type(channels) == "number" and channels > 0
  end
  if not hasAudio(take1) or not hasAudio(take2) then
    reaper.ShowConsoleMsg("❌ One or both first items have no audio source (MIDI/empty/text?)\n")
    return
  end

  -- Item-position timing comparison
  local source1 = reaper.GetMediaItemTake_Source(take1)
  local sample_rate = source1 and reaper.GetMediaSourceSampleRate(source1) or 0
  if not sample_rate or sample_rate <= 0 then
    sample_rate = 48000
  end
  local pos1 = reaper.GetMediaItemInfo_Value(item1, "D_POSITION")
  local pos2 = reaper.GetMediaItemInfo_Value(item2, "D_POSITION")
  local time_diff = math.abs(pos1 - pos2)

  reaper.ShowConsoleMsg("Position difference: " .. string.format("%.4fs (%.1f samples @ %dHz)\n",
    time_diff, time_diff * sample_rate, sample_rate))

  if time_diff < 0.0002 then  -- Less than 0.2ms
    reaper.ShowConsoleMsg("\n✅ EXCELLENT: Item positions are within 0.2ms\n")
    reaper.ShowConsoleMsg("   Item positions alone do not establish phase or mono compatibility.\n")
  elseif time_diff < 0.001 then  -- Less than 1ms
    reaper.ShowConsoleMsg("\n✓ GOOD: Tracks are well aligned\n")
    reaper.ShowConsoleMsg("   Minor timing differences add natural width\n")
  elseif time_diff < 0.005 then  -- Less than 5ms
    reaper.ShowConsoleMsg("\n⚠ ACCEPTABLE: Slight timing difference\n")
    reaper.ShowConsoleMsg("   May cause subtle phase issues in mono\n")
  else
    reaper.ShowConsoleMsg("\n❌ WARNING: Significant misalignment detected\n")
    reaper.ShowConsoleMsg("   Run the alignment tool to fix this\n")
  end
end

-- ===================================
-- MANUAL NUDGE TOOL
-- ===================================

local function nudgeSelectedItems(direction, amount)
  local num_items = reaper.CountSelectedMediaItems(0)

  if num_items == 0 then
    reaper.ShowConsoleMsg("No items selected\n")
    return
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local nudge_amount = amount * direction
  local ok, err = pcall(function()
    for i = 0, num_items - 1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      if item then
        nudgeItem(item, nudge_amount)
      end
    end
  end)

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Nudge Items", -1)
  reaper.UpdateArrange()

  if not ok then
    reaper.ShowMessageBox("Nudge failed:\n" .. tostring(err), "Phase Alignment", 0)
    return
  end
  reaper.ShowConsoleMsg(string.format("Nudged %d items by %.4fs\n", num_items, nudge_amount))
end

-- ===================================
-- MAIN MENU
-- ===================================

local function showMenu()
  local menu = ""
  menu = menu .. "1. Auto-Align Selected Tracks (Quad-Track Guitar)|"
  menu = menu .. "2. Analyze Item Timing Difference (2 tracks)|"
  menu = menu .. "Nudge Left 1ms|"
  menu = menu .. "Nudge Right 1ms|"
  menu = menu .. "Nudge Left 0.1ms (fine)|"
  menu = menu .. "Nudge Right 0.1ms (fine)|"
  menu = menu .. "Settings..."

  local mx, my = gfx.mouse_x or 0, gfx.mouse_y or 0
  if reaper.GetMousePosition then
    local rx, ry = reaper.GetMousePosition()
    if rx and ry then mx, my = rx, ry end
  end
  if gfx.init then
    gfx.init("", 0, 0, 0, mx, my)
    gfx.x, gfx.y = 0, 0
  else
    gfx.x, gfx.y = mx, my
  end
  local result = gfx.showmenu(menu)
  if gfx.quit then gfx.quit() end

  if result == 1 then
    alignSelectedTracks()
  elseif result == 2 then
    analyzePhaseCorrelation()
  elseif result == 3 then
    nudgeSelectedItems(-1, 0.001)
  elseif result == 4 then
    nudgeSelectedItems(1, 0.001)
  elseif result == 5 then
    nudgeSelectedItems(-1, 0.0001)
  elseif result == 6 then
    nudgeSelectedItems(1, 0.0001)
  elseif result == 7 then
    reaper.ShowConsoleMsg("=== SETTINGS ===\n")
    reaper.ShowConsoleMsg("Transient Threshold: " .. CONFIG.transient_threshold .. "\n")
    reaper.ShowConsoleMsg("Analysis Window: " .. CONFIG.analysis_window .. "s\n")
    reaper.ShowConsoleMsg("\nEdit these values at the top of the script\n")
  end
end

_G.SGMPhaseAlignment = {
  CONFIG = CONFIG,
  inspectTakeConfiguration = inspectTakeConfiguration,
  findFirstTransient = findFirstTransient,
  alignSelectedTracks = alignSelectedTracks,
}

-- Run menu
showMenu()
