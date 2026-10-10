#!/usr/bin/env python3
"""Compile the shipped Swift bridge through its direct Bazel target."""
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parent.parent
subprocess.run([sys.executable, str(root / 'scripts/bazel/sdk.py'), 'test-ios'], cwd=root, check=True)
