# AGENTS.md — reaper-scripts

ReaScript (Lua) and Python helpers for REAPER + AI audio workflows by Scott Mills.

## Validating changes

Always run these before considering a change done:

```bash
# Lua syntax (REAPER 7 = Lua 5.4)
for f in *.lua; do lua5.4 -e "assert(loadfile('$f'))" || echo "SYNTAX ERROR: $f"; done

# Python syntax
python3 -m compileall -q .

# Python lint (install pyflakes)
python3 -m pyflakes *.py   # RPR_* names are provided by the REAPER runtime; ignore those

# Module tests
python3 test_modules.py

# Suno workflow suite (needs: pip install numpy soundfile)
python3 suno_workflow_comprehensive_test_suite.py
```

CI (`.github/workflows/ci.yml`) runs the Lua 5.4 and Python compile checks.

## Conventions

- Lua scripts must parse under Lua 5.4 (`loadfile`), not just LuaJIT.
- Python helpers run under REAPER's Python (RPR_* / aaf2) or standalone; guard
  REAPER-only imports so modules stay importable outside REAPER where possible.
- Optional components (yourmt3_stem_separator, batch_process_suno, SEMAS) are
  not bundled; import them behind try/except or skip guards.
- Keep `__pycache__/` and `*.pyc` out of git (see `.gitignore`).
