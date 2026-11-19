"""Regression tests for defects found during the repository audit."""

import asyncio
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import wave

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from extract_reaper_uuids import parse_reaper_ini
from suno_workflow_config_system import PathConfig, WorkflowConfig as BaseConfig
from suno_workflow_helper import SunoReaperWorkflow
from suno_workflow_performance_utils import (
    AsyncProcessor,
    PerformanceMonitor,
    get_optimal_chunk_size,
    monitor_performance,
    performance_monitor,
)


def load_plugin_module():
    name = "plugin_compatibility_system"
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(
        name, ROOT / "plugin-compatibility-system.py"
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def write_wav(path, frames=441):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(44100)
        audio.writeframes(b"\0\0" * frames)


class FakeSeparator:
    def __init__(self, output_dir):
        self.output_dir = output_dir

    def separate(self, _):
        paths = {}
        for name in ("vocals", "drums", "bass", "other"):
            path = Path(self.output_dir) / f"{name}.wav"
            write_wav(path)
            paths[name] = str(path)
        return paths


def keyword_sum(value, *, offset=0):
    return value + offset


class SunoWorkflowRegressions(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.input = self.root / "input.wav"
        write_wav(self.input)
        self.output = self.root / "projects"
        config = BaseConfig(paths=PathConfig(output_dir=str(self.output)))
        self.workflow = SunoReaperWorkflow(config=config)

    def tearDown(self):
        self.temp.cleanup()

    def test_auto_import_writes_real_relative_media_and_preserves_config(self):
        self.workflow.config.generate_instructions = True
        with patch("suno_workflow_helper.YourMT3StemSeparator", FakeSeparator):
            result = self.workflow.process_suno_track(str(self.input), "Song")
        self.assertTrue(result.success, result.error_message)
        self.assertEqual(Path(result.project_dir), self.output / "Song")
        self.assertEqual(Path(result.original_file).suffix, ".wav")
        project = Path(result.project_file).read_text(encoding="utf-8")
        self.assertEqual(project.count("<ITEM"), 5)
        self.assertIn('FILE "stems/vocals.wav"', project)
        self.assertIn('FILE "original_mix.wav"', project)
        self.assertNotIn(str(self.root).replace("\\", "/"), project)
        instructions = Path(result.instructions_file).read_text(encoding="utf-8")
        self.assertIn("already placed", instructions)

    def test_manual_mode_and_nonempty_directory_protection(self):
        with patch("suno_workflow_helper.YourMT3StemSeparator", FakeSeparator):
            result = self.workflow.process_suno_track(
                str(self.input), "Manual", auto_import=False
            )
            rerun = self.workflow.process_suno_track(str(self.input), "Manual")
        self.assertTrue(result.success, result.error_message)
        self.assertNotIn("<ITEM", Path(result.project_file).read_text(encoding="utf-8"))
        self.assertFalse(rerun.success)
        self.assertIn("not empty", rerun.error_message)

    def test_project_name_cannot_escape_output_root(self):
        result = self.workflow.process_suno_track(str(self.input), "../outside")
        self.assertFalse(result.success)
        self.assertIn("not a path", result.error_message)

    def test_cli_returns_nonzero_for_returned_workflow_failure(self):
        import suno_workflow_helper
        old_cwd = os.getcwd()
        os.chdir(self.root)
        try:
            with patch.object(
                sys, "argv", ["suno_workflow_helper.py", str(self.root / "missing.wav")]
            ):
                self.assertEqual(suno_workflow_helper.main(), 1)
        finally:
            os.chdir(old_cwd)

    def test_suno_rpp_uses_valid_mutesolo_syntax(self):
        with patch("suno_workflow_helper.YourMT3StemSeparator", FakeSeparator):
            result = self.workflow.process_suno_track(str(self.input), "MuteCheck")
        self.assertTrue(result.success, result.error_message)
        project = Path(result.project_file).read_text(encoding="utf-8")
        self.assertIn("MUTESOLO 1 0 0", project)
        self.assertNotIn("B_MUTE", project)

    def test_rpp_item_placement_duration_and_path_portability(self):
        # Verify ITEM structure, exact duration calculation, POSITION 0, and portable / paths
        frames_count = 88200  # exactly 2.0 seconds at 44100
        test_wav = self.root / "two_seconds.wav"
        write_wav(test_wav, frames=frames_count)

        class TwoSecondSeparator:
            def __init__(self, output_dir):
                self.output_dir = output_dir

            def separate(self, _):
                paths = {}
                for name in ("vocals", "drums", "bass", "other"):
                    path = Path(self.output_dir) / f"{name}.wav"
                    write_wav(path, frames=frames_count)
                    paths[name] = str(path)
                return paths

        with patch("suno_workflow_helper.YourMT3StemSeparator", TwoSecondSeparator):
            result = self.workflow.process_suno_track(str(test_wav), "PrecisionCheck")
        self.assertTrue(result.success, result.error_message)

        content = Path(result.project_file).read_text(encoding="utf-8")
        lines = [line.strip() for line in content.splitlines()]

        # Assert no backslashes in any FILE statement
        file_lines = [l for l in lines if l.startswith("FILE ")]
        self.assertEqual(len(file_lines), 5)  # 4 stems + 1 original
        for fl in file_lines:
            self.assertNotIn("\\", fl, f"Non-portable backslash in RPP FILE line: {fl}")
            self.assertIn('"', fl)

        # Assert position 0 and duration is 2.000000000
        item_positions = [l for l in lines if l.startswith("POSITION ")]
        self.assertEqual(len(item_positions), 5)
        for pos in item_positions:
            self.assertEqual(pos, "POSITION 0")

        item_lengths = [l for l in lines if l.startswith("LENGTH ")]
        self.assertEqual(len(item_lengths), 5)
        for length in item_lengths:
            val = float(length.split()[1])
            self.assertAlmostEqual(val, 2.0, places=4)

        # Ensure no absolute leak
        self.assertNotIn(str(self.root).replace("\\", "/"), content)

    def test_workflow_fails_cleanly_on_unwritable_directory(self):
        # Simulating unwriteable destination folder
        unwritable_root = self.root / "locked_output"
        unwritable_root.mkdir()
        unwritable_root.chmod(0o444)
        try:
            locked_config = BaseConfig(paths=PathConfig(output_dir=str(unwritable_root)))
            wf = SunoReaperWorkflow(config=locked_config)
            with patch("suno_workflow_helper.YourMT3StemSeparator", FakeSeparator):
                result = wf.process_suno_track(str(self.input), "Locked")
            self.assertFalse(result.success)
            self.assertIn("Permission denied", result.error_message)
        finally:
            unwritable_root.chmod(0o777)

    def test_ogg_source_type_and_windows_invalid_project_name(self):
        ogg_input = self.root / "track.ogg"
        ogg_input.write_bytes(b"OggS")
        with patch("suno_workflow_helper.YourMT3StemSeparator", FakeSeparator):
            ok = self.workflow.process_suno_track(str(ogg_input), "OggSong")
        self.assertTrue(ok.success, ok.error_message)
        project = Path(ok.project_file).read_text(encoding="utf-8")
        self.assertIn("<SOURCE VORBIS", project)

        result = self.workflow.process_suno_track(str(self.input), "Bad:Name?")
        self.assertFalse(result.success)
        self.assertIn("folder name", result.error_message.lower())

    def test_separation_failure_cleans_up_empty_dir_for_retry(self):
        class FailingSeparator:
            def __init__(self, output_dir, **_kwargs):
                self.output_dir = output_dir

            def separate(self, _):
                raise RuntimeError("backend unavailable")

        with patch("suno_workflow_helper.YourMT3StemSeparator", FailingSeparator):
            first = self.workflow.process_suno_track(str(self.input), "RetrySong")
        self.assertFalse(first.success)
        self.assertFalse((self.output / "RetrySong").exists())

        with patch("suno_workflow_helper.YourMT3StemSeparator", FakeSeparator):
            second = self.workflow.process_suno_track(str(self.input), "RetrySong")
        self.assertTrue(second.success, second.error_message)

    def test_separator_receives_configured_model_and_device(self):
        captured = {}

        class CapturingSeparator(FakeSeparator):
            def __init__(self, output_dir, model_name=None, device=None):
                super().__init__(output_dir)
                captured["model_name"] = model_name
                captured["device"] = device

        self.workflow.config.models.demucs_model = "htdemucs_ft"
        with patch("suno_workflow_helper.YourMT3StemSeparator", CapturingSeparator):
            result = self.workflow.process_suno_track(str(self.input), "ModelPass")
        self.assertTrue(result.success, result.error_message)
        self.assertEqual(captured["model_name"], "htdemucs_ft")
        self.assertEqual(captured["device"], "auto")

    def test_cli_does_not_mutate_os_environ(self):
        import suno_workflow_helper

        before = os.environ.get("SUNO_OUTPUT_DIR")
        with patch("suno_workflow_helper.YourMT3StemSeparator", FakeSeparator):
            rc = suno_workflow_helper.main(
                [str(self.input), "--output-dir", str(self.output), "-n", "CliClean"]
            )
        self.assertEqual(rc, 0)
        self.assertEqual(os.environ.get("SUNO_OUTPUT_DIR"), before)


class PerformanceRegressions(unittest.TestCase):
    def test_executor_keyword_arguments(self):
        async def run():
            with AsyncProcessor(max_workers=2) as processor:
                self.assertEqual(
                    await processor.run_io_bound(keyword_sum, 2, offset=3), 5
                )
                self.assertEqual(
                    await processor.run_cpu_bound(keyword_sum, 4, offset=5), 9
                )
        asyncio.run(run())

    def test_lazy_executors_and_max_workers_zero_rejected(self):
        with self.assertRaises(ValueError):
            AsyncProcessor(max_workers=0)
        processor = AsyncProcessor(max_workers=2)
        self.assertIsNone(processor._thread_executor)
        self.assertIsNone(processor._process_executor)
        processor.close()

    def test_wait_for_memory_timeout_and_nonfinite_chunk_size(self):
        from suno_workflow_performance_utils import MemoryManager

        manager = MemoryManager(max_memory_mb=1.0)
        with patch.object(manager, "get_memory_usage", return_value=500.0):
            ok = asyncio.run(manager.wait_for_memory(target_mb=1.0, timeout=0.02))
        self.assertFalse(ok)

        for bad in (float("nan"), float("inf"), -1.0):
            with self.assertRaises(ValueError):
                get_optimal_chunk_size(bad, 10.0)
        with self.assertRaises(ValueError):
            get_optimal_chunk_size(10.0, float("nan"))

    def test_monitor_ids_and_failed_metrics(self):
        monitor = PerformanceMonitor()
        first = monitor.start_monitoring("same")
        second = monitor.start_monitoring("same")
        self.assertNotEqual(first, second)
        monitor.stop_monitoring(first)
        monitor.stop_monitoring(second)
        self.assertEqual(len(monitor.get_metrics("same")), 2)

        @monitor_performance("failure_test")
        def fail():
            raise RuntimeError("expected")

        with self.assertRaisesRegex(RuntimeError, "expected"):
            fail()
        metric = performance_monitor.get_metrics("failure_test")[-1]
        self.assertEqual(metric.operations_failed, 1)
        self.assertIsNotNone(metric.duration)

    def test_chunk_count_covers_partial_chunk(self):
        self.assertEqual(get_optimal_chunk_size(25, 10), 4)
        with self.assertRaises(ValueError):
            get_optimal_chunk_size(10, 0)


class PluginAndCacheRegressions(unittest.TestCase):
    def test_scanner_detects_files_bundles_and_jsfx(self):
        module = load_plugin_module()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "Bundle.VST3" / "Contents").mkdir(parents=True)
            (root / "Unit.component").mkdir()
            (root / "Filter.lv2").mkdir()
            (root / "Old.VST").mkdir()
            (root / "Bundle.clap" / "Contents").mkdir(parents=True)
            (root / "Effect.CLAP").write_text("binary")
            (root / "Legacy.DLL").write_text("binary")
            effects = root / "Effects"
            effects.mkdir()
            (effects / "utility").write_text("desc:Utility")
            (effects / ".DS_Store").write_text("hidden")
            (effects / "include.jsfx-inc").write_text("include")
            scanner = module.PluginScanner()
            scanner.plugin_paths = [str(root), str(effects)]
            found = scanner.scan_plugins()
            self.assertEqual(len(found["vst3"]), 1)
            self.assertEqual(len(found["au"]), 1)
            self.assertEqual(len(found["lv2"]), 1)
            self.assertEqual(len(found["vst2"]), 2)  # .vst bundle and .dll
            self.assertEqual(len(found["clap"]), 2)  # .clap bundle and .CLAP file
            self.assertEqual([Path(p).name for p in found["js"]], ["utility"])

    def test_database_init_and_json_round_trip_are_real(self):
        module = load_plugin_module()
        with tempfile.TemporaryDirectory() as temp_dir:
            first_path = Path(temp_dir) / "first.db"
            second_path = Path(temp_dir) / "second.db"
            database = module.PluginDatabase(str(first_path))
            expected = database.get_alternatives("rea_eq")
            module.PluginDatabase(str(first_path))
            self.assertEqual(database.get_alternatives("rea_eq"), expected)
            # Verify LIKE wildcard escaping does not match everything for "%"
            self.assertIsNone(database.find_plugin("%"))

            export = Path(temp_dir) / "plugins.json"
            database.export_json(str(export))
            payload = json.loads(export.read_text(encoding="utf-8"))
            self.assertTrue(payload["plugins"])
            # Customize quality_match and set a null last_updated to verify preservation & null guard
            payload["plugins"][0]["last_updated"] = None
            payload["alternatives"][0]["quality_match"] = 0.95
            payload["alternatives"][0]["notes"] = "Exact match"
            export.write_text(json.dumps(payload), encoding="utf-8")

            imported = module.PluginDatabase(str(second_path))
            imported.import_json(str(export))
            self.assertEqual(imported.find_plugin("ReaEQ").manufacturer, "Cockos")
            alt_map = dict(imported.get_alternatives(payload["alternatives"][0]["plugin_id"]))
            self.assertAlmostEqual(
                alt_map[payload["alternatives"][0]["alternative_id"]], 0.95
            )

            template = Path(temp_dir) / "fixture.rpp"
            template.write_text(
                '<VST "VST3: Pro-Q 3 (FabFilter)" plugin.vst3 0 ""\n'
                '<VST "VST3i: Vital (Vital Audio)" vital.vst3 0 ""\n'
                '<CLAP "CLAP: Secret Sauce (Vendor)" secret.clap 0 ""\n'
                '<LV2 "LV2i: Calf Synth (Calf)" uri 0 ""\n'
                '<DX "DXi: Legacy Synth (Vendor)" guid 0 ""\n'
                '<JS utility/volume ""\n',
                encoding="utf-8",
            )
            checker = module.CompatibilityChecker.__new__(module.CompatibilityChecker)
            self.assertEqual(
                checker._parse_template_plugins(str(template)),
                ["Calf Synth", "Legacy Synth", "Pro-Q 3", "Secret Sauce", "Vital", "utility/volume"],
            )
            self.assertTrue(
                checker._is_installed("Secret Sauce", ["Secret Sauce.vst3"])
            )
            self.assertTrue(
                checker._is_installed("VST3i: Vital (Vital Audio)", ["Vital.vst3"])
            )

            # Unreadable template reports error and 0 score
            unreadable = Path(temp_dir) / "locked.rpp"
            unreadable.write_text('<VST "VST3: Pro-Q 3" p.vst3 0 ""\n', encoding="utf-8")
            unreadable.chmod(0o000)
            try:
                checker.db = imported
                checker.scanner = module.PluginScanner()
                report = checker.check_template_compatibility(str(unreadable))
                self.assertEqual(report["score"], 0.0)
                self.assertTrue(report["errors"])
            finally:
                unreadable.chmod(0o644)

    def test_reaper_cache_parser_handles_quotes_and_commas(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            cache = Path(temp_dir) / "reaper-vstplugins64.ini"
            cache.write_text(
                '[vstcache]\n'
                '; comment line\n'
                'reaeq.dll=0070CFBF0558D301,1919247729,ReaEQ (Cockos)\n'
                'Plugin.vst3=0070CFBF0558D301,12345,"Delay, Wide (Vendor)!!!VST3i"\n',
                encoding="utf-8",
            )
            parsed = parse_reaper_ini(str(cache))
            self.assertIn("ReaEQ (Cockos)", parsed)
            self.assertEqual(parsed["ReaEQ (Cockos)"]["uid"], "1919247729")
            self.assertIn("Delay, Wide (Vendor)", parsed)
            self.assertEqual(parsed["Delay, Wide (Vendor)"]["uid"], "12345")
            self.assertEqual(parsed["Delay, Wide (Vendor)"]["type"], "VST3")

    def test_reaper_ai_integration_null_ptr_and_automation_fixes(self):
        import reaper_ai_integration as rai

        self.assertFalse(rai._is_valid_ptr(None))
        self.assertFalse(rai._is_valid_ptr(""))
        self.assertFalse(rai._is_valid_ptr("(MediaEnvelope*)0x0000000000000000"))
        self.assertFalse(rai._is_valid_ptr("0x00000000"))
        self.assertTrue(rai._is_valid_ptr("(MediaEnvelope*)0x00007F1234567890"))

        aaf = rai.AAFInterface()
        # Leading unautomated item should get neutral pan 0.0 (not 1.0)
        track = {
            "name": "PanTrack",
            "items": [
                {"position": 0.0, "duration": 2.0},
                {
                    "position": 2.0,
                    "duration": 2.0,
                    "panning_envelope": [{"time": 0.0, "value": -0.5}, {"time": 2.0, "value": 0.5}],
                },
            ],
        }
        result = aaf.collect_vol_pan_automation(track)
        self.assertEqual(result["panning_envelope"][0], {"time": 0.0, "value": 0.0})
        self.assertEqual(result["panning_envelope"][1], {"time": 2.0, "value": 0.0})
        self.assertEqual(result["panning_envelope"][2], {"time": 2.0, "value": -0.5})

        # Existing track-level panning_envelope must not be clobbered
        existing_env = [{"time": 0.0, "value": 0.25}]
        track_with_env = {
            "name": "ExistingPan",
            "panning_envelope": list(existing_env),
            "items": [
                {
                    "position": 0.0,
                    "duration": 1.0,
                    "panning_envelope": [{"time": 0.0, "value": -1.0}],
                }
            ],
        }
        preserved = aaf.collect_vol_pan_automation(track_with_env)
        self.assertEqual(preserved["panning_envelope"], existing_env)

        # EOFError in CLI composition prompt must return None cleanly
        with patch("builtins.input", side_effect=EOFError):
            self.assertIsNone(rai.UserInteraction.get_composition_cli(["A", "B"]))

    def test_batch_processor_disambiguates_duplicate_stems_recursively(self):
        from batch_process_suno import BatchProcessor

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            in_root = root / "inputs"
            out_root = root / "out"
            write_wav(in_root / "album1" / "song.wav")
            write_wav(in_root / "album2" / "song.wav")

            with patch("suno_workflow_helper.YourMT3StemSeparator", FakeSeparator):
                processor = BatchProcessor(output_dir=str(out_root))
                results = processor.process_directory(str(in_root), recursive=True)

            self.assertEqual(len(results), 2)
            self.assertTrue(all(r["success"] for r in results), results)
            self.assertNotEqual(results[0]["project_dir"], results[1]["project_dir"])

    def test_semas_prevents_double_execution_and_preserves_empty_operations(self):
        from SEMAS.api import SEMASAPI
        from SEMAS.core.data_structures import JobStatus, SEMASJob
        from SEMAS.core.orchestrator import SEMASOrchestrator

        calls = []

        def counting_processor(job):
            calls.append(job.id)
            return {"ok": True}

        orchestrator = SEMASOrchestrator(processor=counting_processor)
        job = SEMASJob(input_file="dummy.wav", operations=["analyze"])
        orchestrator.submit_job(job, auto_process=False)
        orchestrator.process_job(job.id)
        orchestrator.process_job(job.id)
        self.assertEqual(len(calls), 1)
        self.assertEqual(job.status, JobStatus.COMPLETED)

        api = SEMASAPI()
        submitted = api.submit("dummy.wav", operations=[], process=False)
        self.assertEqual(submitted["operations"], [])

    def test_yourmt3_timeout_validation_and_edge_window_preservation(self):
        import numpy as np
        from yourmt3_stem_separator import YourMT3StemSeparator

        with tempfile.TemporaryDirectory() as temp_dir:
            bad_dir = Path(temp_dir) / "should_not_exist"
            with self.assertRaises(ValueError):
                YourMT3StemSeparator(output_dir=str(bad_dir), timeout_seconds=0)
            self.assertFalse(bad_dir.exists())

            sep = YourMT3StemSeparator(output_dir=str(Path(temp_dir) / "ok"))
            # Low-frequency cosine starting at 1.0 at sample 0 should not collapse to 0
            sr = 44100
            t = np.arange(4096, dtype=np.float32) / sr
            tone = np.cos(2 * np.pi * 200.0 * t).astype(np.float32)
            stereo = np.vstack([tone, tone])
            cleaned = sep._reduce_spectral_artifacts(stereo, sr)
            self.assertEqual(cleaned.shape, stereo.shape)
            self.assertGreater(float(cleaned[0, 0]), 0.9)

    def test_reaper_interface_build_project_balances_undo_and_cleans_up(self):
        import reaper_ai_integration as rai

        calls = []
        tracks = []

        def rpr_get_cursor():
            return 4.5

        def rpr_set_cursor(pos, _moveview, _seek):
            calls.append(("cursor", pos))

        def rpr_undo_begin():
            calls.append("undo_begin")

        def rpr_undo_end(desc, _flags):
            calls.append(("undo_end", desc))

        def rpr_prevent(delta):
            calls.append(("refresh", delta))

        def rpr_update():
            calls.append("update")

        def rpr_num_tracks():
            return len(tracks)

        def rpr_insert_track(idx, _defaults):
            tracks.insert(idx, {"idx": idx})

        def rpr_get_track(_proj, idx):
            return tracks[idx]

        def rpr_getset_track_str(tr, _key, val, set_val):
            if set_val:
                tr["name"] = val
            return (True, tr.get("name", ""))

        def rpr_delete_track(tr):
            tracks.remove(tr)
            calls.append(("deleted", tr.get("name")))

        def rpr_get_env_by_name(_tr, _name):
            return {"env": True}

        def rpr_get_env_scaling(_env):
            return 0

        def rpr_scale_to_env(mode, val):
            calls.append(("scale_mode", mode))
            return val

        def rpr_insert_env_pt(*_args):
            pass

        def rpr_sort_pts(_env):
            pass

        mocks = {
            "RPR_GetCursorPosition": rpr_get_cursor,
            "RPR_SetEditCurPos": rpr_set_cursor,
            "RPR_Undo_BeginBlock": rpr_undo_begin,
            "RPR_Undo_EndBlock": rpr_undo_end,
            "RPR_PreventUIRefresh": rpr_prevent,
            "RPR_UpdateArrange": rpr_update,
            "RPR_GetNumTracks": rpr_num_tracks,
            "RPR_InsertTrackAtIndex": rpr_insert_track,
            "RPR_GetTrack": rpr_get_track,
            "RPR_GetSetMediaTrackInfo_String": rpr_getset_track_str,
            "RPR_DeleteTrack": rpr_delete_track,
            "RPR_GetTrackEnvelopeByName": rpr_get_env_by_name,
            "RPR_GetEnvelopeScalingMode": rpr_get_env_scaling,
            "RPR_ScaleToEnvelopeMode": rpr_scale_to_env,
            "RPR_InsertEnvelopePoint": rpr_insert_env_pt,
            "RPR_Envelope_SortPoints": rpr_sort_pts,
        }
        with patch.dict(rai.__dict__, mocks):
            iface = rai.ReaperInterface()
            iface.build_project({
                "tracks": [{
                    "name": "Track 1",
                    "volume_envelope": [{"time": 0.0, "value": 1.0}],
                    "items": [{"source": "", "offset": 0.0, "position": 0.0, "duration": 1.0}],
                }],
                "markers": [],
            })
        self.assertEqual(len(tracks), 1)
        self.assertIn("undo_begin", calls)
        self.assertIn(("undo_end", "Import AAF"), calls)
        self.assertIn(("refresh", 1), calls)
        self.assertIn(("refresh", -1), calls)
        self.assertNotIn(("deleted", "Insertion"), calls)
        self.assertFalse(any(c[0] == "deleted" for c in calls if isinstance(c, tuple)))
        self.assertIn(("cursor", 4.5), calls)
        self.assertIn(("scale_mode", 0), calls)

    def test_suno_media_duration_falls_back_to_ffprobe(self):
        import types
        from suno_workflow_helper import SunoReaperWorkflow

        with tempfile.TemporaryDirectory() as temp_dir:
            fake_ogg = Path(temp_dir) / "song.ogg"
            fake_ogg.write_bytes(b"OggS-not-a-wav")
            fake_completed = types.SimpleNamespace(returncode=0, stdout="123.45\n")
            with patch("suno_workflow_helper.sf", None), \
                 patch("suno_workflow_helper.shutil.which", return_value="/usr/bin/ffprobe"), \
                 patch("suno_workflow_helper.subprocess.run", return_value=fake_completed):
                dur = SunoReaperWorkflow._media_duration(str(fake_ogg))
            self.assertAlmostEqual(dur, 123.45, places=6)

    def test_import_aaf_confirms_when_existing_tracks_present(self):
        import reaper_ai_integration as rai

        mb_calls = []
        project_built = []

        with tempfile.TemporaryDirectory() as temp_dir:
            mocks = {
                "have_reaper": True,
                "aaf2": object(),
                "RPR_GetUserFileNameForRead": lambda *_: (True, "dummy.aaf", "", ""),
                "RPR_GetProjectPath": lambda *_: (temp_dir, 512),
                "RPR_GetNumTracks": lambda: 3,
                "RPR_ShowConsoleMsg": lambda msg: None,
                "RPR_MB": lambda msg, title, typ: mb_calls.append((msg, title, typ)) or 2,  # User clicks Cancel
            }

            class MockAAF:
                def open(self, _): return True
                def get_aaf_metadata(self): return {}
                def get_embedded_essence_count(self): return 0
                def extract_essence(self, *args): pass
                def get_composition_list(self): return ["Comp 1"]
                def get_composition(self, _): return {"tracks": [], "markers": []}
                def close(self): pass

            with patch.dict(rai.__dict__, mocks), \
                 patch.object(rai, "AAFInterface", return_value=MockAAF()), \
                 patch.object(rai.ReaperInterface, "build_project", lambda self, data: project_built.append(data)):
                result = rai.import_aaf()

            self.assertFalse(result)
            self.assertEqual(len(mb_calls), 1)
            self.assertIn("already contains 3 track(s)", mb_calls[0][0])
            self.assertEqual(len(project_built), 0)

    def test_get_composition_awkward_accepts_and_cancels_cleanly(self):
        import reaper_ai_integration as rai

        prompts = []

        def fake_mb_decline(msg, _title, _flags):
            prompts.append(msg)
            return 7  # IDNO

        with patch.dict(rai.__dict__, {"RPR_MB": fake_mb_decline}):
            res = rai.UserInteraction.get_composition_awkward(["Comp A", "Comp B"])
        self.assertIsNone(res)
        self.assertEqual(len(prompts), 2)

        def fake_mb_accept_second(msg, _title, _flags):
            return 6 if "Comp B" in msg else 7

        with patch.dict(rai.__dict__, {"RPR_MB": fake_mb_accept_second}):
            res = rai.UserInteraction.get_composition_awkward(["Comp A", "Comp B"])
        self.assertEqual(res, 1)


if __name__ == "__main__":
    unittest.main()
