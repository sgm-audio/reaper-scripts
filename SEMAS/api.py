"""Programmatic facade for local SEMAS jobs."""

from SEMAS.core.data_structures import JobStatus, SEMASJob
from SEMAS.core.orchestrator import SEMASOrchestrator

__all__ = ["JobStatus", "SEMASAPI", "SEMASJob", "SEMASOrchestrator"]


class SEMASAPI:
    def __init__(self, orchestrator=None):
        self.orchestrator = orchestrator or SEMASOrchestrator()

    def submit(self, input_file, operations=None, process=False):
        job = SEMASJob(
            input_file=str(input_file),
            operations=list(operations or ["analyze"]),
        )
        self.orchestrator.submit_job(job)
        if process:
            self.orchestrator.process_job(job.id)
        return job.to_dict()

    def status(self, job_id):
        job = self.orchestrator.get_job(job_id)
        return job.to_dict() if job else None

    def shutdown(self):
        self.orchestrator.shutdown()
