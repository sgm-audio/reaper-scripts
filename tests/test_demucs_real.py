"""Real Demucs execution test (no mocks).

Runs the actual htdemucs model on CPU over a short (3s) multi-tone WAV fixture.
Gated by SGM_REAL_DEMUCS=1 so the lightweight suites stay fast; the dedicated CI
job sets it and a missing backend or model download FAILS instead of skipping.
"""
import contextlib
import errno
import hashlib
import io
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

ENABLED = os.environ.get("SGM_REAL_DEMUCS") == "1"
SR = 44100
SECONDS = 3


def _mix():
    import numpy as np
    t = np.arange(SR * SECONDS) / SR
    rng = np.random.default_rng(7)
    bass = 0.35 * np.sin(2 * np.pi * 55 * t)
    chord = sum(0.08 * np.sin(2 * np.pi * f * t) for f in (220, 277.2, 329.6, 440))
    kick_env = np.exp(-((t % 0.5) * 18))
    kick = 0.6 * np.sin(2 * np.pi * 60 * (t % 0.5) * 8) * kick_env
    hats = 0.15 * rng.standard_normal(t.size) * np.exp(-(((t + 0.25) % 0.5) * 40))
    mono = bass + chord + kick + hats
    return np.stack([mono, 0.9 * mono], axis=1).astype("float32")


def _sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


