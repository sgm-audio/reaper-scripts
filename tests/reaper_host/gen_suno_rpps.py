"""Generate real WAV, MP3, FLAC, OGG, and M4A Suno .rpp projects for live REAPER 7.x verification."""
import math
import shutil
import struct
import subprocess
import sys
import wave
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))

from suno_workflow_config_system import PathConfig
from suno_workflow_helper import SunoReaperWorkflow, WorkflowConfig


def write_sine_wav(path: Path, seconds: float = 2.0, rate: int = 44100, freq: float = 440.0) -> None:
    n = int(rate * seconds)
    frames = bytearray()
    for i in range(n):
        sample = int(0.4 * 32767 * math.sin(2.0 * math.pi * freq * i / rate))
        frames.extend(struct.pack("<hh", sample, sample))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(frames))


def encode_format(src_wav: Path, dst: Path, fmt: str) -> None:
    if fmt == "wav":
        shutil.copy2(src_wav, dst)
        return
    codec_args = {
        "mp3": ["-c:a", "libmp3lame", "-b:a", "192k"],
        "flac": ["-c:a", "flac"],
        "ogg": ["-c:a", "libvorbis", "-q:a", "4"],
        "m4a": ["-c:a", "aac", "-b:a", "192k"],
    }[fmt]
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-i", str(src_wav), *codec_args, str(dst)],
        check=True,
    )


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: gen_suno_rpps.py <output_dir>", file=sys.stderr)
        return 2
    out_root = Path(sys.argv[1]).resolve()
    out_root.mkdir(parents=True, exist_ok=True)
    master_wav = out_root / "_master.wav"
    write_sine_wav(master_wav, seconds=2.0, rate=44100, freq=440.0)

    stem_freqs = {"vocals": 523.25, "drums": 110.0, "bass": 82.41, "other": 329.63}
    wf = SunoReaperWorkflow(config=WorkflowConfig(paths=PathConfig(output_dir=str(out_root))))

    for fmt in ("wav", "mp3", "flac", "ogg", "m4a"):
        proj_dir = out_root / f"suno_{fmt}"
        stems_dir = proj_dir / "stems"
        stems_dir.mkdir(parents=True, exist_ok=True)
        orig_file = proj_dir / f"original_mix.{fmt}"
        encode_format(master_wav, orig_file, fmt)

        stem_paths = {}
        for stem_name, freq in stem_freqs.items():
            stem_file = stems_dir / f"{stem_name}.wav"
            write_sine_wav(stem_file, seconds=2.0, rate=44100, freq=freq)
            stem_paths[stem_name] = str(stem_file)

        rpp_path = wf._create_reaper_project(
            project_dir=str(proj_dir),
            project_name=f"suno_{fmt}",
            stem_paths=stem_paths,
            original_file=str(orig_file),
            auto_import=True,
        )
        print(f"GENERATED {fmt}: {rpp_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
