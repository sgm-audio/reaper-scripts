"""Executable smoke checks for the bundled SEMAS integration."""

import sys
import tempfile
from pathlib import Path
import wave

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from SEMAS.api import SEMASAPI
from SEMAS.cli import main
from SEMAS.core.data_structures import JobStatus, SEMASJob
from SEMAS.core.orchestrator import SEMASOrchestrator


def run_checks():
    orchestrator = SEMASOrchestrator()
    with tempfile.TemporaryDirectory() as temporary:
        source = Path(temporary) / "tone.wav"
        with wave.open(str(source), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(44100)
            output.writeframes(b"\0\0" * 441)
        job = SEMASJob(input_file=str(source))
        orchestrator.submit_job(job)
        assert orchestrator.process_job(job.id).status == JobStatus.COMPLETED
        assert orchestrator.get_job(job.id).results["sample_rate"] == 44100
        assert SEMASAPI(orchestrator).status(job.id)["id"] == job.id
        assert main([str(source), "--json"]) == 0
    orchestrator.shutdown()
    print("SEMAS import and job-processing checks passed.")


if __name__ == "__main__":
    run_checks()
