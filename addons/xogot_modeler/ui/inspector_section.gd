@tool
extends VBoxContainer

## The Editable Mesh section of the inspector, as in Xogot: mesh counts, the
## shape, Bezier or Poly Shape recipe, UVs, collision, and export.

signal make_editable_requested

const ParameterForm := preload("parameter_form.gd")

var bridge: RefCounted
var node: MeshInstance3D

var _session: RefCounted
var _content: VBoxContainer
var _recipe_scope := ""


func setup(native_bridge: RefCounted, mesh_node: MeshInstance3D) -> void:
	bridge = native_bridge
	node = mesh_node
	var header := Label.new()
	header.text = tr("Editable Mesh")
	header.add_theme_font_override("font", EditorInterface.get_editor_theme().get_font("bold", "EditorFonts"))
	add_child(header)
	_content = VBoxContainer.new()
	add_child(_content)
	add_child(HSeparator.new())
	if node and ClassDB.class_exists("XogotModelerInspectorSession"):
		_session = ClassDB.instantiate("XogotModelerInspectorSession")
		_session.open(node)
		_session.changed.connect(refresh)
	refresh()


func _exit_tree() -> void:
	if _session:
		_session.close()


func refresh() -> void:
	if _content == null:
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var values: Dictionary = _session.snapshot() if _session else {}
	if not values.get("is_editable", false):
		_build_not_editable(values)
		return
	_build_mesh(values)
	_build_recipe(values)
	_build_uv(values)
	_build_collision(values)
	_build_export()


func _build_not_editable(values: Dictionary) -> void:
	var summary := _note(values.get("error", "") if not str(values.get("error", "")).is_empty() else tr("This mesh is not editable yet."))
	_content.add_child(summary)
	var convert := Button.new()
	convert.text = tr("Make Editable")
	convert.pressed.connect(func() -> void: make_editable_requested.emit())
	_content.add_child(convert)


func _build_mesh(values: Dictionary) -> void:
	var section := _section(tr("Mesh"))
	section.add_child(_note(tr("%d vertices, %d edges, %d faces") % [values["vertex_count"], values["edge_count"], values["face_count"]]))
	for slot in values.get("material_slots", []):
		section.add_child(_note(slot))


func _build_recipe(values: Dictionary) -> void:
	var recipe: String = values.get("recipe", "")
	if recipe.is_empty():
		return
	var section := _section({"shape": tr("Shape"), "bezier": tr("Bezier"), "polygon": tr("Poly Shape")}[recipe])
	if recipe == "shape" or recipe == "bezier":
		_recipe_scope = recipe
		var form := ParameterForm.new()
		form.setup_with(func() -> Array: return _session.parameters(_recipe_scope), func(key: String, value: Variant) -> void: _session.set_parameter(_recipe_scope, key, value))
		section.add_child(form)
	if values.get("recipe_stale", false):
		section.add_child(_note(tr("Rebuilding replaces the element edits. Undo can restore them.")))
		var rebuild := Button.new()
		rebuild.text = tr("Rebuild Shape")
		rebuild.disabled = values.get("tool_active", false)
		rebuild.pressed.connect(_confirm_rebuild)
		section.add_child(rebuild)
	elif values.get("tool_active", false):
		section.add_child(_note(tr("Finish or cancel the active creation tool to edit this shape.")))
	if recipe == "polygon" or recipe == "bezier":
		var edit := Button.new()
		edit.text = tr("Edit Poly Shape") if recipe == "polygon" else tr("Edit Bezier Shape")
		edit.disabled = values.get("tool_active", false)
		var command := "edit_polygon" if recipe == "polygon" else "edit_bezier"
		edit.pressed.connect(func() -> void: _session.run(command))
		section.add_child(edit)
	var error: String = values.get("recipe_error", "")
	if not error.is_empty():
		var label := _note(error)
		label.add_theme_color_override("font_color", EditorInterface.get_editor_theme().get_color("error_color", "Editor"))
		section.add_child(label)


func _build_uv(values: Dictionary) -> void:
	var section := _section(tr("UV & Lightmap"))
	section.add_child(_note(tr("Lightmap UVs: %s") % (tr("present") if values.get("has_uv2", false) else tr("none"))))
	var row := HFlowContainer.new()
	section.add_child(row)
	row.add_child(_command_button(tr("Open UV Editor"), "uv_editor"))
	row.add_child(_command_button(tr("Generate Lightmap UVs"), "lightmap_uvs"))


func _build_collision(values: Dictionary) -> void:
	var section := _section(tr("Collision"))
	var role: String = values.get("collision_role", "none")
	section.add_child(_note(tr("Current: %s") % {"collider": tr("Collider"), "trigger": tr("Trigger")}.get(role, tr("Detail"))))
	var row := HFlowContainer.new()
	section.add_child(row)
	row.add_child(_command_button(tr("Set Collider"), "collider"))
	row.add_child(_command_button(tr("Set Trigger"), "trigger"))


func _build_export() -> void:
	var section := _section(tr("Export & Data"))
	var row := HFlowContainer.new()
	section.add_child(row)
	row.add_child(_command_button(tr("Export Native Mesh…"), "export_mesh"))
	var strip := Button.new()
	strip.text = tr("Strip Editable Data…")
	strip.tooltip_text = tr("Keep the mesh but remove the Modeler's editable source. Undo restores it.")
	strip.pressed.connect(_confirm_strip)
	row.add_child(strip)


func _confirm_rebuild() -> void:
	_confirm(tr("Replace Element Edits?"), tr("Undo can restore the element edits."), tr("Rebuild Shape"), func() -> void: _session.run("rebuild"))


func _confirm_strip() -> void:
	_confirm(tr("Strip Editable Data?"), tr("The compiled mesh and materials are kept. Undo restores the editable data."), tr("Strip"), func() -> void: _session.run("strip"))


func _confirm(title: String, text: String, action: String, confirmed: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = text
	dialog.ok_button_text = action
	dialog.confirmed.connect(confirmed)
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free())
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()


# MARK: - Helpers

func _section(title: String) -> VBoxContainer:
	var foldable := FoldableContainer.new()
	foldable.title = title
	_content.add_child(foldable)
	var column := VBoxContainer.new()
	foldable.add_child(column)
	return column


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 160 * EditorInterface.get_editor_scale()
	label.add_theme_color_override("font_color", EditorInterface.get_editor_theme().get_color("font_disabled_color", "Editor"))
	return label


func _command_button(text: String, command: String) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func() -> void: _session.run(command))
	return button
