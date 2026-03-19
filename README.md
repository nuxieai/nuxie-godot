# Nuxie Godot SDK

Godot 4 native-first plugin for Nuxie.

This package wraps the native Nuxie SDKs (Android + iOS) and exposes a Godot-friendly GDScript facade that keeps wrapper semantics aligned with iOS/Android/React Native/Flutter contracts.

## What is included

- `addons/nuxie/`
- `addons/nuxie/nuxie.gd`: static async facade used from game code.
- `addons/nuxie/nuxie-trigger-operation.gd`: trigger stream helper.
- `addons/nuxie/nuxie-errors.gd`: normalized bridge error helper.
- `addons/nuxie/android/export_plugin.gd`: Android export integration.
- `addons/nuxie/ios/nuxie_godot.gdip`: iOS plugin descriptor.
- `android-plugin/`: Godot Android plugin (`GodotPlugin`) backed by `io.nuxie:nuxie-android`.
- `ios-plugin/`: Swift bridge + C ABI wrapper backed by `nuxie-ios`.
- `docs/`: API + integration docs.
- `VERSIONS.md`: wrapper-to-native version mapping.

## Runtime contract (high level)

- Native singleton name: `NuxieGodot`
- GDScript facade class: `Nuxie`
- Required native event stream:
- `operation_result`
- `trigger_update`
- `feature_access_changed`
- `purchase_request`
- `restore_request`
- `flow_lifecycle`

The facade handles request IDs internally and returns awaitable payloads in this shape:

```gdscript
{
  "ok": bool,
  "result": Dictionary,
  "error": Dictionary, # normalized: { code, message, nativeStack? }
}
```

## Build from source

Prerequisites:

- Godot `4.2+` (validated on 4.5.x/4.6 track).
- Android toolchain (JDK 17 + Android SDK) for Android builds.
- Xcode 16+ for iOS bridge builds.

### Android plugin (AAR)

```bash
./gradlew :android-plugin:assemble
```

This also copies built artifacts to:

- `addons/nuxie/android/bin/debug/NuxieGodot-debug.aar`
- `addons/nuxie/android/bin/release/NuxieGodot-release.aar`

### iOS plugin (XCFramework)

```bash
./ios-plugin/scripts/build_xcframework.sh
cp -R ios-plugin/.build/xcframework/nuxie_godot.xcframework addons/nuxie/ios/
```

## Godot project integration

1. Copy `addons/nuxie` into your Godot project.
2. Enable the plugin in `Project Settings -> Plugins`.
3. In Android export preset, ensure plugin `NuxieGodot` is enabled.
4. In iOS export preset, include `addons/nuxie/ios/nuxie_godot.gdip` and `nuxie_godot.xcframework`.

If authored flows use native permission actions, also add the matching iOS
usage-description keys and Android manifest permissions to your exported mobile
projects.

## Quick start (GDScript)

```gdscript
extends Node

func _ready() -> void:
  if not Nuxie.is_available():
    push_error("Nuxie native bridge not available on this runtime")
    return

  var configured = await Nuxie.configure("nuxie_public_api_key", {
    "environment": "production",
    "logLevel": "warning",
  })

  if not configured.ok:
    push_error("Nuxie configure failed: %s" % [configured.error])
    return

  var trigger_op := Nuxie.trigger("game_opened", {
    "properties": {"source": "menu"},
  })

  trigger_op.update_received.connect(func(update: Dictionary, is_terminal: bool, _timestamp_ms: int) -> void:
    print("Trigger update", update, "terminal=", is_terminal)
  )

  var terminal_update := await trigger_op.wait_done()
  print("Trigger terminal update", terminal_update)
```

## Purchase / restore bridge

If your app handles billing outside Nuxie SDK internals, provide a purchase controller:

```gdscript
func _ready() -> void:
  Nuxie.set_purchase_controller(_on_purchase_requested, _on_restore_requested)
  await Nuxie.configure("nuxie_public_api_key", {}, true)

func _on_purchase_requested(request: Dictionary) -> Dictionary:
  # Execute store purchase and return one of:
  # { "type": "success", ... }
  # { "type": "cancelled" }
  # { "type": "pending" }
  # { "type": "failed", "message": "reason" }
  return {"type": "cancelled"}

func _on_restore_requested(_request: Dictionary) -> Dictionary:
  # Return one of:
  # { "type": "success", "restoredCount": 1 }
  # { "type": "no_purchases" }
  # { "type": "failed", "message": "reason" }
  return {"type": "no_purchases"}
```

The facade auto-calls `complete_purchase` / `complete_restore` with callback results.

## Native permission actions

No extra GDScript API is needed for:

- `request_notifications`
- `request_tracking`
- `request_permission("camera" | "microphone" | "photos" | "location")`

Those actions execute in the underlying native SDKs. The host mobile projects
still need:

- iOS `Info.plist` usage-description keys for tracking/camera/microphone/photos/location
- Android manifest declarations for camera, microphone, photo-library, and
  location permissions used by your flows

## Testing and validation

Android:

```bash
./gradlew :android-plugin:testDebugUnitTest :android-plugin:assembleDebug :android-plugin:assembleRelease
```

iOS package tests:

```bash
xcodebuild test \
  -scheme NuxieGodotBridge \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation
```

iOS XCFramework build:

```bash
./ios-plugin/scripts/build_xcframework.sh
```

## Documentation

- `docs/api-reference.md`: method, event, and payload contract.
- `docs/integration-guide.md`: Android/iOS build + Godot export setup.
- `docs/release-checklist.md`: release workflow and verification gates.
- `VERSIONS.md`: wrapper/native dependency matrix.
