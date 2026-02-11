@tool
extends EditorExportPlugin

var _plugin_name := "NuxieGodot"

func _supports_platform(platform):
  return platform is EditorExportPlatformAndroid

func _get_android_libraries(platform, debug):
  if debug:
    return PackedStringArray(["res://addons/nuxie/android/bin/debug/NuxieGodot-debug.aar"])
  return PackedStringArray(["res://addons/nuxie/android/bin/release/NuxieGodot-release.aar"])

func _get_name() -> String:
  return _plugin_name

func _get_android_dependencies(platform, debug):
  return PackedStringArray([
    "org.godotengine:godot:4.5.1.stable",
  ])
