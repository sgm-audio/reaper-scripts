# Stem Surgeon — Roadmap to Full Functionality

Audited 2026-05-14. Every item verified against source code.
This document describes what must be done to make Stem Surgeon work as
described in `README.md` and `CLAUDE.md`:
> Load plugin → select stem → enter text prompt → click Analyze → ARA
> processes audio → adjust Amount knob to crossfade.

The project is currently at **~60% functional**: the Python training stack
is complete, the C++ plugin compiles and loads ONNX models, the signal chain
bugs are fixed, but the audio output is meaningless because the ONNX weights
are from random initialisation and the CLAP text encoder is a mock. No
trained model checkpoint exists.

---

## Phase Overview

| Phase | Goal | Estimated Effort | Depends On |
|-------|------|-----------------|------------|
| 1 | Fix C++ signal chain (tokenizer, input shape) | 1–2 days | None |
| 2 | Real CLAP text encoder export | 1–2 days | Phase 1 |
| 3 | Training pipeline — produce a real checkpoint | 3–7 days GPU | Phase 2 |
| 4 | Plugin audio-thread safety | 2–3 days | Phase 1 |
| 5 | Plugin output quality (resampling, blending) | 1–2 days | Phase 1 |
| 6 | ARA integration completion | 2–3 days | Phase 4 |
| 7 | End-to-end verification tests | 1–2 days | Phase 3 |
| 8 | Rust inference server | ~~3–5 days~~ DONE | Phase 3 |
| 9 | Release hardening & polish | 2–3 days | Phases 1–7 |

---

## Phase 1: Fix C++ Signal Chain (BLOCKERS)

These are the bugs that make the plugin produce silence or garbage.
Nothing else matters until these are fixed.

### 1.1 Fix `applyBPE` UTF-8 Codepoint Iteration — GAP 3

**Status:** ALREADY FIXED
**File:** `plugin/src/ClapTokenizer.cpp:348`
`applyBPE()` now uses `Utf8Iter` for codepoint iteration, preserving multi-byte
UTF-8 characters intact as single BPE pieces.

### 1.2 Fix Model Input Length Mismatch — GAP 4

**Status:** ALREADY FIXED
**File:** `plugin/src/InferenceEngine.cpp:168-172`
`processChunked()` now pads each chunk to `expected` samples with
`std::vector<float> padded((size_t) expected, 0.0f)` and passes
shape `{1, 1, (int64_t) expected}` to ORT.

### 1.3 Clean Up Dead Declarations — GAPs 10 & 11

**Status:** ALREADY FIXED
**Files:** `plugin/src/ClapTokenizer.h`
Dead `bytesToByteLevel()` declaration removed. `getBosId()` and `getEosId()`
are public at lines 17-18.

### 1.4 Fix Stale `export_manifest.json`

**Status:** ALREADY FIXED
**File:** `exports/export_manifest.json`
Updated to T=441344, correct output names (`refined_specs [B, 5, T]`,
`confidences [B, 5, F, T_frames]`), and `is_waveform_out: true`.

---

## Phase 2: Real CLAP Text Encoder Export — GAP 6

The mock CLAP encoder (`Linear(77, 512)`, 159KB) produces meaningless
embeddings. Text prompts have zero effect on separation. This must be
replaced with the real LAION CLAP text encoder (~500MB).

### 2.1 Export Real CLAP Text Encoder to ONNX

**File:** `model/scripts/export_onnx.py`

**Current state:** `MockCLAPTextBranch` is used as fallback when
`laion_clap` is not importable during export. The mock is a single
`Linear(77, 512)` layer.

**Fix:**
1. Install `laion_clap` in the training environment.
2. Modify `export_onnx.py` to trace the real CLAP text encoder:
   ```python
   from laion_clap import CLAP_Module
   clap = CLAP_Module(enable_fusion=False)
   clap.load_checkpoint()  # loads music_audioset_epoch_15_esc_90.14.pt

   # Extract just the text branch
   text_encoder = clap.model.text_branch
   text_encoder.eval()

   # Trace with dummy input
   dummy_ids = torch.randint(0, 49408, (1, 77))
   dummy_mask = torch.ones(1, 77, dtype=torch.long)

   torch.onnx.export(
       text_encoder,
       (dummy_ids, dummy_mask),
       "exports/clap_text_encoder.onnx",
       input_names=["input_ids", "attention_mask"],
       output_names=["clap_embedding"],
       dynamic_axes=None,  # fixed length 77
       opset_version=17,
   )
   ```
