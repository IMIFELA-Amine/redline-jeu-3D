@tool
extends EditorInspectorPlugin

## Adds the "Editable Mesh" section to the inspector of mesh and CSG nodes.

const InspectorSection := preload("inspector_section.gd")

var bridge: RefCounted
var make_editable_requested: Callable


func _can_handle(object: Object) -> bool:
	return object is MeshInstance3D


func _parse_begin(object: Object) -> void:
	var section := InspectorSection.new()
	section.setup(bridge, object as MeshInstance3D)
	section.make_editable_requested.connect(make_editable_requested)
	add_custom_control(section)
