"""
Suno Track Workflow Helper
Automates the process of importing Suno tracks into Reaper with stem separation
"""

import os
import sys
import argparse
import logging
import logging.config
from pathlib import Path
from typing import Optional, Dict, Any, Union
import shutil
from dataclasses import dataclass

# Add current directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from yourmt3_stem_separator import YourMT3StemSeparator
from config import (
    WorkflowConfig as BaseWorkflowConfig,
    WorkflowResult,
    PathConfig,
    AudioConfig,
    ModelConfig,
    DEFAULT_CONFIG,
    LOGGING_CONFIG,
    ERROR_MESSAGES,
    get_config_from_env,
    validate_config,
)

# Apply logging configuration
logging.config.dictConfig(LOGGING_CONFIG)
logger = logging.getLogger(__name__)


@dataclass
class WorkflowConfig(BaseWorkflowConfig):
    """Extended configuration for Suno workflow processing"""

    template_path: Optional[str] = None

    def __post_init__(self):
        super().__post_init__()
        if self.template_path is None:
            self.template_path = os.path.join(
                os.path.dirname(__file__), "templates", "suno-track-import-template.rpp"
            )


class SunoReaperWorkflow:
    """Manages the complete workflow from Suno track to Reaper project"""

    def __init__(
        self,
        config: Optional[BaseWorkflowConfig] = None,
        reaper_project_path: Optional[str] = None,
        template_path: Optional[str] = None,
    ):
        # Create configuration with precedence: config > env > defaults
        if config is None:
            config = get_config_from_env()

        # Convert to WorkflowConfig if needed
        if not isinstance(config, WorkflowConfig):
            config = WorkflowConfig(
                paths=config.paths,
                audio=config.audio,
                models=config.models,
                auto_import=config.auto_import,
                create_stems_dir=config.create_stems_dir,
                copy_original=config.copy_original,
                enable_semas=config.enable_semas,
                enhancement_profile=config.enhancement_profile,
                target_format=config.target_format,
                target_daw=config.target_daw,
                template_path=template_path,
            )
        elif template_path:
            config.template_path = template_path

        self.config = config
        self.reaper_project_path = reaper_project_path

        # Validate configuration
        issues = validate_config(self.config)
        if issues:
            logger.warning("Configuration issues detected:")
            for issue in issues:
                logger.warning(f"  - {issue}")

    def process_suno_track(
        self,
        suno_audio_file: str,
        project_name: Optional[str] = None,
        auto_import: Optional[bool] = None,
    ) -> WorkflowResult:
        """
        Complete workflow for processing a Suno track

        Steps:
        1. Separate stems using YourMT3+
        2. Create Reaper project from template
        3. Generate import instructions
        4. Optionally auto-import stems into Reaper

        Args:
            suno_audio_file: Path to Suno-generated audio file
            project_name: Name for the Reaper project (auto-generated if None)
            auto_import: Automatically import stems into Reaper (uses config default)

        Returns:
            WorkflowResult with project info and stem paths
        """
        try:
            # Validate input
            self._validate_input_file(suno_audio_file)

            # Generate project name
            project_name = self._generate_project_name(suno_audio_file, project_name)

            # Setup project directory
            project_dir = self._setup_project_directory(suno_audio_file, project_name)

            logger.info(f"Processing Suno track: {suno_audio_file}")
            logger.info(f"Project name: {project_name}")

            # Step 1: Separate stems
            stem_paths = self._separate_stems(suno_audio_file, project_dir)

            # Step 2: Copy original file
            original_copy = (
                self._copy_original_file(suno_audio_file, project_dir)
                if self.config and self.config.copy_original
                else None
            )

            # Step 3: Create Reaper project
            project_file = self._create_reaper_project(
                project_dir, project_name, stem_paths, original_copy
            )

            # Step 4: Generate import instructions
            instructions_file = self._generate_instructions(
                project_dir, project_file, stem_paths, original_copy
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

        except Exception as e:
            logger.error(f"Workflow failed: {e}")
            return WorkflowResult(
                project_dir="",
                project_file="",
                stem_paths={},
                original_file="",
                instructions_file="",
                success=False,
                error_message=str(e),
            )

    def _validate_input_file(self, file_path: str) -> None:
        """Validate input audio file exists and is accessible"""
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"Audio file not found: {file_path}")

        if not os.access(file_path, os.R_OK):
            raise PermissionError(f"Cannot read audio file: {file_path}")

    def _generate_project_name(
        self, audio_file: str, project_name: Optional[str]
    ) -> str:
        """Generate project name from audio file if not provided"""
        if project_name:
            return project_name

        audio_path = Path(audio_file)
        return f"{audio_path.stem}_reaper_project"

    def _setup_project_directory(self, audio_file: str, project_name: str) -> str:
        """Create and return project directory path"""
        output_dir = (
            self.config.paths.output_dir if self.config and self.config.paths else None
        )
        project_dir = output_dir or os.path.join(
            os.path.dirname(audio_file), project_name
        )
        os.makedirs(project_dir, exist_ok=True)
        return project_dir

    def _separate_stems(self, audio_file: str, project_dir: str) -> Dict[str, str]:
        """Separate audio into stems"""
        logger.info("\n" + "=" * 60)
        logger.info("STEP 1: Separating stems with YourMT3+")
        logger.info("=" * 60)

        stems_dir = (
            os.path.join(project_dir, "stems")
            if self.config and self.config.create_stems_dir
            else project_dir
        )
        separator = YourMT3StemSeparator(output_dir=stems_dir)

        return separator.separate(audio_file)

    def _copy_original_file(self, audio_file: str, project_dir: str) -> str:
        """Copy original audio file to project directory"""
        logger.info("\n" + "=" * 60)
        logger.info("STEP 2: Copying original file")
        logger.info("=" * 60)

        original_copy = os.path.join(project_dir, "original_mix.wav")
        shutil.copy2(audio_file, original_copy)
        logger.info(f"Original saved to: {original_copy}")
        return original_copy

    def _create_reaper_project(
        self,
        project_dir: str,
        project_name: str,
        stem_paths: Dict[str, str],
        original_file: Optional[str],
    ) -> str:
        """Create Reaper project file from template"""

        project_file = os.path.join(project_dir, f"{project_name}.rpp")

        template_path = self.config.template_path if self.config else None
        if template_path and os.path.exists(template_path):
            # Copy template
            shutil.copy2(template_path, project_file)
            logger.info(f"Project created from template: {project_file}")
        else:
            logger.warning(f"Template not found: {template_path}")
            logger.warning("Creating basic project file")
            self._create_basic_project(project_file, stem_paths, original_file)

        return project_file

    def _create_basic_project(
        self,
        project_file: str,
        stem_paths: Dict[str, str],
        original_file: Optional[str],
    ):
        """Create a basic Reaper project file"""

        # This creates a minimal RPP file
        # For full functionality, use the template
        with open(project_file, "w") as f:
            f.write('<REAPER_PROJECT 0.1 "7.0" 1737167280\n')
            f.write("  TEMPO 120 4 4\n")
            f.write("  SAMPLERATE 48000 0 0\n")

            # Add tracks for each stem
            track_names = ["Vocals", "Drums", "Bass", "Other", "Original Mix"]
            for i, track_name in enumerate(track_names):
                f.write(f"  <TRACK\n")
                f.write(f'    NAME "{track_name}"\n')
                f.write(f"    TRACKID {{{i}}}\n")
                f.write(f"  >\n")

            f.write(">\n")

        logger.info(f"Basic project file created: {project_file}")

    def _generate_instructions(
        self,
        project_dir: str,
        project_file: str,
        stem_paths: Dict[str, str],
        original_file: Optional[str] = None,
    ) -> str:
        """Generate detailed import instructions"""

        instructions_file = os.path.join(project_dir, "IMPORT_INSTRUCTIONS.md")

        with open(instructions_file, "w") as f:
            f.write("# Suno Track Import Instructions\n\n")

            f.write("## Quick Start\n\n")
            f.write(f"1. Open the Reaper project: `{project_file}`\n")
            f.write("2. Import stems to the corresponding tracks:\n\n")

            track_mapping = {
                "vocals": "Track 1: Vocals",
                "drums": "Track 2: Drums",
                "bass": "Track 3: Bass",
                "other": "Track 4: Other (Instruments)",
            }

            for stem_name, track_name in track_mapping.items():
                if stem_name in stem_paths:
                    stem_path = stem_paths[stem_name]
                    # Handle case where stem_path might be on different drive
                    try:
                        relative_path = os.path.relpath(stem_path, project_dir)
                    except ValueError:
                        # Different drives, use absolute path
                        relative_path = stem_path
                    f.write(f"   - **{track_name}**: `{relative_path}`\n")

            if original_file:
                try:
                    original_relative = os.path.relpath(original_file, project_dir)
                except (ValueError, TypeError):
                    original_relative = original_file or "original_mix.wav"
                f.write(
                    f"\n3. Import original mix to Track 5 (reference): `{original_relative}`\n"
                )

            f.write("\n## Manual Import Steps\n\n")
            f.write("If not using the template:\n\n")
            f.write("1. Create new tracks in Reaper\n")
            f.write("2. Drag and drop each stem file to its corresponding track\n")
            f.write("3. Align all items to start at position 0:00\n")
            f.write("4. Set track colors for easy identification\n")
            f.write("5. Add sends to a master bus if needed\n")

            f.write("\n## Stem Files\n\n")
            for stem_name, stem_path in stem_paths.items():
                # Handle cross-drive path issues
                try:
                    relative_path = os.path.relpath(stem_path, project_dir)
                except ValueError:
                    relative_path = stem_path
                f.write(f"- **{stem_name.capitalize()}**: `{relative_path}`\n")

            f.write(f"\n## Original Mix\n\n")
            if original_file:
                try:
                    original_relative = os.path.relpath(original_file, project_dir)
                except (ValueError, TypeError):
                    original_relative = original_file
                f.write(f"- **Original**: `{original_relative}`\n")
            else:
                f.write("- **Original**: Not copied\n")

            f.write("\n## Mixing Tips\n\n")
            f.write("- Mute the 'Original Mix' track while working on stems\n")
            f.write("- Solo individual stems to check separation quality\n")
            f.write("- Use reference track for A/B comparison\n")
            f.write(
                "- Add EQ, compression, and effects to individual stems as needed\n"
            )
            f.write("- Route stems to a bus for group processing\n")

            f.write("\n## Troubleshooting\n\n")
            f.write(
                "- If stems don't align: Check sample rates match (48kHz recommended)\n"
            )
            f.write(
                "- If separation quality is poor: Try re-running with different model\n"
            )
            f.write("- For stem bleeding: Apply gentle gating or expanders\n")

        logger.info(f"Instructions saved to: {instructions_file}")
        return instructions_file

    def _print_summary(self, result: WorkflowResult):
        """Print workflow summary"""

        if not result.success:
            print(f"\nERROR: {result.error_message}")
            return

        print("\n" + "=" * 80)
        print(" " * 25 + "WORKFLOW COMPLETE")
        print("=" * 80)
        print("\nProject created successfully!")
        print(f"\nProject Directory: {result.project_dir}")
        print(f"Project File:      {result.project_file}")
        print(f"\nStems Generated:")

        for stem_name, stem_path in result.stem_paths.items():
            print(f"  {stem_name:12s} -> {os.path.basename(stem_path)}")

        print(f"\nNext Steps:")
        print(f"  1. Open Reaper")
        print(f"  2. Load project: {result.project_file}")
        print(f"  3. Import stems using instructions in: {result.instructions_file}")
        print(f"  4. Start mixing!")
        print("=" * 80 + "\n")


def main():
    """Command-line interface"""

    parser = argparse.ArgumentParser(
        description="Suno Track Workflow Helper - Process Suno tracks for Reaper"
    )

    parser.add_argument("input", help="Input Suno audio file")

    parser.add_argument(
        "-n", "--name", help="Project name (default: auto-generated from filename)"
    )

    parser.add_argument("-t", "--template", help="Path to Reaper template file")

    parser.add_argument(
        "--no-auto-import",
        action="store_true",
        help="Skip automatic import (manual import only)",
    )

    args = parser.parse_args()

    # Create workflow
    workflow = SunoReaperWorkflow(template_path=args.template)

    # Process track
    try:
        result = workflow.process_suno_track(
            suno_audio_file=args.input,
            project_name=args.name,
            auto_import=not args.no_auto_import,
        )

        print("\nSuccess! Project ready to use.")
        return 0

    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback

        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
