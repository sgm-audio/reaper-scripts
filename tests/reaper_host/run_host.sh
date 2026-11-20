#!/usr/bin/env bash
# Run the in-host REAPER harness headlessly (Xvfb) against a real REAPER 7.x install.
# usage: tests/reaper_host/run_host.sh <path-to-REAPER-dir-containing-./reaper> [cases]
# Exit 0 only if REAPER 7.x reports HOST_RESULT with fail=0 and pass>0, every JSON file the
# scripts wrote parses, and the host reached HOST_EXIT.
set -u
REAPER_DIR="${1:?path to REAPER directory (contains ./reaper)}"
CASES="${2:-}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
OUT="${SGM_HOST_OUT:-$WORK/host.log}"
mkdir -p "$WORK/cfg" "$WORK/home"

# Either stage a real compiled VST3 bundle (for juce_vst3_live) or filesystem fixtures for scan-real-plugins.lua.
H="$WORK/home"
if [ -n "${SGM_VST3_BUNDLE:-}" ]; then
  mkdir -p "$H/.vst3"
  cp -a "$SGM_VST3_BUNDLE" "$H/.vst3/"
else
  mkdir -p "$H/.vst3/Neural DSP Archetype Gojira.vst3/Contents/x86_64-linux" \
           "$H/.vst3/Vendor/Deep/iZotope Ozone 11.vst3" "$H/.clap" "$H/.lxvst" "$H/.vst" "$H/.lv2/Some.lv2"
  : > "$H/.vst3/Neural DSP Archetype Gojira.vst3/Contents/x86_64-linux/Gojira.so"
  : > "$H/.vst3/FabFilter Pro-Q 3.vst3"; : > "$H/.vst3/Foo v2.5.vst3"; : > "$H/.vst3/readme.txt"
  : > "$H/.clap/FabFilter Saturn 2.clap"; : > "$H/.vst/Waves SSL Comp.vst"; : > "$H/.vst/notes.md"
fi
export SGM_FIXTURE_HOME="$H"

SCRIPT="${SGM_SCRIPT:-$REPO/tests/reaper_host/harness.lua}"
if [ -n "${SGM_PYTHON_LIB:-}" ]; then
  # Point REAPER's ReaScript at a real CPython (e.g. SGM_PYTHON_LIB=/usr/lib/x86_64-linux-gnu/libpython3.11.so.1.0).
  echo 'reaper.Main_OnCommand(40004,0)' > "$WORK/quit.lua"
  ( cd "$REAPER_DIR" && HOME="$H" timeout 90 xvfb-run -a ./reaper -nosplash \
      -cfgfile "$WORK/cfg/reaper.ini" -newinst -nonewinst "$WORK/quit.lua" >/dev/null 2>&1 )
  [ -f "$WORK/cfg/reaper.ini" ] || { echo "warmup produced no reaper.ini"; exit 1; }
  sed -i "s|^\[reaper\]\$|[reaper]\nreascript=1\npythonlibpath64=$(dirname "$SGM_PYTHON_LIB")\npythonlibdll64=$(basename "$SGM_PYTHON_LIB")\npythonuse64=1|" "$WORK/cfg/reaper.ini"
  grep -q '^pythonuse64=1' "$WORK/cfg/reaper.ini" || { echo "failed to configure python"; exit 1; }
fi
case "$SCRIPT" in
  *.py)  # REAPER only auto-runs Lua from the command line: register and run the Python via a Lua launcher.
    cat > "$WORK/launch_py.lua" <<LUA
local id = reaper.AddRemoveReaScript(true, 0, "$SCRIPT", true)
local f = io.open(os.getenv("SGM_HOST_OUT") .. ".launch", "w"); f:write("id=" .. tostring(id), "\\n"); f:close()
if id and id ~= 0 then reaper.Main_OnCommand(id, 0) end
LUA
    SCRIPT="$WORK/launch_py.lua" ;;
esac
export SGM_REPO="$REPO" SGM_HOST_OUT="$OUT" SGM_CASES="$CASES"
TIMEOUT="${SGM_HOST_TIMEOUT:-240}"
( cd "$REAPER_DIR" && HOME="$H" exec xvfb-run -a ./reaper -nosplash \
    -cfgfile "$WORK/cfg/reaper.ini" -newinst -nonewinst "$SCRIPT" \
    >"$WORK/reaper.stdout" 2>&1 ) &
PID=$!
for _ in $(seq 1 "$TIMEOUT"); do
  grep -q "^HOST_EXIT" "$OUT" 2>/dev/null && break
  kill -0 "$PID" 2>/dev/null || break
  sleep 1
done
sleep 1
pkill -P "$PID" 2>/dev/null; kill "$PID" 2>/dev/null; sleep 1; pkill -9 -x reaper 2>/dev/null
cat "$OUT" 2>/dev/null

status=0
grep -q "^HOST_EXIT" "$OUT" || { echo "host never reached HOST_EXIT (hang/crash)"; status=1; }
grep -q "^HOST_RESULT pass=[1-9][0-9]* fail=0$" "$OUT" || { echo "HOST RESULT NOT CLEAN"; status=1; }
grep -q "^HOST_VERSION 7\." "$OUT" || { echo "not a REAPER 7.x host"; status=1; }
for f in "$WORK"/cfg/*.json; do
  [ -e "$f" ] || continue
  python3 -c "import json,sys; json.load(open(sys.argv[1], encoding='utf-8'))" "$f" \
    && echo "JSON OK: $(basename "$f")" || { echo "INVALID JSON written by script: $f"; status=1; }
done
if [ -n "${SGM_HOST_ARTIFACTS:-}" ]; then
  mkdir -p "$SGM_HOST_ARTIFACTS"; cp "$OUT" "$SGM_HOST_ARTIFACTS/host.log" 2>/dev/null
  cp "$WORK"/cfg/*.json "$WORK/reaper.stdout" "$SGM_HOST_ARTIFACTS/" 2>/dev/null
fi
[ "$status" -eq 0 ] && echo "HOST RUN OK" || echo "HOST RUN FAILED"
exit "$status"