3. Update `export_manifest.json` with real CLAP encoder metadata.

**Risk:** The LAION CLAP text branch uses attention layers that may not
export cleanly to ONNX. Test the exported model first with `onnxruntime`
in Python before copying to the plugin directory.

**Verification:**
- `clap_text_encoder.onnx.data` should be ~500MB (not 159KB).
- Run the ONNX model in Python: `ort.InferenceSession("exports/clap_text_encoder.onnx")`
  with the same token IDs and compare the output embedding to the
  PyTorch model's output (cosine similarity > 0.99).

### 2.2 Handle CLAP Model Size in Plugin Distribution

A 500MB ONNX model is too large to bundle with the plugin. Options:

| Option | Pros | Cons |
|--------|------|------|
| A. First-time download on plugin init | Small plugin binary | Requires network; UX friction |
| B. Ship as separate download | Clean separation | User must install manually |
| C. Quantise CLAP to INT8 | ~125MB, may be acceptable | Small quality loss |
| D. Use a smaller text encoder | Much smaller | Training must match |

**Recommendation:** Start with **B** (separate download, plugin prompts
for path). Evaluate **C** (INT8 quantisation) in Phase 9 if distribution
size is a problem.

### 2.3 Enable CLAP Loss in Training

**Status:** DONE
`base.yaml` now defaults `use_clap_loss: true`. `debug.yaml` keeps `false`
for fast iteration. `CLAPReconstructionLoss` is fully implemented — uses
frozen CLAP audio embeddings with cosine distance; falls back to spectral
cosine distance when `laion_clap` is not installed.

---

## Phase 3: Training Pipeline — Produce a Real Checkpoint — GAP 14

Without a trained model, nothing the plugin does is meaningful. The
architecture is complete and tests pass; what's missing is actual
training data + GPU time.

### 3.1 Data Preparation

**Commands:**
```bash
just prepare-data  # processes MUSDB18-HQ / Slakh2100 / custom
```

**Requirements:**
- MUSDB18-HQ (150 songs, ~40GB) or Slakh2100 (2100 songs, ~100GB)
- SSD storage for training speed
- Precompute CLAP embeddings: `StemPairDataset(precomputed_clap_dir=...)`
  to avoid recomputation per epoch

**Verification:** `uv run pytest model/tests/test_data.py` passes.
Dataset yields batches with correct shapes: `mix (B,1,T)`, `stems
(B,5,T)`, `clap_emb (B,512)`.

### 3.2 Training Run

**Commands:**
```bash
just train model/configs/full_train.yaml
```

**Requirements:**
- NVIDIA GPU with ≥24GB VRAM (Mamba-SSM requires CUDA)
- `mamba_ssm` package installed (`pip install mamba-ssm`)
- Wandb account for logging (or set `WANDB_MODE=disabled`)

**Key hyperparameters** (from `full_train.yaml`):
- Batch size: 8 (gradient accumulation if OOM)
- Learning rate: 3e-4 with cosine decay + warmup
- Epochs: 100+ (monitor validation SI-SDR)
- Mixed precision: bfloat16

**Monitoring:**
- Track `val/si_sdr` — should reach >10 dB for vocals
- Track `val/bleed` — should decrease (less cross-stem leakage)
- Track `val/sum_consistency` — should approach 0
- Early stop if `val/si_sdr` plateaus for 10 epochs

### 3.3 ONNX Export from Trained Checkpoint

**Commands:**
```bash
just export checkpoints/best.ckpt exports/
```

**Critical steps:**
1. If `compile: true` was used during training, call
   `torch._dynamo.reset()` before export.
2. Ensure `mamba_ssm` is installed — otherwise ONNX export uses
   `nn.Linear` fallback (GAP 13), producing a broken model.
3. Verify the exported model produces output close to the PyTorch model
   (SNR > 80 dB on a test clip).
4. Export both `stem_surgeon.onnx` and `clap_text_encoder.onnx`.

**Verification:** `uv run pytest model/tests/test_onnx_parity.py` passes
(requires `onnxruntime` + `exports/stem_surgeon.onnx`).

### 3.4 Mamba3 SSM in ONNX — GAP 13

**Current state:** When `mamba_ssm` is not installed, `Mamba3Block`
falls back to `nn.Linear(d_model, d_model)`. This produces a broken
model in ONNX export.

