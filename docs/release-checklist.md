# Nuxie Godot Release Checklist

Run every gate from the repository root before tagging a release.

## Contract audit

- Public `trigger` is event-only and returns `void`.
- `reset` defaults to `keep_anonymous_id = false`.
- Feature checks expose cache-first and remote policies.
- `use_feature` is fire-and-forget and `use_feature_and_wait` returns authoritative access.
- Activity and app-action payload values remain typed.
- Purchase and restore fields use `snake_case` on Android and iOS.
- `VERSIONS.md`, `Package.resolved`, Gradle dependencies, and addon version all agree.

## Android

```bash
./gradlew :android-plugin:testDebugUnitTest \
  :android-plugin:lint \
  :android-plugin:assembleDebug \
  :android-plugin:assembleRelease
```

Verify:

- `addons/nuxie/android/bin/debug/NuxieGodot-debug.aar`
- `addons/nuxie/android/bin/release/NuxieGodot-release.aar`

## iOS

Run package tests against the exact `nuxie-ios` `0.1.0` dependency, then package against Godot 4.5.1 source:

```bash
xcodebuild test \
  -scheme NuxieGodotBridge \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation

GODOT_SOURCE_DIR=/path/to/godot-4.5.1 \
  ./ios-plugin/scripts/build_xcframework.sh
```

Verify:

- `ios-plugin/.build/xcframework/nuxie_godot_plugin.xcframework`
- `ios-plugin/.build/xcframework/NuxieGodotBridge.xcframework`
- Static plugin slices contain `nuxie_godot_init` and `nuxie_godot_deinit`.
- Swift framework slices export all `NuxieGodot_*` C ABI functions.
- `NuxieGodotBridge.framework/Nuxie_Nuxie.bundle` exists in each slice.
- Device slice is `arm64`; simulator slice supports `arm64` and `x86_64`.

## Godot facade

Parse the addon and run the checked-in facade contract:

```bash
godot --headless --path . --editor --quit
godot --headless --path . --quit
```

In exported Android and iOS smoke projects, verify configuration, event capture, Journey presentation, feature access, app actions, activity, dismiss, locale changes, and app-managed purchases.

## Publish

1. Copy both iOS XCFrameworks into `addons/nuxie/ios/` for the release bundle.
2. Confirm the addon contains no generated debug artifacts or local dependency mirrors.
3. Commit code, tests, docs, and release artifacts as required by the SDK release process.
4. Tag the SDK release.
5. Update the parent monorepo submodule pointer to the reviewed SDK commit.
