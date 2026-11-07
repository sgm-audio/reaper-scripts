"""Import a Suno audio file and its separated stems into a REAPER project."""

import argparse
import copy
import logging
import logging.config
import os
from pathlib import Path
import shutil
import sys
from dataclasses import dataclass
from typing import Dict, Optional
import uuid
import wave

try:
    import soundfile as sf
except ImportError:
    sf = None

# Allow the script to be launched directly from any working directory.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    from yourmt3_stem_separator import YourMT3StemSeparator
except ImportError:
    # Optional dependency: only required when stem separation is enabled.
    YourMT3StemSeparator = None

from suno_workflow_config_system import (
    WorkflowConfig as BaseWorkflowConfig,
    WorkflowResult,
    LOGGING_CONFIG,
    get_config_from_env,
    validate_config,
)

logger = logging.getLogger(__name__)


@dataclass
class WorkflowConfig(BaseWorkflowConfig):
    """Extended configuration for Suno workflow processing."""

    template_path: Optional[str] = None


class SunoReaperWorkflow:
    """Manage stem separation and REAPER project generation for one input file."""

    def __init__(
        self,
        config: Optional[BaseWorkflowConfig] = None,
        reaper_project_path: Optional[str] = None,
        template_path: Optional[str] = None,
    ):
        if config is None:
            config = get_config_from_env()

        if not isinstance(config, WorkflowConfig):
            # Preserve every base option when extending the configuration.
            config = WorkflowConfig(
                paths=config.paths,
                audio=config.audio,
                models=config.models,
                auto_import=config.auto_import,
                create_stems_dir=config.create_stems_dir,
                copy_original=config.copy_original,
                generate_instructions=config.generate_instructions,
                enable_semas=config.enable_semas,
                enhancement_profile=config.enhancement_profile,
                target_format=config.target_format,
                target_daw=config.target_daw,
                template_path=template_path,
            )
        elif template_path:
            config.template_path = template_path

        self.config = config
        # Reserved for a future live REAPER connection; project generation does not
        # require REAPER to be running.
        self.reaper_project_path = reaper_project_path

        issues = validate_config(self.config)
        for issue in issues:
            logger.warning("Configuration issue: %s", issue)

    def process_suno_track(
        self,
        suno_audio_file: str,
        project_name: Optional[str] = None,
        auto_import: Optional[bool] = None,
    ) -> WorkflowResult:
        """Separate *suno_audio_file* and create a project without raising errors.

        Failures are returned in ``WorkflowResult`` so API and CLI callers can use
        the same error path. By default the fallback project contains media items;
        pass ``auto_import=False`` to create empty tracks and manual instructions.
        """
        try:
            self._validate_input_file(suno_audio_file)
            project_name = self._generate_project_name(suno_audio_file, project_name)
            project_dir = self._setup_project_directory(suno_audio_file, project_name)
            should_auto_import = (
                self.config.auto_import if auto_import is None else auto_import
            )

            logger.info("Processing Suno track: %s", suno_audio_file)
            logger.info("Project name: %s", project_name)

            stem_paths = self._separate_stems(suno_audio_file, project_dir)
            original_copy = (
                self._copy_original_file(suno_audio_file, project_dir)
                if self.config.copy_original
                else None
            )
            project_file = self._create_reaper_project(
                project_dir,
                project_name,
                stem_paths,
                original_copy,
                auto_import=should_auto_import,
            )
            instructions_file = (
                self._generate_instructions(
                    project_dir,
                    project_file,
                    stem_paths,
                    original_copy,
                    auto_import=should_auto_import and not self._using_custom_template(),
                )
                if self.config.generate_instructions
                else ""
            )

            result = WorkflowResult(
                project_dir=project_dir,
                project_file=project_file,
                stem_paths=stem_paths,
                original_file=original_copy,
                instructions_file=instructions_file,
            )
            self._print_summary(result)
            return result
        except Exception as exc:
            logger.error("Workflow failed: %s", exc)
            return WorkflowResult(
                project_dir="",
                project_file="",
                stem_paths={},
                original_file=None,
                instructions_file="",
                success=False,
                error_message=str(exc),
            )

    def _validate_input_file(self, file_path: str) -> None:
        if not os.path.isfile(file_path):
            raise FileNotFoundError(f"Audio file not found: {file_path}")
        if not os.access(file_path, os.R_OK):
            raise PermissionError(f"Cannot read audio file: {file_path}")
        suffix = Path(file_path).suffix.lower()
        if suffix not in self.config.paths.audio_extensions:
            raise ValueError(f"Unsupported audio format: {suffix or '(none)'}")

    def _generate_project_name(
        self, audio_file: str, project_name: Optional[str]
    ) -> str:
        name = project_name.strip() if project_name else f"{Path(audio_file).stem}_reaper_project"
        if not name or name in {".", ".."} or any(c in name for c in ("/", "\\", "\0")):
            raise ValueError("Project name must be a non-empty folder name, not a path")
        return name

    def _setup_project_directory(self, audio_file: str, project_name: str) -> str:
        output_root = self.config.paths.output_dir
        if output_root:
            base_dir = os.path.abspath(os.path.expanduser(output_root))
        else:
            base_dir = os.path.dirname(os.path.abspath(audio_file))
        project_dir = os.path.join(base_dir, project_name)

        # Never silently overwrite an existing project or its media.
        if os.path.isdir(project_dir) and os.listdir(project_dir):
            raise FileExistsError(
                f"Project directory is not empty: {project_dir}. "
                "Choose another project name or output directory."
            )
        if os.path.exists(project_dir) and not os.path.isdir(project_dir):
            raise FileExistsError(f"Project path is an existing file: {project_dir}")
        os.makedirs(project_dir, exist_ok=True)
        return project_dir

    def _separate_stems(self, audio_file: str, project_dir: str) -> Dict[str, str]:
        logger.info("Step 1: separating stems with the Demucs backend")
        stems_dir = (
            os.path.join(project_dir, "stems")
            if self.config.create_stems_dir
            else project_dir
        )
        os.makedirs(stems_dir, exist_ok=True)
        if YourMT3StemSeparator is None:
            raise RuntimeError(
                "The bundled stem separator could not be imported. Reinstall "
                "the package and its core requirements, then install the "
                "'.[stem-separation]' extra for real Demucs execution."
            )

        separated = YourMT3StemSeparator(output_dir=stems_dir).separate(audio_file)
        if not isinstance(separated, dict) or not separated:
            raise RuntimeError("Stem separator returned no stems")

        stem_paths = {}
        for name, path in separated.items():
            if not isinstance(path, (str, os.PathLike)):
                raise RuntimeError(f"Invalid path returned for stem '{name}'")
            resolved = os.path.abspath(os.path.join(stems_dir, os.fspath(path)))
            if not os.path.isfile(resolved):
                raise FileNotFoundError(f"Separated stem was not created: {resolved}")
            stem_paths[str(name)] = resolved
        return stem_paths

    def _copy_original_file(self, audio_file: str, project_dir: str) -> str:
        logger.info("Step 2: copying original file")
        suffix = Path(audio_file).suffix.lower()
        original_copy = os.path.join(project_dir, f"original_mix{suffix}")
        if os.path.abspath(audio_file) != os.path.abspath(original_copy):
            shutil.copy2(audio_file, original_copy)
        logger.info("Original saved to: %s", original_copy)
        return original_copy

    def _using_custom_template(self) -> bool:
        return bool(self.config.template_path)

    def _create_reaper_project(
        self,
        project_dir: str,
        project_name: str,
        stem_paths: Dict[str, str],
        original_file: Optional[str],
        auto_import: bool = True,
    ) -> str:
        project_file = os.path.join(project_dir, f"{project_name}.rpp")
        template_path = self.config.template_path
        if template_path:
            if not os.path.isfile(template_path):
                raise FileNotFoundError(f"Template not found: {template_path}")
            # A template is copied verbatim. Media is only injected into the
            # built-in generator, whose structure is known and safe to write.
            shutil.copy2(template_path, project_file)
            logger.info("Project copied from template: %s", project_file)
        else:
            self._create_basic_project(
                project_file, stem_paths, original_file, auto_import=auto_import
            )
        return project_file

    @staticmethod
    def _rpp_string(value: str) -> str:
        return os.fspath(value).replace("\\", "/").replace('"', "'").replace("\n", " ")

    @staticmethod
    def _media_duration(path: str) -> float:
        if sf is not None:
            try:
                info = sf.info(path)
                if info.samplerate > 0:
                    return float(info.frames) / info.samplerate
            except (RuntimeError, OSError):
                pass
        try:
            with wave.open(path, "rb") as audio:
                if audio.getframerate() > 0:
                    return audio.getnframes() / audio.getframerate()
        except (wave.Error, EOFError, OSError):
            pass
        return 0.0

    def _create_basic_project(
        self,
        project_file: str,
        stem_paths: Dict[str, str],
        original_file: Optional[str],
        auto_import: bool = True,
    ):
        """Write a self-contained RPP with tracks and optional media items."""
        tracks = [
            ("vocals", "Vocals"),
            ("drums", "Drums"),
            ("bass", "Bass"),
            ("other", "Other (Instruments)"),
            ("original", "Original Mix (Reference)"),
        ]
        media = dict(stem_paths)
        if original_file:
            media["original"] = original_file
        source_types = {
            ".wav": "WAVE",
            ".aif": "WAVE",
            ".aiff": "WAVE",
            ".mp3": "MP3",
            ".flac": "FLAC",
            ".ogg": "OGG",
            ".m4a": "VIDEO",
        }
        media_source_types = {}
        for key, path in media.items():
            suffix = Path(path).suffix.lower()
            if suffix not in source_types:
                raise ValueError(f"Unsupported generated media format: {path}")
            media_source_types[key] = source_types[suffix]
        durations = {key: self._media_duration(path) for key, path in media.items()}
        fallback_duration = max(durations.values(), default=0.0)
        if auto_import and media and fallback_duration <= 0:
            raise RuntimeError("Could not determine media duration for the REAPER project")

        with open(project_file, "w", encoding="utf-8", newline="\n") as project:
            project.write('<REAPER_PROJECT 0.1 "7.0" 0\n')
            project.write("  TEMPO 120 4 4\n")
            project.write(f"  SAMPLERATE {self.config.audio.sample_rate} 0 0\n")
            for key, track_name in tracks:
                project.write(f"  <TRACK {{{uuid.uuid4()}}}\n")
                project.write(f'    NAME "{self._rpp_string(track_name)}"\n')
                if key == "original":
                    project.write("    B_MUTE 1\n")
                path = media.get(key)
                if auto_import and path:
                    relative = os.path.relpath(path, os.path.dirname(project_file))
                    source_type = media_source_types[key]
                    # All stems and the original represent the same song, so a
                    # known sibling duration is a safe fallback for codecs that
                    # libsndfile cannot inspect on this system.
                    duration = durations.get(key, 0.0) or fallback_duration
                    project.write("    <ITEM\n")
                    project.write("      POSITION 0\n")
                    project.write(f"      LENGTH {duration:.9f}\n")
                    project.write(f"      <SOURCE {source_type}\n")
                    project.write(f'        FILE "{self._rpp_string(relative)}"\n')
                    project.write("      >\n")
                    project.write("    >\n")
                project.write("  >\n")
            project.write(">\n")
        logger.info("Basic project file created: %s", project_file)

    def _generate_instructions(
        self,
        project_dir: str,
        project_file: str,
        stem_paths: Dict[str, str],
        original_file: Optional[str] = None,
        auto_import: bool = False,
    ) -> str:
        instructions_file = os.path.join(project_dir, "IMPORT_INSTRUCTIONS.md")
        track_mapping = {
            "vocals": "Track 1: Vocals",
            "drums": "Track 2: Drums",
            "bass": "Track 3: Bass",
            "other": "Track 4: Other (Instruments)",
        }

        def relative(path):
            try:
                return os.path.relpath(path, project_dir)
            except ValueError:  # Different Windows drives.
                return os.fspath(path)

        with open(instructions_file, "w", encoding="utf-8") as instructions:
            instructions.write("# Suno Track Import Instructions\n\n## Quick Start\n\n")
            instructions.write(f"1. Open the REAPER project: `{project_file}`\n")
            if auto_import:
                instructions.write(
                    "2. Stems and the copied original are already placed on tracks.\n"
                    "3. Unmute the original only for A/B reference.\n"
                )
            else:
                instructions.write("2. Import stems to the corresponding tracks:\n\n")
                for stem_name, track_name in track_mapping.items():
                    if stem_name in stem_paths:
                        instructions.write(
                            f"   - **{track_name}**: `{relative(stem_paths[stem_name])}`\n"
                        )
                if original_file:
                    instructions.write(
                        f"\n3. Import original mix to Track 5 (reference): "
                        f"`{relative(original_file)}`\n"
                    )

            instructions.write("\n## Stem Files\n\n")
            for stem_name, stem_path in stem_paths.items():
                instructions.write(f"- **{stem_name.capitalize()}**: `{relative(stem_path)}`\n")
            instructions.write("\n## Original Mix\n\n")
            instructions.write(
                f"- **Original**: `{relative(original_file)}`\n"
                if original_file
                else "- **Original**: Not copied\n"
            )
            instructions.write(
                "\n## Mixing Tips\n\n"
                "- Keep the original reference muted while working on stems.\n"
                "- Solo individual stems to check separation quality.\n"
                "- Align all manually imported items at position 0:00.\n"
            )
        logger.info("Instructions saved to: %s", instructions_file)
        return instructions_file

    def _print_summary(self, result: WorkflowResult):
        if not result.success:
            print(f"\nERROR: {result.error_message}")
            return
        print("\n" + "=" * 80)
        print("WORKFLOW COMPLETE".center(80))
        print("=" * 80)
        print(f"Project Directory: {result.project_dir}")
        print(f"Project File:      {result.project_file}")
        print("Stems Generated:")
        for stem_name, stem_path in result.stem_paths.items():
            print(f"  {stem_name:12s} -> {os.path.basename(stem_path)}")
        if result.instructions_file:
            print(f"Instructions:      {result.instructions_file}")
        print("=" * 80 + "\n")


