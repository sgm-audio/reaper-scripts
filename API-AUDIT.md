# REAPER API Conformance Audit — ReaScripts

**Audit date:** 2026-11-12  
**Branch:** `arena/19dda839-reaper-scripts` (from `main` @ `114b6e8`)  
**Scope:** The 11 tracked ReaScript (Lua) files in the repository root  
**Reference:** Official REAPER ReaScript API docs (REAPER v7.85),
https://www.reaper.fm/sdk/reascript/reascripthelp.html  
**Language target:** Lua 5.4 (REAPER 7), per `AGENTS.md`  
**Verification environment:** Lua 5.4.6 compiled from source (no system Lua/interactive REAPER in this sandbox)

## Method

Every `reaper.*`, `gfx.*`, and `io/os` call in each ReaScript was checked
against the official API function list. Scripts were then executed with the
repository's own validation harness (stubbed REAPER API) plus a small
standalone demonstration of the real documented semantics for the APIs most
likely to be misused.

Repo checks, run with a locally compiled Lua 5.4.6:

| Check | Result |
|-------|--------|
| `lua5.4 -e "assert(loadfile('$f'))"` — all 11 scripts | 11/11 pass |
| `tests/lua_smoke.lua` per script (stubbed REAPER) | 11/11 pass (RUN-OK) |
| `tests/lua_regression.lua` | 72/72 pass |

The stub-based checks pass both before and after the change below; the stubs
deliberately mask the API-signature defect in F1 (they return 0 for every
`TrackFX_AddByName`, so no warning is ever raised). That is exactly the
"stubs mask bugs" failure mode `AGENTS.md` warns about; the standalone
semantics demo in `/tmp/verify_api.lua` reproduces the real behavior.

## Per-script conformance

| File | API surface | Status |
|------|-------------|--------|
| `Reaper AI Control Hub.lua` | TrackFX_GetCount, TrackFX_GetFXName, GetMasterTrack, GetResourcePath, GetOS, GetProjectPath, RecursiveCreateDirectory, gfx.showmenu, io stdlib | Conformant; see F4 |
| `SGM_Professional_Session_Builder.lua` | CountTracks, InsertTrackAtIndex, GetTrack, GetSetMediaTrackInfo_String, SetTrackColor, ColorToNative, SetMediaTrackInfo_Value, TrackFX_AddByName, GetTrackName, CreateTrackSend, SetTrackSendInfo_Value, Undo_BeginBlock/EndBlock, PreventUIRefresh, TrackList_AdjustWindows, UpdateArrange, ShowMessageBox, gfx.showmenu | **F1 — bug found and fixed** |
| `SGM_plugin_development_blueprint.lua` | GetProjectPath, ShowMessageBox, RecursiveCreateDirectory, io stdlib | Conformant (F5 cosmetic) |
| `VALIDATE-ALL-SCRIPTS.lua` | loadfile, ClearConsole, ShowConsoleMsg | Conformant |
| `list-all-available-plugins.lua` | EnumerateFiles, EnumerateSubdirectories, GetResourcePath, io stdlib, os.date | Conformant |
| `phase-alignment-tool.lua` | CountSelectedTracks/GetSelectedTrack, CountTrackMediaItems/GetTrackMediaItem, GetActiveTake, GetMediaItemTake_Source, GetMediaSourceSampleRate/NumChannels, CreateTakeAudioAccessor/DestroyAudioAccessor, GetAudioAccessorSamples, GetMediaItemInfo/SetMediaItemInfo_Value (D_POSITION), CountSelectedMediaItems/GetSelectedMediaItem, Undo block, gfx.showmenu | Conformant |
| `plugin-wrapper.lua` | TrackFX_GetCount/Name/NumParams/Param/SetParam/ParamName/GetFormattedParamValue, GetPresetIndex/SetPreset/SetPresetByIndex, GetEnabled/SetEnabled, Delete, GetNamedConfigParm("vst_chunk"), GetFXEnvelope, InsertEnvelopePoint, Envelope_SortPoints, Master_GetTempo, GetCursorPosition, GetLastTouchedFX, GetMasterTrack/GetTrack, EnumerateFiles/Subdirectories, gfx.showmenu | Conformant; F3 note |
| `reaper-template-installer.lua` | GetResourcePath, ShowMessageBox/ConsoleMsg, RecursiveCreateDirectory, io stdlib | Conformant |
| `rule-of-30-plugin-presets.lua` | Data-only module (returns a table); helpers use TrackFX_GetCount/GetFXName | Conformant |
| `scan-real-plugins.lua` | GetOS, GetResourcePath, EnumerateFiles/Subdirectories, time_precise, io stdlib, os.date | Conformant |
| `signal-chain-presets.lua` | Data-only module (returns a table); no API calls at top level | Conformant (no API surface) |

### API calls verified against official signatures

- `TrackFX_AddByName(track, fxname, recFX, instantiate)` — returns -1 on failure, else chain position.
- `SetTrackSendInfo_Value(tr, category, sendidx, parmname, value)` — category `0` = sends (as used); dB→linear `10^(db/20)` matches the docs' `exp(db/8.68588963806)`.
- `TrackFX_GetPresetIndex(track, fx)` — returns `(current_index, numberOfPresets)`; the wrapper captures `numberOfPresets` correctly.
- `TrackFX_GetNamedConfigParm(track, fx, "vst_chunk")` — supported read/write value since REAPER 6.71 (base64 VST chunk); valid on REAPER 7.
- `GetLastTouchedFX()` — returns `(touched, tracknumber, fxnumber, paramnumber)`; tracknumber `0` = master, `1` = track 1; fx/param numbers are zero-based.
- `GetProjectPath("")` — documented Lua signature takes a dummy string; scripts pass `0`, which works in practice but does not match the documented signature.

