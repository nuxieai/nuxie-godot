# Nuxie Godot Integration Guide

This guide covers installing the plugin, producing native artifacts, and configuring Godot export presets.

## 1. Copy plugin files into your game

Copy `addons/nuxie` from this repository into your Godot project:

```bash
cp -R addons/nuxie /path/to/your-godot-project/addons/
```

In Godot editor:

1. Open `Project Settings -> Plugins`.
2. Enable plugin `Nuxie`.

## 2. Build Android artifact

From `packages/nuxie-godot`:

```bash
./gradlew :android-plugin:assemble
```

This generates and copies:

- `addons/nuxie/android/bin/debug/NuxieGodot-debug.aar`
- `addons/nuxie/android/bin/release/NuxieGodot-release.aar`

### Android export preset

In your Android export preset:

1. Ensure plugin `NuxieGodot` is enabled.
2. Confirm gradle dependencies include:
- `org.godotengine:godot:4.5.1.stable`
- `io.nuxie:nuxie-android:<version>`
3. Export with the same build type as packaged AAR (`debug` vs `release`).

If flows use `request_permission(...)`, the Android app manifest must also
declare the matching dangerous permissions:

- `android.permission.CAMERA`
- `android.permission.RECORD_AUDIO`
- `android.permission.READ_MEDIA_IMAGES` on Android 13+ or
  `android.permission.READ_EXTERNAL_STORAGE` on Android 12 and below
- `android.permission.ACCESS_COARSE_LOCATION` and/or
  `android.permission.ACCESS_FINE_LOCATION`

## 3. Build iOS artifact

From `packages/nuxie-godot`:

```bash
./ios-plugin/scripts/build_xcframework.sh
cp -R ios-plugin/.build/xcframework/nuxie_godot.xcframework addons/nuxie/ios/
```

The plugin descriptor at `addons/nuxie/ios/nuxie_godot.gdip` expects the binary name:

- `nuxie_godot.xcframework`

### iOS export preset

In your iOS export preset:

1. Ensure plugin descriptor `addons/nuxie/ios/nuxie_godot.gdip` is active.
2. Ensure `nuxie_godot.xcframework` is present next to the `.gdip` file.
3. Keep system frameworks required by the plugin descriptor:
- `StoreKit.framework`
- `WebKit.framework`

If flows use `request_tracking` or `request_permission(...)`, also add the
matching `Info.plist` usage-description keys:

- `NSUserTrackingUsageDescription`
- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription`
- `NSPhotoLibraryUsageDescription`
- `NSLocationWhenInUseUsageDescription`

## 4. Runtime initialization

Use the static facade from your game scripts:

```gdscript
if not Nuxie.is_available():
  push_error("Nuxie bridge unavailable")
  return

var op := await Nuxie.configure("nuxie_public_api_key", {
  "environment": "production",
})
if not op.ok:
  push_error("Nuxie configure failed: %s" % [op.error])
```

## 5. Purchase bridge wiring (optional)

If you use custom store handling, register callbacks before `configure(..., use_purchase_controller=true)`:

```gdscript
Nuxie.set_purchase_controller(_on_purchase, _on_restore)
await Nuxie.configure("key", {}, true)
```

Callback return payloads must follow contract documented in `docs/api-reference.md`.

## 6. Verification checklist

- `Nuxie.is_available()` returns `true` on device runtime.
- `configure` emits successful `operation_result`.
- `trigger` receives progressive `trigger_update` events.
- `trigger_once` returns terminal update.
- Feature checks and profile refresh return data in `result`.
- Purchase/restore requests are emitted and completion methods resolve native continuations.

## 7. Common issues

- `NATIVE_SDK_UNAVAILABLE`: native plugin is not enabled in export preset or artifacts were not copied.
- iOS symbol/link issues: XCFramework not present at `addons/nuxie/ios/nuxie_godot.xcframework`.
- Android class not found: AAR missing in `addons/nuxie/android/bin/...` or plugin not enabled in export preset.
