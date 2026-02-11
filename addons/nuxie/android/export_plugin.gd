@tool
extends EditorExportPlugin

const _PLUGIN_NAME := "NuxieGodot"

func _get_name() -> String:
  return _PLUGIN_NAME

func _supports_platform(platform):
  return platform is EditorExportPlatformAndroid

func _get_android_libraries(_platform, debug: bool) -> PackedStringArray:
  if debug:
    return PackedStringArray(["res://addons/nuxie/android/bin/debug/NuxieGodot-debug.aar"])
  return PackedStringArray(["res://addons/nuxie/android/bin/release/NuxieGodot-release.aar"])

func _get_android_dependencies(_platform, _debug: bool) -> PackedStringArray:
  return PackedStringArray([
    "org.godotengine:godot:4.5.1.stable",
    "io.nuxie:nuxie-android:0.0.1",
  ])
