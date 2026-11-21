-- Live REAPER 7.x tests opening real generated Suno .rpp files across WAV, MP3, FLAC, OGG, and M4A.
return function(T)
  local rpp_dir = os.getenv("SGM_SUNO_RPP_DIR")
  if not rpp_dir or rpp_dir == "" then
    return
  end

  local formats = {"wav", "mp3", "flac", "ogg", "m4a"}
  for _, fmt in ipairs(formats) do
    T.test("suno.live.rpp_opens_cleanly_" .. fmt, function()
      local rpp_path = rpp_dir .. "/suno_" .. fmt .. "/suno_" .. fmt .. ".rpp"
      local fh = io.open(rpp_path, "rb")
      T.ok(fh ~= nil, "generated .rpp exists: " .. rpp_path)
      if fh then fh:close() end

      reaper.Main_openProject("noprompt:" .. rpp_path)
      local ntracks = reaper.CountTracks(0)
      T.eq(ntracks, 5, fmt .. ": 4 stem tracks + 1 reference track")

      local found_muted_ref = false
      for i = 0, ntracks - 1 do
        local tr = reaper.GetTrack(0, i)
        local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        local nitems = reaper.CountTrackMediaItems(tr)
        T.eq(nitems, 1, fmt .. " track " .. name .. " must have 1 item")
        local item = reaper.GetTrackMediaItem(tr, 0)
        local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        T.ok(item_len >= 1.8 and item_len <= 2.3,
          fmt .. " track " .. name .. " item length expected ~2.0s, got " .. tostring(item_len))

        local take = reaper.GetActiveTake(item)
        T.ok(take ~= nil, fmt .. " track " .. name .. " active take")
        local src = reaper.GetMediaItemTake_Source(take)
        T.ok(src ~= nil, fmt .. " track " .. name .. " PCM source loaded")
        local sr = reaper.GetMediaSourceSampleRate(src)
        local ch = reaper.GetMediaSourceNumChannels(src)
        local src_len = reaper.GetMediaSourceLength(src)
        T.ok(sr > 0, fmt .. " track " .. name .. " decoded sample rate > 0 (got " .. tostring(sr) .. ")")
        T.ok(ch >= 1, fmt .. " track " .. name .. " decoded channels >= 1 (got " .. tostring(ch) .. ")")
        T.ok(src_len >= 1.8 and src_len <= 2.3,
          fmt .. " track " .. name .. " decoded source length ~2.0s (got " .. tostring(src_len) .. ")")

        local src_fn = reaper.GetMediaSourceFileName(src, "")
        if src_fn:lower():find("original_mix." .. fmt, 1, true) then
          local muted = reaper.GetMediaTrackInfo_Value(tr, "B_MUTE")
          T.eq(muted, 1.0, fmt .. " reference track must be muted (MUTESOLO 1 0 0)")
          found_muted_ref = true
        end
      end
      T.ok(found_muted_ref, fmt .. ": muted reference track original_mix." .. fmt .. " verified")
      T.log("SUNO_RPP_OK", fmt, "tracks=" .. ntracks)
    end)
  end
end
