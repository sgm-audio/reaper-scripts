"""
Performance Optimization Utilities
Provides async processing and performance monitoring capabilities
"""

import asyncio
import time
import functools
import logging
import os
import shutil
from typing import Callable, Any, Optional, Dict, List
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor
from dataclasses import dataclass, field
from datetime import datetime
import threading
import psutil
import gc

logger = logging.getLogger(__name__)


@dataclass
class PerformanceMetrics:
    """Performance metrics for monitoring"""

    start_time: float = field(default_factory=time.time)
    end_time: Optional[float] = None
    duration: Optional[float] = None
    memory_usage_mb: Optional[float] = None
    cpu_usage_percent: Optional[float] = None
    operations_completed: int = 0
    operations_failed: int = 0
    operations_per_second: Optional[float] = None


class PerformanceMonitor:
    """Monitor performance during processing"""

    def __init__(self):
        self.metrics: Dict[str, PerformanceMetrics] = {}
        self.process = psutil.Process()

    def start_monitoring(self, operation_name: str) -> str:
        """Start monitoring an operation"""
        monitor_id = f"{operation_name}_{int(time.time() * 1000)}"
        self.metrics[monitor_id] = PerformanceMetrics(
            start_time=time.time(),
            memory_usage_mb=self.process.memory_info().rss / 1024 / 1024,
            cpu_usage_percent=self.process.cpu_percent(),
        )
        return monitor_id

    def stop_monitoring(
        self, monitor_id: str, operations_completed: int = 1
    ) -> PerformanceMetrics:
        """Stop monitoring and return metrics"""
        if monitor_id not in self.metrics:
            raise ValueError(f"Monitor ID {monitor_id} not found")

        metrics = self.metrics[monitor_id]
        metrics.end_time = time.time()
        metrics.duration = metrics.end_time - metrics.start_time
        metrics.operations_completed = operations_completed

        if metrics.duration > 0:
            metrics.operations_per_second = operations_completed / metrics.duration

        metrics.memory_usage_mb = self.process.memory_info().rss / 1024 / 1024
        metrics.cpu_usage_percent = self.process.cpu_percent()

        return metrics

    def get_metrics(
        self, operation_name: Optional[str] = None
    ) -> List[PerformanceMetrics]:
        """Get metrics for operations"""
        if operation_name:
            return [
                m for mid, m in self.metrics.items() if mid.startswith(operation_name)
            ]
        return list(self.metrics.values())

    def print_summary(self, operation_name: Optional[str] = None):
        """Print performance summary"""
        metrics = self.get_metrics(operation_name)
        if not metrics:
            return

        total_duration = sum(m.duration for m in metrics if m.duration)
        total_operations = sum(m.operations_completed for m in metrics)
        avg_memory = sum(m.memory_usage_mb for m in metrics if m.memory_usage_mb) / len(
            metrics
        )

        print("\n" + "=" * 60)
        print("Performance Summary")
        print("=" * 60)
        print(f"Operations: {len(metrics)}")
        print(f"Total Duration: {total_duration:.2f}s")
        print(f"Total Operations: {total_operations}")
        print(
            f"Avg Operations/sec: {total_operations / total_duration:.2f}"
            if total_duration > 0
            else "N/A"
        )
        print(f"Avg Memory Usage: {avg_memory:.1f} MB")
        print("=" * 60)


# Global performance monitor
performance_monitor = PerformanceMonitor()


