#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
OUTPUT_DIR="$ROOT_DIR/.build/xcframework"
SCHEME="NuxieGodotBridge"

cd "$ROOT_DIR"

resolve_framework_path() {
  local archive_dir="$1"
  local candidate_usr_local_lib="$archive_dir/Products/usr/local/lib/NuxieGodotBridge.framework"
  local candidate_frameworks="$archive_dir/Products/Library/Frameworks/NuxieGodotBridge.framework"

  if [ -d "$candidate_usr_local_lib" ]; then
    printf "%s\n" "$candidate_usr_local_lib"
    return 0
  fi

  if [ -d "$candidate_frameworks" ]; then
    printf "%s\n" "$candidate_frameworks"
    return 0
  fi

  echo "Unable to find NuxieGodotBridge.framework in $archive_dir" >&2
  return 1
}

rm -rf "$DERIVED_DATA" "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

xcodebuild archive \
  -scheme "$SCHEME" \
  -destination "generic/platform=iOS" \
  -archivePath "$OUTPUT_DIR/ios.xcarchive" \
  -derivedDataPath "$DERIVED_DATA" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

xcodebuild archive \
  -scheme "$SCHEME" \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "$OUTPUT_DIR/ios-simulator.xcarchive" \
  -derivedDataPath "$DERIVED_DATA" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

IOS_FRAMEWORK_PATH="$(resolve_framework_path "$OUTPUT_DIR/ios.xcarchive")"
IOS_SIMULATOR_FRAMEWORK_PATH="$(resolve_framework_path "$OUTPUT_DIR/ios-simulator.xcarchive")"

xcodebuild -create-xcframework \
  -framework "$IOS_FRAMEWORK_PATH" \
  -framework "$IOS_SIMULATOR_FRAMEWORK_PATH" \
  -output "$OUTPUT_DIR/nuxie_godot.xcframework"

echo "Created: $OUTPUT_DIR/nuxie_godot.xcframework"