@unittest.skipUnless(ENABLED, "set SGM_REAL_DEMUCS=1 to run real Demucs")
class RealDemucsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import numpy as np
        import soundfile as sf
        import torch
        import demucs
        from yourmt3_stem_separator import YourMT3StemSeparator
        cls.np, cls.sf = np, sf
        cls.tmp = tempfile.TemporaryDirectory()
        cls.src = Path(cls.tmp.name) / "mix.wav"
        cls.mix = _mix()
        sf.write(cls.src, cls.mix, SR, subtype="FLOAT")
        cls.mix_sha256 = _sha256(cls.src)
        print(f"HOST torch={torch.__version__} demucs={getattr(demucs, '__version__', '?')}")
        cls.sep = YourMT3StemSeparator(
            output_dir=str(Path(cls.tmp.name) / "out"), device="cpu", timeout_seconds=1500)
        print("HOST model container:", cls.sep.download_model("htdemucs"))
        cls.stems = cls.sep.separate(str(cls.src))
        cls.stem_sha256 = {name: _sha256(path) for name, path in sorted(cls.stems.items())}
        print(f"HOST sha256 mix={cls.mix_sha256[:16]} " +
              " ".join(f"{k}={v[:16]}" for k, v in cls.stem_sha256.items()))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def _read(self, name):
        data, sr = self.sf.read(self.stems[name], always_2d=True, dtype="float32")
        return data, sr

    def test_real_demucs_returns_exactly_four_existing_stems_with_unique_checksums(self):
        self.assertEqual(set(self.stems), {"vocals", "drums", "bass", "other"})
        for name, path in self.stems.items():
            self.assertTrue(Path(path).is_file(), name)
            self.assertNotEqual(self.stem_sha256[name], self.mix_sha256,
                                f"{name} checksum must differ from input mix")
        self.assertEqual(len(set(self.stem_sha256.values())), 4,
                         f"all 4 stem SHA-256 checksums must be distinct: {self.stem_sha256}")

    def test_real_demucs_stems_preserve_rate_length_and_channels(self):
        for name in self.stems:
            data, sr = self._read(name)
            self.assertEqual(sr, SR, name)
            self.assertEqual(data.shape, self.mix.shape, name)
            self.assertTrue(self.np.isfinite(data).all(), name)
            self.assertGreater(float(self.np.max(self.np.abs(data))), 0.0, f"{name} must be non-silent")

    def test_real_demucs_stems_are_not_passthrough_copies(self):
        np = self.np
        stems = {n: self._read(n)[0][:, 0] for n in self.stems}
        mix = self.mix[:, 0]
        for n, s in stems.items():
            # no stem may equal the mix
            self.assertGreater(np.linalg.norm(s - mix), 0.05 * np.linalg.norm(mix), n)
        names = list(stems)
        for i, a in enumerate(names):
            for b in names[i + 1:]:
                self.assertFalse(np.allclose(stems[a], stems[b], atol=1e-4), (a, b))

    def test_real_demucs_stems_resum_to_the_input(self):
        np = self.np
        total = sum(self._read(n)[0] for n in self.stems)
        mix = self.mix
        # demucs is near-conservative; preprocessing (20 Hz HPF) only trims sub-bass
        corr = np.corrcoef(total[:, 0], mix[:, 0])[0, 1]
        self.assertGreater(corr, 0.95)
        err = np.linalg.norm(total - mix) / np.linalg.norm(mix)
        self.assertLess(err, 0.5)

    def test_real_demucs_energy_is_distributed_across_stems(self):
        np = self.np
        energies = {n: float(np.mean(self._read(n)[0] ** 2)) for n in self.stems}
        self.assertGreater(sum(energies.values()), 0)
        self.assertGreater(max(energies.values()), 0)
        self.assertGreater(sum(1 for e in energies.values() if e > 1e-6), 1, energies)

    def test_real_demucs_subset_selection_returns_only_requested(self):
        out = self.sep.separate(str(self.src), stems=["bass"])
        self.assertEqual(set(out), {"bass"})

    def test_real_demucs_workflow_generates_relative_rpp_and_muted_reference_track(self):
        from suno_workflow_config_system import DeviceType, ModelConfig, PathConfig
        from suno_workflow_helper import SunoReaperWorkflow, WorkflowConfig

        wf_dir = Path(self.tmp.name) / "wf_projects"
        wf_dir.mkdir(parents=True, exist_ok=True)
        cfg = WorkflowConfig(
            paths=PathConfig(output_dir=str(wf_dir)),
            models=ModelConfig(demucs_model="htdemucs", device=DeviceType.CPU),
        )
        wf = SunoReaperWorkflow(config=cfg)
        result = wf.process_suno_track(str(self.src), project_name="RealDemucsSession")
        self.assertTrue(result.success, result)
        rpp_path = Path(result.project_file)
        self.assertTrue(rpp_path.is_file(), "generated .rpp must exist")
        rpp_text = rpp_path.read_text(encoding="utf-8")

        # All referenced media files must use relative forward-slash paths and exist on disk
        file_refs = re.findall(r'FILE "([^"]+)"', rpp_text)
        self.assertEqual(len(file_refs), 5, f"expected 4 stems + 1 reference mix, got {file_refs}")
        for ref in file_refs:
            self.assertFalse(os.path.isabs(ref), f"RPP FILE reference must be relative: {ref}")
            self.assertNotIn("\\", ref, f"RPP FILE reference must use forward slashes: {ref}")
            self.assertTrue((rpp_path.parent / ref).is_file(), f"referenced file missing: {ref}")
        for stem in ("vocals.wav", "drums.wav", "bass.wav", "other.wav"):
            self.assertTrue(any(ref.endswith(stem) for ref in file_refs), f"missing {stem} in {file_refs}")
        self.assertIn("original_mix.wav", file_refs)

        # Reference track must be muted with valid REAPER MUTESOLO 1 0 0 syntax
        ref_idx = rpp_text.find("original_mix.wav")
        ref_block_start = rpp_text.rfind("<TRACK", 0, ref_idx)
        ref_block = rpp_text[ref_block_start:ref_idx + 128]
        self.assertIn("MUTESOLO 1 0 0", ref_block, "reference track must have MUTESOLO 1 0 0")

    def test_real_demucs_honest_failure_on_missing_or_corrupt_weights(self):
        import yourmt3_stem_separator as yss

        fail_out = Path(self.tmp.name) / "fail_weights"
        fail_out.mkdir(parents=True, exist_ok=True)
        err_buf = io.StringIO()
        with patch.dict(os.environ, {"HF_HUB_OFFLINE": "1"}), \
             contextlib.redirect_stderr(err_buf):
            with self.assertRaises(SystemExit) as ctx:
                yss.main([str(self.src), "-o", str(fail_out), "--model", "nonexistent_corrupt_weights", "--device", "cpu"])
        self.assertNotEqual(ctx.exception.code, 0, "missing/corrupt model weights must exit non-zero")
        self.assertIn("error:", err_buf.getvalue().lower())
        self.assertEqual(list(fail_out.glob("*.wav")), [], "failed weight load must not write fake stems")

    def test_real_demucs_honest_failure_on_disk_full(self):
        import yourmt3_stem_separator as yss

        full_out = Path(self.tmp.name) / "disk_full"
        full_out.mkdir(parents=True, exist_ok=True)
        err_buf = io.StringIO()
        with patch.object(yss.sf, "write", side_effect=OSError(errno.ENOSPC, "No space left on device")), \
             contextlib.redirect_stderr(err_buf):
            with self.assertRaises(SystemExit) as ctx:
                yss.main([str(self.src), "-o", str(full_out), "--model", "htdemucs", "--device", "cpu", "-s", "bass"])
        self.assertNotEqual(ctx.exception.code, 0, "disk-full ENOSPC must exit non-zero")
        self.assertIn("no space left on device", err_buf.getvalue().lower())
        self.assertEqual(list(full_out.glob("*.wav")), [], "disk-full failure must not leave completed stems")


if __name__ == "__main__":
    unittest.main()
