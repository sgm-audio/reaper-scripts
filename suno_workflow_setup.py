#!/usr/bin/env python3
"""Setuptools entry point for the standalone Suno workflow helpers."""

from pathlib import Path
from setuptools import setup

ROOT = Path(__file__).resolve().parent

setup(
    name="suno-reaper-workflow",
    version="1.0.0",
    author="Scott Mills",
    description="Generate REAPER projects from Suno audio and separated stems",
    long_description=(ROOT / "README.md").read_text(encoding="utf-8"),
    long_description_content_type="text/markdown",
    url="https://github.com/sgm-audio/reaper-scripts",
    py_modules=[
        "suno_workflow_config_system",
        "suno_workflow_helper",
        "suno_workflow_performance_utils",
    ],
    python_requires=">=3.9",
    install_requires=["numpy>=1.21", "soundfile>=0.10", "psutil>=5.8"],
    extras_require={
        "stem-separation": ["torch", "torchaudio"],
        "aaf": ["pyaaf2>=1.7"],
        "dev": ["pyflakes>=3", "pytest>=7"],
    },
    entry_points={
        "console_scripts": ["suno-workflow=suno_workflow_helper:main"],
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Multimedia :: Sound/Audio",
    ],
    project_urls={
        "Bug Reports": "https://github.com/sgm-audio/reaper-scripts/issues",
        "Source": "https://github.com/sgm-audio/reaper-scripts",
    },
)
