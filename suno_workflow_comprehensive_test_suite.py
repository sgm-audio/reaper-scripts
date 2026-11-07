#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Comprehensive Test Suite for Suno Reaper Workflow System
Tests all major components with proper error handling and reporting
"""

import sys
import os
import unittest
import tempfile
import shutil
import subprocess
import logging
from unittest.mock import patch
import numpy as np
import soundfile as sf

# Add project root to path and resolve fixtures independently of the cwd.
ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)

# Configure logging for tests
logging.basicConfig(level=logging.WARNING)


class TestSunoWorkflowHelper(unittest.TestCase):
    """Test Suno Workflow Helper functionality"""

    def setUp(self):
        """Set up test environment"""
        self.test_dir = tempfile.mkdtemp()
        self.workflow = __import__("suno_workflow_helper").SunoReaperWorkflow()

    def tearDown(self):
        """Clean up test environment"""
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def create_test_audio(self, filename: str, duration: float = 1.0):
        """Create a test audio file"""
        sample_rate = 44100
        t = np.linspace(0, duration, int(sample_rate * duration))
        audio = 0.3 * np.sin(2 * np.pi * 440 * t)  # 440Hz sine wave
        stereo_audio = np.column_stack([audio, audio])

        # Ensure filename has audio extension
        if not any(filename.lower().endswith(ext) for ext in [".wav", ".mp3", ".flac"]):
            filename = filename + ".wav"

        file_path = os.path.join(self.test_dir, filename)
        sf.write(file_path, stereo_audio, sample_rate)
        return file_path

    def mock_stem_separation(self, mock_separator, project_dir):
        """Return real media files from the mocked separator."""
        def separate(_):
            stems_dir = os.path.join(project_dir, "stems")
            os.makedirs(stems_dir, exist_ok=True)
            paths = {}
            for name in ("vocals", "drums", "bass", "other"):
                path = os.path.join(stems_dir, f"{name}.wav")
                sf.write(path, np.zeros((441, 2), dtype=np.float32), 44100)
                paths[name] = path
            return paths
        mock_separator.return_value.separate.side_effect = separate

    @patch("suno_workflow_helper.YourMT3StemSeparator")
    def test_workflow_initialization(self, mock_separator):
        """Test workflow initialization"""
        workflow = __import__("suno_workflow_helper").SunoReaperWorkflow()

        self.assertIsNotNone(workflow)
        self.assertIsNotNone(workflow.config)
        self.assertIsNone(workflow.config.template_path)

    @patch("suno_workflow_helper.YourMT3StemSeparator")
    def test_process_suno_track_success(self, mock_separator):
        """Test successful Suno track processing"""
        self.mock_stem_separation(
            mock_separator, os.path.join(self.test_dir, "test_project")
        )

        workflow = __import__("suno_workflow_helper").SunoReaperWorkflow()

        # Create test audio file
        test_file = self.create_test_audio("test_track.mp3")

        result = workflow.process_suno_track(test_file, project_name="test_project")

        self.assertTrue(result.success)
        self.assertTrue(os.path.exists(result.project_dir))
        self.assertTrue(os.path.exists(result.project_file))
        self.assertEqual(len(result.stem_paths), 4)
        with open(result.project_file, encoding="utf-8") as project:
            content = project.read()
        self.assertIn('<SOURCE WAVE', content)
        self.assertIn('FILE "stems/vocals.wav"', content)
        self.assertIn('B_MUTE 1', content)

    def test_process_nonexistent_file(self):
        """Test handling of nonexistent file"""
        workflow = __import__("suno_workflow_helper").SunoReaperWorkflow()

        result = workflow.process_suno_track("/nonexistent/file.mp3")

        self.assertFalse(result.success)
        self.assertIsNotNone(result.error_message)

    @patch("suno_workflow_helper.YourMT3StemSeparator")
    def test_project_name_generation(self, mock_separator):
        """Test automatic project name generation"""
        self.mock_stem_separation(
            mock_separator,
            os.path.join(self.test_dir, "my_track_reaper_project"),
        )
        workflow = __import__("suno_workflow_helper").SunoReaperWorkflow()

        test_file = self.create_test_audio("my_track.mp3")
        result = workflow.process_suno_track(test_file)

        self.assertIn("my_track_reaper_project", result.project_dir)

    def test_create_reaper_project(self):
        """Test Reaper project creation"""
        workflow = __import__("suno_workflow_helper").SunoReaperWorkflow()

        stem_paths = {"vocals": "/fake/vocals.wav", "drums": "/fake/drums.wav"}

        project_file = workflow._create_reaper_project(
            self.test_dir, "test_project", stem_paths, "/fake/original.wav",
            auto_import=False,
        )

        self.assertTrue(project_file.endswith(".rpp"))
        self.assertTrue(os.path.exists(project_file))

    def test_generate_instructions(self):
        """Test instruction generation"""
        workflow = __import__("suno_workflow_helper").SunoReaperWorkflow()

        stem_paths = {"vocals": "/fake/vocals.wav", "drums": "/fake/drums.wav"}

        instructions_file = workflow._generate_instructions(
            self.test_dir, "/fake/project.rpp", stem_paths, "/fake/original.wav"
        )

        self.assertTrue(instructions_file.endswith(".md"))
        self.assertTrue(os.path.exists(instructions_file))

        # Check content
        with open(instructions_file, "r") as f:
            content = f.read()
            self.assertIn("Suno Track Import Instructions", content)
            self.assertIn("vocals", content)


class TestYourMT3StemSeparator(unittest.TestCase):
    """Test the compatibility-named Demucs separator adapter."""

    def setUp(self):
        """Set up test environment"""
        self.test_dir = tempfile.mkdtemp()
        self.separator_class = __import__("yourmt3_stem_separator").YourMT3StemSeparator

    def tearDown(self):
        """Clean up test environment"""
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def create_test_audio(self, filename: str, duration: float = 1.0):
        """Create a test audio file"""
        sample_rate = 44100
        t = np.linspace(0, duration, int(sample_rate * duration))
        audio = 0.3 * np.sin(2 * np.pi * 440 * t)
        stereo_audio = np.column_stack([audio, audio])

        file_path = os.path.join(self.test_dir, filename)
        sf.write(file_path, stereo_audio, sample_rate)
        return file_path

    def test_separator_initialization(self):
        """Test separator initialization"""
        separator = self.separator_class(output_dir=self.test_dir)

        self.assertIsNotNone(separator)
        self.assertEqual(separator.output_dir, self.test_dir)
        self.assertTrue(os.path.exists(separator.output_dir))

    @patch("yourmt3_stem_separator.torch.cuda.is_available")
    def test_device_selection(self, mock_cuda):
        """Test device selection logic"""
        mock_cuda.return_value = True

        separator = self.separator_class()
        self.assertEqual(separator.device, "cuda")

        mock_cuda.return_value = False
        separator = self.separator_class()
        self.assertEqual(separator.device, "cpu")

    def test_audio_loading(self):
        """Test audio file loading"""
        separator = self.separator_class()
        test_file = self.create_test_audio("test.wav")

        audio, sr = separator._load_audio(test_file)

        self.assertIsInstance(audio, np.ndarray)
        self.assertEqual(audio.shape[0], 2)  # Stereo
        self.assertGreater(sr, 0)

    def test_mono_to_stereo_conversion(self):
        """Test mono to stereo conversion"""
        separator = self.separator_class()

        # Create mono audio
        sample_rate = 44100
        t = np.linspace(0, 1.0, sample_rate)
        mono_audio = 0.3 * np.sin(2 * np.pi * 440 * t)

        file_path = os.path.join(self.test_dir, "mono.wav")
        sf.write(file_path, mono_audio, sample_rate)

        audio, sr = separator._load_audio(file_path)

        self.assertEqual(audio.shape[0], 2)  # Should be stereo

    def test_audio_preprocessing(self):
        """Test AI audio preprocessing"""
        separator = self.separator_class()

        # Create test audio
        sample_rate = 44100
        t = np.linspace(0, 1.0, sample_rate)
        audio = 0.3 * np.sin(2 * np.pi * 440 * t)
        stereo_audio = np.column_stack([audio, audio])

        processed = separator._preprocess_ai_audio(stereo_audio, sample_rate)

        self.assertEqual(processed.shape, stereo_audio.shape)
        self.assertIsInstance(processed, np.ndarray)

    def test_highpass_filter(self):
        """Test high-pass filter application"""
        separator = self.separator_class()

        # Create test audio
        audio = np.random.randn(2, 44100) * 0.1
        filtered = separator._apply_highpass(audio, 44100, 20)

        self.assertEqual(filtered.shape, audio.shape)
        self.assertIsInstance(filtered, np.ndarray)

    def test_spectral_artifact_reduction(self):
        """Test spectral artifact reduction"""
        separator = self.separator_class()

        # Create test audio
        audio = np.random.randn(2, 44100) * 0.1
        cleaned = separator._reduce_spectral_artifacts(audio, 44100)

        self.assertEqual(cleaned.shape, audio.shape)
        self.assertIsInstance(cleaned, np.ndarray)

    def test_model_info(self):
        """Test model information retrieval"""
        separator = self.separator_class()
        info = separator.get_model_info()

        self.assertIsInstance(info, dict)
        self.assertIn("model_name", info)
        self.assertIn("device", info)
        self.assertIn("ai_audio_optimized", info)
        self.assertTrue(info["ai_audio_optimized"])


class TestBatchProcessor(unittest.TestCase):
    """Test Batch Processor functionality"""

    def setUp(self):
        """Set up test environment"""
        self.test_dir = tempfile.mkdtemp()
        self.processor_class = __import__("batch_process_suno").BatchProcessor

    def tearDown(self):
        """Clean up test environment"""
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def create_test_audio(self, filename: str):
        """Create a test audio file, defaulting extensionless names to WAV."""
        if not os.path.splitext(filename)[1]:
            filename += ".wav"
        sample_rate = 44100
        duration = 1.0
        t = np.linspace(0, duration, int(sample_rate * duration))
        audio = 0.3 * np.sin(2 * np.pi * 440 * t)
        stereo_audio = np.column_stack([audio, audio])

        file_path = os.path.join(self.test_dir, filename)
        sf.write(file_path, stereo_audio, sample_rate)
        return file_path

    def test_processor_initialization(self):
        """Test processor initialization"""
        processor = self.processor_class()

        self.assertIsNotNone(processor)
        self.assertFalse(processor.parallel)
        self.assertEqual(processor.max_workers, 2)

    def test_audio_file_discovery(self):
        """Test audio file discovery in directory"""
        processor = self.processor_class()

        # Create test files
        self.create_test_audio("test1.mp3")
        self.create_test_audio("test2.wav")
        self.create_test_audio("test3.flac")

        # Create non-audio file
        with open(os.path.join(self.test_dir, "readme.txt"), "w") as f:
            f.write("test")

        audio_files = processor.process_directory(self.test_dir)

        self.assertIsInstance(audio_files, list)

    def test_extension_filtering(self):
        """Test file extension filtering"""
        processor = self.processor_class()

        # Create test files
        self.create_test_audio("test1.mp3")
        self.create_test_audio("test2.wav")
        self.create_test_audio("test3")  # Will get .wav extension automatically

        # Test with specific extensions
        results = processor.process_directory(self.test_dir, extensions=[".wav"])

        self.assertIsInstance(results, list)

    def test_parallel_processing_setting(self):
        """Test parallel processing configuration"""
        processor = self.processor_class(parallel=True, max_workers=4)

        self.assertTrue(processor.parallel)
        self.assertEqual(processor.max_workers, 4)

    def test_report_generation(self):
        """Test batch report generation"""
        processor = self.processor_class()

        # Mock results
        mock_results = [
            {
                "success": True,
                "input_file": "/fake/test1.mp3",
                "processing_time": 10.5,
                "project_dir": "/fake/project1",
            },
            {
                "success": False,
                "input_file": "/fake/test2.mp3",
                "error": "Processing failed",
                "processing_time": 2.1,
            },
        ]

        report_file = os.path.join(self.test_dir, "test_report.md")
        processor.generate_batch_report(mock_results, report_file)

        self.assertTrue(os.path.exists(report_file))

        with open(report_file, "r") as f:
            content = f.read()
            self.assertIn("Batch Processing Report", content)
            self.assertIn("test1.mp3", content)
            self.assertIn("test2.mp3", content)


class TestSEMASIntegration(unittest.TestCase):
    """Test SEMAS Multi-Agent System Integration"""

    def setUp(self):
        """Set up test environment"""
        self.test_dir = tempfile.mkdtemp()

    def tearDown(self):
        """Clean up test environment"""
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def test_semas_imports(self):
        """Test SEMAS module imports"""
        try:
            # Test core imports
            from SEMAS.core.orchestrator import SEMASOrchestrator
            from SEMAS.core.data_structures import SEMASJob

            self.assertIsNotNone(SEMASOrchestrator)
            self.assertIsNotNone(SEMASJob)
        except ImportError as e:
            self.fail(f"SEMAS import failed: {e}")

    def test_cli_import(self):
        """Test CLI module import"""
        try:
            import SEMAS.cli

            self.assertIsNotNone(SEMAS.cli)
        except ImportError as e:
            self.fail(f"SEMAS CLI import failed: {e}")

    def test_api_import(self):
        """Test API module import"""
        try:
            import SEMAS.api

            self.assertIsNotNone(SEMAS.api)
        except ImportError as e:
            self.fail(f"SEMAS API import failed: {e}")

    def test_semas_functionality(self):
        """Test basic SEMAS functionality"""
        try:
            # Run SEMAS tests
            result = subprocess.run(
                [sys.executable, os.path.join(ROOT, "SEMAS", "test_imports.py")],
                capture_output=True,
                text=True,
                timeout=30,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

        except subprocess.TimeoutExpired:
            self.fail("SEMAS test timed out")
        except Exception as e:
            self.fail(f"SEMAS test failed: {e}")


def run_integration_tests():
    """Run integration tests that require full system"""
    print("\n" + "=" * 60)
    print("INTEGRATION TESTS")
    print("=" * 60)

    # Test module imports
    print("\n1. Testing module imports...")
    try:
        __import__("suno_workflow_helper")
        print("   [OK] suno_workflow_helper imported successfully")
    except ImportError as e:
        print(f"   [FAIL] Import error: {e}")
        return False
    for bundled in ("yourmt3_stem_separator", "batch_process_suno", "SEMAS"):
        try:
            __import__(bundled)
            print(f"   [OK] {bundled} imported successfully")
        except ImportError as e:
            print(f"   [FAIL] bundled integration import failed: {bundled}: {e}")
            return False

    # Test AGENTS.md file exists
    print("\n2. Checking documentation...")
    if os.path.exists(os.path.join(ROOT, "AGENTS.md")):
        print("   [OK] AGENTS.md documentation exists")
    else:
        print("   [FAIL] AGENTS.md documentation missing")
        return False

    # Test requirements files
    print("\n3. Checking requirements files...")
    req_files = ["requirements.txt", "requirements_yourmt3.txt"]
    for req_file in req_files:
        if os.path.exists(os.path.join(ROOT, req_file)):
            print(f"   [OK] {req_file} exists")
        else:
            print(f"   [FAIL] {req_file} missing")
            return False

    print("\n   [OK] Integration tests passed")
    return True


def main():
    """Main test runner"""
    print("\n" + "=" * 60)
    print("COMPREHENSIVE TEST SUITE - Suno Reaper Workflow")
    print("=" * 60)

    # Run unit tests
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    # Add test cases
    suite.addTests(loader.loadTestsFromTestCase(TestSunoWorkflowHelper))
    suite.addTests(loader.loadTestsFromTestCase(TestYourMT3StemSeparator))
    suite.addTests(loader.loadTestsFromTestCase(TestBatchProcessor))
    suite.addTests(loader.loadTestsFromTestCase(TestSEMASIntegration))

    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    unit_test_result = runner.run(suite)

    # Run integration tests
    integration_result = run_integration_tests()

    # Summary
    print("\n" + "=" * 60)
    print("TEST SUMMARY")
    print("=" * 60)

    total_tests = unit_test_result.testsRun
    failures = len(unit_test_result.failures)
    errors = len(unit_test_result.errors)
    skipped = len(unit_test_result.skipped)
    passed = total_tests - failures - errors - skipped

    print(f"Unit Tests: {passed} passed, {skipped} skipped, {total_tests} total")
    print(f"Failures: {failures}, Errors: {errors}")

    if integration_result:
        print("Integration Tests: PASSED")
    else:
        print("Integration Tests: FAILED")

    success = failures == 0 and errors == 0 and skipped == 0 and integration_result

    if success:
        print("\n*** ALL 23 TESTS PASSED WITH NO SKIPS! ***")
        return 0
    if skipped:
        print(f"\n{skipped} tests were skipped; bundled integration tests must execute.")
    print("\n*** SOME TESTS FAILED OR WERE SKIPPED ***")
    print("Please review the test output above.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
