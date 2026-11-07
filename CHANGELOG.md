# Changelog

All notable changes to this repository. Format follows Keep a Changelog.

## [Unreleased]

### Added

- `tests/lua_regression.lua` with 54 behavioral checks for cache parsing, JSON
  persistence/escaping, portable bundle paths, session routing, and manifests.
- `tests/test_regressions.py` with 10 regressions for workflow safety, async
  kwargs/metrics, scanner bundles, database idempotence/export, and cache CSV.
- `AUDIT.md` with findings, verification results, output-path review, and the
  remaining interactive REAPER QA checklist.
- Standard `setup.py` entry point; real package modules, URLs, dependencies, and
  optional extras in `suno_workflow_setup.py`.
- Earlier validation infrastructure: `tests/lua_smoke.lua`, `AGENTS.md`,
  `requirements.txt`, `requirements_yourmt3.txt`, ReaScript metadata, and CI
  syntax/lint/test jobs.

### Fixed

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
- Test summaries distinguish optional skips from passes.
- Logging is console-only unless `SUNO_LOG_FILE` is explicitly set.
- Earlier cleanup: pyflakes fixes, `.gitignore`, Linux/macOS scan paths, and
  removal of unrelated `ROADMAP.md` / `peer_review.md`.

### Removed

- Placeholder claims for automatic third-party chain installation, external stem
  rendering, buildable plugin generation, 48+ track/folder automation, and other
  operations that were not implemented. Replaced with explicit manual guidance.
