#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Setup script for Suno Reaper Workflow System
"""

from setuptools import setup, find_packages
import os
from pathlib import Path

# Read README for long description
readme_path = Path(__file__).parent / "README.md"
long_description = (
    readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""
)

# Read version from __init__.py
version_file = Path(__file__).parent / "__init__.py"
version = "1.0.0"  # Default version
if version_file.exists():
    for line in version_file.read_text(encoding="utf-8").splitlines():
        if line.startswith("__version__"):
            version = line.split("=")[1].strip().strip("\"'")
            break

setup(
    name="suno-reaper-workflow",
    version=version,
    author="Suno Reaper Workflow Team",
    author_email="contact@example.com",
    description="Comprehensive audio processing pipeline for AI-generated music",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/suno-reaper-workflow",
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    package_data={
        "": ["*.txt", "*.md", "*.yml", "*.yaml"],
    },
    # Python version requirement
    python_requires=">=3.8",
    # Core dependencies from requirements.txt
    install_requires=[
        "numpy>=1.21.0",
        "scipy>=1.7.0",
        "soundfile>=0.10.0",
        "pathlib2>=2.3.0; python_version<'3.7'",
        "torch>=1.12.0",
        "torchaudio>=0.12.0",
        "psutil>=5.8.0",
        "requests>=2.31.0",
        "pandas>=2.0.0",
    ],
    # Optional dependencies for extra features
    extras_require={
        "stem-separation": [
            "demucs>=3.0.0",
            "spleeter>=2.3.0",
        ],
        "advanced-analysis": [
            "librosa>=0.9.0",
            "soxr>=0.3.0",
        ],
        "api": [
            "fastapi>=0.85.0",
            "uvicorn>=0.18.0",
        ],
        "dev": [
            "pytest>=7.0.0",
            "pytest-asyncio>=0.21.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=0.991",
        ],
        "logging": [
            "structlog>=22.0.0",
        ],
        "progress": [
            "tqdm>=4.64.0",
        ],
        "config": [
            "pydantic>=1.10.0",
            "pyyaml>=6.0",
        ],
        "all": [
            "demucs>=3.0.0",
            "spleeter>=2.3.0",
            "librosa>=0.9.0",
            "soxr>=0.3.0",
            "fastapi>=0.85.0",
            "uvicorn>=0.18.0",
            "structlog>=22.0.0",
            "tqdm>=4.64.0",
            "pydantic>=1.10.0",
            "pyyaml>=6.0",
        ],
    },
    # Entry points / console scripts
    entry_points={
        "console_scripts": [
            "suno-workflow=suno_workflow_helper:main",
            "suno-separate=yourmt3_stem_separator:main",
            "semas=SEMAS.cli:main",
        ],
    },
    # Classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: End Users/Desktop",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Multimedia :: Sound/Audio",
        "Topic :: Multimedia :: Sound/Audio :: Analysis",
        "Topic :: Multimedia :: Sound/Audio :: Conversion",
        "Topic :: Software Development :: Libraries :: Python Modules",
    ],
    # Keywords
    keywords="audio processing, stem separation, music, AI, machine learning, REAPER, DAW",
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/example/suno-reaper-workflow/issues",
        "Source": "https://github.com/example/suno-reaper-workflow",
        "Documentation": "https://suno-reaper-workflow.readthedocs.io/",
    },
)
