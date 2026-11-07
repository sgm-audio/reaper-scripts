# Suno Track Workflow for REAPER

Generate a REAPER project from a Suno audio file and stems produced by an
optional external `yourmt3_stem_separator` module.

> **Important:** `yourmt3_stem_separator.py`, `batch_process_suno.py`, SEMAS, AI
> models, and project templates are not bundled. The helper returns a clear error
> if the separator is unavailable. No separation-quality or GPU-performance
> claims are made by this repository.

## What the bundled helper does

1. Validates the input file and project name.
2. Creates a new, empty project directory (and refuses to overwrite a nonempty one).
3. Calls `YourMT3StemSeparator(output_dir=...).separate(input_file)` and verifies
   that every returned stem file exists.
4. Copies the original without changing its codec or filename extension.
5. Generates a `.rpp` with Vocals, Drums, Bass, Other, and a muted Original Mix
   reference track. By default, media items reference the stems and original with
   relative paths.
6. Writes `IMPORT_INSTRUCTIONS.md` unless disabled in configuration.
7. Returns a structured failure and exits nonzero on CLI errors.

This is **file generation**, not remote control of a running REAPER instance.

## Installation

### Python

```bash
python -m pip install -r requirements.txt
```

Install your compatible external YourMT3 separator separately. The optional
`requirements_yourmt3.txt` lists common torch/audio dependencies, but does not
install the unbundled separator itself.

The standalone package can also be installed from the repository root:

```bash
python -m pip install .
```

### ReaScripts

Run `reaper-template-installer.lua` inside REAPER, or copy root-level `.lua`
files to the appropriate directory:

- Windows: `%APPDATA%\REAPER\Scripts\`
- macOS: `~/Library/Application Support/REAPER/Scripts/`
- Linux: `~/.config/REAPER/Scripts/`

Then use **Actions → Show action list → Load ReaScript**. No SWS extension is
required for the bundled inventory tool.

## CLI usage

```bash
python suno_workflow_helper.py "path/to/track.mp3"
python suno_workflow_helper.py "track.wav" --name "My Song"
python suno_workflow_helper.py "track.wav" --output-dir "/path/to/projects"
python suno_workflow_helper.py "track.wav" --no-auto-import
```

The installed command is equivalent:

```bash
suno-workflow "track.wav" --name "My Song"
```

### Output layout

For `--output-dir "/projects" --name "My Song"`:

```text
/projects/My Song/
├── My Song.rpp
├── IMPORT_INSTRUCTIONS.md
├── original_mix.wav                 # extension matches the actual input
└── stems/
    ├── vocals.wav                   # names/extensions come from the separator
    ├── drums.wav
    ├── bass.wav
    └── other.wav
```

If `--output-dir` is omitted, the project folder is created beside the input.
The CLI also honors `SUNO_OUTPUT_DIR`; the explicit option takes precedence.
Rerunning with the same nonempty project directory fails rather than overwriting
media. Choose another name or output root.

### Manual import mode

`--no-auto-import` creates the five tracks without `<ITEM>` media entries and
writes manual mapping instructions. It does not disable stem separation.

### Custom project file

```bash
python suno_workflow_helper.py "track.wav" --template "path/to/custom.rpp"
```

A custom template is copied **verbatim** to the new project directory. The helper
does not inject stems into an arbitrary existing RPP; use the generated import
instructions. A missing explicit template is an error. The old implicit
`templates/suno-track-import-template.rpp` path is no longer used because that
file is not bundled.

## Generated project details

- Track 1: Vocals
- Track 2: Drums
- Track 3: Bass
- Track 4: Other (Instruments)
- Track 5: Original Mix (Reference), muted by default

The basic generator does not create a stem bus, custom colors, or third-party FX.
Media duration is read with `soundfile` (or Python's WAV reader); if one codec
cannot be inspected, the common song duration from another generated stem is
used. Open and save the generated RPP in REAPER before further editing.

## Configuration API

```python
from suno_workflow_config_system import PathConfig, WorkflowConfig
from suno_workflow_helper import SunoReaperWorkflow

config = WorkflowConfig(paths=PathConfig(output_dir="/projects"))
workflow = SunoReaperWorkflow(config=config)
result = workflow.process_suno_track("track.wav", project_name="Song")
if not result.success:
    print(result.error_message)
```

Environment overrides:

| Variable | Values |
|----------|--------|
| `SUNO_OUTPUT_DIR` | Root directory for generated project folders |
| `SUNO_DEVICE` | `auto`, `cpu`, or `cuda` |
| `SUNO_SAMPLE_RATE` | `44100`, `48000`, or `96000` |
| `SUNO_ENHANCEMENT_PROFILE` | `minimal`, `balanced`, or `aggressive` |
| `SUNO_LOG_FILE` | Optional log filename; console-only logging is used when unset |

Model/device and enhancement settings are configuration data passed through the
workflow; the external separator controls their actual interpretation.

## Plugin inventory

Run `list-all-available-plugins.lua` in REAPER. It scans extensionless and
`.jsfx` JS effects (excluding `.jsfx-inc` includes) and reads available VST,
VST3, CLAP, AU, and LV2 cache files. Output is written to:

```text
<REAPER resource path>/plugin_inventory.json
```

`scan-real-plugins.lua` is different: it recursively scans standard filesystem
paths and writes `rule-of-30-plugins.json`. The Python
`plugin-compatibility-system.py scan` command provides a third, database-oriented
filesystem scan.

## Troubleshooting

### “Stem separation requires … yourmt3_stem_separator”

Install the external module in the same Python environment as the helper. The
repository cannot provide installation instructions for an unbundled fork; check
that this import works first:

```bash
python -c "from yourmt3_stem_separator import YourMT3StemSeparator; print('OK')"
```

### “Project directory is not empty”

This is overwrite protection. Use another `--name` or `--output-dir`; do not
delete a project unless you have a backup.

### “Separated stem was not created”

The separator returned a path that does not exist. Check its output directory,
relative-path behavior, logs, disk space, and supported input codecs.

### Project opens without expected media

Confirm that the generated `stems/` directory moved with the RPP, review the
relative `FILE` paths, and use REAPER's missing-media search. Projects made with
`--no-auto-import` intentionally contain empty tracks. Custom templates are
intentionally copied unchanged.

### AAF import

`reaper_ai_integration.py` is separate from the Suno workflow. Install `pyaaf2`
and run it inside REAPER for project construction, or standalone with an `.aaf`
argument to print composition JSON. AAF variations still require testing with
your source DAW and REAPER version.

## Validation

```bash
python test_modules.py
python -m unittest discover -s tests -p "test_*.py" -v
python suno_workflow_comprehensive_test_suite.py
```

Optional YourMT3/batch/SEMAS tests are reported as skipped when those modules
are absent; skipped tests are not counted as passes.

**Compatible with:** REAPER 7.0+, Python 3.9+
