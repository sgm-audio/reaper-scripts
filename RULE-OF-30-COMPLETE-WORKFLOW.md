<!-- META: This is a comprehensive production workflow document for heavy industrial metal production in REAPER -->

# THE RULE OF 30 - COMPLETE PRODUCTION WORKFLOW
## Professional Heavy Industrial Metal Production System
### Drop Bb Tuning | 48+ Tracks | Maximum Density Without Mud

---

## 📋 TABLE OF CONTENTS

1. [Pre-Production Setup](#1-pre-production-setup)
2. [Session Creation](#2-session-creation)
3. [Recording Phase](#3-recording-phase)
4. [Editing & Alignment](#4-editing--alignment)
5. [Mixing Phase](#5-mixing-phase)
6. [Master Bus Processing](#6-master-bus-processing)
7. [Export & Delivery](#7-export--delivery)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. PRE-PRODUCTION SETUP

### A. REAPER Configuration

**Buffer Size Settings:**
- **Recording:** 64-128 samples (low latency for monitoring)
- **Mixing:** 512-1024 samples (more processing power)
- **Mastering:** 2048 samples (maximum stability)

**Project Settings:**
```
Sample Rate: 48kHz (or 96kHz if CPU allows)
Bit Depth: 24-bit (32-bit float for stems)
Time Base: Beats (position, length, rate)
BPM: 95-110 (heavy groove range)
Time Signature: 4/4
```

**Track Template Prep:**
1. Run `rule-of-30-session-builder.lua`
2. Select "Build Complete Session Structure"
3. Result: 48+ tracks with folders, routing, and color coding

### B. Tuning & Calibration

**Drop Bb Standard:**
```
String 1: C  (523.25 Hz)
String 2: G  (392.00 Hz)
String 3: Eb (311.13 Hz)
String 4: Bb (233.08 Hz)
String 5: F  (174.61 Hz)
String 6: Bb (116.54 Hz)
```

**Tuning Protocol:**
- Use **Peterson StroboClip** or **PolyTune**
- Check intonation at 12th fret
- New strings mandatory for bass (dead strings = mud)
- Fresh strings recommended for guitars (under 2 hours of play time)

### C. Plugin Preparation

**Run Plugin Scanner:**
```lua
-- Execute this script in REAPER:
D:\[Reaper Custom]\ReaScripts\scan-real-plugins.lua
```

**Critical Plugins Checklist:**
- ✅ Waves V16 (SSL Comp, CLA-76, H-Delay, H-EQ, J37 Tape, OVox)
- ✅ iZotope (Ozone 11, Neutron 4, Trash 2, Nectar 4, Stutter Edit 2)
- ✅ FabFilter (Pro-Q 3, Pro-L 2, Saturn 2)
- ✅ Neural DSP (Archetype Gojira or Fortin Nameless Suite)

---

## 2. SESSION CREATION

### Step-by-Step Session Build

**Option A: Automated (Recommended)**
1. Open REAPER
2. Actions → Show action list
3. Load script: `rule-of-30-session-builder.lua`
4. Select "Build Complete Session Structure"
5. Wait for completion message
6. Save project as: `[Band Name] - [Song Title] - Rule of 30.RPP`

**Option B: Manual Template**
1. File → Project Templates → Load template...
2. Select: `suno-track-import-template.rpp`
3. Modify track names and routing as needed

### Session Structure Verification

Your session should now have:

```
📁 DRUMS (Titan Bus) - 12 tracks
  ├─ Kick (3 tracks: In, Out, Sub)
  ├─ Snare (4 tracks: Top, Bottom, Sample, Glitch)
  ├─ Cymbals/OH (5 tracks)
  └─ Toms (2 tracks)

📁 BASS ENGINE (Drop Bb) - 4 tracks
  ├─ Bass DI (Lows <200Hz)
  ├─ Bass Amp (Mids 200-2k)
  ├─ Bass Fuzz (Highs >2k)
  └─ Bass Synth Layer

📁 GUITARS (Wall of Sound) - 12 tracks
  ├─ Rhythm (Quad-tracked, 4 tracks)
  └─ Texture (Leads, Scrape, Ambient, 8 tracks)

📁 GLITCH & ATMOSPHERE - 10 tracks
  ├─ Industrial FX (3 tracks)
  └─ Synth Layer (3 tracks)

📁 VOCALS (Corrupted Robot) - 12+ tracks
  ├─ Core (2 tracks: Lead, Double)
  ├─ Glitch (2 tracks: Demon, Telephonic)
  ├─ Whispers (2 tracks: L/R)
  ├─ Screams (3 tracks)
  └─ Ad-libs (3 tracks)

📁 SEND FX - 5 tracks
  └─ Reverbs, Delays, Parallel Processing

🎛️ MASTER
```

---

## 3. RECORDING PHASE

### A. Drums (Acoustic or Programmed)

**If Programming MIDI:**
1. Use **GetGood Drums**, **Superior Drummer**, or **Addictive Drums**
2. Humanize velocity (90-127 range)
3. **CRITICAL:** Keep kick on grid for sidechain accuracy
4. Render MIDI to audio before mixing

**If Recording Live:**
1. Record to separate tracks (Kick In, Kick Out, Snare Top, etc.)
2. Check for phase between top/bottom snare mics
3. Maintain consistent gain staging (-18dB to -12dB peaks)

### B. Bass (3-Band Recording)

**Recording Order:**
1. **Bass DI** - Record first (clean, no processing)
2. **Bass Amp** - Record same performance through amp sim (Neural DSP Darkglass)
3. **Bass Fuzz** - Duplicate DI, add distortion later in mix
4. **Bass Synth** - MIDI track following root notes (add in mixing)

**DI Recording Settings:**
- **Input Gain:** Peak at -12dB
- **Monitoring:** OFF (use direct monitoring from interface)
- **Processing:** None (completely dry)

### C. Guitars (Quad-Tracking Protocol)

**THE MOST CRITICAL STEP FOR "WALL OF SOUND"**

**Performance Order:**
```
Pass 1: Rhythm L  (Bridge pickup, tight performance)
Pass 2: Rhythm R  (Bridge pickup, tight performance, DIFFERENT take)
Pass 3: Rhythm L2 (Neck pickup OR different guitar, loose feel)
Pass 4: Rhythm R2 (Neck pickup OR different guitar, loose feel)
```

**Recording Checklist per Pass:**
- [ ] Input peaks at -12dB to -6dB (leave headroom for amp sim)
- [ ] Noise gate active (or silence noise manually after)
- [ ] Record DI only (no amp sim while tracking)
- [ ] Play entire song without stopping (punch-ins sound obvious)
- [ ] DO NOT copy/paste - natural timing differences = width

**Visual Check:**
- Zoom in on waveforms
- The 4 takes should look SIMILAR but NOT IDENTICAL
- If they look identical, you accidentally copied a take

### D. Vocals (Dual-Layer System)

**Core Vocal Takes:**
1. **Lead Vocal** - Main performance, dry signal
2. **Lead Vocal Double** - Second take, full lyrics, dry
3. **Whisper Take** - Full lyrics in breathy ASMR style

**Texture Vocal Takes:**
4. **Screams** - Record twice (one center, one for texture)
5. **Ad-libs** - Short phrases, echoes, shouts
6. **Breaths** - Leave them in (remove in mix with Nectar)

**Monitoring Setup:**
- Monitor: WET (reverb + delay for vibe)
- Record: DRY (100% clean signal)
- Reason: Pitch correction and Stutter Edit need dry signal

### E. Glitch Source Material

**Foley Recording (30 seconds each):**
1. Mouse clicks (aggressive, rapid)
2. Mechanical keyboard typing
3. Metal surface hits (pot, pan, lamp)
4. Hard drive seeking sounds (use actual HDD)
5. White noise (from synth or generate in REAPER)

**Synthesis:**
1. Create MIDI track
2. Load **Serum** or **Waves Element**
3. Program:
   - Dark pad (minor chord, Bb)
   - Arpeggiator (fast 1/16 notes)
   - Reverse piano (reverse audio samples)

---

## 4. EDITING & ALIGNMENT

### A. Comping & Cleanup

**For Each Track:**
1. **Comp the best takes** (if you recorded multiple)
2. **Remove silence** between notes (manual or ReaGate)
3. **Crossfade edits** (select all items → press X)

### B. Phase Alignment (CRITICAL!)

**Automated Method:**
1. Select all 4 guitar DI tracks (Rhythm L, R, L2, R2)
2. Run script: `phase-alignment-tool.lua`
3. Choose "Auto-Align Selected Tracks"
4. Check console for results

**Manual Method (if automated fails):**
1. Zoom way in on first chug
2. Identify the "master" track (tightest performance)
3. Hold ALT and drag other waveforms to align peaks
4. Use slip-edit to match transients

**Verification:**
1. Click **MONO** on master track
2. Play the guitar section
3. **GOOD:** Louder, focused, powerful
4. **BAD:** Thinner, hollow, phasy

### C. Quantize (If Needed)

**For "Industrial Robot" Precision:**
1. Select guitar DI item
2. Press `D` (Dynamic Split)
3. Set to "Split at transients"
4. Press `Q` (Quantize to grid)
5. Crossfade all cuts (press `X`)

**Warning:** Over-quantizing kills groove. Use sparingly.

---

## 5. MIXING PHASE

### A. Gain Staging

**Target Levels (before processing):**
- Kick: -12dB peak
- Snare: -12dB peak
- Bass: -18dB peak
- Guitars: -18dB peak (per track)
- Vocals: -12dB peak
- Master Bus Input: -6dB peak (before SSL Comp)

### B. Plugin Chain Application

**Automated Plugin Loading:**
```lua
-- In rule-of-30-session-builder.lua menu:
Select option #2: Add Drum Processing Chains
Select option #3: Add Bass Processing Chains
Select option #4: Add Guitar Chains
Select option #5: Add Vocal Chains
```

**Manual Plugin Addition (if needed):**

**Kick Out Example:**
```
1. iZotope Neutron 4 (Sculptor module)
   - Lock fundamental to 60-80Hz

2. Waves dbx 160
   - Fast attack, hard compression
   - 4:1 ratio, 6dB gain reduction

3. FabFilter Pro-Q 3
   - Cut 200-400Hz (mud)
   - Boost 3kHz (click)
   - Boost 60Hz (weight)
```

### C. Sidechain Compression (The Low-End Protocol)

**Setup:**
1. Run script menu option #6: "Setup Kick/Bass Sidechain"
2. Verify routing:
   - Kick Out → Bass DI (channels 3/4)
   - Kick Out → Bass Synth (channels 3/4)

**Add Sidechain Compressor on Bass DI:**

**Method A: iZotope Neutron 4 (Unmask)**
1. Insert iZotope Relay on Kick Out track
2. Insert Neutron 4 on Bass DI track
3. Enable "Unmask" module
4. Select source: "Kick Out (Relay)"
5. Adjust amount until you see ducking on kick hits

**Method B: Waves F6 (Manual Control)**
1. Setup routing (already done by script)
2. Insert Waves F6 on Bass DI
3. Band 1: 50Hz, narrow Q
4. Enable "Ext" (external sidechain)
5. Pull Range knob down (-6dB)
6. Adjust threshold until kick triggers ducking

### D. Parallel Processing

**Parallel Drum Crush:**
1. Send all drum tracks to "Parallel Drum Crush" bus (pre-fader, -6dB)
2. On crush bus:
   - Waves CLA-76 (all buttons in, 20:1 ratio)
   - Smash it until you see 10-15dB gain reduction
   - Blend back under main drums (30% wet)

**Parallel Vocal Excitement:**
1. Duplicate lead vocal track
2. Add heavy saturation/distortion
3. Blend at -10dB to -15dB under main vocal

### E. Send Effects Configuration

**Hall Reverb:**
- Waves H-Reverb or Valhalla Room
- Pre-delay: 30ms
- Decay: 2.5s
- HPF: 200Hz, LPF: 8kHz

**1/8 Dotted Delay:**
- Waves H-Delay or EchoBoy
- Time: 1/8 note dotted (tempo-synced)
- Feedback: 35%
- Mix: 100% (it's a send)

### F. Vocal Processing (Dual-Layer)

**Lead Vocal (Core):**
```
1. iZotope Nectar 4
   - Gate (remove breaths)
   - De-esser (heavy)
   - Pitch correction (natural mode)

2. Waves CLA Vocals
   - Preset: Rock
   - Adjust Bass/Treble to taste

3. FabFilter Saturn 2
   - Tape saturation (subtle warmth)
```

**Demon Layer (-12 semitones):**
```
1. Waves OVox
   - Pitch: -12 semitones
   - Lock to scale: Bb Minor
   - Mix: 100%

2. Mix under lead vocal at -8dB
```

**Telephonic Layer:**
```
1. Waves Q10
   - Band-pass filter: 500Hz - 3kHz

2. iZotope Trash 2
   - Bitcrush module
   - Sample rate reduction

3. Mix at -10dB for "corrupted" texture
```

### G. Glitch Automation

**iZotope Stutter Edit 2 Setup:**
1. Create MIDI track
2. Route to "Glitch Bus Master" FX
3. Load Stutter Edit 2 on bus
4. Create gestures:
   - C3: Repeater (1/16 notes)
   - D3: Tape Stop
   - E3: Filter Sweep
5. Draw MIDI notes where you want glitches

**Manual Glitch (Alternative):**
1. Select vocal phrase
2. Press `D` (dynamic split)
3. Hold ALT and stretch middle slices
4. Sounds like corrupted audio file

---

## 6. MASTER BUS PROCESSING

**Refer to separate document:**
📄 `OZONE-11-MASTER-BUS-GUIDE.md`

**Quick Reference:**
```
Signal Flow:
INPUT → SSL Comp → J37 Tape → Ozone 11 → OUTPUT

Target Levels:
- Integrated LUFS: -6 to -7
- True Peak: -0.5dB
- Dynamic Range: 6-8 DR
```

---

## 7. EXPORT & DELIVERY

### A. Pre-Export Checklist

- [ ] Mono check (bass should not disappear)
- [ ] Reference check (compare to professional track)
- [ ] Codec check (export to MP3, re-import, check for artifacts)
- [ ] Silence check (mute all tracks, no hum/buzz on master)
- [ ] Metadata entered (artist, album, track number, ISRC)

### B. Export Settings

**For Streaming (Spotify, Apple Music, YouTube):**
```
Format: WAV
Bit Depth: 24-bit
Sample Rate: 48kHz (or match project rate)
Dither: None (Ozone handles this)
Normalize: OFF
True Peak Limit: -1.0dB (already set in Ozone)
```

**For Mastering Engineer:**
```
Format: WAV
Bit Depth: 32-bit float
Sample Rate: 48kHz
Disable: Ozone Maximizer module
Leave headroom: Peaks at -6dB (not -0.5dB)
Include: Separate stem exports (drums, bass, guitars, vocals)
```

**For CD/Vinyl:**
```
Contact mastering engineer
Do NOT use Ozone Maximizer
Export at 32-bit float, 48kHz
Provide 2-3dB of headroom
```

### C. File Naming Convention

```
Artist - Song Title - Version - Date.wav

Examples:
Manic Records - Rule of 30 - Master - 2025-01-19.wav
Manic Records - Rule of 30 - Instrumental - 2025-01-19.wav
Manic Records - Rule of 30 - Stems - 2025-01-19.zip
```

---

## 8. TROUBLESHOOTING

### Problem: Mix Sounds Muddy

**Diagnosis:**
- Too much low-end overlap (bass + kick fighting)
- Guitars have too much 200-500Hz
- Reverb is too long/wet

**Fix:**
1. Check kick/bass sidechain is working
2. High-pass guitars at 100Hz
3. Cut 200-400Hz on rhythm guitars (-3dB)
4. Shorten reverb decay times

### Problem: Mix Sounds Thin/Weak

**Diagnosis:**
- Phase cancellation (guitars out of phase)
- Not enough low-end
- Over-compression

**Fix:**
1. Run phase alignment tool on guitars
2. Check bass DI has low-pass filter (<200Hz)
3. Reduce SSL bus comp ratio (from 4:1 to 2:1)
4. Add harmonic saturation (J37 Tape)

### Problem: Vocals Buried in Mix

**Diagnosis:**
- Too much guitar in 2-4kHz range (vocal presence zone)
- Vocal not bright enough
- Reverb/delay too loud

**Fix:**
1. Cut 2-4kHz on rhythm guitars by -2 to -3dB
2. Boost 3-5kHz on lead vocal (+2dB)
3. Reduce reverb send by -3dB
4. Add FabFilter Saturn 2 for presence boost

### Problem: Kick Disappears When Limited

**Diagnosis:**
- Ozone Maximizer crushing transients
- Bass is louder than kick
- Kick EQ'd wrong

**Fix:**
1. Enable "Transient Emphasis" in Ozone Maximizer (+5)
2. Increase kick/bass sidechain amount
3. Check kick has boost at 60-80Hz AND 3-4kHz

### Problem: Sounds Great in REAPER, Terrible on Phone

**Diagnosis:**
- Low-end too wide (bass in stereo)
- Highs too harsh
- Phase issues

**Fix:**
1. Check Ozone Imager - mono below 120Hz
2. Reduce Ozone Exciter amount
3. Export to MP3, re-import, fix issues
4. Test on multiple devices before finalizing

---

## 9. BACKUP & PROJECT MANAGEMENT

### Auto-Save Configuration

**REAPER Preferences → Project:**
```
✅ Save to timestamped file in project directory
Interval: 5 minutes
Keep: 10 versions
Separate folder: Yes
```

### Project Folder Structure

```
[Band Name] - [Song Title]/
├─ [Song Title].RPP (main project)
├─ Audio/
│  ├─ Drums/
│  ├─ Bass/
│  ├─ Guitars/
│  └─ Vocals/
├─ Bounces/
│  ├─ Masters/
│  ├─ Stems/
│  └─ References/
├─ Backups/ (auto-save location)
└─ Notes.txt
```

---

## 10. ADVANCED TECHNIQUES

### A. Glitch Automation (Advanced)

**Parameter Automation for "System Failure" Effect:**

1. **On Vocal Track → iZotope Trash 2:**
   - Automate "Bitcrush" parameter
   - Draw ramp from 16-bit → 4-bit over 2 bars
   - Sounds like voice degrading

2. **On Guitar Track → Filter Cutoff:**
   - Automate low-pass filter sweep
   - 20kHz → 500Hz during breakdown
   - Creates "sucked into a black hole" effect

3. **On Master Track → Ozone Maximizer Threshold:**
   - Verse: -8 LUFS (more dynamic)
   - Chorus: -6 LUFS (louder, more aggressive)
   - Automate threshold during playback

### B. Frequency Slotting (Advanced Mixing)

**The "Rule of 30" requires strict frequency management:**

| Element | Frequency Range | Processing |
|---------|----------------|------------|
| **Sub-Bass** | 20-60Hz | Kick Sub + Bass Synth (mono) |
| **Low-End** | 60-200Hz | Kick Body + Bass DI (mono) |
| **Low-Mids** | 200-500Hz | Bass Amp + Snare Body (cut on guitars!) |
| **Mids** | 500Hz-2kHz | Guitars (quad-tracked, wide) |
| **Presence** | 2kHz-5kHz | Vocals + Guitar Attack |
| **Highs** | 5kHz-10kHz | Cymbals + Vocal Air |
| **Air** | 10kHz+ | Stereo width (reverb tails) |

**EQ Strategy:**
- Cut before boost
- Make room for vocals in 2-4kHz (cut guitars)
- High-pass everything except kick/bass
- Use dynamic EQ (iZotope Neutron) on conflicting elements

---

## 11. PERFORMANCE OPTIMIZATION

### CPU Management for 48+ Track Session

**During Recording:**
- Buffer: 64-128 samples
- Disable plugins on tracks you're not recording
- Use "Track FX Offline" for unused folders

**During Mixing:**
- Buffer: 512-1024 samples
- Freeze tracks with heavy plugins (Neural DSP, iZotope)
- Right-click track → Render/Freeze → Freeze to Stereo

**Before Export:**
- Buffer: 2048 samples
- Unfreeze all tracks
- Render all MIDI to audio
- Test full playback without dropouts

---

## FINAL NOTES

This workflow is designed for **maximum density without mud**. The key principles:

1. **Frequency Separation** - Bass is split into 3 bands
2. **Phase Coherence** - Guitars are sample-aligned
3. **Sidechain Compression** - Kick and bass never fight
4. **Parallel Processing** - Aggression without destruction
5. **Dual-Layer Vocals** - Clarity + texture

**Estimated Time Investment:**
- Session Setup: 30 minutes
- Recording: 4-8 hours
- Editing/Alignment: 2-4 hours
- Mixing: 8-12 hours
- Mastering: 2-3 hours

**Total:** 16-27 hours for a complete professional mix

---

📄 **Related Documents:**
- `OZONE-11-MASTER-BUS-GUIDE.md` - Detailed mastering chain
- `rule-of-30-session-builder.lua` - Automated session creation
- `phase-alignment-tool.lua` - Guitar alignment automation
- `scan-real-plugins.lua` - Plugin inventory system

**Questions? Issues?**
Check the console output from the ReaScripts for diagnostic information.

---

**NOW GO CREATE SOMETHING MASSIVE.** 🎸🔥🥁
