#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
python3 "$ROOT_DIR/scripts/bazel/sdk.py" prepare-ios --configuration Debug
python3 "$ROOT_DIR/scripts/bazel/sdk.py" prepare-ios --configuration Release
