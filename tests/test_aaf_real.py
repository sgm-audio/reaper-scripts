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


@unittest.skipIf(aaf2 is None and os.environ.get("SGM_ALLOW_MISSING_PYAAF2") == "1",
                 "pyaaf2 not installed (explicitly allowed)")
class RealAAFComprehensiveRoundTrip(unittest.TestCase):
    """Comprehensive real pyaaf2 round-trip: embedded + linked essence, volume/pan envelopes,
    markers, multiple compositions, envelope scaling mode, and clean file-handle closure."""

    @classmethod
    def setUpClass(cls):
        if aaf2 is None:
            raise RuntimeError("pyaaf2 is required for the real AAF tests: pip install pyaaf2")
        from fractions import Fraction
        cls.tmp = tempfile.TemporaryDirectory()
        cls.dir = cls.tmp.name
        cls.emb_wav = os.path.join(cls.dir, "emb_vox.wav")
        cls.emb_pcm = write_sine_wav(cls.emb_wav, 2.0, 330.0)
        cls.linked_wav = os.path.join(cls.dir, "linked_drum.wav")
        cls.linked_pcm = write_sine_wav(cls.linked_wav, 1.0, 220.0)
        cls.aaf_path = os.path.join(cls.dir, "comprehensive.aaf")

        with aaf2.open(cls.aaf_path, "w") as f:
            emb = f.create.MasterMob("LeadVox")
            f.content.mobs.append(emb)
            emb.import_audio_essence(cls.emb_wav, 1)

            # Linked SourceMob with NetworkLocator pointing to another host dir (tests aaf_directory fallback)
            src_mob = f.create.SourceMob("LinkedSrc")
            f.content.mobs.append(src_mob)
            desc = f.create.PCMDescriptor()
            src_mob.descriptor = desc
            desc["SampleRate"].value = RATE
            desc["AudioSamplingRate"].value = RATE
            desc["Channels"].value = 1
            desc["QuantizationBits"].value = 16
            desc["BlockAlign"].value = 2
            desc["AverageBPS"].value = RATE * 2
            desc["Length"].value = RATE
            loc = f.create.NetworkLocator()
            loc["URLString"].value = "file:///remote_workstation/audio/linked_drum.wav"
            desc["Locator"].append(loc)
            s_slot = src_mob.create_sound_slot(RATE)
            s_slot.segment = f.create.SourceClip(media_kind="sound", length=RATE)

            lnk = f.create.MasterMob("LinkedDrum")
            f.content.mobs.append(lnk)
            m_slot = lnk.create_sound_slot(RATE)
            m_slot.segment = src_mob.create_source_clip(slot_id=s_slot.slot_id, start=0, length=RATE)

            # Register interpolation, gain, and pan definitions
            interp = f.create.InterpolationDef(
                aaf2.auid.AUID("5b6c85a4-0ede-11d3-80a9-006008143e6f"), "LinearInterp")
            f.dictionary.register_def(interp)

            gain_op = f.create.OperationDef(
                aaf2.auid.AUID("9d2ea890-0968-11d3-8a38-0050040ef7d2"), "Mono Audio Gain")
            gain_op.media_kind = "sound"
            gain_op["NumberInputs"].value = 1
            f.dictionary.register_def(gain_op)
            amp_pdef = f.create.ParameterDef(
                aaf2.auid.AUID("e4962322-2267-11d3-8a4c-0050040ef7d2"), "Amplitude", "", "Rational")
            f.dictionary.register_def(amp_pdef)

            pan_op = f.create.OperationDef(
                aaf2.auid.AUID("9d2ea893-0968-11d3-8a38-0050040ef7d2"), "Mono Audio Pan")
            pan_op.media_kind = "sound"
            pan_op["NumberInputs"].value = 1
            f.dictionary.register_def(pan_op)
            pan_pdef = f.create.ParameterDef(
                aaf2.auid.AUID("e4962320-2267-11d3-8a4c-0050040ef7d2"), "Pan value", "", "Rational")
            f.dictionary.register_def(pan_pdef)

            # Composition 1: 2 audio tracks (embedded w/ vol+pan envelopes + linked) + markers
            comp1 = f.create.CompositionMob("Mix 1 - Main")
            f.content.mobs.append(comp1)

            slot1 = comp1.create_empty_sequence_slot(RATE, media_kind="sound", slot_id=1)
            slot1.name = "Lead Vox"
            og_gain = f.create.OperationGroup(gain_op, RATE)
            vv_gain = f.create.VaryingValue(amp_pdef, interp)
            vv_gain.add_keyframe(0.0, Fraction(1, 2))
            vv_gain.add_keyframe(1.0, Fraction(1, 1))
            og_gain.parameters.append(vv_gain)

            og_pan = f.create.OperationGroup(pan_op, RATE)
            vv_pan = f.create.VaryingValue(pan_pdef, interp)
            vv_pan.add_keyframe(0.0, Fraction(0, 1))
            vv_pan.add_keyframe(1.0, Fraction(1, 1))
            og_pan.parameters.append(vv_pan)
            og_pan.segments.append(emb.create_source_clip(slot_id=1, start=0, length=RATE))
            og_gain.segments.append(og_pan)
            slot1.segment.components.append(og_gain)
            # Second unautomated clip after 0.5s filler tests neutral-value padding in collect_vol_pan_automation
            slot1.segment.components.append(f.create.Filler("sound", RATE // 2))
            slot1.segment.components.append(emb.create_source_clip(slot_id=1, start=RATE // 2, length=RATE // 2))

            slot2 = comp1.create_empty_sequence_slot(RATE, media_kind="sound", slot_id=2)
            slot2.name = "Linked Drums"
            slot2.segment.components.append(lnk.create_source_clip(slot_id=m_slot.slot_id, start=0, length=RATE))

            ev_slot = f.create.EventMobSlot()
            ev_slot.slot_id = 3
            ev_slot.name = "Markers"
            ev_slot.edit_rate = RATE
            ev_seq = f.create.Sequence("DescriptiveMetadata")
            ev_slot.segment = ev_seq
            m1 = f.create.DescriptiveMarker()
            m1["Position"].value = RATE // 2
            m1["Comment"].value = "Chorus"
            ev_seq.components.append(m1)
            m2 = f.create.DescriptiveMarker()
            m2["Position"].value = RATE * 2
            m2["Comment"].value = "Outro"
            ev_seq.components.append(m2)
            comp1.slots.append(ev_slot)

            # Composition 2: alternate arrangement
            comp2 = f.create.CompositionMob("Mix 2 - Alt")
            f.content.mobs.append(comp2)
            c2_slot = comp2.create_empty_sequence_slot(RATE, media_kind="sound", slot_id=1)
            c2_slot.name = "Alt Vox"
            c2_slot.segment.components.append(emb.create_source_clip(slot_id=1, start=0, length=RATE // 2))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_multiple_compositions_linked_embedded_markers_and_envelopes(self):
        iface = rai.AAFInterface()
        self.assertTrue(iface.open(self.aaf_path))
        self.addCleanup(iface.close)

        self.assertEqual(iface.get_composition_list(), ["Mix 1 - Main", "Mix 2 - Alt"])
        self.assertEqual(iface.get_embedded_essence_count(), 1)

        out_dir = os.path.join(self.dir, "comp_extracted")
        os.makedirs(out_dir, exist_ok=True)
        iface.extract_essence(out_dir, None)

        # Embedded essence extracted bit-exactly, linked essence resolved via aaf_directory fallback
        emb_out = iface.get_essence_file("LeadVox", 1)
        lnk_out = iface.get_essence_file("LinkedDrum", 1)
        self.assertTrue(os.path.isfile(emb_out))
        self.assertEqual(os.path.abspath(lnk_out), os.path.abspath(self.linked_wav))
        frames, rate, ch, width = read_wav_frames(emb_out)
        self.assertEqual((rate, ch, width), (RATE, 1, 2))
        self.assertEqual(frames, self.emb_pcm)

        comp0 = iface.get_composition(0)
        self.assertEqual([t["name"] for t in comp0["tracks"]], ["Lead Vox", "Linked Drums"])
        vox_track = comp0["tracks"][0]
        self.assertEqual(len(vox_track["items"]), 2)
        self.assertAlmostEqual(vox_track["items"][0]["position"], 0.0, places=6)
        self.assertAlmostEqual(vox_track["items"][1]["position"], 1.5, places=6)

        # Volume envelope: 0.5 -> 1.0 on clip 0, plus neutral 1.0 bounds on unautomated clip 1
        vol_pts = vox_track["volume_envelope"]
        self.assertEqual(len(vol_pts), 4)
        self.assertAlmostEqual(vol_pts[0]["time"], 0.0, places=6)
        self.assertAlmostEqual(vol_pts[0]["value"], 0.5, places=6)
        self.assertAlmostEqual(vol_pts[1]["time"], 1.0, places=6)
        self.assertAlmostEqual(vol_pts[1]["value"], 1.0, places=6)
        self.assertAlmostEqual(vol_pts[2]["time"], 1.5, places=6)
        self.assertAlmostEqual(vol_pts[2]["value"], 1.0, places=6)

        # Pan envelope: AAF 0..1 -> REAPER +1..-1
        pan_pts = vox_track["panning_envelope"]
        self.assertEqual(len(pan_pts), 4)
        self.assertAlmostEqual(pan_pts[0]["value"], 1.0, places=6)
        self.assertAlmostEqual(pan_pts[1]["value"], -1.0, places=6)
        self.assertAlmostEqual(pan_pts[2]["value"], 0.0, places=6)

        # Linked track references external linked WAV
        self.assertEqual(os.path.abspath(comp0["tracks"][1]["items"][0]["source"]),
                         os.path.abspath(self.linked_wav))

        # Markers parsed accurately
        self.assertEqual(len(comp0["markers"]), 2)
        self.assertEqual(comp0["markers"][0]["name"], "Chorus")
        self.assertAlmostEqual(comp0["markers"][0]["position"], 0.5, places=6)
        self.assertEqual(comp0["markers"][1]["name"], "Outro")
        self.assertAlmostEqual(comp0["markers"][1]["position"], 2.0, places=6)

        # Second composition and out-of-range guard
        comp1 = iface.get_composition(1)
        self.assertEqual(len(comp1["tracks"]), 1)
        self.assertEqual(comp1["tracks"][0]["name"], "Alt Vox")
        self.assertAlmostEqual(comp1["tracks"][0]["items"][0]["duration"], 0.5, places=6)
        self.assertEqual(iface.get_composition(99), {"tracks": [], "markers": []})

    def test_envelope_scaling_mode_queries_host_and_scales_real_aaf_points(self):
        from unittest.mock import patch

        iface = rai.AAFInterface()
        self.assertTrue(iface.open(self.aaf_path))
        self.addCleanup(iface.close)
        out_dir = os.path.join(self.dir, "scale_extracted")
        os.makedirs(out_dir, exist_ok=True)
        iface.extract_essence(out_dir, None)
        comp0 = iface.get_composition(0)

        for expected_mode in (0, 1):
            scaled_calls = []
            inserted_vol = []
            inserted_pan = []
            tracks = []
            vol_env = {"kind": "vol"}
            pan_env = {"kind": "pan"}
            mocks = {
                "RPR_GetCursorPosition": lambda: 0.0,
                "RPR_SetEditCurPos": lambda *_: None,
                "RPR_Undo_BeginBlock": lambda: None,
                "RPR_Undo_EndBlock": lambda *_: None,
                "RPR_PreventUIRefresh": lambda *_: None,
                "RPR_UpdateArrange": lambda: None,
                "RPR_GetNumTracks": lambda: len(tracks),
                "RPR_InsertTrackAtIndex": lambda idx, _: tracks.insert(idx, {"items": []}),
                "RPR_GetTrack": lambda _, idx: tracks[idx],
                "RPR_GetSetMediaTrackInfo_String": lambda tr, _, val, s: (True, val),
                "RPR_AddMediaItemToTrack": lambda tr: {"track": tr, "take": {"ok": True}},
                "RPR_SelectAllMediaItems": lambda *_: None,
                "RPR_SetMediaItemSelected": lambda *_: None,
                "RPR_InsertMedia": lambda *_: None,
                "RPR_GetActiveTake": lambda item: item["take"],
                "RPR_SetMediaItemInfo_Value": lambda *_: None,
                "RPR_SetMediaItemTakeInfo_Value": lambda *_: None,
                "RPR_GetTrackEnvelopeByName": lambda _, name: vol_env if name == "Volume" else pan_env,
                "RPR_GetEnvelopeScalingMode": lambda _, m=expected_mode: m,
                "RPR_ScaleToEnvelopeMode": lambda mode, val: (scaled_calls.append((mode, val)) or val),
                "RPR_InsertEnvelopePoint": lambda env, t, v, *_: (
                    inserted_vol.append((t, v)) if env is vol_env else inserted_pan.append((t, v))
                ),
                "RPR_Envelope_SortPoints": lambda *_: None,
                "RPR_AddProjectMarker2": lambda *_: None,
            }
            with patch.dict(rai.__dict__, mocks):
                rai.ReaperInterface().build_project(comp0)

            self.assertEqual(len(tracks), 2)
            self.assertEqual(len(scaled_calls), 4)
            self.assertTrue(all(mode == expected_mode for mode, _ in scaled_calls),
                            f"must query and pass scaling mode {expected_mode}, got {scaled_calls}")
            self.assertAlmostEqual(inserted_vol[0][1], 0.5, places=6)
            self.assertAlmostEqual(inserted_pan[0][1], 1.0, places=6)
            self.assertAlmostEqual(inserted_pan[1][1], -1.0, places=6)

    def test_clean_file_handle_closure_and_reopen(self):
        iface = rai.AAFInterface()
        self.assertTrue(iface.open(self.aaf_path))
        first_handle = iface.aaf.f
        self.assertFalse(first_handle.closed)
        # Re-opening must close the prior handle before opening the new one
        self.assertTrue(iface.open(self.aaf_path))
        self.assertTrue(first_handle.closed, "re-open must close previous AAF handle")
        second_handle = iface.aaf.f
        iface.close()
        self.assertIsNone(iface.aaf)
        self.assertTrue(second_handle.closed, "close() must close underlying file handle")
        # Double close is idempotent
        iface.close()
        self.assertIsNone(iface.aaf)


class ReaperBridgeCompatibilityTests(unittest.TestCase):
    """Verify RPR_* global injection, reaper_python fallback, missing media, corrupt AAF, and non-empty cancel/confirm."""

    def test_rpr_resolution_supports_globals_reaper_python_and_main_fallback(self):
        import types
        from unittest.mock import patch

        global_fn = lambda: "from-global"  # noqa: E731
        mod_fn = lambda: "from-reaper-python"  # noqa: E731
        main_fn = lambda: "from-main"  # noqa: E731

        fake_rp = types.SimpleNamespace(
            RPR_TestFallback=mod_fn,
            RPR_ValidatePtr=lambda ptr, typ: ptr == 0x1234 and typ == "MediaItem*",
        )
        fake_main = types.SimpleNamespace(RPR_TestMainOnly=main_fn)

        # 1) Global injection path takes precedence
        with patch.dict(rai.__dict__, {"RPR_TestFallback": global_fn, "_reaper_python": fake_rp}):
            self.assertEqual(rai._rpr("RPR_TestFallback")(), "from-global")

        # 2) reaper_python import fallback path when globals lack RPR_*
        with patch.dict(rai.__dict__, {"_reaper_python": fake_rp}), \
             patch.dict(sys.modules, {"__main__": fake_main}):
            self.assertNotIn("RPR_TestFallback", rai.__dict__)
            self.assertEqual(rai._rpr("RPR_TestFallback")(), "from-reaper-python")
            self.assertTrue(rai._is_valid_ptr("(MediaItem*)0x1234", "MediaItem*"))
            self.assertFalse(rai._is_valid_ptr("(MediaItem*)0x00000000", "MediaItem*"))
            self.assertEqual(rai._rpr("RPR_TestMainOnly")(), "from-main")
            with self.assertRaises(NameError):
                rai._rpr("RPR_DoesNotExistAnywhere")

    def test_create_item_skips_missing_media_without_mutating_track(self):
        from unittest.mock import patch

        added = []
        with patch.dict(rai.__dict__, {"RPR_AddMediaItemToTrack": lambda tr: added.append(tr)}):
            res = rai.ReaperInterface().create_item({"tr": 1}, "/nonexistent/missing.wav", 0.0, 0.0, 1.0)
        self.assertIsNone(res)
        self.assertEqual(added, [], "missing media must skip before calling AddMediaItemToTrack")

    def test_import_aaf_nonempty_project_cancel_vs_confirm(self):
        from unittest.mock import patch

        with tempfile.TemporaryDirectory() as td:
            for answer, expect_built in ((2, False), (1, True)):
                built = []

                class StubAAF:
                    def open(self, _): return True
                    def close(self): pass
                    def get_aaf_metadata(self): return {}
                    def get_embedded_essence_count(self): return 0
                    def get_composition_list(self): return ["Mix 1"]
                    def extract_essence(self, *_, **__): pass
                    def get_composition(self, _): return {"tracks": [{"name": "T", "items": []}], "markers": []}

                mocks = {
                    "have_reaper": True,
                    "aaf2": object(),
                    "RPR_GetUserFileNameForRead": lambda *_: (True, "session.aaf", "", ""),
                    "RPR_GetProjectPath": lambda *_: (td, 512),
                    "RPR_GetNumTracks": lambda: 2,
                    "RPR_ShowConsoleMsg": lambda *_: None,
                    "RPR_MB": lambda *_: answer,
                }
                with patch.dict(rai.__dict__, mocks), \
                     patch.object(rai, "AAFInterface", return_value=StubAAF()), \
                     patch.object(rai.ReaperInterface, "build_project", side_effect=lambda d: built.append(d)):
                    rai.import_aaf()
                self.assertEqual(bool(built), expect_built, f"RPR_MB={answer} expect_built={expect_built}")


if __name__ == "__main__":
    unittest.main()
