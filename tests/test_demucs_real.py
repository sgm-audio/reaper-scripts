"""Real Demucs execution test (no mocks).

Runs the actual htdemucs model on CPU. Gated by SGM_REAL_DEMUCS=1 so the
lightweight suites stay fast; the dedicated CI job sets it and a missing
backend then FAILS instead of skipping.
"""
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

ENABLED = os.environ.get("SGM_REAL_DEMUCS") == "1"
SR = 44100
SECONDS = 8


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
        print(f"HOST torch={torch.__version__} demucs={getattr(demucs, '__version__', '?')}")
        cls.sep = YourMT3StemSeparator(
            output_dir=str(Path(cls.tmp.name) / "out"), device="cpu", timeout_seconds=1500)
        print("HOST model container:", cls.sep.download_model("htdemucs"))
        cls.stems = cls.sep.separate(str(cls.src))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def _read(self, name):
        data, sr = self.sf.read(self.stems[name], always_2d=True, dtype="float32")
        return data, sr

    def test_real_demucs_returns_exactly_four_existing_stems(self):
        self.assertEqual(set(self.stems), {"vocals", "drums", "bass", "other"})
        for path in self.stems.values():
            self.assertTrue(Path(path).is_file())

    def test_real_demucs_stems_preserve_rate_length_and_channels(self):
        for name in self.stems:
            data, sr = self._read(name)
            self.assertEqual(sr, SR, name)
            self.assertEqual(data.shape, self.mix.shape, name)
            self.assertTrue(self.np.isfinite(data).all(), name)

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


if __name__ == "__main__":
    unittest.main()
