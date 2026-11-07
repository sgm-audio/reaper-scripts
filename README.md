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
| `SGM_plugin_development_blueprint.lua` | Copies the complete bundled JUCE/CMake project into a saved REAPER project after confirmation; compilation remains a separate documented step |
| `VALIDATE-ALL-SCRIPTS.lua` | Syntax-checks bundled Lua files in the validator's directory |
| `list-all-available-plugins.lua` | Reads REAPER plugin caches and scans JSFX; writes `plugin_inventory.json` in the resource path |
| `phase-alignment-tool.lua` | Aligns the first item on selected tracks by transient onset; includes timing comparison and item-nudge actions |
| `plugin-wrapper.lua` | Scans plugin paths, persists a JSON database, lists track FX, and automates the last touched parameter |
| `reaper-template-installer.lua` | Copies the bundled scripts/documents and JUCE source tree into `Scripts/ScottMills`; despite the legacy filename, no project template or compiled plugin is installed |
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
| `suno_workflow_helper.py` | Uses the bundled separator adapter and generates a five-track RPP with relative media paths |
| `yourmt3_stem_separator.py` | Compatibility-named Demucs adapter with audio preprocessing; real model execution requires the optional heavy backend |
| `batch_process_suno.py` | Deterministic directory discovery, serial/parallel per-file isolation, and Markdown batch reports |
| `SEMAS/` | Bundled local job API/CLI with real PCM-WAV analysis; enhancement/mastering require an external processor and fail honestly |
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
- Real stem separation: `python -m pip install -e '.[stem-separation]'` (or
  `python -m pip install -r requirements_yourmt3.txt`). The separator adapter,
  batch processor, and SEMAS interfaces are bundled; Demucs, Torch, and model
  downloads are optional heavy runtime dependencies. Without them, lightweight
  tests still run and separation returns an actionable error instead of fake stems.
- Not bundled: third-party plugins, AI models, JUCE, and a C++ toolchain.
- SWS is not required for the bundled inventory scanner. Individual user workflows
  may still choose to install it.

Install the standalone Suno command with:

```bash
python -m pip install .
suno-workflow --help
suno-batch --help
semas --help
yourmt3-stems --help
```

## Optional Demucs ML backend and model

The `YourMT3StemSeparator` class name is retained for compatibility; the actual
separator is **Demucs**. Python packages and model weights are not bundled. The
default `htdemucs` model separates vocals, drums, bass, and other.

### 1. Install the backend

Use an isolated environment so the large Torch dependencies do not alter your
system Python:

```bash
python -m venv .venv
source .venv/bin/activate             # Windows: .venv\Scripts\activate
python -m pip install --upgrade pip
python -m pip install -e '.[stem-separation]'
```

Demucs 4.1 requires Python 3.10 or newer. On Linux, the default PyPI Torch wheel
can include large CUDA components. For a smaller CPU-only installation or a
specific CUDA version, install Torch/Torchaudio first using the
[official PyTorch selector](https://pytorch.org/get-started/locally/), then run
the `stem-separation` extra above.

Check the code backend:

```bash
python -c "from yourmt3_stem_separator import YourMT3StemSeparator; print(YourMT3StemSeparator(output_dir='stems').get_model_info())"
```

`backend_available: True` means the Python backend imports; it does **not** prove
that model weights have been downloaded. For an offline code-only runtime check,
`yourmt3-stems --model demucs_unittest --download-model` constructs Demucs's
built-in test architecture. That check validates Torch/Demucs loading only; it
is not a pretrained model or a separation-quality test.

### 2. Download and verify the model

The official model is **[adefossez/HTDemucs on Hugging Face](https://huggingface.co/adefossez/HTDemucs)**.
It is public and does not require a Hugging Face token. Download and load-test it
with the bundled command:

```bash
yourmt3-stems --download-model
# Success ends with: Demucs model 'htdemucs' is available and loadable (BagOfModels).
```

Demucs 4.1+ tries Hugging Face first, then its legacy torch-hub source. Relevant
official files are:

- [Model definition (`htdemucs.yaml`)](https://huggingface.co/adefossez/HTDemucs/resolve/main/htdemucs.yaml)
- [Model weights (`955717e8.safetensors`)](https://huggingface.co/adefossez/HTDemucs/resolve/main/955717e8.safetensors)
- [Legacy torch-hub weights (`955717e8-8726e21a.th`)](https://dl.fbaipublicfiles.com/demucs/hybrid_transformer/955717e8-8726e21a.th)

The verified Hugging Face weight is **84,025,440 bytes** with SHA-256:

```text
d9fa14133cfcc034a6758923bb3a8ca9f8dfd0b582134643bbf83f72c17576dd
```

For a manual Hugging Face download that still populates the correct cache, use
the `hf` command installed with Demucs 4.1, then perform the load test:

```bash
hf download adefossez/HTDemucs htdemucs.yaml 955717e8.safetensors
yourmt3-stems --download-model
```

Both the YAML definition and safetensors weight are required. Prefer these
commands over manually inventing Hugging Face cache paths. Caches default to:

- Hugging Face: `~/.cache/huggingface/hub` (override the parent with `HF_HOME`).
- Legacy torch hub: `~/.cache/torch/hub/checkpoints` (override the parent with
  `TORCH_HOME`). A manual legacy download belongs at
  `~/.cache/torch/hub/checkpoints/955717e8-8726e21a.th`.

The download hosts `huggingface.co` and `dl.fbaipublicfiles.com` must be
reachable. Once the load test succeeds, run real separation with:

```bash
yourmt3-stems "path/to/track.wav" --device cpu --output "path/to/stems"
```

Use `--device cuda` only when `torch.cuda.is_available()` is true and the model
fits in GPU memory. No inference is performed by `--download-model` itself.

## Buildable JUCE plugin baseline

[`plugin/`](plugin/) is a complete JUCE 8.0.4/CMake project with VST3 and
Standalone targets, smoothed gain, bypass, parameter state/automation, an editor,
and native processing tests. It deliberately contains **no AI inference or CLAP
implementation**. The blueprint copies these exact sources; it does not compile
a binary or silently install a plugin.

Install CMake 3.22+, a C++17 compiler, and the platform dependencies listed in
[`plugin/README.md`](plugin/README.md), then run:

```bash
cmake -S plugin -B plugin/build -DCMAKE_BUILD_TYPE=Release
cmake --build plugin/build --config Release
ctest --test-dir plugin/build -C Release --output-on-failure
```

CMake fetches JUCE at an immutable commit. For an existing JUCE checkout, add
`-DSGM_JUCE_SOURCE_DIR=/absolute/path/to/JUCE` to the configure command. CI
builds the VST3, Standalone, and native tests on Linux, Windows, and macOS.

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
python -m pyflakes *.py tests/*.py SEMAS/*.py SEMAS/core/*.py  # ignore only injected RPR_* diagnostics
python test_modules.py
python -m unittest discover -s tests -p "test_*.py" -v
python suno_workflow_comprehensive_test_suite.py  # exactly 23 passed, 0 skipped
```

The comprehensive runner fails on any skip: bundled integration modules must not
silently become “optional” again. Heavy Demucs execution is tested through its
CLI boundary with fixtures, not represented as a model run.

The stubs and unit tests do not replace an interactive test in REAPER. See
[`AUDIT.md`](AUDIT.md) for the audit findings, verification record, and remaining
manual-QA checklist.

## License

MIT. See `LICENSE`.
