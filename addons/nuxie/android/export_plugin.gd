@tool
extends EditorExportPlugin

func _pins() -> Dictionary:
	var path := "res://addons/nuxie/native-pins.json"
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _get_name() -> String:
	return "NuxieGodot"

func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid or platform is EditorExportPlatformIOS

func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	var variant := "debug" if debug else "release"
	return PackedStringArray(["res://addons/nuxie/android/bin/%s/NuxieGodot-%s.aar" % [variant, variant]])

func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	return PackedStringArray(["ai.nuxie:nuxie-android:0.2.0-" + str(_pins().get("android", {}).get("revision", "missing")), "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0"])

func _get_android_dependencies_maven_repos(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	return PackedStringArray(["file://" + ProjectSettings.globalize_path("res://addons/nuxie/android/maven")])

func _get_export_options(_platform: EditorExportPlatform) -> Array[Dictionary]:
	return [{"option": {"name": "nuxie/artifacts", "type": TYPE_BOOL}, "default_value": true}]

func _get_export_option_warning(platform: EditorExportPlatform, _option: String) -> String:
	var version := Engine.get_version_info()
	var expected: String = _pins().get("godot", "missing")
	if "%d.%d.%d" % [version.major, version.minor, version.patch] != expected:
		return "Install Godot " + expected + " and matching templates for this Nuxie package."
	if not FileAccess.file_exists("res://addons/nuxie/artifact-checksums.json"):
		return "Nuxie native artifacts are missing. Install the prepared addon ZIP."
	for variant: String in ["debug", "release"]:
		if platform is EditorExportPlatformAndroid and not FileAccess.file_exists("res://addons/nuxie/android/bin/%s/NuxieGodot-%s.aar" % [variant, variant]):
			return "Nuxie Android " + variant + " artifact is missing. Reinstall the prepared addon."
		if platform is EditorExportPlatformIOS:
			for framework: String in ["nuxie_godot_plugin", "NuxieGodotBridge"]:
				if not FileAccess.file_exists("res://addons/nuxie/ios/%s.%s.xcframework/Info.plist" % [framework, variant]):
					return "Nuxie iOS " + variant + " artifact is missing. Reinstall the prepared addon."
	if platform is EditorExportPlatformAndroid and not get_option("gradle_build/use_gradle_build"):
		return "Enable Gradle builds for Nuxie Android dependencies."
	if platform is EditorExportPlatformIOS and not get_option("plugins/NuxieGodot"):
		return "Enable NuxieGodot in this iOS export preset."
	return ""

func _export_begin(features: PackedStringArray, debug: bool, _path: String, _flags: int) -> void:
	if "ios" in features:
		var variant := "debug" if debug else "release"
		add_apple_embedded_platform_embedded_framework("res://addons/nuxie/ios/NuxieGodotBridge.%s.xcframework" % variant)

func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	# Native export hooks package these separately; never copy opposite-platform
	# frameworks, Maven metadata or their JSON resources into the game's pack.
	if path.begins_with("res://addons/nuxie/ios/") or path.begins_with("res://addons/nuxie/android/"):
		skip()
