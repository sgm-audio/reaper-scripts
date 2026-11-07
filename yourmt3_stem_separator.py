"""Stem-separation adapter with lightweight AI-audio preprocessing.

The public ``YourMT3StemSeparator`` name is retained for compatibility. Model
execution uses Demucs through its CLI; YourMT3 itself is a transcription model,
not a stem-separation engine. Heavy ML dependencies are needed only by
:meth:`YourMT3StemSeparator.separate`.
"""

import argparse
import importlib.util
import logging
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Dict, Optional, Sequence

import numpy as np
import soundfile as sf

try:
    import torch
except ImportError:
    class _UnavailableCuda:
        @staticmethod
        def is_available():
            return False

    class _UnavailableTorch:
        cuda = _UnavailableCuda()
        __version__ = "not installed"

    torch = _UnavailableTorch()

logger = logging.getLogger(__name__)


class YourMT3StemSeparator:
    """Run a Demucs backend and apply bounded, conservative preprocessing."""

    STEMS = ("vocals", "drums", "bass", "other")

    def __init__(
        self,
        output_dir: str = "stems",
        model_name: str = "htdemucs",
        device: Optional[str] = None,
        timeout_seconds: int = 1800,
    ):
        self.output_dir = os.fspath(output_dir)
        self.model_name = model_name
        self.device = self._select_device(device)
        self.timeout_seconds = timeout_seconds
        os.makedirs(self.output_dir, exist_ok=True)
        if timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")

    @staticmethod
    def _select_device(device: Optional[str]) -> str:
        selected = device or "auto"
        if selected not in {"auto", "cpu", "cuda"}:
            raise ValueError("device must be 'auto', 'cpu', or 'cuda'")
        if selected == "auto":
            return "cuda" if torch.cuda.is_available() else "cpu"
        if selected == "cuda" and not torch.cuda.is_available():
            logger.warning("CUDA was requested but is unavailable; using CPU")
            return "cpu"
        return selected

    def _load_audio(self, file_path: str):
        """Load audio as ``(channels, frames)`` float32, duplicating mono."""
        audio, sample_rate = sf.read(file_path, always_2d=True, dtype="float32")
        audio = audio.T
        if audio.shape[0] == 1:
            audio = np.repeat(audio, 2, axis=0)
        if not np.isfinite(audio).all():
            raise ValueError(f"Audio contains NaN or infinite samples: {file_path}")
        return np.ascontiguousarray(audio), int(sample_rate)

    def _apply_highpass(self, audio, sample_rate: int, cutoff_hz: float = 20.0):
        """Apply a stable one-pole high-pass filter independently per channel."""
        if sample_rate <= 0 or not 0 < cutoff_hz < sample_rate / 2:
            raise ValueError("High-pass cutoff must be between zero and Nyquist")
        samples = np.asarray(audio, dtype=np.float32)
        if samples.ndim != 2:
            raise ValueError("Expected audio shaped (channels, frames)")
        if samples.shape[1] == 0:
            return samples.copy()
        dt = 1.0 / sample_rate
        rc = 1.0 / (2.0 * math.pi * cutoff_hz)
        alpha = rc / (rc + dt)
        filtered = np.empty_like(samples)
        filtered[:, 0] = samples[:, 0]
        # Vectorizing over channels keeps memory bounded to the input/output.
        for index in range(1, samples.shape[1]):
            filtered[:, index] = alpha * (
                filtered[:, index - 1] + samples[:, index] - samples[:, index - 1]
            )
        return filtered

    def _reduce_spectral_artifacts(self, audio, sample_rate: int):
        """Attenuate only quiet high-frequency bins with overlap/add restoration.

        This is deliberately a soft spectral floor, not a claim of removing all
        generative artifacts. Frame and hop sizes bound memory for long tracks.
        """
        samples = np.asarray(audio, dtype=np.float32)
        if samples.ndim != 2:
            raise ValueError("Expected audio shaped (channels, frames)")
        if sample_rate <= 0:
            raise ValueError("sample_rate must be positive")
        if samples.shape[1] == 0:
            return samples.copy()
        frame_size = 2048
        hop_size = frame_size // 2
        window = np.hanning(frame_size).astype(np.float32)
        frequencies = np.fft.rfftfreq(frame_size, 1.0 / sample_rate)
        high_band = frequencies >= 8000
        output = np.zeros_like(samples)
        weights = np.zeros(samples.shape[1], dtype=np.float32)

        for start in range(0, samples.shape[1], hop_size):
            end = min(start + frame_size, samples.shape[1])
            valid = end - start
            block = np.zeros((samples.shape[0], frame_size), dtype=np.float32)
            block[:, :valid] = samples[:, start:end]
            for channel in range(samples.shape[0]):
                spectrum = np.fft.rfft(block[channel] * window)
                magnitudes = np.abs(spectrum)
                if np.any(high_band):
                    noise = float(np.median(magnitudes[high_band]))
                    gains = np.ones_like(magnitudes)
                    quiet = high_band & (magnitudes < noise)
                    # Never remove a bin completely; musical content is preserved.
                    gains[quiet] = 0.5
                    spectrum *= gains
                restored = np.fft.irfft(spectrum, n=frame_size).astype(np.float32)
                output[channel, start:end] += restored[:valid] * window[:valid]
            weights[start:end] += window[:valid] ** 2

        output /= np.maximum(weights, 1e-8)
        return np.nan_to_num(output, copy=False)

    def _preprocess_ai_audio(self, audio, sample_rate: int):
        """Remove DC/rumble and quiet HF artifacts without normalizing quiet mixes."""
        samples = np.asarray(audio, dtype=np.float32)
        if samples.ndim != 2:
            raise ValueError("Expected audio shaped (channels, frames)")
        if samples.size == 0:
            return samples.copy()
        samples = samples - np.mean(samples, axis=1, keepdims=True)
        samples = self._apply_highpass(samples, sample_rate, 20.0)
        samples = self._reduce_spectral_artifacts(samples, sample_rate)
        peak = float(np.max(np.abs(samples))) if samples.size else 0.0
        if peak > 0.99:
            samples *= 0.99 / peak
        return samples.astype(np.float32, copy=False)

    def get_model_info(self) -> Dict[str, object]:
        return {
            "model_name": self.model_name,
            "backend": "demucs",
            "backend_available": self._demucs_available(),
            "device": self.device,
            "ai_audio_optimized": True,
            "torch_version": getattr(torch, "__version__", "unknown"),
        }

    @staticmethod
    def _demucs_available() -> bool:
        return importlib.util.find_spec("demucs") is not None

    def separate(self, audio_file: str, stems: Optional[Sequence[str]] = None) -> Dict[str, str]:
        """Separate *audio_file* and return canonical stem paths.

        Raises an actionable ``RuntimeError`` when the optional Demucs backend is
        not installed. No passthrough audio is mislabeled as separated stems.
        """
        input_path = Path(audio_file).expanduser().resolve()
        if not input_path.is_file():
            raise FileNotFoundError(f"Audio file not found: {input_path}")
        selected = tuple(stems or self.STEMS)
        if not selected or any(stem not in self.STEMS for stem in selected):
            raise ValueError(f"stems must be selected from {', '.join(self.STEMS)}")
        if not self._demucs_available():
            raise RuntimeError(
                "Demucs is not installed. Install the ML backend with "
                "`python -m pip install -e .[stem-separation]` (or install demucs, "
                "torch, and torchaudio), then run the separation again."
            )

        with tempfile.TemporaryDirectory(prefix="demucs-", dir=self.output_dir) as temp_dir:
            command = [
                sys.executable, "-m", "demucs", "-n", self.model_name,
                "-d", self.device, "-o", temp_dir, str(input_path),
            ]
            try:
                completed = subprocess.run(
                    command, capture_output=True, text=True,
                    timeout=self.timeout_seconds, check=False,
                )
            except subprocess.TimeoutExpired as exc:
                raise RuntimeError(
                    f"Demucs timed out after {self.timeout_seconds} seconds"
                ) from exc
            if completed.returncode != 0:
                details = (completed.stderr or completed.stdout).strip()
                raise RuntimeError(f"Demucs failed ({completed.returncode}): {details}")

            candidates = list(Path(temp_dir).rglob(f"{input_path.stem}/*.wav"))
            result = {}
            for stem in selected:
                matches = [path for path in candidates if path.stem == stem]
                if not matches:
                    matches = list(Path(temp_dir).rglob(f"{stem}.wav"))
                if not matches:
                    raise RuntimeError(f"Demucs did not produce the '{stem}' stem")
                audio, sample_rate = self._load_audio(str(matches[0]))
                processed = self._preprocess_ai_audio(audio, sample_rate)
                destination = Path(self.output_dir) / f"{stem}.wav"
                sf.write(destination, processed.T, sample_rate, subtype="FLOAT")
                result[stem] = str(destination.resolve())
        return result


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="Input audio file")
    parser.add_argument("-o", "--output", default="stems", help="Output directory")
    parser.add_argument("--model", default="htdemucs", help="Demucs model name")
    parser.add_argument("--device", choices=("auto", "cpu", "cuda"), default="auto")
    parser.add_argument("-s", "--stems", nargs="+", choices=YourMT3StemSeparator.STEMS)
    parser.add_argument("--timeout", type=int, default=1800)
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO)
    try:
        separator = YourMT3StemSeparator(
            output_dir=args.output, model_name=args.model,
            device=args.device, timeout_seconds=args.timeout,
        )
        paths = separator.separate(args.input, stems=args.stems)
    except (OSError, RuntimeError, ValueError) as exc:
        parser.exit(1, f"error: {exc}\n")
    for name, path in paths.items():
        print(f"{name}: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
