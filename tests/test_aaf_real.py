"""Real pyaaf2 round-trip tests for reaper_ai_integration.AAFInterface.

Unlike the mock-based regressions these tests *author a genuine AAF file with pyaaf2*
(master mob + embedded PCM essence + composition mob), then drive AAFInterface over it
and assert on the exact timeline numbers and the extracted audio bytes. They fail if
pyaaf2 is not installed (it is a hard CI dependency: see requirements.txt) unless
SGM_ALLOW_MISSING_PYAAF2=1 is set for local lightweight runs.
"""
import math
import os
import struct
import sys
import tempfile
import unittest
import wave

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    import aaf2
except ImportError:  # pragma: no cover - exercised only without the dependency
    aaf2 = None

import reaper_ai_integration as rai

RATE = 48000


def write_sine_wav(path, seconds, freq=440.0, amp=0.5):
    n = int(RATE * seconds)
    frames = b"".join(
        struct.pack("<h", int(amp * 32767 * math.sin(2 * math.pi * freq * i / RATE)))
        for i in range(n)
    )
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    return frames


def read_wav_frames(path):
    with wave.open(path, "rb") as w:
        return w.readframes(w.getnframes()), w.getframerate(), w.getnchannels(), w.getsampwidth()


@unittest.skipIf(aaf2 is None and os.environ.get("SGM_ALLOW_MISSING_PYAAF2") == "1",
                 "pyaaf2 not installed (explicitly allowed)")
class RealAAFRoundTrip(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if aaf2 is None:
            raise RuntimeError("pyaaf2 is required for the real AAF tests: pip install pyaaf2")
        cls.tmp = tempfile.TemporaryDirectory()
        cls.dir = cls.tmp.name
        cls.wav_a = os.path.join(cls.dir, "clipA.wav")
        cls.pcm_a = write_sine_wav(cls.wav_a, 2.0, 440.0)
        cls.wav_b = os.path.join(cls.dir, "clipB.wav")
        cls.pcm_b = write_sine_wav(cls.wav_b, 1.0, 880.0)
        cls.aaf_path = os.path.join(cls.dir, "session.aaf")
        cls._author(cls.aaf_path)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    @classmethod
    def _author(cls, path):
        with aaf2.open(path, "w") as f:
            masters = []
            for name, wav in (("ClipA", cls.wav_a), ("ClipB", cls.wav_b)):
                master = f.create.MasterMob(name)
                f.content.mobs.append(master)
                master.import_audio_essence(wav, 1)
                masters.append(master)

            comp = f.create.CompositionMob("Mix 1")
            f.content.mobs.append(comp)
            slot = comp.create_empty_sequence_slot(RATE, media_kind="sound", slot_id=1)
            slot.name = "Gtr DI"
            seq = slot.segment
            # [ClipA 0.0-1.0s] [filler 0.5s] [ClipB from 0.25s, 0.5s long]
            seq.components.append(masters[0].create_source_clip(slot_id=1, start=0, length=RATE))
            seq.components.append(f.create.Filler("sound", RATE // 2))
            seq.components.append(masters[1].create_source_clip(slot_id=1, start=RATE // 4, length=RATE // 2))

    def setUp(self):
        self.iface = rai.AAFInterface()
        self.assertTrue(self.iface.open(self.aaf_path), "AAFInterface.open on a real AAF")
        self.addCleanup(self.iface.close)

    def test_open_lists_the_authored_composition(self):
        self.assertEqual(self.iface.get_composition_list(), ["Mix 1"])

    def test_open_rejects_garbage_file_without_raising(self):
        bad = os.path.join(self.dir, "garbage.aaf")
        with open(bad, "wb") as fh:
            fh.write(b"not an aaf")
        other = rai.AAFInterface()
        self.assertFalse(other.open(bad))

    def test_embedded_essence_count_matches_authored_clips(self):
        self.assertEqual(self.iface.get_embedded_essence_count(), 2)

    def test_extracted_essence_is_bit_exact_pcm(self):
        out = os.path.join(self.dir, "extracted")
        os.makedirs(out, exist_ok=True)
        messages = []
        self.iface.extract_essence(out, messages.append)
        self.assertEqual(len(messages), 2, "progress callback fired per embedded essence")
        got_a = self.iface.get_essence_file("ClipA", 1)
        got_b = self.iface.get_essence_file("ClipB", 1)
        for path in (got_a, got_b):
            self.assertTrue(os.path.isfile(path), path)
        frames_a, rate_a, ch_a, width_a = read_wav_frames(got_a)
        frames_b, rate_b, ch_b, width_b = read_wav_frames(got_b)
        self.assertEqual((rate_a, ch_a, width_a), (RATE, 1, 2))
        self.assertEqual((rate_b, ch_b, width_b), (RATE, 1, 2))
        self.assertEqual(frames_a, self.pcm_a, "ClipA audio survives AAF embed/extract bit-exactly")
        self.assertEqual(frames_b, self.pcm_b, "ClipB audio survives AAF embed/extract bit-exactly")

    def test_composition_timeline_numbers_are_exact(self):
        out = os.path.join(self.dir, "extracted2")
        os.makedirs(out, exist_ok=True)
        self.iface.extract_essence(out, None)
        data = self.iface.get_composition(0)
        self.assertEqual(data["markers"], [])
        self.assertEqual(len(data["tracks"]), 1)
        track = data["tracks"][0]
        self.assertEqual(track["name"], "Gtr DI")
        first, second = track["items"]
        self.assertAlmostEqual(first["position"], 0.0, places=9)
        self.assertAlmostEqual(first["duration"], 1.0, places=9)
        self.assertAlmostEqual(first["offset"], 0.0, places=9)
        self.assertAlmostEqual(second["position"], 1.5, places=9, msg="filler gap preserved")
        self.assertAlmostEqual(second["duration"], 0.5, places=9)
        self.assertAlmostEqual(second["offset"], 0.25, places=9)
        self.assertTrue(first["source"].endswith(".wav") and os.path.isfile(first["source"]))
        self.assertTrue(second["source"].endswith(".wav") and os.path.isfile(second["source"]))
        self.assertNotEqual(first["source"], second["source"])

    def test_metadata_identifies_pyaaf2_as_writer(self):
        meta = self.iface.get_aaf_metadata()
        self.assertIn("pyaaf", meta.get("product", "").lower())

    def test_missing_essence_is_reported_not_crashed(self):
        # No extract_essence() call: sources are unresolved and must come back empty.
        data = self.iface.get_composition(0)
        items = data["tracks"][0]["items"]
        self.assertEqual([i["source"] for i in items], ["", ""])


if __name__ == "__main__":
    unittest.main()