**Fix:**
1. Ensure `mamba_ssm` is installed in the export environment.
2. If Mamba ops cannot be exported via `torch.onnx.export` (custom CUDA
   kernels), implement a custom ONNX export path:
   - Decompose each `Mamba3Block` into its constituent operations
     (linear projections, selective scan, S6 recurrence)
   - Export each as standard ONNX ops
   - Alternatively: convert to a reference implementation that uses
     only standard ONNX ops (may be slower but correct)
3. As a fallback, replace `Mamba3Backbone` with a transformer-based
   backbone that exports cleanly to ONNX. This requires retraining.

**Recommendation:** First attempt export with `mamba_ssm` installed. If
that fails, investigate `mamba-ssm` ONNX decomposition. Transformer
fallback is a last resort (requires architecture change + retraining).

---

## Phase 4: Plugin Audio-Thread Safety — GAP 8

**Status:** ALREADY MITIGATED
Non-ARA path uses `InferenceWorker` (background thread) with SPSC queue.
ARA renderer returns `false` if `Realtime::yes`. The remaining work
(latency compensation, real-time vs offline mode detection) is optional
polish.

### 4.1 Background Inference Thread

**Current state:** `StemSurgeonRuntime` already has a ring buffer and
`runInferenceOnChunk()` dispatch. The issue is that
`PluginProcessor::processBlock()` calls inference synchronously.

**Fix:**
1. Add a dedicated inference thread (`std::thread`) that:
   - Waits on a condition variable for new input chunks
   - Runs ORT `Run()` on the background thread
   - Writes results to a lock-free output buffer
2. In `processBlock()`:
   - Read from the lock-free output buffer (non-blocking)
   - If no output is available yet, output silence or the dry signal
   - Write input audio to the ring buffer
3. The inference thread signals completion via `std::atomic<bool>`.

**Files:** `plugin/src/PluginProcessor.cpp`, `plugin/src/StemSurgeonRuntime.cpp`

### 4.2 Latency Compensation

**Current state:** Plugin reports 0 latency.

**Fix:**
1. Report latency = `modelLookaheadSamples44100()` (882 samples at 44.1k
   = ~20ms).
2. Call `setLatencySamples(latency)` in `prepareToPlay()`.
3. DAWs will compensate for this latency automatically.

### 4.3 Real-time vs Offline Mode Detection

**Fix:**
1. If the host is processing in real-time (detected via
   `juce::AudioProcessor::isNonRealtime() == false`), use the background
   thread path with dry-signal fallback.
2. If the host is in offline mode (`isNonRealtime() == true`), allow
   synchronous inference (faster, no dropouts).
3. ARA rendering is always offline — synchronous is fine there.

---

## Phase 5: Plugin Output Quality

### 5.1 Resampling Quality — GAP 9

**Status:** ALREADY FIXED
**File:** `plugin/src/PluginProcessor.h:93-95`
Uses `juce::Interpolators::WindowedSinc` (200-tap windowed sinc interpolation),
NOT linear interpolation. This provides high-quality anti-aliased resampling
at non-44.1k sample rates. No fix needed.

### 5.2 Confidence-Weighted Blending

**Status:** ALREADY FIXED
Non-ARA path: `PluginProcessor.cpp:306-309` and `323-326` — per-sample
`conf * wet + (1.0f - conf) * dry` blended with `blend_amount`.
ARA path: `StemSurgeonARAPlaybackRenderer.cpp:111-122` — per-sample
confidence blend using extracted per-stem confidence from `result.confidence`.

### 5.3 Stereo Processing

**Status:** DONE
Non-ARA path: `PluginProcessor.cpp` — per-sample separation gain (`wet / mono_input`) applied
to each channel independently, preserving stereo image. ARA path:
`StemSurgeonARAPlaybackRenderer.cpp` — same gain-based per-channel blending.

**Implementation:**
1. `InferenceWorker::doInference()` computes `separation_gain[i] = stem[i] / mono_input[i]`
   (clamped at epsilon) and stores it alongside `stem_audio` and `confidence`.
2. `PluginProcessor::processBlock()` uses `gain * input_ch` for each output channel,
   then applies confidence blending and amount crossfade.
3. ARA renderer computes the same gain inline and applies it per-channel.

**Key insight:** Applying the same mono separation gain to both L and R channels preserves
the stereo image: if a vocal is panned left, the separated vocal stays panned left.
The mono `wet` stem alone would collapse to mono.

---

## Phase 6: ARA Integration Completion

### 6.1 ARA Stem Selection — GAP 12

