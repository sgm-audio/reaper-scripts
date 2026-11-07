"""
Constants and configuration for Suno Reaper Workflow System
Centralized configuration management for all components
"""

import math
import os
from typing import Dict, List, Optional
from dataclasses import dataclass, field
from enum import Enum


class DeviceType(Enum):
    """Supported processing device types"""

    AUTO = "auto"
    CPU = "cpu"
    CUDA = "cuda"


class EnhancementProfile(Enum):
    """Audio enhancement profiles"""

    MINIMAL = "minimal"
    BALANCED = "balanced"
    AGGRESSIVE = "aggressive"


class TargetFormat(Enum):
    """Target audio formats"""

    STREAMING = "streaming"
    CD = "cd"
    VINYL = "vinyl"
    BROADCAST = "broadcast"


class TargetDAW(Enum):
    """Supported DAW targets"""

    REAPER = "reaper"
    ABLETON = "ableton"
    LOGIC = "logic"


@dataclass
class AudioConfig:
    """Audio processing configuration"""

    sample_rate: int = 44100
    bit_depth: int = 16
    channels: int = 2
    chunk_size: float = 10.0  # seconds
    overlap_ratio: float = 0.5

    # AI-specific processing
    apply_spectral_cleaning: bool = True
    enhance_transients: bool = True
    artifact_reduction: bool = True

    # Normalization
    target_level: float = -14.0  # LUFS for streaming
    headroom_db: float = -1.0


@dataclass
class ModelConfig:
    """Model configuration"""

    demucs_model: str = "htdemucs"
    use_transformer: bool = True
    device: DeviceType = DeviceType.AUTO

    # Fallback models
    enable_spleeter_fallback: bool = True
    spleeter_model: str = "spleeter:4stems"


@dataclass
class PathConfig:
    """Path configuration"""

    # Default directories
    output_dir: Optional[str] = None
    templates_dir: Optional[str] = None
    temp_dir: Optional[str] = None

    # File extensions
    audio_extensions: List[str] = field(
        default_factory=lambda: [".wav", ".mp3", ".flac", ".m4a", ".ogg"]
    )
    project_extensions: List[str] = field(
        default_factory=lambda: [".rpp", ".als", ".logicx"]
    )

    def __post_init__(self):
        if self.audio_extensions is None:
            self.audio_extensions = [".wav", ".mp3", ".flac", ".m4a", ".ogg"]
        if self.project_extensions is None:
            self.project_extensions = [".rpp", ".als", ".logicx"]


@dataclass
class WorkflowConfig:
    """Main workflow configuration"""

    # Paths
    paths: PathConfig = field(default_factory=PathConfig)

    # Audio processing
    audio: AudioConfig = field(default_factory=AudioConfig)

    # Models
    models: ModelConfig = field(default_factory=ModelConfig)

    # Workflow options
    auto_import: bool = True
    create_stems_dir: bool = True
    copy_original: bool = True
    generate_instructions: bool = True

    # SEMAS integration
    enable_semas: bool = True
    enhancement_profile: EnhancementProfile = EnhancementProfile.BALANCED
    target_format: TargetFormat = TargetFormat.STREAMING
    target_daw: TargetDAW = TargetDAW.REAPER

    def __post_init__(self):
        if self.paths is None:
            self.paths = PathConfig()
        if self.audio is None:
            self.audio = AudioConfig()
        if self.models is None:
            self.models = ModelConfig()


# Default configuration instance
DEFAULT_CONFIG = WorkflowConfig()


# Logging configuration
LOGGING_CONFIG = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "standard": {"format": "%(asctime)s [%(levelname)s] %(name)s: %(message)s"},
        "detailed": {
            "format": "%(asctime)s [%(levelname)s] %(name)s:%(lineno)d: %(message)s"
        },
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "level": "INFO",
            "formatter": "standard",
            "stream": "ext://sys.stdout",
        },
        "file": {
            "class": "logging.FileHandler",
            "level": "DEBUG",
            "formatter": "detailed",
            "filename": "suno_workflow.log",
            "mode": "a",
        },
    },
    "loggers": {
        "": {"handlers": ["console", "file"], "level": "DEBUG", "propagate": False}
    },
}


