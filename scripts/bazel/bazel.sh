#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if [[ -n "${NUXIE_BAZEL_BIN:-}" ]]; then
  bazel_bin="$NUXIE_BAZEL_BIN"
elif [[ -x "$ROOT_DIR/node_modules/.bin/bazelisk" ]]; then
  bazel_bin="$ROOT_DIR/node_modules/.bin/bazelisk"
elif [[ -x "$ROOT_DIR/../../node_modules/.bin/bazelisk" ]]; then
  bazel_bin="$ROOT_DIR/../../node_modules/.bin/bazelisk"
elif command -v bazelisk >/dev/null 2>&1; then
  bazel_bin="$(command -v bazelisk)"
elif command -v bazel >/dev/null 2>&1; then
  bazel_bin="$(command -v bazel)"
else
  bazel_bin="$ROOT_DIR/scripts/bazel/launcher.py"
fi

startup_args=()
if [[ -n "${NUXIE_BAZEL_CACHE_DIR+x}" ]]; then
  cache_options="$(python3 "$ROOT_DIR/scripts/bazel/cache.py")"
  startup_args+=("$cache_options")
fi
if [[ "${NUXIE_BAZEL_BATCH:-${CI:-0}}" == "1" ]]; then
  startup_args+=("--batch")
fi
if [[ -n "${NUXIE_BAZEL_OUTPUT_USER_ROOT:-}" ]]; then
  if [[ "$NUXIE_BAZEL_OUTPUT_USER_ROOT" != /* ]]; then
    echo "NUXIE_BAZEL_OUTPUT_USER_ROOT must be an absolute path" >&2
    exit 1
  fi
  startup_args+=("--output_user_root=$NUXIE_BAZEL_OUTPUT_USER_ROOT")
fi
command="${1:?Expected Bazel command}"
shift
command_args=()
case "$command" in
  build|test|run|cquery|aquery)
    if [[ -n "${NUXIE_BAZEL_JOBS:-}" ]]; then
      if [[ ! "$NUXIE_BAZEL_JOBS" =~ ^[1-9][0-9]*$ ]]; then
        echo "NUXIE_BAZEL_JOBS must be a positive integer" >&2
        exit 1
      fi
      command_args+=("--jobs=$NUXIE_BAZEL_JOBS")
    fi
    ;;
esac
exec "$bazel_bin" ${startup_args[@]+"${startup_args[@]}"} "$command" ${command_args[@]+"${command_args[@]}"} "$@"
