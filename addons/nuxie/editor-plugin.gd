@tool
extends EditorPlugin

const AUTOLOAD := "res://addons/nuxie/nuxie.gd"
const Exporter = preload("android/export_plugin.gd")
var _exporter: EditorExportPlugin
var _owns_autoload := false

func _enter_tree() -> void:
	var existing: String = ProjectSettings.get_setting("autoload/Nuxie", "")
	if not existing.is_empty() and existing.trim_prefix("*") != AUTOLOAD:
		push_error("Nuxie autoload name is already owned by another script. Rename it before enabling Nuxie.")
		return
	if existing.is_empty():
		add_autoload_singleton("Nuxie", AUTOLOAD)
	_owns_autoload = true
	_exporter = Exporter.new()
	add_export_plugin(_exporter)
	_stage_ios_descriptor()

func _exit_tree() -> void:
	if _exporter != null:
		remove_export_plugin(_exporter)
	if _owns_autoload and str(ProjectSettings.get_setting("autoload/Nuxie", "")).trim_prefix("*") == AUTOLOAD:
		remove_autoload_singleton("Nuxie")

func _stage_ios_descriptor() -> void:
	var target := "res://ios/plugins/nuxie/nuxie_godot.gdip"
	var source := "res://addons/nuxie/ios/nuxie_godot.gdip"
	var marker := target + ".sha256"
	var managed := FileAccess.file_exists(marker) and FileAccess.get_file_as_string(marker) == FileAccess.get_sha256(target)
	if FileAccess.file_exists(target) and not managed and FileAccess.get_file_as_string(target) != FileAccess.get_file_as_string(source):
		push_error("Preserving a modified ios/plugins/nuxie descriptor. Remove or reconcile it before exporting.")
		return
	DirAccess.make_dir_recursive_absolute("res://ios/plugins/nuxie")
	if DirAccess.copy_absolute(source, target) == OK:
		var record := FileAccess.open(marker, FileAccess.WRITE)
		if record != null:
			record.store_string(FileAccess.get_sha256(target))
