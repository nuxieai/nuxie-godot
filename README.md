# Nuxie Godot SDK

Godot 4.5 plugin for Nuxie on Android and iOS. It wraps the native Nuxie SDKs and exposes one GDScript API for event-driven Journeys, feature access, activity telemetry, app actions, and app-managed purchases.

`Nuxie.trigger(...)` records an event and returns immediately. The native SDK evaluates and presents matching Journeys asynchronously.

## Package layout

- `addons/nuxie/nuxie.gd`: public `Nuxie` GDScript facade.
- `addons/nuxie/nuxie-errors.gd`: normalized bridge error reporting.
- `addons/nuxie/android/export_plugin.gd`: Android export integration.
- `addons/nuxie/ios/nuxie_godot.gdip`: iOS plugin descriptor.
- `android-plugin/`: Godot Android plugin backed by `ai.nuxie:nuxie-android:0.1.0`.
- `ios-plugin/`: Swift runtime bridge and C++ Godot singleton backed by `nuxie-ios` `0.1.0`.

## Quick start

```gdscript
extends Node

func _ready() -> void:
  if not Nuxie.is_available():
    push_error("Nuxie native bridge is unavailable")
    return

  Nuxie.on("app_action", _on_app_action)

  var configured := await Nuxie.configure("nuxie_public_api_key", {
    "environment": "production",
    "log_level": "warning",
  })
  if not configured.ok:
    push_error("Nuxie configure failed: %s" % [configured.error])
    return

  Nuxie.trigger("game_opened", {"source": "menu"})

func _on_app_action(action: Dictionary) -> void:
  print("Journey requested app action: ", action)
```

`trigger` is intentionally fire-and-forget. It has no operation object, terminal update, cancellation API, or return payload.

## Build native artifacts

Prerequisites:

- Godot 4.5.x.
- JDK 17 and Android SDK for Android.
- Xcode 16 or newer, SCons, and a Godot 4.5 source checkout for iOS.

Android:

```bash
./gradlew :android-plugin:testDebugUnitTest :android-plugin:assembleDebug :android-plugin:assembleRelease
```

The Gradle build copies AARs into `addons/nuxie/android/bin/{debug,release}/`.

GDScript facade contract:

```bash
godot --headless --path . --editor --quit
godot --headless --path . --quit
```

iOS:

```bash
GODOT_SOURCE_DIR=/path/to/godot-4.5.1 \
  ./ios-plugin/scripts/build_xcframework.sh

cp -R ios-plugin/.build/xcframework/nuxie_godot_plugin.xcframework addons/nuxie/ios/
cp -R ios-plugin/.build/xcframework/NuxieGodotBridge.xcframework addons/nuxie/ios/
```

The static `nuxie_godot_plugin.xcframework` registers the `NuxieGodot` engine singleton. The embedded `NuxieGodotBridge.xcframework` contains the Swift bridge and native iOS SDK.

## App-managed purchases

Register handlers before configuration and pass `true` as the third configure argument:

```gdscript
func _ready() -> void:
  Nuxie.set_purchase_controller(_purchase, _restore)
  await Nuxie.configure("nuxie_public_api_key", {
    "purchase_handling_mode": "observer",
  }, true)

func _purchase(request: Dictionary) -> Dictionary:
  # Return purchased, cancelled, pending, or failed.
  return {"type": "cancelled"}

func _restore(_request: Dictionary) -> Dictionary:
  # Return restored, no_purchases, or failed.
  return {"type": "no_purchases"}
```

The facade completes the native purchase or restore continuation with the callback result. Requests and commerce fields use `snake_case` on both platforms. Purchase delegation and transaction ownership are independent: choose `observer` only when the app or another billing SDK owns transaction finishing.

## Documentation

- `docs/api-reference.md`: exact public GDScript contract and payloads.
- `docs/integration-guide.md`: Android and iOS export setup.
- `docs/release-checklist.md`: release verification.
- `VERSIONS.md`: wrapper and native dependency versions.
