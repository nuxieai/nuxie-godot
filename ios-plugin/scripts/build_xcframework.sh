#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
OUTPUT_DIR="$ROOT_DIR/.build/xcframework"
PLUGIN_BUILD_DIR="$OUTPUT_DIR/plugin-build"
SCHEME="NuxieGodotBridge"
PLUGIN_SOURCE="$ROOT_DIR/Sources/NuxieGodotPlugin/nuxie_godot_plugin.cpp"
MIN_IOS_VERSION="15.0"

if [[ -z "${GODOT_SOURCE_DIR:-}" ]]; then
  echo "GODOT_SOURCE_DIR must point to a Godot 4.5 source checkout." >&2
  exit 1
fi

if [[ ! -f "$GODOT_SOURCE_DIR/version.py" ]]; then
  echo "GODOT_SOURCE_DIR does not contain a Godot source checkout: $GODOT_SOURCE_DIR" >&2
  exit 1
fi

GODOT_VERSION="$(sed -nE 's/^major = ([0-9]+)$/\1/p' "$GODOT_SOURCE_DIR/version.py").$(sed -nE 's/^minor = ([0-9]+)$/\1/p' "$GODOT_SOURCE_DIR/version.py")"
if [[ "$GODOT_VERSION" != "4.5" ]]; then
  echo "Godot 4.5.x source is required; found $GODOT_VERSION." >&2
  exit 1
fi

SCONS_BIN="${SCONS_BIN:-$(command -v scons || true)}"
if [[ -z "$SCONS_BIN" ]]; then
  echo "SCons is required to generate Godot's public build headers." >&2
  exit 1
fi

(
  cd "$GODOT_SOURCE_DIR"
  "$SCONS_BIN" \
    platform=ios \
    target=template_release \
    arch=arm64 \
    core/disabled_classes.gen.h \
    core/version_generated.gen.h \
    core/object/gdvirtual.gen.inc \
    core/extension/ext_wrappers.gen.inc \
    core/extension/gdextension_interface_dump.gen.h
)

cd "$ROOT_DIR"

resolve_framework_path() {
  local archive_dir="$1"
  local candidate_usr_local_lib="$archive_dir/Products/usr/local/lib/NuxieGodotBridge.framework"
  local candidate_frameworks="$archive_dir/Products/Library/Frameworks/NuxieGodotBridge.framework"

  if [[ -d "$candidate_usr_local_lib" ]]; then
    printf '%s\n' "$candidate_usr_local_lib"
    return 0
  fi

  if [[ -d "$candidate_frameworks" ]]; then
    printf '%s\n' "$candidate_frameworks"
    return 0
  fi

  echo "Unable to find NuxieGodotBridge.framework in $archive_dir" >&2
  return 1
}

compile_plugin_slice() {
  local sdk="$1"
  local arch="$2"
  local deployment_flag="$3"
  local slice_name="$4"
  local sdk_path
  local object_path="$PLUGIN_BUILD_DIR/$slice_name/nuxie_godot_plugin.o"
  local library_path="$PLUGIN_BUILD_DIR/$slice_name/libnuxie_godot_plugin.a"

  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  mkdir -p "$(dirname "$object_path")"

  xcrun --sdk "$sdk" clang++ \
    -c "$PLUGIN_SOURCE" \
    -o "$object_path" \
    -arch "$arch" \
    -isysroot "$sdk_path" \
    "$deployment_flag" \
    -std=gnu++17 \
    -O2 \
    -fno-exceptions \
    -fblocks \
    -fvisibility=hidden \
    -fmodules \
    -fcxx-modules \
    -Wno-ambiguous-macro \
    -DNDEBUG \
    -DNS_BLOCK_ASSERTIONS=1 \
    -DPTRCALL_ENABLED \
    -DNEED_LONG_INT \
    -DLIBYUV_DISABLE_NEON \
    -DIOS_ENABLED \
    -DAPPLE_EMBEDDED_ENABLED \
    -DUNIX_ENABLED \
    -DCOREAUDIO_ENABLED \
    -I"$GODOT_SOURCE_DIR" \
    -I"$GODOT_SOURCE_DIR/platform/ios"

  xcrun libtool -static -o "$library_path" "$object_path"
}

