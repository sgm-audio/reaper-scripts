# AGENTS.md — reaper-scripts

ReaScript (Lua) and Python helpers for REAPER + AI audio workflows by Scott Mills.

## Validating changes

Run from the repository root:

```bash
# Lua syntax (REAPER 7 = Lua 5.4)
for f in *.lua; do lua5.4 -e "assert(loadfile('$f'))" || exit 1; done

# Load-time/runtime smoke checks with conservative REAPER stubs
for f in *.lua; do timeout 10 lua5.4 tests/lua_smoke.lua "$f" || exit 1; done

# Behavioral Lua regressions (cache parsing, JSON, paths, routing, manifests)
lua5.4 tests/lua_regression.lua

# Python syntax and lint (RPR_* names are injected by REAPER)
python3 -m compileall -q .
python3 -m pyflakes *.py tests/*.py | grep -v "undefined name 'RPR_"

# Python tests
python3 test_modules.py
python3 -m unittest discover -s tests -p "test_*.py" -v
python3 suno_workflow_comprehensive_test_suite.py
```

Install test dependencies with `python3 -m pip install -r requirements.txt pyflakes`.
CI (`.github/workflows/ci.yml`) runs all of these checks. Optional
YourMT3/batch/SEMAS tests skip when their unbundled modules are absent; do not
count skips as passes.

## Conventions

- Lua scripts must parse and run under Lua 5.4, not just LuaJIT.
- Use portable `/` path joins in ReaScripts and resolve output beneath an explicit
  REAPER resource/project path. Never assume Windows environment variables exist.
- Keep the current project safe: confirm destructive or multi-track operations,
  group edits in undo blocks, and do not claim success when an operation is only
  instructions or a scaffold.
- Python helpers run under REAPER's Python or standalone. Guard REAPER-only
  globals and optional imports so modules remain importable outside REAPER.
- Optional components (`yourmt3_stem_separator`, `batch_process_suno`, SEMAS) are
  not bundled; import them behind guards and report skipped tests accurately.
- JSON writers must escape backslashes before quotes/control characters. Add a
  round-trip or parse test when changing persistence code.
- Add focused regressions for fixed bugs; a syntax check or unselected menu smoke
  test is not proof that an action works.
- Keep `__pycache__/`, `*.pyc`, build output, local databases, and logs out of Git.
