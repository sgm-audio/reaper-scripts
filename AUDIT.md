# Repository Audit and QA Report

**Audit date:** 2026-11-06  
**Scope:** All tracked Lua scripts, Python helpers, tests, CI configuration,
packaging, documentation, generated-file destinations, and platform-specific
paths in this checkout.

## Executive summary

The audit found that syntax/import checks had been passing while several core
actions were placeholders or could not run. The highest-risk problems were a
session builder using invalid REAPER APIs, an installer calling undefined
helpers, false-success CLI behavior, data-losing plugin persistence, invalid
JSON, and Windows-only paths in cross-platform scanners.

Those areas were repaired or replaced with narrower, honest implementations.
Focused regression tests were added for the confirmed defects. Features that do
not exist (automatic third-party chain installation, external rendering,
48+ track/folder generation, and buildable plugin scaffolding) are no longer
reported as working.

## Findings and resolutions

| Severity | Finding | Resolution |
|----------|---------|------------|
| Critical | Session builder called nonexistent track/deletion/automation APIs, had missing session modes, and passed dB directly as REAPER send gain | Rebuilt around valid append/track/send APIs; four modes, one undo block, stock FX, linear gain conversion, existing-project preservation |
| Critical | Installer advertised templates/toolbars/shortcuts but called undefined helpers and could alter the open project | Replaced with a confirmed, manifest-driven copier for files that actually exist; no project/preference mutation |
| High | Suno CLI printed success and returned 0 after `process_suno_track()` returned a failure | CLI now checks `WorkflowResult.success` and returns 1 with an error |
| High | Suno “auto import” generated empty tracks; output roots, custom names, original extensions, and reruns were unsafe | RPP now contains relative media items/durations; output-root handling, traversal rejection, overwrite protection, codec-preserving copy, and honest custom-template behavior added |
| High | Plugin inventory parser referenced an out-of-scope `plugins` variable and did not parse REAPER's documented cache rows | Cache parser rewritten; quoted commas, multiple formats, JSFX, categories, and deduplication covered by tests |
| High | `plugin-wrapper.lua` discarded saved contents on every load and emitted insufficiently escaped JSON | Added round-trip persistence for its flat schema, proper escaping, corrupt-data rejection, and regression tests |
| High | Lua scanners concatenated `\` on macOS/Linux and missed directory-based VST3/AU/LV2 bundles | Portable `/` joins and bundle-aware enumeration added across scanners |
| High | Lua JSON writers escaped in the wrong order or not at all | Centralized escaping per writer; control characters, quotes, and backslashes handled; focused output/round-trip checks added |
| High | Generic smoke stubs returned tables for numeric APIs and never ended enumeration | Concrete scalar/path/menu stubs added; CI now treats every unexpected exit code as failure |
| High | Existing module suite tested nonexistent `AIProductionSystem`; optional skips were reported as passes | Tests now target real classes; separate pass/skip totals; 10 new Python regressions added |
| High | Last-touched automation used the selected track and parameter zero | Uses the actual touched track, FX, and parameter; envelope failure is reported |
| Medium | Phase tool treated interleaved audio as mono, used scalar sample indexes as time, disabled menu items, and left undo blocks open on early returns | Frame/channel indexing corrected, menus enabled, undo begins only when edits are possible; timing analysis no longer called correlation |
| Medium | Async executor forwarded unsupported keyword arguments; monitor IDs could collide; failed operations had incomplete metrics | `functools.partial`, UUID IDs, cleanup/close methods, failure duration, concurrent batch copies, and validation added |
| Medium | Plugin DB initialization repeatedly inserted duplicate alternatives; DB export/import only printed claims | Relationship replacement/idempotence and real JSON round trips implemented |
| Medium | AAF module assumed REAPER and `aaf2` were always present; files were not reliably closed | Runtime/dependency guards, safe standalone import, close/finally handling, empty-composition and metadata checks added |
| Medium | UUID exporter could crash on missing `APPDATA` and mishandled quoted names | Environment guards, noninteractive CLI options, CSV parsing, and nonzero failures added |
| Medium | Packaging referenced placeholder URLs, absent entry points/modules, and mismatched dependencies | Real modules/URLs/dependencies, Python 3.9 floor, standard `setup.py`, and package metadata check added |
| Medium | Development scaffolder did not create directories and claimed a buildable project | Confirmed directory-only scaffold; existing files protected; no bogus CMake/plugin success |
| Low | Documentation referenced nonexistent menus, implicit templates, stale install paths, and unsupported capabilities | README, both workflow guides, contributor instructions, installer manifest, and this report updated |

## Verification record

The following checks are wired into CI and were run locally under Python 3.11
and Lua 5.4 (via the Lua 5.4 runtime):

| Check | Result |
|-------|--------|
| Python compilation (`compileall`) | Pass |
| pyflakes | Pass after filtering only REAPER-injected `RPR_*` names |
| `test_modules.py` | 3/3 pass |
| `tests/test_regressions.py` | 10/10 pass |
| Suno comprehensive suite | 6 pass, 17 optional-module skips, 0 failures |
| Lua syntax, all 11 ReaScripts | Pass |
| Lua smoke, all 11 ReaScripts | Pass |
| `tests/lua_regression.lua` | 54/54 checks pass |
| Setuptools metadata and wheel build (`python setup.py --name`, `pip wheel --no-deps .`) | Pass |

No optional YourMT3, batch processor, or SEMAS code is present, so those 17
integration tests are explicitly skipped rather than counted as successful.

## Path and generated-file audit

| Output | Current destination / behavior |
|--------|-------------------------------|
| `plugin_inventory.json` | REAPER resource path |
| `rule-of-30-plugins.json` | REAPER resource path |
| `ai_routing_template.json` | REAPER resource path; unsaved projects do not cause root-relative writes |
| `plugin_database.json` | REAPER resource path; saved data now reloads |
| Installed scripts/docs | `<resource>/Scripts/ScottMills/` and `Documentation/` beneath it |
| Suno projects | Explicit output root, or beside the source; project name is one safe path component |
| Suno logs | Console by default; file only when `SUNO_LOG_FILE` is set |
| UUID map | Explicit `-o`, otherwise `reaper_plugin_map.json` in the caller's chosen cwd |
| Plugin compatibility DB | Explicit constructor path, otherwise legacy `plugin_compatibility.db` in cwd (ignored by Git) |
| External AI renders | No files are created automatically; manual target directory is printed |

## Remaining limitations and manual QA

The sandbox does not provide an interactive REAPER installation, real plugin
folders from every OS, third-party AI modules, or AAFs from multiple DAWs. The
following therefore remain **manual integration checks**, not claimed passes:

1. **Generated RPP:** Open WAV, MP3, FLAC, OGG, and M4A workflows in REAPER 7;
   verify media source types, durations, relative-path relocation, mute state,
   and custom-template instructions.
2. **Session builder:** Run each mode in a populated project; inspect all sends,
   direct-master-send flags, stock FX, duplicate-name behavior, and one-step undo.
3. **Phase tool:** Test mono/stereo items, take offsets/play rates, multiple items,
   quiet transients, and nudge actions. Validate alignment by ear; the tool is not
   a full phase/polarity analyzer.
4. **Plugin caches:** Compare inventories on current Windows/macOS/Linux REAPER
   builds. Unknown cache formats are skipped; cache availability depends on a
   REAPER plugin rescan.
5. **AAF import:** Test linked/embedded essence and automation with AAFs from the
   actual source DAWs. Broad AAF-variant compatibility cannot be proven by stubs.
6. **Optional AI modules:** Run their skipped suites only after installing the
   exact external forks expected by the caller.

Intentional limitations are also documented for users: preset Lua files are data,
not chain loaders; the AI hub does not render/launch automatically; the builder
does not create a 48+ track folder hierarchy, third-party chains, sidechains, or
automation; and the development scaffold is not a buildable plugin.