**Status:** ALREADY FIXED
`StemSurgeonARAPlaybackRenderer.cpp:87-103` reads the `stem` parameter
from APVTS and maps it: choice 0 = Mix, choice > 0 → `ml_stem_idx = choice - 1`.

### 6.2 ARA Persistence Key — Raw Pointer Bug

**Status:** ALREADY FIXED
`StemSurgeonARADocumentController.cpp` now uses `std::string` keys
(from `getPersistentID()`) in `analysis_cache_` instead of raw
`AudioSource*` pointers. Serialization already used persistent IDs;
the in-memory map now matches.

### 6.3 ARA Analysis Trigger

**Current state:** ARA processing is triggered but the "Analyze" button
in the UI needs to initiate background analysis properly.

**Fix:**
1. "Analyze" button → sets a flag → ARA `processBlock()` detects it
   → runs inference on the full audio source → stores results.
2. After analysis completes, ARA renderer reads pre-computed results
   from the document controller's state.
3. This avoids re-running inference on every playback call.

---

## Phase 7: End-to-End Verification Tests — GAP 7

### 7.1 ONNX Parity Test

**File:** `model/tests/test_onnx_parity.py`

**Current state:** Test skips unless `onnxruntime` + ONNX file exist, and
is marked `xfail`.

**Fix:**
1. Remove `xfail` marker once parity is confirmed.
2. Test protocol:
   - Generate a known input waveform (e.g., 1kHz sine at 44100Hz,
     length 440320 samples)
   - Run through PyTorch `StemSurgeon` model → get 5 stem waveforms
   - Run through ONNX `stem_surgeon.onnx` → get 5 stem waveforms
   - Assert SNR > 80 dB for each stem
3. Add as CI step (requires GPU runner for PyTorch, ORT for inference).

### 7.2 Plugin Smoke Test

**Fix:**
1. Create a test that loads the VST3 via JUCE's `PluginHost` and
   processes a block of silence → check output is finite (no NaN/Inf).
2. Process a 1kHz sine → check output is non-zero.
3. Process a full-length clip → check output length matches input.

### 7.3 CLAP Tokenizer Roundtrip Test

**Fix:**
1. Tokenize a set of known strings → compare token IDs to HuggingFace
   `roberta-base` tokenizer output.
2. Test strings should include:
   - Simple ASCII: "hello world"
   - Multi-byte UTF-8: "café résumé"
   - Byte-level BPE characters: "Ġisolation"
   - The actual prompt: "isolated female vocals"
3. Add as a C++ unit test using JUCE's test framework.

### 7.4 Integration Test Matrix

| Test | Input | Expected Output | Tolerance |
|------|-------|-----------------|-----------|
| Silence in | All zeros | All zeros (stems = silence) | Exact |
| Sine in | 1kHz sine, 440320 samples | 5 non-zero stems | RMS > -60 dB |
| Music clip | MUSDB18-HQ song excerpt | SI-SDR(vocals) > 8 dB | With trained model |
| Short clip | 220500 samples (< 440320) | Padded, inferred, truncated | No ORT error |
| Long clip | 30s (1,323,000 samples) | Overlap-add seamless output | No clicks at seams |
| Non-44.1k | 48kHz input | Resampled correctly | No aliasing |

---

## Phase 8: Rust Inference Server

**Status:** DONE (ONNX inference, overlap-add, file + server mode fully implemented)

### 8.1 ONNX Runtime Integration — DONE

**File:** `inference/src/main.rs`

**Current state:** Fully implemented.
- `InferenceEngine` wraps `Mutex<Session>` for thread-safe ONNX access.
- `process()` method: pads input to `expected_mix_samples`, creates input tensor, runs ORT inference, applies confidence blending.
- Overlap-add chunking with half-Hann crossfade (882-sample overlap at 44.1kHz), window-sum normalization.
- `process_file()` reads stereo WAV → sums to mono → chunks → overlap-add → writes 5 stem WAVs.
- Default CLAP embedding = zeros `[512]` (no text prompt support yet — needs Rust BPE tokenizer).
- Uses `ort = "2.0.0-rc.12"` with `download-binaries` feature.

### 8.2 CLAP Text Encoder in Rust — STILL NEEDED

**Current state:** Not yet implemented. The Rust server defaults to a zeros `[512]` CLAP embedding when no text prompt is provided. To support text prompts:
1. Implement BPE tokenization in Rust (same logic as C++ `ClapTokenizer`).
2. When `--text-prompt` is provided: tokenize → run `clap_text_encoder.onnx` → pass embedding to main model.
3. Cache CLAP embedding per prompt string.

