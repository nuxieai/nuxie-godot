# Nuxie Godot Release Checklist

Use this checklist before tagging a new `nuxie-godot` release.

## Build + test gates

Run from `packages/nuxie-godot`.

1. Android unit tests + builds:

```bash
./gradlew :android-plugin:testDebugUnitTest :android-plugin:assembleDebug :android-plugin:assembleRelease
```

2. iOS package tests:

```bash
xcodebuild test \
  -scheme NuxieGodotBridge \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation
```

3. iOS XCFramework packaging:

```bash
./ios-plugin/scripts/build_xcframework.sh
```

## Artifact checks

1. Android artifacts exist:
- `addons/nuxie/android/bin/debug/NuxieGodot-debug.aar`
- `addons/nuxie/android/bin/release/NuxieGodot-release.aar`
2. iOS artifact exists:
- `ios-plugin/.build/xcframework/nuxie_godot.xcframework`
3. Copy iOS artifact into plugin distribution path when preparing release bundles:
- `addons/nuxie/ios/nuxie_godot.xcframework`

## Contract checks

1. Trigger terminal fixture parity remains green in:
- `android-plugin/src/test/kotlin/io/nuxie/godot/BridgeContractsTest.kt`
- `ios-plugin/Tests/NuxieGodotBridgeTests/TriggerContractTests.swift`
2. Purchase/restore payload mappings remain green in platform tests.

## Documentation checks

1. `README.md` reflects current build/test commands.
2. `docs/api-reference.md` matches current facade signatures and event payloads.
3. `VERSIONS.md` is updated with:
- Godot wrapper version
- Android native SDK version
- iOS native SDK ref (tag/SHA)

## Publishing sequence

1. Commit code and docs.
2. Tag release (`vX.Y.Z`) in `nuxie-godot`.
3. Push tag.
4. Update parent monorepo submodule pointer.
5. In parent monorepo release notes, include:
- plugin version
- native dependency versions
- migration notes (if any)
