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
python3 -m pyflakes *.py tests/*.py SEMAS/*.py SEMAS/core/*.py | grep -v "undefined name 'RPR_"

# Python tests
python3 test_modules.py
python3 -m unittest discover -s tests -p "test_*.py" -v
python3 suno_workflow_comprehensive_test_suite.py
```

Install test dependencies with `python3 -m pip install -r requirements.txt pyflakes`.
CI (`.github/workflows/ci.yml`) runs all of these checks. The separator, batch
processor, and SEMAS are bundled: the comprehensive suite must report exactly
23 passes and zero skips, and any skip is a failure. Heavy Demucs execution uses
the optional `.[stem-separation]` extra and is not faked in lightweight tests.

For native plugin changes, also configure/build/test `plugin/` with CMake and a
pinned JUCE 8.0.4 source as documented in `plugin/README.md`. CI builds VST3,
Standalone, and native processing tests on Linux, Windows, and macOS.

## Conventions

- Lua scripts must parse and run under Lua 5.4, not just LuaJIT.
- Use portable `/` path joins in ReaScripts and resolve output beneath an explicit
  REAPER resource/project path. Never assume Windows environment variables exist.
- Keep the current project safe: confirm destructive or multi-track operations,
  group edits in undo blocks, and distinguish source generation/instructions from
  completed compilation, rendering, or REAPER edits.
- Python helpers run under REAPER's Python or standalone. Guard REAPER-only
  globals and optional imports so modules remain importable outside REAPER.
- Keep heavyweight model/AAF/REAPER dependencies guarded and actionable. The
  `yourmt3_stem_separator` compatibility class uses Demucs for real separation;
  never label passthrough audio as stems or claim a model ran in a fixture test.
- JSON writers must escape backslashes before quotes/control characters. Add a
  round-trip or parse test when changing persistence code.
- Add focused regressions for fixed bugs; a syntax check or unselected menu smoke
  test is not proof that an action works.
- Keep `__pycache__/`, `*.pyc`, build output, local databases, and logs out of Git.
