@tool
extends EditorExportPlugin

## Keeps the editor-only add-on out of exported projects: its native library
## exists only for the editor, and games do not need its scripts.

const ADDON_PATH := "res://addons/xogot_modeler/"


func _get_name() -> String:
	return "XogotModelerExportFilter"


func _export_file(path: String, type: String, features: PackedStringArray) -> void:
	if path.begins_with(ADDON_PATH):
		skip()
