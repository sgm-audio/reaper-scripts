# Changelog

All notable changes to this repository. Format follows Keep a Changelog.

## [Unreleased]

### Added
- `tests/lua_smoke.lua`: CI harness that runs every ReaScript with a stubbed
  REAPER environment to catch load-time crashes (undefined globals, nil math)
- CI jobs: `lua-smoke`, `python-lint` (pyflakes, ignoring REAPER-runtime `RPR_*`),
  `python-tests` (`test_modules.py`, Suno workflow suite)
- ReaScript metadata headers (`@description` / `@author` / `@version`) on all Lua scripts
- README "Which script do I run?" guide disambiguating overlapping plugin tools
- `AGENTS.md`, `requirements.txt`, `requirements_yourmt3.txt`
- This changelog

### Fixed
- `suno_workflow_helper.py` / test suite imported a nonexistent `config` module —
  now imports from `suno_workflow_config_system`; optional `yourmt3_stem_separator`
  import guarded with a clear error
- `reaper_ai_integration.py`: undefined `warn()` call (NameError) → `log(..., WARNING)`;
  added guarded `tkinter` import + `have_tk` detection
- `reaper-template-installer.lua`: crashed on launch (called ~20 undefined helpers);
  added real `copy_file`/`save_script`/`open_url`, per-step `pcall` in `main()`,
  `-inf` nil global → -150 dB, stale bundled filename `ai-integration-module.py` →
  `reaper_ai_integration.py`
- `scan-real-plugins.lua` / `plugin-wrapper.lua`: nil-concat crashes from unguarded
  `os.getenv("LOCALAPPDATA")` / `os.getenv("HOME")`
- `VALIDATE-ALL-SCRIPTS.lua`: validated a nonexistent script name; now checks the
  scripts that actually exist
- `test_modules.py`: pointed at a nonexistent `files/` dir; loads real modules,
  skips REAPER-only ones gracefully
- Suno test suite: stale assertions updated to `WorkflowResult`; skip guards for
  absent optional modules; duplicate imports removed
- Plugin scan paths now cover Linux (and macOS) in `plugin-wrapper.lua`,
  `scan-real-plugins.lua`, `SGM_Professional_Session_Builder.lua`,
  `Reaper AI Control Hub.lua`

### Changed
- pyflakes-clean Python codebase (unused imports/locals, f-string fixes)
- `__pycache__/` untracked; `.gitignore` added

### Removed
- `ROADMAP.md`, `peer_review.md` — belonged to a different repository
- Profanity in `SGM_Professional_Session_Builder.lua` header
