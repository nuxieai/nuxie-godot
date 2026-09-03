# Nuxie Godot Integration Guide

## Install the facade

Copy `addons/nuxie` into the game and enable `Nuxie` under **Project Settings → Plugins**.

```bash
cp -R addons/nuxie /path/to/game/addons/
```

## Android

Build the plugin with JDK 17 and an Android SDK:

```bash
./gradlew :android-plugin:testDebugUnitTest \
  :android-plugin:assembleDebug \
  :android-plugin:assembleRelease
```

The build copies these files into the addon:

- `addons/nuxie/android/bin/debug/NuxieGodot-debug.aar`
- `addons/nuxie/android/bin/release/NuxieGodot-release.aar`

The export plugin declares exact dependencies on Godot `4.5.1.stable` and `ai.nuxie:nuxie-android:0.1.0`. Enable `NuxieGodot` in the Android export preset and use the matching debug or release artifact.

For local native SDK validation, point `NUXIE_ANDROID_MAVEN_REPO` at a Maven repository containing `ai.nuxie:nuxie-android:0.1.0`.

## iOS

The iOS export contains two artifacts:

- `nuxie_godot_plugin.xcframework`: static C++ plugin that registers the `NuxieGodot` Godot singleton.
- `NuxieGodotBridge.xcframework`: embedded Swift framework containing the bridge, native SDK, runtime, and SDK resources.

Build them with Xcode, SCons, and a Godot 4.5.x source checkout:

```bash
GODOT_SOURCE_DIR=/path/to/godot-4.5.1 \
  ./ios-plugin/scripts/build_xcframework.sh

cp -R ios-plugin/.build/xcframework/nuxie_godot_plugin.xcframework addons/nuxie/ios/
cp -R ios-plugin/.build/xcframework/NuxieGodotBridge.xcframework addons/nuxie/ios/
```

Keep both XCFrameworks next to `addons/nuxie/ios/nuxie_godot.gdip`. The descriptor links the static plugin, embeds the Swift framework, enables the Swift runtime, and links StoreKit and WebKit.

Enable `NuxieGodot` in the iOS export preset. A successful device launch makes `Engine.has_singleton("NuxieGodot")` return `true`.

## Configure at runtime

```gdscript
if not Nuxie.is_available():
  push_error("Nuxie bridge unavailable")
  return

var configured := await Nuxie.configure("nuxie_public_api_key", {
  "environment": "production",
  "log_level": "warning",
  "locale_identifier": null,
  "purchase_handling_mode": "full",
})

if not configured.ok:
  push_error("Nuxie configure failed: %s" % [configured.error])
  return

Nuxie.trigger("game_opened", {"source": "launch"})
```

Identity changes update native SDK state. Profile synchronization follows the native SDK lifecycle and occurs at launch and foreground sync points.

## App actions

Journeys can ask the host app to perform a typed action:

```gdscript
Nuxie.on("app_action", func(action: Dictionary) -> void:
  match action.name:
    "open_inventory": _open_inventory(action.payload)
    _: push_warning("Unhandled Nuxie app action: %s" % action.name)
)
```

Add any platform permissions and usage descriptions required by actions your game implements.

## App-managed purchases

Set callbacks before configuration:

```gdscript
Nuxie.set_purchase_controller(_purchase, _restore)
var configured := await Nuxie.configure("nuxie_public_api_key", {
  "purchase_handling_mode": "observer",
}, true)
```

The callback contracts are documented in `docs/api-reference.md`. Both callbacks may return immediately or suspend.

## Verification

- `Nuxie.is_available()` is `true` in an exported mobile build.
- `configure` resolves with `ok == true`.
- `trigger` returns immediately and matching Journeys present through the native SDK.
- `has_feature` honors both cache-first and remote policies.
- `use_feature_and_wait` includes `authoritativeAccess` when the server supplies it.
- `activity` and `app_action` callbacks preserve typed property values.
- App-managed purchase and restore callbacks resolve their native continuations.

If `NATIVE_SDK_UNAVAILABLE` is reported, verify that the platform artifact and export plugin are enabled. On iOS, verify that both XCFrameworks are present beside the `.gdip` file.
