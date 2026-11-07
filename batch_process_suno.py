"""Batch audio discovery and Suno-to-REAPER project processing."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import time
from typing import Callable, Iterable, List, Optional

from suno_workflow_config_system import PathConfig, WorkflowConfig
from suno_workflow_helper import SunoReaperWorkflow


class BatchProcessor:
    """Process independent files with deterministic discovery and result reporting."""

    def __init__(
        self,
        output_dir: Optional[str] = None,
        parallel: bool = False,
        max_workers: int = 2,
        workflow_factory: Optional[Callable] = None,
    ):
        if max_workers < 1:
            raise ValueError("max_workers must be at least 1")
        self.output_dir = os.fspath(output_dir) if output_dir else None
        self.parallel = parallel
        self.max_workers = max_workers
        self.workflow_factory = workflow_factory or SunoReaperWorkflow

    @staticmethod
    def discover_audio_files(
        directory: str,
        extensions: Optional[Iterable[str]] = None,
        recursive: bool = False,
    ) -> List[str]:
        root = Path(directory).expanduser().resolve()
        if not root.is_dir():
            raise NotADirectoryError(f"Directory not found: {root}")
        normalized = {
            suffix.lower() if suffix.startswith(".") else f".{suffix.lower()}"
            for suffix in (extensions or (".wav", ".mp3", ".flac", ".m4a", ".ogg"))
        }
        candidates = root.rglob("*") if recursive else root.glob("*")
        return [
            str(path) for path in sorted(candidates, key=lambda item: str(item).lower())
            if path.is_file() and path.suffix.lower() in normalized
        ]

    def process_file(self, input_file: str) -> dict:
        started = time.monotonic()
        config = WorkflowConfig(paths=PathConfig(output_dir=self.output_dir))
        try:
            workflow = self.workflow_factory(config=config)
            result = workflow.process_suno_track(input_file)
            return {
                "success": result.success,
                "input_file": os.fspath(input_file),
                "processing_time": time.monotonic() - started,
                "project_dir": result.project_dir,
                "project_file": result.project_file,
                "stem_paths": result.stem_paths,
                "error": result.error_message,
            }
        except Exception as exc:  # One bad file must not abort the batch.
            return {
                "success": False,
                "input_file": os.fspath(input_file),
                "processing_time": time.monotonic() - started,
                "project_dir": "",
                "project_file": "",
                "stem_paths": {},
                "error": str(exc),
            }

    def process_files(self, audio_files: Iterable[str]) -> List[dict]:
        files = list(audio_files)
        if self.parallel and files:
            with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
                return list(executor.map(self.process_file, files))
        return [self.process_file(path) for path in files]

    def process_directory(
        self,
        directory: str,
        extensions: Optional[Iterable[str]] = None,
        recursive: bool = False,
    ) -> List[dict]:
        """Discover and process matching files, returning one result per file."""
        files = self.discover_audio_files(directory, extensions, recursive)
        return self.process_files(files)

    @staticmethod
    def generate_batch_report(results: List[dict], report_file: str) -> str:
        succeeded = sum(bool(result.get("success")) for result in results)
        failed = len(results) - succeeded
        lines = [
            "# Batch Processing Report",
            "",
            f"- Total: {len(results)}",
            f"- Succeeded: {succeeded}",
            f"- Failed: {failed}",
            f"- Total processing time: {sum(float(r.get('processing_time', 0)) for r in results):.2f}s",
            "",
            "| Input | Status | Project / Error | Time (s) |",
            "|---|---|---|---:|",
        ]
        for result in results:
            input_name = Path(result.get("input_file", "")).name.replace("|", "\\|")
            detail = (
                result.get("project_dir") if result.get("success")
                else result.get("error", "Unknown error")
            ) or ""
            detail = str(detail).replace("|", "\\|").replace("\n", " ")
            lines.append(
                f"| {input_name} | {'OK' if result.get('success') else 'FAILED'} "
                f"| {detail} | {float(result.get('processing_time', 0)):.2f} |"
            )
        destination = Path(report_file)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return str(destination)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", help="Directory containing audio files")
    parser.add_argument("-o", "--output-dir", help="Root for generated projects")
    parser.add_argument("--parallel", action="store_true")
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--recursive", action="store_true")
    parser.add_argument("--extensions", nargs="+", help="Extensions such as .wav .flac")
    parser.add_argument("--report", help="Write a Markdown report to this path")
    args = parser.parse_args(argv)

    try:
        processor = BatchProcessor(
            output_dir=args.output_dir,
            parallel=args.parallel,
            max_workers=args.workers,
        )
        results = processor.process_directory(
            args.directory, extensions=args.extensions, recursive=args.recursive
        )
    except (OSError, ValueError) as exc:
        parser.exit(2, f"error: {exc}\n")

    if args.report:
        processor.generate_batch_report(results, args.report)
    failures = sum(not result["success"] for result in results)
    print(f"Processed {len(results)} files: {len(results) - failures} succeeded, {failures} failed")
    for result in results:
        if not result["success"]:
            print(f"FAILED {result['input_file']}: {result['error']}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
