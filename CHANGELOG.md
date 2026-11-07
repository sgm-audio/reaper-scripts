# Changelog

All notable changes to this repository. Format follows Keep a Changelog.

## [Unreleased]

### Added

- `yourmt3-stems --download-model` to preload and load-test the real Demucs
  backend without processing audio. The README now links the official HTDemucs
  model, YAML/weight downloads, verified size/SHA-256, legacy fallback, cache
  locations, manual `hf download` alternative, and CPU/GPU setup instructions.
- A complete `plugin/` JUCE 8.0.4/CMake baseline with VST3, Standalone, native
  processing tests, smoothed gain/bypass, parameter state, bus validation, and
  an editor. The Lua blueprint copies these exact sources transactionally, and
  the installer carries them without compiling or installing a binary.
- Bundled `yourmt3_stem_separator.py` (Demucs-backed), `batch_process_suno.py`,
  and the `SEMAS/` job/API/CLI package. Lightweight interfaces are tested without
  heavy ML dependencies; missing backends and unsupported SEMAS operations fail
  honestly. Packaging now includes all three integrations and their commands.
- Native JUCE build/test CI on Linux, Windows, and macOS.
- `tests/lua_regression.lua` with 72 behavioral checks for cache parsing, JSON
  persistence/escaping, portable bundle paths, session routing, manifests, and
  exact generated-plugin source parity/overwrite protection.
- Twenty focused Python regressions for workflow safety, async kwargs/metrics,
  scanner bundles, database idempotence/export, cache CSV, separator backend
  boundaries/model preloading, batch isolation/reporting, and SEMAS execution.
- `AUDIT.md` with findings, verification results, output-path review, and the
  remaining interactive REAPER QA checklist.
- Standard `setup.py` entry point; real package modules, URLs, dependencies, and
  optional extras in `suno_workflow_setup.py`.
- Earlier validation infrastructure: `tests/lua_smoke.lua`, `AGENTS.md`,
  `requirements.txt`, `requirements_yourmt3.txt`, ReaScript metadata, and CI
  syntax/lint/test jobs.

### Fixed

- Batch discovery/filter tests inspect the processing boundary instead of
  launching real model downloads when the optional backend happens to be installed.
- All 17 former optional-integration skips are eliminated. The comprehensive
  suite now requires exactly 23 passes and fails on any skip; the extensionless
  audio fixture and direct SEMAS test import path were corrected.
- Native JUCE builds enable the SDK's C sources on Linux/macOS and normalize
  sub-step floating-point noise around 0 dB, preserving strict double-precision
  unity behavior across GCC, Clang, and MSVC. CI configure/test failures retain
  actionable diagnostics.
- Suno workflow failures now produce nonzero CLI exits instead of “Success!”;
  `--no-auto-import` is meaningful, configuration is preserved, media items and
  durations are generated, original codecs keep their extension, output roots
  work, traversal is rejected, and nonempty projects are not overwritten.
- Session builder replaced invalid/destructive APIs with four working append-only
  modes, stock REAPER FX, correct linear send gain, duplicate-name-safe routing,
  actual created-send reporting, and a single undo block.
- Installer now copies only bundled files after confirmation. It no longer calls
  undefined template/toolbar/shortcut helpers or edits the current project.
- Plugin inventory parses actual cache rows without an out-of-scope variable,
  supports quoted commas and more formats, includes extensionless JSFX, and
  writes valid JSON. Filesystem scans use portable paths and detect bundles.
- Plugin manager reloads its saved database instead of returning an empty stub;
  JSON strings round-trip safely, preset counts use the correct return value,
  and automation targets the actual last-touched track/parameter.
- Phase alignment handles interleaved channels/frame times correctly, enables
  menu actions, avoids open undo blocks on early exits, and labels its timing
  comparison accurately.
- AAF integration detects standalone vs REAPER execution, guards `pyaaf2`, closes
  files, handles missing compositions/metadata, and rejects negative CLI choices.
- Async utilities support keyword arguments and concurrent copies, use unique
  monitor IDs, record failed durations, validate concurrency, and close cleanly.
- Plugin database initialization no longer duplicates alternatives; JSON database
  import/export is implemented, and unchanged preset bytes are not mislabeled as
  a successful conversion.
- UUID extraction handles missing environment variables and quoted CSV names.
- Earlier fixes: optional YourMT3 imports, `warn()` NameError, nil OS paths,
  nonexistent validator/test filenames, and Lua `-inf` misuse.

### Changed

- Documentation now matches implemented behavior, actual menu labels, output
  locations, Python 3.9+/REAPER 7 requirements, and optional dependencies.
- The Suno guide no longer references an implicit unbundled template or claims a
  stem bus/third-party routing that the basic generator does not create.
- The Rule of 30 guide distinguishes the 25-track generated base session from a
  manually expanded 48+ production session and removes nonexistent menu actions.
- Lua smoke stubs return realistic scalars and terminate enumeration; CI rejects
  unexpected exit codes and runs focused Python and Lua regressions.
- Test summaries reject skips for bundled integrations instead of treating them
  as optional successes.
- Logging is console-only unless `SUNO_LOG_FILE` is explicitly set.
- Earlier cleanup: pyflakes fixes, `.gitignore`, Linux/macOS scan paths, and
  removal of unrelated `ROADMAP.md` / `peer_review.md`.

### Removed

- Placeholder claims for automatic third-party chain installation, external stem
  rendering, buildable plugin generation, 48+ track/folder automation, and other
  operations that were not implemented. Replaced with explicit manual guidance.
