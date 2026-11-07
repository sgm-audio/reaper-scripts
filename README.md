# reaper-scripts

REAPER ReaScripts and Python helpers by Scott Mills. The repository contains file
scanners, session/routing builders, preset **data**, AAF import code, and a Suno
project generator. It does not bundle third-party plugins, AI models, project
templates, or FX-chain files.

## ReaScripts

| File | Implemented behavior |
|------|----------------------|
| `Reaper AI Control Hub.lua` | Inspects master-track FX for AI/routing tools, writes routing notes, and prints manual external-processing commands |
| `SGM_Professional_Session_Builder.lua` | Adds full-production, mixing, mastering, or stem-session tracks, stock REAPER FX, and sends to the **current project** |
| `SGM_plugin_development_blueprint.lua` | Shows a development guide and can create a directory-only scaffold after confirmation; not a buildable plugin generator |
| `VALIDATE-ALL-SCRIPTS.lua` | Syntax-checks bundled Lua files in the validator's directory |
| `list-all-available-plugins.lua` | Reads REAPER plugin caches and scans JSFX; writes `plugin_inventory.json` in the resource path |
| `phase-alignment-tool.lua` | Aligns the first item on selected tracks by transient onset; includes timing comparison and item-nudge actions |
| `plugin-wrapper.lua` | Scans plugin paths, persists a JSON database, lists track FX, and automates the last touched parameter |
| `reaper-template-installer.lua` | Copies the bundled scripts/documents into `Scripts/ScottMills`; despite the legacy filename, no project template is installed |
| `rule-of-30-plugin-presets.lua` | Rule of 30 plugin-chain data and lookup helpers |
| `scan-real-plugins.lua` | Recursively scans standard OS plugin paths and writes `rule-of-30-plugins.json` in the resource path |
| `signal-chain-presets.lua` | Signal-chain and routing preset data; does not instantiate plugins by itself |

### Session-builder safety

The session builder asks for confirmation, preserves existing tracks/items, and
uses one undo block. “Full Production” creates 25 tracks and 31 sends—not the
48+ track structure described by older versions of the workflow guide. Routing
is built from stock tracks and does not require third-party plugins. Missing
stock FX are reported as warnings.

The installer also asks for confirmation. It replaces only same-named files in
its destination and never edits the open project, shortcuts, toolbars, or
preferences. After installation, register scripts through **Actions → Show
action list → Load ReaScript**.

## Python helpers

| File | Purpose |
|------|---------|
| `suno_workflow_helper.py` | Separates stems through an optional external module and generates a five-track RPP with relative media paths |
| `suno_workflow_config_system.py` | Dataclass configuration, environment overrides, and validation |
| `suno_workflow_performance_utils.py` | Async executor, batch-copy, memory, and metrics utilities |
| `plugin-compatibility-system.py` | Plugin SQLite database, filesystem scanner, template checks, and JSON import/export |
| `reaper_ai_integration.py` | AAF parsing and REAPER AAF import; also exports composition JSON standalone |
| `extract_reaper_uuids.py` | Converts REAPER's VST cache to `reaper_plugin_map.json` |
| `suno_workflow_setup.py` / `setup.py` | Setuptools configuration and standard package entry point |

See [`SUNO_REAPER_WORKFLOW.md`](SUNO_REAPER_WORKFLOW.md) for CLI examples and
limitations. Rule of 30 production notes are in
[`RULE-OF-30-COMPLETE-WORKFLOW.md`](RULE-OF-30-COMPLETE-WORKFLOW.md).

## Requirements

- REAPER 7.0+ (Lua 5.4) for the ReaScripts.
- Python 3.9+ for Python helpers.
- Core test/Suno packages: `python -m pip install -r requirements.txt`.
- AAF support: `python -m pip install pyaaf2` (the import name is `aaf2`).
- Optional and **not bundled**: `yourmt3_stem_separator`, `batch_process_suno`,
  `SEMAS`, third-party plugins, and AI models.
- SWS is not required for the bundled inventory scanner. Individual user workflows
  may still choose to install it.

Install the standalone Suno command with:

```bash
python -m pip install .
suno-workflow --help
```

## Validate

CI runs Lua 5.4 syntax/smoke checks, focused Lua regressions, Python compilation,
pyflakes, module tests, and Python/Suno suites:

```bash
# Lua syntax and behavior
for f in *.lua; do lua5.4 -e "assert(loadfile('$f'))" || exit 1; done
for f in *.lua; do timeout 10 lua5.4 tests/lua_smoke.lua "$f" || exit 1; done
lua5.4 tests/lua_regression.lua

# Python
python -m compileall -q .
python -m pyflakes *.py tests/*.py  # ignore only REAPER-injected RPR_* diagnostics
python test_modules.py
python -m unittest discover -s tests -p "test_*.py" -v
python suno_workflow_comprehensive_test_suite.py
```

The stubs and unit tests do not replace an interactive test in REAPER. See
[`AUDIT.md`](AUDIT.md) for the audit findings, verification record, and remaining
manual-QA checklist.

## License

MIT. See `LICENSE`.
