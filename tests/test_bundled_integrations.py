"""Focused regressions for the bundled separator, batch, and SEMAS modules."""

from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import numpy as np
import soundfile as sf

from batch_process_suno import BatchProcessor
from SEMAS.core.data_structures import JobStatus, SEMASJob
from SEMAS.core.orchestrator import SEMASOrchestrator
from yourmt3_stem_separator import YourMT3StemSeparator, main as separator_main


class SeparatorBackendTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.source = self.root / "input.wav"
        sf.write(self.source, np.zeros((441, 1), dtype=np.float32), 44100)
        self.separator = YourMT3StemSeparator(output_dir=self.root / "stems", device="cpu")

    def tearDown(self):
        self.temporary.cleanup()

    def test_missing_backend_is_actionable_and_creates_no_stems(self):
        with patch.object(self.separator, "_demucs_available", return_value=False):
            with self.assertRaisesRegex(RuntimeError, "stem-separation"):
                self.separator.separate(str(self.source))
        self.assertEqual(list((self.root / "stems").glob("*.wav")), [])

    def test_model_download_and_cli(self):
        container_type = type("BagOfModels", (), {})
        with patch.object(YourMT3StemSeparator, "_demucs_available", return_value=True), \
                patch("yourmt3_stem_separator.importlib.import_module") as import_module:
            import_module.return_value.get_model.return_value = container_type()
            self.assertEqual(
                YourMT3StemSeparator.download_model("htdemucs"), "BagOfModels"
            )
            import_module.return_value.get_model.assert_called_once_with("htdemucs")

        with patch.object(
            YourMT3StemSeparator, "download_model", return_value="BagOfModels"
        ) as download:
            self.assertEqual(separator_main(["--download-model"]), 0)
            download.assert_called_once_with("htdemucs")

    def test_model_download_failure_is_actionable(self):
        with patch.object(YourMT3StemSeparator, "_demucs_available", return_value=True), \
                patch("yourmt3_stem_separator.importlib.import_module") as import_module:
            import_module.return_value.get_model.side_effect = OSError("offline")
            with self.assertRaisesRegex(RuntimeError, "manual cache instructions"):
                YourMT3StemSeparator.download_model()

    def test_demucs_output_discovery_and_selected_stems(self):
        observed = {}

        def fake_run(command, **kwargs):
            observed["command"] = command
            observed["kwargs"] = kwargs
            output = Path(command[command.index("-o") + 1])
            destination = output / "htdemucs" / "input"
            destination.mkdir(parents=True)
            for index, stem in enumerate(self.separator.STEMS, start=1):
                samples = np.full((220, 2), index * 0.05, dtype=np.float32)
                sf.write(destination / f"{stem}.wav", samples, 22050)
            return subprocess.CompletedProcess(command, 0, "", "")

        with patch.object(self.separator, "_demucs_available", return_value=True), \
                patch.object(self.separator, "_preprocess_ai_audio", side_effect=lambda audio, _: audio), \
                patch("yourmt3_stem_separator.subprocess.run", side_effect=fake_run):
            paths = self.separator.separate(str(self.source), stems=["vocals", "drums"])

        self.assertEqual(set(paths), {"vocals", "drums"})
        self.assertFalse((self.root / "stems" / "bass.wav").exists())
        audio, sample_rate = sf.read(paths["vocals"], always_2d=True)
        self.assertEqual(sample_rate, 22050)
        self.assertEqual(audio.shape, (220, 2))
        # The fake backend's default WAV subtype is PCM16; output preserves it.
        self.assertAlmostEqual(float(audio[10, 0]), 0.05, delta=2.0e-5)
        self.assertEqual(observed["command"][:3], [sys.executable, "-m", "demucs"])
        self.assertEqual(observed["kwargs"]["timeout"], 1800)

    def test_empty_preprocessing_is_well_defined(self):
        empty = np.empty((2, 0), dtype=np.float32)
        self.assertEqual(self.separator._apply_highpass(empty, 44100).shape, (2, 0))
        self.assertEqual(self.separator._reduce_spectral_artifacts(empty, 44100).shape, (2, 0))
        self.assertEqual(self.separator._preprocess_ai_audio(empty, 44100).shape, (2, 0))


class BatchBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def test_recursive_discovery_filtering_and_order(self):
        (self.root / "nested").mkdir()
        for relative in ("z.WAV", "a.mp3", "nested/b.wav", "nested/c.txt"):
            (self.root / relative).write_bytes(b"fixture")
        discovered = BatchProcessor.discover_audio_files(
            self.root, extensions=["wav"], recursive=True
        )
        self.assertEqual(
            [Path(path).relative_to(self.root).as_posix() for path in discovered],
            ["nested/b.wav", "z.WAV"],
        )
        with self.assertRaises(NotADirectoryError):
            BatchProcessor.discover_audio_files(self.root / "missing")

    def test_parallel_processing_preserves_order_and_isolates_errors(self):
        for name in ("one.wav", "bad.wav", "three.wav"):
            (self.root / name).write_bytes(b"fixture")

        def factory(config):
            class Workflow:
                def process_suno_track(self, input_file):
                    if Path(input_file).name == "bad.wav":
                        raise RuntimeError("intentional test failure")
                    return type("Result", (), {
                        "success": True,
                        "project_dir": str(Path(config.paths.output_dir) / Path(input_file).stem),
                        "project_file": "project.rpp",
                        "stem_paths": {},
                        "error_message": None,
                    })()
            return Workflow()

        processor = BatchProcessor(
            output_dir=self.root / "output", parallel=True, max_workers=3,
            workflow_factory=factory,
        )
        files = [str(self.root / name) for name in ("one.wav", "bad.wav", "three.wav")]
        results = processor.process_files(files)
        self.assertEqual([Path(result["input_file"]).name for result in results],
                         ["one.wav", "bad.wav", "three.wav"])
        self.assertEqual([result["success"] for result in results], [True, False, True])
        self.assertIn("intentional", results[1]["error"])

    def test_report_counts_and_markdown_escaping(self):
        destination = self.root / "reports" / "batch.md"
        BatchProcessor.generate_batch_report([
            {"success": False, "input_file": "bad|name.wav", "error": "bad|error\nnext"},
        ], destination)
        report = destination.read_text(encoding="utf-8")
        self.assertIn("Failed: 1", report)
        self.assertIn("bad\\|name.wav", report)
        self.assertIn("bad\\|error next", report)


class SEMASBehaviorTests(unittest.TestCase):
    def test_unsupported_operation_fails_honestly(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "audio.wav"
            source.write_bytes(b"not decoded for unsupported operation")
            orchestrator = SEMASOrchestrator()
            job = SEMASJob(input_file=str(source), operations=["master"])
            orchestrator.submit_job(job)
            result = orchestrator.process_job(job.id)
            self.assertEqual(result.status, JobStatus.FAILED)
            self.assertIn("external processor", result.error)

    def test_worker_processes_jobs_submitted_after_startup(self):
        def processor(job):
            return {"input_file": job.input_file, "sample_rate": 48000}

        orchestrator = SEMASOrchestrator(processor=processor)
        orchestrator.start_worker()
        job = SEMASJob(input_file="virtual.wav")
        orchestrator.submit_job(job)
        for _ in range(100):
            if job.status in (JobStatus.COMPLETED, JobStatus.FAILED):
                break
            time.sleep(0.01)
        orchestrator.shutdown()
        self.assertEqual(job.status, JobStatus.COMPLETED)
        self.assertEqual(job.results["sample_rate"], 48000)


if __name__ == "__main__":
    unittest.main()
