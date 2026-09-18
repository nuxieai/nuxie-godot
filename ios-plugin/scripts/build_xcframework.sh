#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/.build/xcframework"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
: "${GODOT_SOURCE_DIR:?Set GODOT_SOURCE_DIR to the pinned engine source checkout}"
python3 - "$ROOT_DIR" "$GODOT_SOURCE_DIR" <<'PY'
import json,runpy,sys
from pathlib import Path
pin=json.loads((Path(sys.argv[1]).parent/'NATIVE-PINS.json').read_text())['godot']
v=runpy.run_path(str(Path(sys.argv[2])/'version.py'))
actual='.'.join(str(v[k]) for k in ['major','minor','patch'])
if actual != pin: raise SystemExit('Godot headers must match '+pin+', found '+actual)
PY
mkdir -p "$OUTPUT_DIR"
(
  cd "$GODOT_SOURCE_DIR"
  "${SCONS_BIN:-scons}" platform=ios target=template_release arch=arm64 \
    core/disabled_classes.gen.h core/version_generated.gen.h \
    core/object/gdvirtual.gen.h core/extension/ext_wrappers.gen.h \
    core/extension/gdextension_interface_dump.gen.h core/extension/gdextension_interface.gen.h
)
cd "$ROOT_DIR"
for variant in release debug; do
  configuration=Release
  cpp_flags=(-DNS_BLOCK_ASSERTIONS=1)
  if [[ "$variant" == debug ]]; then configuration=Debug; cpp_flags+=(-DDEBUG_ENABLED); fi
  framework_args=()
  for platform in ios simulator; do
    architectures=(arm64)
    sdk=iphoneos
    destination='generic/platform=iOS'
    deployment=-miphoneos-version-min=15.0
    if [[ "$platform" == simulator ]]; then
      architectures+=(x86_64)
      sdk=iphonesimulator
      destination='generic/platform=iOS Simulator'
      deployment=-mios-simulator-version-min=15.0
    fi
    archive="$OUTPUT_DIR/$variant-$platform.xcarchive"
    xcodebuild archive -quiet -scheme NuxieGodotBridge -configuration "$configuration" \
      -destination "$destination" -archivePath "$archive" -derivedDataPath "$DERIVED_DATA" \
      "ARCHS=${architectures[*]}" ONLY_ACTIVE_ARCH=NO SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES
    framework="$archive/Products/usr/local/lib/NuxieGodotBridge.framework"
    if [[ ! -d "$framework" ]]; then framework="$archive/Products/Library/Frameworks/NuxieGodotBridge.framework"; fi
    test -d "$framework"
    for architecture in "${architectures[@]}"; do
      xcrun lipo "$framework/NuxieGodotBridge" -verify_arch "$architecture"
    done
    framework_args+=(-framework "$framework")
    resource="$DERIVED_DATA/Build/Intermediates.noindex/ArchiveIntermediates/NuxieGodotBridge/IntermediateBuildFilesPath/UninstalledProducts/$sdk/Nuxie_Nuxie.bundle"
    test -d "$resource"
    ditto "$resource" "$framework/Nuxie_Nuxie.bundle"
    mkdir -p "$OUTPUT_DIR/plugin-build/$variant-$platform"
    libraries=()
    for architecture in "${architectures[@]}"; do
      object="$OUTPUT_DIR/plugin-build/$variant-$platform/plugin-$architecture.o"
      library="$OUTPUT_DIR/plugin-build/$variant-$platform/plugin-$architecture.a"
      xcrun --sdk "$sdk" clang++ -c Sources/NuxieGodotPlugin/nuxie_godot_plugin.cpp -o "$object" \
        -arch "$architecture" -isysroot "$(xcrun --sdk "$sdk" --show-sdk-path)" "$deployment" \
        -std=gnu++17 -O2 -fno-exceptions -fblocks -fvisibility=hidden -DNDEBUG \
        -DPTRCALL_ENABLED -DNEED_LONG_INT -DTHREADS_ENABLED -DIOS_ENABLED -DAPPLE_EMBEDDED_ENABLED \
        -DUNIX_ENABLED -DCOREAUDIO_ENABLED "${cpp_flags[@]}" -I"$GODOT_SOURCE_DIR" -I"$GODOT_SOURCE_DIR/platform/ios"
      xcrun libtool -static -o "$library" "$object"
      libraries+=("$library")
    done
    combined="$OUTPUT_DIR/plugin-build/$variant-$platform/plugin.a"
    xcrun lipo -create "${libraries[@]}" -output "$combined"
    for architecture in "${architectures[@]}"; do
      xcrun lipo "$combined" -verify_arch "$architecture"
    done
  done
  # Delete only the two generated artifacts being replaced; retain the incremental build cache.
  rm -rf "$OUTPUT_DIR/NuxieGodotBridge.$variant.xcframework" "$OUTPUT_DIR/nuxie_godot_plugin.$variant.xcframework"
  xcodebuild -create-xcframework \
    "${framework_args[@]}" \
    -output "$OUTPUT_DIR/NuxieGodotBridge.$variant.xcframework"
  xcodebuild -create-xcframework \
    -library "$OUTPUT_DIR/plugin-build/$variant-ios/plugin.a" \
    -library "$OUTPUT_DIR/plugin-build/$variant-simulator/plugin.a" \
    -output "$OUTPUT_DIR/nuxie_godot_plugin.$variant.xcframework"
done