# Stem mapping for different models
STEM_MAPPINGS = {
    "demucs": ["drums", "bass", "other", "vocals"],
    "spleeter": ["vocals", "drums", "bass", "other"],
    "custom": ["vocals", "drums", "bass", "other", "piano", "guitar"],
}


# Default track mappings for Reaper projects
REAPER_TRACK_MAPPING = {
    "vocals": "Track 1: Vocals",
    "drums": "Track 2: Drums",
    "bass": "Track 3: Bass",
    "other": "Track 4: Other (Instruments)",
    "original": "Track 5: Original Mix (Reference)",
}


# Processing timeouts (seconds)
TIMEOUTS = {
    "stem_separation": 300,  # 5 minutes
    "semas_processing": 600,  # 10 minutes
    "file_operations": 30,  # 30 seconds
    "model_loading": 60,  # 1 minute
}


# Error messages
ERROR_MESSAGES = {
    "file_not_found": "File not found: {file_path}",
    "permission_denied": "Permission denied accessing: {file_path}",
    "model_not_loaded": "Model failed to load: {model_name}",
    "separation_failed": "Stem separation failed: {error}",
    "invalid_format": "Unsupported audio format: {format}",
    "disk_space": "Insufficient disk space in: {directory}",
    "timeout": "Operation timed out after {timeout} seconds",
}


@dataclass
class WorkflowResult:
    """Result of workflow processing"""

    project_dir: str
    project_file: str
    stem_paths: Dict[str, str]
    original_file: Optional[str]
    instructions_file: str
    success: bool = True
    error_message: Optional[str] = None


def get_config_from_env() -> WorkflowConfig:
    """Create configuration from environment variables"""
    config = WorkflowConfig()

    # Override with environment variables if present
    if os.getenv("SUNO_OUTPUT_DIR"):
        config.paths.output_dir = os.getenv("SUNO_OUTPUT_DIR")

    if os.getenv("SUNO_DEVICE"):
        config.models.device = DeviceType(os.getenv("SUNO_DEVICE"))

    if os.getenv("SUNO_SAMPLE_RATE"):
        config.audio.sample_rate = int(os.getenv("SUNO_SAMPLE_RATE"))

    if os.getenv("SUNO_ENHANCEMENT_PROFILE"):
        config.enhancement_profile = EnhancementProfile(
            os.getenv("SUNO_ENHANCEMENT_PROFILE")
        )

    return config


def validate_config(config: WorkflowConfig) -> List[str]:
    """Validate configuration and return list of issues"""
    issues = []

    # Check paths. Relative paths have a valid implicit parent (the cwd).
    if config.paths.output_dir:
        output_path = os.path.abspath(os.path.expanduser(config.paths.output_dir))
        if os.path.exists(output_path) and not os.path.isdir(output_path):
            issues.append(f"Output path is not a directory: {output_path}")
        elif not os.path.isdir(os.path.dirname(output_path)):
            issues.append(
                f"Output directory parent does not exist: {os.path.dirname(output_path)}"
            )

    # Check audio settings
    if config.audio.sample_rate not in [44100, 48000, 96000]:
        issues.append(f"Unsupported sample rate: {config.audio.sample_rate}")

    if config.audio.bit_depth not in [16, 24, 32]:
        issues.append(f"Unsupported bit depth: {config.audio.bit_depth}")

    if config.audio.channels < 1:
        issues.append("Channel count must be at least 1")
    if not math.isfinite(config.audio.chunk_size) or config.audio.chunk_size <= 0:
        issues.append("Chunk size must be a positive, finite number")
    if not 0 <= config.audio.overlap_ratio < 1:
        issues.append("Overlap ratio must be in the range [0, 1)")

    # Check model settings
    if config.models.demucs_model not in ["htdemucs", "mdx", "mdx_extra", "mdx_q"]:
        issues.append(f"Unknown demucs model: {config.models.demucs_model}")

    return issues