def monitor_performance(operation_name: Optional[str] = None):
    """Decorator to monitor function performance"""

    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        def sync_wrapper(*args, **kwargs):
            op_name = operation_name or func.__name__
            monitor_id = performance_monitor.start_monitoring(op_name)

            try:
                result = func(*args, **kwargs)
                performance_monitor.stop_monitoring(monitor_id, operations_completed=1)
                return result
            except Exception as e:
                if monitor_id in performance_monitor.metrics:
                    performance_monitor.metrics[monitor_id].operations_failed += 1
                raise

        @functools.wraps(func)
        async def async_wrapper(*args, **kwargs):
            op_name = operation_name or func.__name__
            monitor_id = performance_monitor.start_monitoring(op_name)

            try:
                result = await func(*args, **kwargs)
                performance_monitor.stop_monitoring(monitor_id, operations_completed=1)
                return result
            except Exception as e:
                if monitor_id in performance_monitor.metrics:
                    performance_monitor.metrics[monitor_id].operations_failed += 1
                raise

        # Return appropriate wrapper based on function type
        if asyncio.iscoroutinefunction(func):
            return async_wrapper
        else:
            return sync_wrapper

    return decorator


class AsyncProcessor:
    """Async processing utilities for CPU and I/O bound operations"""

    def __init__(self, max_workers: Optional[int] = None):
        self.max_workers = max_workers or min(32, (os.cpu_count() or 1) + 4)
        self.thread_executor = ThreadPoolExecutor(max_workers=self.max_workers)
        self.process_executor = ProcessPoolExecutor(
            max_workers=min(4, os.cpu_count() or 1)
        )

    async def run_cpu_bound(self, func: Callable, *args, **kwargs) -> Any:
        """Run CPU-bound function in process pool"""
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(self.process_executor, func, *args, **kwargs)

    async def run_io_bound(self, func: Callable, *args, **kwargs) -> Any:
        """Run I/O-bound function in thread pool"""
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(self.thread_executor, func, *args, **kwargs)

    async def process_batch(
        self,
        items: List[Any],
        processor: Callable[[Any], Any],
        batch_size: int = 4,
        use_processes: bool = False,
    ) -> List[Any]:
        """Process items in batches for better resource utilization"""
        results = []
        executor = self.process_executor if use_processes else self.thread_executor

        for i in range(0, len(items), batch_size):
            batch = items[i : i + batch_size]
            batch_tasks = []

            for item in batch:
                loop = asyncio.get_event_loop()
                task = loop.run_in_executor(executor, processor, item)
                batch_tasks.append(task)

            batch_results = await asyncio.gather(*batch_tasks, return_exceptions=True)

            # Handle exceptions
            for result in batch_results:
                if isinstance(result, Exception):
                    logger.error(f"Batch processing error: {result}")
                    results.append(None)
                else:
                    results.append(result)

        return results

    async def parallel_map(
        self,
        processor: Callable[[Any], Any],
        items: List[Any],
        max_concurrent: Optional[int] = None,
    ) -> List[Any]:
        """Map processor to items with controlled concurrency"""
        if max_concurrent is None:
            max_concurrent = self.max_workers

        semaphore = asyncio.Semaphore(max_concurrent)

        async def process_with_semaphore(item):
            async with semaphore:
                loop = asyncio.get_event_loop()
                return await loop.run_in_executor(self.thread_executor, processor, item)

        tasks = [process_with_semaphore(item) for item in items]
        return await asyncio.gather(*tasks, return_exceptions=True)

    def __del__(self):
        """Clean up executors"""
        self.thread_executor.shutdown(wait=True)
        self.process_executor.shutdown(wait=True)


