# Suno Track Workflow for Reaper

Complete workflow for importing and processing Suno AI-generated tracks in Reaper with advanced stem separation.

## Overview

This workflow provides:

1. **Advanced Stem Separation** - YourMT3+ transformer-based separation optimized for AI-generated audio
2. **Reaper Project Templates** - Pre-configured track routing and organization
3. **Plugin Discovery** - List all available Reaper plugins for your setup
4. **Automated Workflow** - One-command processing from Suno track to Reaper project

## Files Included

### Core Scripts

- `yourmt3_stem_separator.py` - Main stem separation engine using YourMT3+
- `suno_workflow_helper.py` - Complete workflow automation
- `requirements_yourmt3.txt` - Python dependencies

### ReaScripts

- `ReaScripts/list-all-available-plugins.lua` - Lists all installed Reaper plugins
- `ReaScripts/daw-discovery-analyzer.lua` - Comprehensive DAW analysis tool

### Templates

- `templates/suno-track-import-template.rpp` - Reaper project template with:
  - 4 stem tracks (Vocals, Drums, Bass, Other)
  - Original mix reference track (muted)
  - Stem bus for group processing
  - Pre-configured routing and colors

## Installation

### 1. Install Python Dependencies

```bash
# Install core dependencies
pip install -r requirements_yourmt3.txt

# For CUDA GPU acceleration (optional but recommended)
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
```

### 2. Install Reaper Scripts

Copy the ReaScripts to your Reaper scripts directory:

```bash
# Windows
copy ReaScripts\*.lua "%APPDATA%\REAPER\Scripts\"

# macOS/Linux
cp ReaScripts/*.lua ~/Library/Application\ Support/REAPER/Scripts/
```

Then in Reaper:
- Actions → Show action list → Load ReaScript
- Select the `.lua` files

## Usage

### Quick Start - Automated Workflow

Process a Suno track in one command:

```bash
python suno_workflow_helper.py "path/to/your_suno_track.mp3"
```

This will:
1. Separate the track into 4 stems (vocals, drums, bass, other)
2. Create a Reaper project with proper routing
3. Generate import instructions
4. Organize everything in a project folder

### Advanced Usage

#### Custom Project Name

```bash
python suno_workflow_helper.py "my_track.mp3" --name "My Awesome Project"
```

#### Use Custom Template

```bash
python suno_workflow_helper.py "my_track.mp3" --template "path/to/custom_template.rpp"
```

#### Manual Stem Separation Only

```bash
python yourmt3_stem_separator.py "my_track.mp3" -o "output/folder"
```

#### Select Specific Stems

```bash
python yourmt3_stem_separator.py "my_track.mp3" -s vocals drums
```

#### GPU Acceleration

```bash
python yourmt3_stem_separator.py "my_track.mp3" --device cuda
```

### List Available Plugins

In Reaper, run the script: `list-all-available-plugins.lua`

This will:
- Scan all installed plugins (VST, VST3, JS, CLAP)
- Display inventory in Reaper console
- Export to `plugin_inventory.json`

## Workflow Details

### Step 1: Stem Separation

The YourMT3+ separator uses:

- **Transformer architecture** for superior quality
- **AI-audio preprocessing** to handle AI-generated artifacts:
  - Spectral cleaning
  - DC offset removal
  - Artifact reduction
- **Enhanced post-processing**:
  - Stem bleeding reduction
  - Transient enhancement (drums)
  - Normalization

### Step 2: Reaper Project Creation

The template includes:

**Track 1: Vocals**
- Color: Pink/Purple
- Routed to Stem Bus

**Track 2: Drums**
- Color: Orange
- Routed to Stem Bus

**Track 3: Bass**
- Color: Blue
- Routed to Stem Bus

**Track 4: Other (Instruments)**
- Color: Yellow
- Routed to Stem Bus

**Track 5: Original Mix (Reference)**
- Color: White
- Muted by default
- 50% volume for A/B comparison

**Track 6: Stem Bus**
- Group processing
- Routed to Master

### Step 3: Import Stems

After running the workflow:

1. Open the generated `.rpp` project file in Reaper
2. Drag and drop stems to corresponding tracks:
   - `vocals.wav` → Track 1
   - `drums.wav` → Track 2
   - `bass.wav` → Track 3
   - `other.wav` → Track 4
   - `original_mix.wav` → Track 5
3. Align items to start at 0:00
4. Start mixing!

## Why YourMT3+ for AI-Generated Audio?

AI-generated audio (like Suno) has unique characteristics:

