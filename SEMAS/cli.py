"""Command-line entry point for SEMAS job submission and analysis."""

import argparse
import json
from pathlib import Path

from SEMAS.core.data_structures import JobStatus, SEMASJob
from SEMAS.core.orchestrator import SEMASOrchestrator


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_file", help="Audio file to analyze")
    parser.add_argument(
        "--operations", nargs="+", default=["analyze"],
        help="Operations to request (the bundled local backend supports analyze)",
    )
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON")
    args = parser.parse_args(argv)

    if not Path(args.input_file).is_file():
        parser.exit(2, f"error: audio file not found: {args.input_file}\n")
    orchestrator = SEMASOrchestrator()
    job = SEMASJob(input_file=args.input_file, operations=args.operations)
    orchestrator.submit_job(job)
    orchestrator.process_job(job.id)
    payload = json.dumps(job.to_dict(), indent=2)
    print(payload if args.json else f"{job.id}: {job.status.value}\n{payload}")
    return 1 if job.status == JobStatus.FAILED else 0


if __name__ == "__main__":
    raise SystemExit(main())