## Findings

### F1 — Confirmed defect: `TrackFX_AddByName` misused in session builder (FIXED)

**File:** `SGM_Professional_Session_Builder.lua`, `addPlugins`

Before:
```lua
local fx_index = reaper.TrackFX_AddByName(template._track, fx_name, 1)
```

The documented 3rd argument is `recFX` (boolean, record-input FX), **not** an
install flag. The 4th argument `instantiate` controls creation: negative =
always add, `0` = query only, positive = add if missing. Omitting it passes
`nil`, which the C binding treats as `0` (query only). Combined with
`recFX = true`, the call searches the track's record-input FX chain and never
installs stock ReaPlugins — so every `ReaEQ`/`ReaComp`/`ReaLimit` addition
returns -1 and the script reports "stock FX unavailable" for every track while
adding no FX.

Fix applied:
```lua
local fx_index = reaper.TrackFX_AddByName(template._track, fx_name, false, 1)
```
`recFX = false` (normal FX chain), `instantiate = 1` (add if not found).

**Verification:** standalone semantics demo against the documented model:
- Before: all 3 stock FX missing, chain empty.
- After: all 3 stock FX added, chain length 3.

The regression suite's `TrackFX_AddByName` stub returns `0` unconditionally,
so it cannot detect this recurrence; a targeted stub returning -1 for
`recFX=true`/`instantiate=0` should be added to `tests/lua_regression.lua`.

### F2 — Investigated, not a bug: zero-based index guards in `plugin-wrapper.lua`

`automateSelectedPlugin` used `not fx_index / not param_index` on values from
`GetLastTouchedFX`. In Lua, `0` is truthy (only `nil`/`false` are falsy), so
zero-based index `0` (first FX / first parameter) is **not** rejected by
`not`; only `touched == false` or a negative index rejects. The guard was
simplified to `fx_index < 0 or param_index < 0` (behaviorally identical,
clearer intent) — no functional change required.

### F3 — Note: deprecated API in `plugin-wrapper.lua`

`GetLastTouchedFX()` is marked "deprecated, use GetTouchedOrFocusedFX instead"
in the REAPER 7 docs. Both require REAPER 7.0+, which is this repo's target,
so the call is valid. Migration to `GetTouchedOrFocusedFX` is recommended
when the script is next touched.

### F4 — Note: plugin format detection cannot work from FX names

`Reaper AI Control Hub.lua:_detect_plugin_type` searches `TrackFX_GetFXName`
results for `".vst3"`, `".clap"`, etc. REAPER returns display names without
format suffixes, so this always reports `"Unknown"`. The discovery results are
informational only (no state changes), so this is cosmetic; either drop format
detection or document it as best-effort.

### F5 — Cosmetic: numeric dummy argument to `GetProjectPath`

`GetProjectPath(0)` appears in `Reaper AI Control Hub.lua` and
`SGM_plugin_development_blueprint.lua`. The documented Lua signature is
`reaper.GetProjectPath("")` (the argument is ignored/dummy). Passing `0`
works in practice but does not match the documented signature; `""` is
preferred.

## Cross-cutting observations

1. **Stub-based tests mask real API misuse.** F1 is invisible to `tests/lua_regression.lua`
   because its `TrackFX_AddByName` stub returns `0` for every call. Any future
   API-signature change should be paired with a stub that models documented
   failure returns (-1).
2. **JSON escaping order is correct** in all three writers
   (`list-all-available-plugins.lua`, `scan-real-plugins.lua`,
   `Reaper AI Control Hub.lua`): backslash first, then quotes, then control
   characters — matching `AGENTS.md` conventions.
3. **Send routing math is correct:** `SetTrackSendInfo_Value(..., "D_VOL", 10 ^ (level_db / 20))`
   matches the documented linear-gain expectation.
4. **Preset/data files (`rule-of-30-plugin-presets.lua`, `signal-chain-presets.lua`)**
   expose no API surface; they are data libraries, not chain loaders, as
   documented in `README.md`.
5. **Undo-block hygiene** in the session builder (`Undo_BeginBlock` … `Undo_EndBlock`
   wrapping create+FX+routing, `PreventUIRefresh` paired) conforms to REAPER
   practice. Early returns in the phase tool occur before `Undo_BeginBlock`,
   so no orphaned undo blocks.

## Recommendations

1. Keep the F1 fix; add a regression stub for `TrackFX_AddByName` returning -1
   when called with `recFX=true`/instantiate `0`.
2. Migrate `plugin-wrapper.lua` from `GetLastTouchedFX` to
   `GetTouchedOrFocusedFX`.
3. Correct or document the informational-only nature of F4's format detection.
4. Pass `""` to `GetProjectPath` where the value is unused (F5).
5. Remaining manual QA from `AUDIT.md` (generated RPP, session-builder modes,
   phase tool, plugin caches on each OS) is unchanged and still required
   before release; no interactive REAPER is available in this sandbox.

## Diff summary

- `SGM_Professional_Session_Builder.lua` — `TrackFX_AddByName` call corrected
  to `(track, fx_name, false, 1)`; comment added documenting the signature.
- `plugin-wrapper.lua` — `automateSelectedPlugin` guard simplified to explicit
  `< 0` checks (behavior identical under Lua semantics; `0` is truthy).