### 8.3 HTTP Server Mode — DONE

**File:** `inference/src/server.rs`

**Current state:** Fully implemented.
- HTTP batch endpoint: `POST /v1/batch` accepts base64-encoded audio (`raw_f32` or `wav_i16` format).
- Returns stem audio as base64-encoded i16 LE.
- Uses `axum` for the HTTP server.
- Thread-safe: `Mutex<Session>` for ONNX access.
- Error handling with counters for failed inference requests.

### 8.4 CLI Mode — DONE

**File:** `inference/src/main.rs`

**Current state:** Fully implemented.
- `cargo run -p stem-surgeon-inference -- --model stem_surgeon.onnx --input mix.wav --output-dir stems/`
- Reads input WAV → stereo→mono downmix → pad → overlap-add ORT inference → write 5 stem WAVs.
- Supports `--text-prompt` flag (currently ignored — defaults to zeros embedding).
- Supports `--output-dir` for stem output files.
- `serve` subcommand for HTTP server mode.

---

## Phase 9: Release Hardening & Polish

### 9.1 CLAP Encoder INT8 Quantisation

If the real CLAP text encoder (~500MB) is too large for distribution:
1. Quantise `clap_text_encoder.onnx` to INT8 using
   `onnxruntime.quantization.quantize_dynamic()`.
2. Expected size reduction: ~4x (500MB → ~125MB).
3. Verify embedding quality after quantisation (cosine similarity > 0.98
   vs FP32).

### 9.2 Mamba3 ONNX Export Cleanup — GAP 13

1. Investigate whether `mamba_ssm` ops can be exported to ONNX directly.
2. If not, implement a custom ONNX decomposition of the selective scan
   operation into standard ONNX ops.
3. As a last resort, provide a transformer-based backbone variant that
   exports cleanly (requires retraining).

### 9.3 Plugin Parameter Validation

1. Clamp `amount` to [0, 100] range.
2. Validate `stem` choice is within valid set.
3. Validate model file paths on load — show error in UI if file is
   corrupt or wrong format.
4. Add "Models Loaded" status indicator in UI.

### 9.4 Error Handling & Edge Cases

**Status:** DONE

1. **ORT session creation fails** → `recreateInferenceEngine()` sets `model_load_status_` error string, stores `nullptr` in `inference_atomic_`, `processBlock()` early-returns (dry passthrough).
2. **Audio is all silence** → `separation_gain` = 0.0f (epsilon guard), so `wet_ch = 0 * dry = 0`. With confidence blending: `(1-conf) * dry`. If model produces NaN/Inf, fallback to `dry` (NaN/Inf check in both `processBlock()` and ARA renderer).
3. **ONNX model file missing** → same as item 1; `model_load_status_` describes the missing file.
4. **Small host buffer (32 samples)** → ring buffer accumulates across `processBlock()` calls; no chunk is submitted until `expected_mix_samples_` accumulated. Output is read from the latest completed inference result. No partial-chunk issue.
5. **Separation gain extreme values** → clamped to [-2, 2] in both `InferenceWorker::doInference()` and ARA renderer.

### 9.5 Documentation

1. Update `README.md` with accurate current instructions.
2. Document the ONNX model format (input/output shapes, types).
3. Document the plugin parameter set.
4. Add a troubleshooting section for common issues (model not found,
   ORT errors, no audio output).

### 9.6 Distribution

1. Package the VST3 plugin binary.
2. Package the ONNX model files (or provide download script).
3. Create an installer or zip archive.
4. Test installation on a clean system.

---

## Dependency Graph

```
Phase 1 (C++ fixes)
    ├── Phase 2 (Real CLAP)
    │       └── Phase 3 (Training) ──── Phase 7 (E2E tests)
    ├── Phase 4 (Audio-thread safety)
    │       └── Phase 6 (ARA completion)
    └── Phase 5 (Output quality)

Phase 3 ──── Phase 8 (Rust server) — DONE

Phases 1–8 ──── Phase 9 (Release)
```

**Critical path:** Phase 1 → Phase 2 → Phase 3 → Phase 7
(Without a trained model, nothing is verifiable.)

---

## Quick Wins (Already Completed)

These were independent of the critical path and have been fixed:

