"""Batch audio discovery and Suno-to-REAPER project processing."""

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import re
import time
from typing import Callable, Iterable, List, Optional, Tuple

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

    @staticmethod
    def _sanitize_segment(text: str) -> str:
        cleaned = re.sub(r'[\\/:*?"<>|\s]+', "_", text).strip("._")
        return cleaned or "track"

    def _assign_project_names(
        self, files: List[str]
    ) -> List[Tuple[str, Optional[str]]]:
        if not self.output_dir or len(files) <= 1:
            return [(path, None) for path in files]

        stem_counts = Counter(Path(path).stem.lower() for path in files)
        if all(count == 1 for count in stem_counts.values()):
            return [(path, None) for path in files]

        resolved_parents = [str(Path(path).expanduser().resolve().parent) for path in files]
        try:
            common_root = Path(os.path.commonpath(resolved_parents))
        except ValueError:
            common_root = None

        used_names = set()
        assignments: List[Tuple[str, Optional[str]]] = []
        for path in files:
            file_path = Path(path).expanduser().resolve()
            stem = file_path.stem
            if stem_counts[stem.lower()] == 1:
                assignments.append((path, None))
                used_names.add(f"{stem.lower()}_reaper_project")
                continue

            prefix_parts = []
            if common_root is not None:
                try:
                    rel_parent = file_path.parent.relative_to(common_root)
                    prefix_parts = [
                        self._sanitize_segment(part)
                        for part in rel_parent.parts
                        if part not in ("", ".")
                    ]
                except ValueError:
                    prefix_parts = [self._sanitize_segment(file_path.parent.name)]
            else:
                prefix_parts = [self._sanitize_segment(file_path.parent.name)]

            safe_stem = self._sanitize_segment(stem)
            base_label = "_".join(prefix_parts + [safe_stem]) if prefix_parts else safe_stem
            candidate = f"{base_label}_reaper_project"
            suffix = 2
            while candidate.lower() in used_names:
                candidate = f"{base_label}_{suffix}_reaper_project"
                suffix += 1
            used_names.add(candidate.lower())
            assignments.append((path, candidate))

        return assignments

    def process_file(
        self, input_file: str, project_name: Optional[str] = None
    ) -> dict:
        started = time.monotonic()
        config = WorkflowConfig(paths=PathConfig(output_dir=self.output_dir))
        try:
            workflow = self.workflow_factory(config=config)
            if project_name is not None:
                result = workflow.process_suno_track(
                    input_file, project_name=project_name
                )
            else:
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
        assignments = self._assign_project_names(files)
        if self.parallel and assignments:
            with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
                return list(
                    executor.map(
                        lambda pair: self.process_file(pair[0], pair[1]),
                        assignments,
                    )
                )
        return [
            self.process_file(path, project_name)
            for path, project_name in assignments
        ]

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
        try:
            processor.generate_batch_report(results, args.report)
        except OSError as exc:
            parser.exit(2, f"error: failed to write batch report: {exc}\n")
    failures = sum(not result["success"] for result in results)
    print(f"Processed {len(results)} files: {len(results) - failures} succeeded, {failures} failed")
    for result in results:
        if not result["success"]:
            print(f"FAILED {result['input_file']}: {result['error']}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