rm -rf "$DERIVED_DATA" "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

xcodebuild archive -quiet \
  -scheme "$SCHEME" \
  -destination "generic/platform=iOS" \
  -archivePath "$OUTPUT_DIR/ios.xcarchive" \
  -derivedDataPath "$DERIVED_DATA" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

IOS_FRAMEWORK_PATH="$(resolve_framework_path "$OUTPUT_DIR/ios.xcarchive")"
IOS_RESOURCE_BUNDLE="$DERIVED_DATA/Build/Intermediates.noindex/ArchiveIntermediates/$SCHEME/IntermediateBuildFilesPath/UninstalledProducts/iphoneos/Nuxie_Nuxie.bundle"
if [[ ! -d "$IOS_RESOURCE_BUNDLE" ]]; then
  echo "Unable to find the Nuxie SDK device resource bundle." >&2
  exit 1
fi
ditto "$IOS_RESOURCE_BUNDLE" "$IOS_FRAMEWORK_PATH/Nuxie_Nuxie.bundle"

xcodebuild archive -quiet \
  -scheme "$SCHEME" \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "$OUTPUT_DIR/ios-simulator.xcarchive" \
  -derivedDataPath "$DERIVED_DATA" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

IOS_SIMULATOR_FRAMEWORK_PATH="$(resolve_framework_path "$OUTPUT_DIR/ios-simulator.xcarchive")"
IOS_SIMULATOR_RESOURCE_BUNDLE="$DERIVED_DATA/Build/Intermediates.noindex/ArchiveIntermediates/$SCHEME/IntermediateBuildFilesPath/UninstalledProducts/iphonesimulator/Nuxie_Nuxie.bundle"
if [[ ! -d "$IOS_SIMULATOR_RESOURCE_BUNDLE" ]]; then
  echo "Unable to find the Nuxie SDK simulator resource bundle." >&2
  exit 1
fi
ditto "$IOS_SIMULATOR_RESOURCE_BUNDLE" "$IOS_SIMULATOR_FRAMEWORK_PATH/Nuxie_Nuxie.bundle"

xcodebuild -create-xcframework \
  -framework "$IOS_FRAMEWORK_PATH" \
  -framework "$IOS_SIMULATOR_FRAMEWORK_PATH" \
  -output "$OUTPUT_DIR/NuxieGodotBridge.xcframework"

compile_plugin_slice iphoneos arm64 "-miphoneos-version-min=$MIN_IOS_VERSION" ios-arm64
compile_plugin_slice iphonesimulator arm64 "-mios-simulator-version-min=$MIN_IOS_VERSION" simulator-arm64
compile_plugin_slice iphonesimulator x86_64 "-mios-simulator-version-min=$MIN_IOS_VERSION" simulator-x86_64

mkdir -p "$PLUGIN_BUILD_DIR/simulator-universal"
xcrun lipo -create \
  "$PLUGIN_BUILD_DIR/simulator-arm64/libnuxie_godot_plugin.a" \
  "$PLUGIN_BUILD_DIR/simulator-x86_64/libnuxie_godot_plugin.a" \
  -output "$PLUGIN_BUILD_DIR/simulator-universal/libnuxie_godot_plugin.a"

xcodebuild -create-xcframework \
  -library "$PLUGIN_BUILD_DIR/ios-arm64/libnuxie_godot_plugin.a" \
  -library "$PLUGIN_BUILD_DIR/simulator-universal/libnuxie_godot_plugin.a" \
  -output "$OUTPUT_DIR/nuxie_godot_plugin.xcframework"

echo "Created: $OUTPUT_DIR/nuxie_godot_plugin.xcframework"
echo "Created: $OUTPUT_DIR/NuxieGodotBridge.xcframework"