1. **Compressed dynamic range** - Often heavily compressed/limited
2. **Spectral artifacts** - AI models can introduce frequency anomalies
3. **Unnatural transients** - Drum hits and attacks may be unnaturally smooth
4. **Bleeding** - More challenging source separation

YourMT3+ addresses these with:

- Transformer-based attention mechanisms for better source localization
- Pre/post-processing optimized for AI audio artifacts
- Higher overlap ratio for smoother separation
- Spectral gating to remove AI-specific noise floor

## Mixing Tips for Suno Tracks

### Fixing Common Issues

**Vocals too quiet/loud?**
- Adjust track volume
- Add compression to even out dynamics
- Use vocal rider plugin

**Drums too muddy?**
- EQ: Cut 200-400 Hz mud
- Boost 2-5 kHz for clarity
- Add transient shaper

**Bass lacks punch?**
- Layer with sub-bass generator
- Add saturation/distortion
- Sidechain compress to kick

**Stems have bleed?**
- Use gates/expanders
- Apply surgical EQ
- Re-run separation with higher quality model

### Recommended Plugin Chain

**Vocals:**
1. De-esser
2. EQ (cut mud, boost presence)
3. Compressor (4:1 ratio, medium attack)
4. Reverb (short room or plate)
5. Delay (subtle, tempo-synced)

**Drums:**
1. Transient shaper
2. EQ (boost kick/snare fundamentals)
3. Parallel compression
4. Room reverb (very subtle)

**Bass:**
1. Low-pass filter (clean up highs)
2. Saturation/distortion (harmonics)
3. Compressor (high ratio, fast attack)
4. Sidechain to kick

**Master Bus:**
1. EQ (gentle corrections)
2. Glue compressor (light)
3. Limiter (catch peaks)

## Troubleshooting

### Installation Issues

**"No module named 'demucs'"**
```bash
pip install demucs
```

**CUDA out of memory**
```bash
# Use CPU instead
python yourmt3_stem_separator.py file.mp3 --device cpu
```

### Separation Quality Issues

**Poor separation quality**
- Try different model: `--model htdemucs_ft`
- Ensure input is high quality (320kbps MP3 or WAV)
- Check for clipping in original file

**Stems don't align**
- Verify all stems are same sample rate
- Re-export from separator
- Use Reaper's automatic item alignment

**Artifacts in stems**
- Try re-running with different settings
- Apply noise reduction in Reaper
- Use spectral editing tools

### Reaper Issues

**Template doesn't load**
- Check file path is correct
- Ensure Reaper version compatibility (7.0+)
- Use basic project mode: `--no-auto-import`

**Can't find plugins**
- Run plugin rescan in Reaper
- Check plugin paths in Preferences
- Use `list-all-available-plugins.lua` to verify

## Advanced Configuration

### Custom Separation Settings

Edit `yourmt3_stem_separator.py` to modify:

```python
self.ai_audio_config = {
    'apply_spectral_cleaning': True,
    'enhance_transients': True,
    'artifact_reduction': True,
    'overlap_ratio': 0.5,  # Higher = better quality, slower
    'chunk_size': 10.0     # Chunk size in seconds
}
```

### Custom Template

Create your own template:

1. Set up tracks in Reaper as desired
2. Save as `.rpp` template
3. Use with: `--template path/to/template.rpp`

## Performance

### Processing Times (approximate)

**CPU (Intel i7):**
- 3-minute track: ~5-8 minutes

**GPU (NVIDIA RTX 3080):**
- 3-minute track: ~1-2 minutes

### Quality Comparison

| Model | Quality | Speed | Best For |
|-------|---------|-------|----------|
| htdemucs | High | Medium | General use |
| htdemucs_ft | Highest | Slow | Final production |
| demucs | Medium | Fast | Quick previews |

## Integration with SEMAS

This workflow can be integrated with the existing SEMAS system:

```python
from yourmt3_stem_separator import YourMT3StemSeparator

# In SEMAS agent
separator = YourMT3StemSeparator(output_dir="SEMAS/output/stems")
stems = separator.separate("input.wav")
```

## Credits & References

- **Demucs**: Facebook Research
- **YourMT3+**: Transformer-based music transcription
- **SEMAS**: Smart Enhancement & Mastering Automation System

## Support

For issues or questions:

1. Check the `IMPORT_INSTRUCTIONS.md` in your project folder
2. Review this guide
3. Check Reaper console for error messages
4. Verify all dependencies are installed

## License

This workflow is provided as-is for use with Reaper and Suno-generated content.
Respect copyright and licensing of all models and plugins used.

---

**Version**: 1.0
**Updated**: 2026-01-18
**Compatible with**: Reaper 7.0+, Python 3.8+
