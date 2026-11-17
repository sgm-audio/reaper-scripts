# TODO — Static Quality & REAPER API Audit Fixes

Tracked from the static quality and REAPER API correctness audit of `sgm-audio/reaper-scripts`.

## Critical / High Priority

- [x] **`reaper_ai_integration.py` — Undo & UI-refresh wrapping in `build_project()`**
  - Wrap `build_project()` in `RPR_Undo_BeginBlock()` + `RPR_PreventUIRefresh(1)` and a `try ... finally` that restores `RPR_PreventUIRefresh(-1)` and `RPR_Undo_EndBlock("Import AAF", -1)` (and cleans up `self.insertion_track` if unused).
- [x] **`reaper_ai_integration.py` — Replace `RPR_InsertMedia` / `insertion_track` hack in `create_item()`**
  - Use `RPR_AddMediaItemToTrack(track)`, `RPR_AddTakeToMediaItem(item)`, `RPR_PCM_Source_CreateFromFile(src)` (with null checks), and `RPR_SetMediaItemTake_Source(take, pcm)`. Avoids edit-cursor mutation, null-item crashes on missing essence, and orphaned `"Insertion"` tracks.
- [x] **`reaper_ai_integration.py` — Query envelope scaling mode in `set_track_volume_envelope()`**
  - Replace hardcoded `RPR_ScaleToEnvelopeMode(1, ...)` with `RPR_ScaleToEnvelopeMode(RPR_GetEnvelopeScalingMode(envelope), ...)`, and guard `envelope` against `None` in both `set_track_volume_envelope()` and `set_track_panning_envelope()`.
- [x] **`reaper_ai_integration.py` — Fix infinite modal loop in `UserInteraction.get_composition_awkward()`**
  - Remove `while True:` so declining all compositions returns `None` and cancels cleanly instead of trapping REAPER.
- [x] **`suno_workflow_helper.py` — Fix invalid RPP token `B_MUTE 1`**
  - Replace `B_MUTE 1` with `MUTESOLO 1 0 0` in `_create_basic_project()` so the reference track actually loads muted in REAPER.
- [x] **`phase-alignment-tool.lua` — Undo/UI-refresh safety & nil guards**
  - Wrap `alignSelectedTracks()` and `nudgeSelectedItems()` in `PreventUIRefresh(1)` + `pcall` + `PreventUIRefresh(-1)`, only open an undo block when items are actually modified, and add `if item then` nil guard in `nudgeSelectedItems()`.
- [x] **`plugin-wrapper.lua` — Undo/UI-refresh wrapping on mutating paths**
  - Wrap `automateSelectedPlugin()` (and `automateParameter` / `createSweep`) in `Undo_BeginBlock()` / `PreventUIRefresh(1)` / `pcall` / `PreventUIRefresh(-1)` / `Undo_EndBlock(..., -1)`.
- [x] **`list-all-available-plugins.lua` — Fix REAPER plugin cache filenames**
  - Replace non-existent `reaper-clap-plugins64.ini`, `reaper-au-plugins64.ini`, `reaper-lv2-plugins64.ini` with `reaper-auplugins64.ini`, `reaper-auplugins_arm64.ini`, `reaper-lv2plugins64.ini`, `reaper-vstplugins_arm64.ini`, and dynamically enumerate `reaper-clap-*.ini`.

## Medium Priority

- [x] **`reaper_ai_integration.py` — Guard `parse_sequence` `items[-1]` and `show_progressbar` Tk lifecycle**
  - Guard `if fade == 0 and items:` before indexing `items[-1]`; remove `window.mainloop()` after `window.destroy()`; fix `if fadein is not None:` / `if fadeout is not None:` in `set_item_fades()`.
- [x] **`plugin-wrapper.lua` — Guard tempo division, JSON parse/save errors, and track nil checks**
  - Check `tempo and tempo > 0` in `automateParameter()`; check `self.db:save()` return value in `performFullScan()`; add `self.track` nil guards in `PluginInstance`.
- [x] **`Reaper AI Control Hub.lua` — Escape JSON in `create_ai_routing_template()` & fix `"ai"`/`"ml"` matching**
  - Use a proper `json_string()` helper with deterministic key ordering and numeric `channel`; use word-boundary patterns (`%f[%w]ai%f[%W]`, `%f[%w]ml%f[%W]`) so `"Gain"`/`"Chain"` are not misclassified as AI plugins.
- [x] **`tests/lua_*.lua` — Expand contract & regression coverage**
  - Add strict `reaper.*` arity/existence checks (`GetProjectPath` 0-arg), undo/UI-refresh error-path balance tests, `list-all-available-plugins.lua` AU/LV2/CLAP cache tests, `plugin-wrapper.lua` automation undo tests, and `Reaper AI Control Hub.lua` JSON escaping tests.
- [x] **`tests/test_regressions.py` — Add RPP `MUTESOLO 1 0 0` and `reaper_ai_integration.py` `RPR_*` mock tests**
  - Assert `suno_workflow_helper.py` emits `MUTESOLO 1 0 0` (not `B_MUTE 1`) and test `ReaperInterface.build_project()` + `get_composition_awkward()` with mock `RPR_*` globals.

## Low Priority / Hygiene

- [x] **Fix `reaper.GetProjectPath(0)` -> `reaper.GetProjectPath()`** in `Reaper AI Control Hub.lua` and `SGM_plugin_development_blueprint.lua`.
- [x] **Localize leaked globals** across `Reaper AI Control Hub.lua`, `SGM_Professional_Session_Builder.lua`, `SGM_plugin_development_blueprint.lua`, `list-all-available-plugins.lua`, `plugin-wrapper.lua`, `rule-of-30-plugin-presets.lua`, and `signal-chain-presets.lua`.
- [x] **Add nil guards** in `rule-of-30-plugin-presets.lua` (`findPlugin`, `getChainForTrack`), fix dead ternary in `SGM_Professional_Session_Builder.lua:110`, use `ProgramFiles` env vars on Windows in `plugin-wrapper.lua` / `scan-real-plugins.lua` / `Reaper AI Control Hub.lua`, and add depth guard to `scan-real-plugins.lua:scanDirectory`.
- [x] **`plugin/Source/PluginProcessor.cpp` — Minor RT/DSP polish**
  - Cache `std::atomic<float>*` parameter pointers in constructor, smooth/sync gain on bypass, and guard `sampleRate > 0` in `prepareToPlay`.
- [x] **Add `.luacheckrc`** for `std = "lua54"` and `read_globals = {"reaper", "gfx", "ImGui"}`.