1. **Fix `applyBPE` UTF-8 iteration** (Phase 1.1) — DONE (uses `Utf8Iter`)
2. **Fix `export_manifest.json`** (Phase 1.4) — DONE (T=441344, correct names)
3. **Remove dead `bytesToByteLevel` declaration** (Phase 1.3) — DONE
4. **Add `getBosId()`/`getEosId()` getters** (Phase 1.3) — DONE
5. **Fix ARA stem selection hardcoded index** (Phase 6.1) — DONE (reads from APVTS)
6. **Fix ARA persistence key** (Phase 6.2) — DONE (uses persistent ID string)
7. **Wire confidence blending in output path** (Phase 5.2) — DONE (both ARA and non-ARA)
8. **Fix model input length padding** (Phase 1.2) — DONE (pads to `expected`)

## Remaining Quick Wins

1. ~~**Replace linear resampling with polyphase FIR** (Phase 5.1)~~ — ALREADY FIXED (uses WindowedSinc)

---

## Known Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Mamba3 SSM cannot export to ONNX | Model architecture must change | Investigate decomposition; transformer fallback |
| Real CLAP text encoder too large | Distribution difficulty | INT8 quantisation; separate download |
| Training does not converge to useful SI-SDR | Plugin is useless with untrained model | Start with debug.yaml; iterate on loss weights |
| ORT inference too slow for real-time | Audio dropouts persist | Background thread + dry fallback; consider GPU inference via CUDA EP |
| ARA SDK version incompatible with DAW | ARA integration fails | Test with multiple DAW versions (REAPER, Ableton) |
| BPE tokenizer produces wrong IDs | Text conditioning is broken | Roundtrip test against HuggingFace reference |

---

## Success Criteria

The project reaches "full functionality" when:

1. **Plugin loads** in a DAW without errors.
2. **User selects a stem** (vocals/drums/bass/other/fx) and the plugin
   outputs that stem (not always vocals).
3. **User enters a text prompt** and the separation result changes
   meaningfully compared to no prompt.
4. **"Analyze" button** triggers ARA background processing.
5. **Amount knob** crossfades between original mix and separated stem.
6. **Audio output** is artifact-free at 44.1kHz and other supported
   sample rates (48kHz, 96kHz, etc.).
7. **No audio dropouts** during real-time playback (background inference
   thread).
8. **SI-SDR ≥ 8 dB** for vocals on MUSDB18-HQ test set.
9. **Overlap-add stitching** is seamless for long audio (no clicks).
10. **E2E test suite** passes in CI.

---

## Appendix: GAP Status Reference

| GAP | Claim | Status | Phase |
|-----|-------|--------|-------|
| 1 | kByteToUnicode table wrong | **ALREADY FIXED** | — |
| 2 | Pre-tokenizer wrong order | **ALREADY FIXED** | — |
| 3 | applyBPE splits on char | **ALREADY FIXED** | 1 |
| 4 | Model input length mismatch | **ALREADY FIXED** | 1 |
| 5 | iSTFT normalization mismatch | **MOOT** | — |
| 6 | CLAP text encoder is mock | **CONFIRMED** | 2 |
| 7 | No e2e verification test | **CONFIRMED** | 7 |
| 8 | Inference on audio thread | **ALREADY MITIGATED** | 4 |
| 9 | Linear resampling low-quality | **ALREADY FIXED** | — |
| 10 | Dead bytesToByteLevel declaration | **ALREADY FIXED** | 1 |
| 11 | Missing getBosId/getEosId getters | **ALREADY FIXED** | 1 |
| 12 | ARA stem selection hardcoded | **ALREADY FIXED** | 6 |
| 13 | Mamba3 Linear fallback in ONNX | **CONFIRMED** | 9 |
| 14 | No trained model checkpoint | **CONFIRMED** | 3 |

### New findings (not in original audit)

| Finding | Severity | Phase | Status |
|---------|----------|-------|--------|
| `export_manifest.json` stale | HIGH | 1 | **FIXED** |
| `use_clap_loss=False` makes CLAP loss zero | MEDIUM | 2 | **FIXED** — `base.yaml` now `true` |
| Plugin confidence blending not implemented | MEDIUM | 5 | **FIXED** |
| ARA persistence uses raw pointer as key | MEDIUM | 6 | **FIXED** |
| Rust inference server is all stub | LOW | 8 | **FIXED** — full ONNX inference, overlap-add, file+server mode |
| Rust server needs CLAP tokenizer | MEDIUM | 8 | Open — defaults to zeros embedding, no text prompt support yet |
