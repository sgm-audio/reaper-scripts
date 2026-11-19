"""Thread-safe SEMAS job queue with an opt-in background worker."""

from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import RLock
from typing import Callable, Dict, List, Optional
import wave

from SEMAS.core.data_structures import JobStatus, SEMASJob


class SEMASOrchestrator:
    """Own SEMAS jobs without starting threads during object construction.

    ``submit_job`` queues work. ``start_worker`` opts into asynchronous execution;
    ``process_job`` provides the synchronous API used by scripts and tests.
    """

    def __init__(
        self,
        processor: Optional[Callable[[SEMASJob], dict]] = None,
        max_workers: int = 1,
    ):
        if max_workers < 1:
            raise ValueError("max_workers must be at least 1")
        self.jobs: Dict[str, SEMASJob] = {}
        self.processor = processor or self._default_processor
        self.max_workers = max_workers
        self._executor = None
        self._lock = RLock()

    @staticmethod
    def _default_processor(job: SEMASJob) -> dict:
        source = Path(job.input_file).expanduser()
        if not source.is_file():
            raise FileNotFoundError(f"Input audio not found: {source}")
        if not job.operations or any(operation != "analyze" for operation in job.operations):
            raise NotImplementedError(
                "The bundled local SEMAS backend performs 'analyze' only; "
                "enhancement and mastering require a configured external processor."
            )
        try:
            with wave.open(str(source), "rb") as audio:
                sample_rate = audio.getframerate()
                frames = audio.getnframes()
                return {
                    "input_file": str(source),
                    "operations": list(job.operations),
                    "sample_rate": sample_rate,
                    "channels": audio.getnchannels(),
                    "sample_width_bytes": audio.getsampwidth(),
                    "frames": frames,
                    "duration_seconds": frames / sample_rate if sample_rate else 0.0,
                }
        except (wave.Error, EOFError) as exc:
            try:
                import soundfile as sf
            except ImportError:
                sf = None
            if sf is not None:
                try:
                    info = sf.info(str(source))
                    if info.samplerate > 0:
                        subtype = (info.subtype or "").upper()
                        if "DOUBLE" in subtype or "64" in subtype:
                            sample_width_bytes = 8
                        elif "FLOAT" in subtype or "32" in subtype:
                            sample_width_bytes = 4
                        elif "24" in subtype:
                            sample_width_bytes = 3
                        elif "08" in subtype or "PCM_U8" in subtype or "PCM_S8" in subtype:
                            sample_width_bytes = 1
                        else:
                            sample_width_bytes = 2
                        return {
                            "input_file": str(source),
                            "operations": list(job.operations),
                            "sample_rate": info.samplerate,
                            "channels": info.channels,
                            "sample_width_bytes": sample_width_bytes,
                            "frames": info.frames,
                            "duration_seconds": info.frames / info.samplerate,
                        }
                except (RuntimeError, OSError):
                    pass
            raise ValueError(
                f"Local SEMAS analysis requires an uncompressed PCM WAV file: {source}"
            ) from exc

    def submit_job(self, job: SEMASJob, auto_process: bool = True) -> str:
        if not isinstance(job, SEMASJob):
            raise TypeError("job must be a SEMASJob")
        with self._lock:
            if job.id in self.jobs:
                raise ValueError(f"Duplicate job id: {job.id}")
            job.status = JobStatus.PENDING
            self.jobs[job.id] = job
            if auto_process and self._executor is not None:
                self._executor.submit(self.process_job, job.id)
        return job.id

    def get_job(self, job_id: str) -> Optional[SEMASJob]:
        with self._lock:
            return self.jobs.get(job_id)

    def list_jobs(self) -> List[SEMASJob]:
        with self._lock:
            return list(self.jobs.values())

    def process_job(self, job_id: str) -> SEMASJob:
        with self._lock:
            job = self.jobs.get(job_id)
            if job is None:
                raise KeyError(f"Unknown SEMAS job: {job_id}")
            if job.status in (
                JobStatus.RUNNING,
                JobStatus.COMPLETED,
                JobStatus.FAILED,
            ):
                return job
            job.status = JobStatus.RUNNING
        try:
            results = dict(self.processor(job) or {})
            with self._lock:
                job.results = results
                job.status = JobStatus.COMPLETED
                job.error = ""
        except Exception as exc:
            with self._lock:
                job.status = JobStatus.FAILED
                job.error = str(exc)
        return job

    def start_worker(self):
        with self._lock:
            if self._executor is None:
                self._executor = ThreadPoolExecutor(
                    max_workers=self.max_workers, thread_name_prefix="semas"
                )
                for job_id, job in self.jobs.items():
                    if job.status == JobStatus.PENDING:
                        self._executor.submit(self.process_job, job_id)
        return self

    def shutdown(self, wait: bool = True):
        with self._lock:
            executor, self._executor = self._executor, None
        if executor is not None:
            executor.shutdown(wait=wait)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.shutdown()
