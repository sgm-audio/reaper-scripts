# reaper-scripts

REAPER ReaScript utilities and AI-workflow helpers by Scott Mills.

## Contents

| File | What it does |
|------|--------------|
| `Reaper AI Control Hub.lua` | Plugin discovery, routing templates, and external AI tool launches |
| `SGM_Professional_Session_Builder.lua` | Builds a full session template (tracks, buses, routing) |
| `SGM_plugin_development_blueprint.lua` | Plugin development scaffolding helpers |
| `VALIDATE-ALL-SCRIPTS.lua` | Runs the bundled validation helpers |
| `list-all-available-plugins.lua` | Lists installed VST/VST3/JSFX plugins |
| `phase-alignment-tool.lua` | Aligns quad-tracked DI guitars by transient onset |
| `plugin-wrapper.lua` | Wraps plugin chains for repeatable loading |
| `reaper-template-installer.lua` | Installs the session template |
| `rule-of-30-plugin-presets.lua` | Plugin-chain preset library for the Rule of 30 workflow |
| `scan-real-plugins.lua` | Scans and reports installed plugins |
| `signal-chain-presets.lua` | Signal-chain preset data |
| `*.py` (Suno workflow) | Helper scripts for the Suno import/production workflow |
| `extract_reaper_uuids.py` | Exports the REAPER plugin UUID map to JSON |

## Which script do I run?

Several scripts overlap in purpose; use this to pick:

| Task | Script | Notes |
|------|--------|-------|
| Build a full mixing session automatically | `SGM_Professional_Session_Builder.lua` | Analyzes the project and builds tracks/buses/routing |
| Install the whole template suite once | `reaper-template-installer.lua` | One-time setup into the REAPER resource path |
| Find which plugins are installed | `scan-real-plugins.lua` | Scans real OS plugin paths, exports JSON |
| Export the full plugin inventory | `list-all-available-plugins.lua` | Includes JSFX; writes `plugin_inventory.json` |
| Manage/wrap plugin chains on tracks | `plugin-wrapper.lua` | Keeps a `plugin_database.json` |
| Discover AI tools / launch external processing | `Reaper AI Control Hub.lua` | Bridges to external AI plugins |
| Align quad-tracked DI guitars | `phase-alignment-tool.lua` | Transient-onset alignment |
| Rule of 30 preset chains | `rule-of-30-plugin-presets.lua` + `signal-chain-presets.lua` | Presets data; see `RULE-OF-30-COMPLETE-WORKFLOW.md` |
| Check scripts for syntax errors | `VALIDATE-ALL-SCRIPTS.lua` | In-REAPER validator |
| Suno track -> REAPER project | `suno_workflow_helper.py` (see `SUNO_REAPER_WORKFLOW.md`) | Stem separation needs the optional YourMT3 module |

## Requirements

- REAPER 7.0+ (Lua 5.4)
- Python 3.9+ for the `.py` helpers
  - `reaper_ai_integration.py` runs inside REAPER's Python (needs `aaf2`, `RPR_*`)
  - `suno_workflow_comprehensive_test_suite.py` needs `pip install numpy soundfile`
  - `suno_workflow_performance_utils.py` additionally needs `psutil`
  - Optional, not bundled: `yourmt3_stem_separator`, `batch_process_suno`, `SEMAS`
- SWS/S&M Extension optional (enables extended routing inspection)

See `AGENTS.md` for the full validation commands. Workflow docs: `SUNO_REAPER_WORKFLOW.md` and `RULE-OF-30-COMPLETE-WORKFLOW.md`. Changes are tracked in `CHANGELOG.md`.

> Note: `suno_workflow_setup.py` is a setuptools packaging script for installing the
> Python helpers as a package; this repo itself is a flat collection of scripts.

## Validate

CI (`.github/workflows/ci.yml`) runs all of these:

```bash
# Lua 5.4 syntax
for f in *.lua; do lua5.4 -e "assert(loadfile('$f'))"; done

# Lua smoke-run with stubbed REAPER (catches runtime crashes; timeout = waits on real input)
for f in *.lua; do timeout 10 lua5.4 tests/lua_smoke.lua "$f"; done

# Python
python -m compileall -q .
python -m pyflakes *.py        # ignore "undefined name 'RPR_*'" (REAPER runtime)
python test_modules.py
pip install -r requirements.txt && python suno_workflow_comprehensive_test_suite.py
```

## License

MIT. See `LICENSE`.
