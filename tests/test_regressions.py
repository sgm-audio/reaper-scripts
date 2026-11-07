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
            (root / "Effect.CLAP").write_text("binary")
            (root / "Legacy.DLL").write_text("binary")
            effects = root / "Effects"
            effects.mkdir()
            (effects / "utility").write_text("desc:Utility")
            (effects / "include.jsfx-inc").write_text("include")
            scanner = module.PluginScanner()
            scanner.plugin_paths = [str(root), str(effects)]
            found = scanner.scan_plugins()
            self.assertEqual(len(found["vst3"]), 1)
            self.assertEqual(len(found["au"]), 1)
            self.assertEqual(len(found["lv2"]), 1)
            self.assertEqual(len(found["vst2"]), 2)  # .vst bundle and .dll
            self.assertEqual(len(found["clap"]), 1)
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
            export = Path(temp_dir) / "plugins.json"
            database.export_json(str(export))
            self.assertTrue(json.loads(export.read_text())["plugins"])
            imported = module.PluginDatabase(str(second_path))
            imported.import_json(str(export))
            self.assertEqual(imported.find_plugin("ReaEQ").manufacturer, "Cockos")

            template = Path(temp_dir) / "fixture.rpp"
            template.write_text(
                '<VST "VST3: Pro-Q 3 (FabFilter)" plugin.vst3 0 ""\n'
                '<CLAP "CLAP: Secret Sauce (Vendor)" secret.clap 0 ""\n',
                encoding="utf-8",
            )
            checker = module.CompatibilityChecker.__new__(module.CompatibilityChecker)
            self.assertEqual(
                checker._parse_template_plugins(str(template)),
                ["Pro-Q 3", "Secret Sauce"],
            )
            self.assertTrue(
                checker._is_installed("Secret Sauce", ["Secret Sauce.vst3"])
            )

    def test_reaper_cache_parser_handles_quotes_and_commas(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            cache = Path(temp_dir) / "reaper-vstplugins64.ini"
            cache.write_text(
                '[vstcache]\nPlugin.vst3=ABC123,1,"Delay, Wide (Vendor)"\n',
                encoding="utf-8",
            )
            parsed = parse_reaper_ini(str(cache))
            self.assertIn("Delay, Wide (Vendor)", parsed)
            self.assertEqual(parsed["Delay, Wide (Vendor)"]["type"], "VST3")


if __name__ == "__main__":
    unittest.main()