def main() -> int:
    logging_config = copy.deepcopy(LOGGING_CONFIG)
    log_file = os.getenv("SUNO_LOG_FILE")
    if log_file:
        logging_config["handlers"]["file"]["filename"] = os.path.abspath(
            os.path.expanduser(log_file)
        )
    else:
        # A library CLI must not fail just because its caller's cwd is read-only.
        logging_config["loggers"][""]["handlers"] = ["console"]
        del logging_config["handlers"]["file"]
    logging.config.dictConfig(logging_config)
    parser = argparse.ArgumentParser(
        description="Separate a Suno track and generate a REAPER project"
    )
    parser.add_argument("input", help="Input Suno audio file")
    parser.add_argument("-n", "--name", help="Project name")
    parser.add_argument("-t", "--template", help="Custom REAPER project to copy as-is")
    parser.add_argument(
        "--output-dir",
        help="Root directory in which to create the project folder (or SUNO_OUTPUT_DIR)",
    )
    parser.add_argument(
        "--no-auto-import",
        action="store_true",
        help="Create empty tracks in the fallback project instead of adding media items",
    )
    args = parser.parse_args()

    if args.output_dir:
        os.environ["SUNO_OUTPUT_DIR"] = args.output_dir
    workflow = SunoReaperWorkflow(template_path=args.template)
    result = workflow.process_suno_track(
        suno_audio_file=args.input,
        project_name=args.name,
        auto_import=not args.no_auto_import,
    )
    if not result.success:
        print(f"Error: {result.error_message}", file=sys.stderr)
        return 1
    print("Success! Project ready to use.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
