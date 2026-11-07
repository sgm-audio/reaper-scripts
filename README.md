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

## Requirements

- REAPER 7.0+ (Lua 5.4)
- Python 3.9+ for the `.py` helpers
  - `reaper_ai_integration.py` runs inside REAPER's Python (needs `aaf2`, `RPR_*`)
  - `suno_workflow_comprehensive_test_suite.py` needs `pip install numpy soundfile`
  - `suno_workflow_performance_utils.py` additionally needs `psutil`
  - Optional, not bundled: `yourmt3_stem_separator`, `batch_process_suno`, `SEMAS`
- SWS/S&M Extension optional (enables extended routing inspection)

See `AGENTS.md` for the full validation commands.

## Validate

All Lua files parse under Lua 5.4. CI runs the same check:

```bash
for f in *.lua; do lua -e "assert(loadfile('$f'))"; done
```

Python helpers:

```bash
python -m compileall -q .
```

## License

MIT. See `LICENSE`.
