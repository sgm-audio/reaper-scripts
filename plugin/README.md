# SGM Utility — buildable JUCE baseline

This directory is a complete JUCE 8 audio-plugin project, not a directory-only
scaffold. It builds **VST3** and **Standalone** targets and a native processing
test executable. The baseline provides smoothed gain, bypass, mono/stereo bus
handling, state save/restore, automation-ready parameters, and a small editor.

**AI scope:** stem separation, mastering inference, model loading, and CLAP are
not implemented in this baseline. The Python Demucs adapter is an offline
workflow tool; it is not embedded in this real-time plugin. Add and validate a
model runtime in a separate development phase before making AI claims.

## Prerequisites

- CMake 3.22 or newer
- A C++17 compiler: Visual Studio 2022 (Windows), Xcode (macOS), or GCC/Clang
  (Linux)
- JUCE 8.0.4. CMake downloads the pinned commit archive and verifies its SHA-256
  checksum automatically; an existing source checkout can be supplied instead.

Linux JUCE development packages on Debian/Ubuntu:

```sh
sudo apt-get update
sudo apt-get install -y build-essential cmake ninja-build pkg-config git \
  libasound2-dev libx11-dev libxext-dev libxinerama-dev libxrandr-dev \
  libxcursor-dev libfreetype6-dev libfontconfig1-dev libgl1-mesa-dev
```

Use the corresponding JUCE platform dependencies on other distributions. A DAW
or plugin host is needed to test the installed VST3; the native tests do not
require a DAW.

## Configure, build, and test

From this directory (`plugin/` in the repository, or the generated
`SGM_AI_Plugin_Suite/` directory):

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
```

For a local JUCE checkout and no dependency download:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
  -DSGM_JUCE_SOURCE_DIR=/absolute/path/to/JUCE
```

To build only one target:

```sh
cmake --build build --config Release --target SGMUtility_VST3
cmake --build build --config Release --target SGMUtility_Standalone
```

JUCE writes artifacts below `build/SGMUtility_artefacts/`. On a single-config
Release build, the VST3 is normally at
`build/SGMUtility_artefacts/Release/VST3/SGM Utility.vst3`; multi-config paths
vary by generator. Copy the `.vst3` bundle to your platform's VST3 directory,
then rescan plugins in REAPER. Do not copy build artifacts into the REAPER
Scripts directory.

## Extend toward AI processing

1. Keep heavy model inference off the audio callback and define explicit
   latency, cancellation, failure, and progress behavior.
2. Add a model runtime and legally distributable model files with pinned
   versions and checksums.
3. Add native tests for model loading, malformed input, offline rendering, and
   parameter/state compatibility before changing the plugin's identity.
4. Add CLAP through a supported JUCE/CLAP extension as a separate target and
   validate it in compatible hosts.