class MemoryManager:
    """Manage memory usage during processing"""

    def __init__(self, max_memory_mb: float = 4096):
        self.max_memory_mb = max_memory_mb
        self.process = psutil.Process()

    def get_memory_usage(self) -> float:
        """Get current memory usage in MB"""
        return self.process.memory_info().rss / 1024 / 1024

    def check_memory_limit(self) -> bool:
        """Check if memory usage exceeds limit"""
        return self.get_memory_usage() > self.max_memory_mb

    def force_garbage_collection(self):
        """Force garbage collection and memory cleanup"""
        gc.collect()

        # Force memory cleanup for large arrays if numpy is available
        try:
            import numpy as np

            # Clear numpy caches if available
            if hasattr(np, "_clear_cache"):
                np._clear_cache()
        except (ImportError, AttributeError):
            pass

    async def wait_for_memory(self, target_mb: Optional[float] = None):
        """Wait until memory usage drops below target"""
        target_mb = target_mb or (self.max_memory_mb * 0.8)

        while self.get_memory_usage() > target_mb:
            self.force_garbage_collection()
            await asyncio.sleep(0.1)  # Brief pause

    def with_memory_management(self, func: Callable) -> Callable:
        """Decorator to add memory management to function"""

        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            # Check memory before
            if self.check_memory_limit():
                logger.warning(
                    f"High memory usage detected: {self.get_memory_usage():.1f} MB"
                )
                self.force_garbage_collection()

            try:
                result = func(*args, **kwargs)

                # Check memory after and cleanup if needed
                if self.check_memory_limit():
                    logger.warning(
                        f"High memory usage after operation: {self.get_memory_usage():.1f} MB"
                    )
                    self.force_garbage_collection()

                return result
            except MemoryError:
                logger.error("Memory error during operation, forcing cleanup")
                self.force_garbage_collection()
                raise

        return wrapper


# Global instances
async_processor = AsyncProcessor()
memory_manager = MemoryManager()


@monitor_performance("audio_file_operation")
async def async_file_copy(src: str, dst: str) -> bool:
    """Async file copy with progress monitoring"""
    try:
        await async_processor.run_io_bound(shutil.copy2, src, dst)
        return True
    except Exception as e:
        logger.error(f"File copy failed {src} -> {dst}: {e}")
        return False


@monitor_performance("audio_file_batch")
async def batch_file_copy(file_pairs: List[tuple]) -> Dict[str, bool]:
    """Batch copy multiple files concurrently"""
    results = {}

    tasks = []
    for src, dst in file_pairs:
        task = async_file_copy(src, dst)
        tasks.append((f"{src}->{dst}", task))

    for name, task in tasks:
        try:
            results[name] = await task
        except Exception as e:
            logger.error(f"Batch copy failed for {name}: {e}")
            results[name] = False

    return results


async def optimize_concurrent_processing(
    items: List[Any],
    processor: Callable,
    max_concurrent: Optional[int] = None,
    batch_size: int = 4,
) -> List[Any]:
    """Optimized concurrent processing with memory management"""

    # Split into batches for memory efficiency
    batches = [items[i : i + batch_size] for i in range(0, len(items), batch_size)]

    all_results = []
    for i, batch in enumerate(batches):
        # Wait for memory to be available before each batch
        await memory_manager.wait_for_memory()

        # Process batch
        batch_results = await async_processor.process_batch(
            batch,
            processor,
            batch_size=len(batch),
            use_processes=False,  # Use threads for better memory sharing
        )

        all_results.extend(batch_results)

        # Force cleanup after each batch
        memory_manager.force_garbage_collection()

        logger.debug(f"Processed batch {i + 1}/{len(batches)} ({len(batch)} items)")

    return all_results


def get_optimal_chunk_size(
    audio_duration: float, target_chunk_duration: float = 10.0
) -> int:
    """Calculate optimal chunk size for audio processing"""
    if audio_duration <= target_chunk_duration:
        return 1

    # Calculate number of chunks, rounding up to nearest power of 2
    num_chunks = int(audio_duration / target_chunk_duration)
    optimal_chunks = 1
    while optimal_chunks < num_chunks:
        optimal_chunks *= 2

    return optimal_chunks


def estimate_processing_time(
    file_size_mb: float, operation_type: str = "stem_separation"
) -> float:
    """Estimate processing time based on file size and operation"""

    # Processing rates (MB/s) for different operations
    processing_rates = {
        "stem_separation": 0.5,  # Very slow, ML-based
        "audio_analysis": 2.0,  # Medium, signal processing
        "format_conversion": 5.0,  # Fast, I/O bound
        "enhancement": 1.0,  # Slow, ML-based
        "file_copy": 20.0,  # Very fast, I/O bound
    }

    rate = processing_rates.get(operation_type, 1.0)
    return file_size_mb / rate
