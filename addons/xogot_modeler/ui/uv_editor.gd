@tool
extends VBoxContainer

## The UV editor in the bottom panel: tools and channels, the canvas, and the
## selection, automatic and manual UV, transform, lightmap and template
## sections, as in Xogot.

const UVCanvas := preload("uv_canvas.gd")
const ParameterForm := preload("parameter_form.gd")

const TOOLS := [["select", "ToolSelect", "Select"], ["move", "ToolMove", "Move"], ["rotate", "ToolRotate", "Rotate"], ["scale", "ToolScale", "Scale"]]
const MODES := [["vertex", "Vertex"], ["edge", "Edge"], ["face", "Face"]]
const CHANNELS := [["uv", "UV"], ["uv2", "UV2"], ["uv3", "UV3"], ["uv4", "UV4"]]

var bridge: RefCounted
var canvas: UVCanvas

var _tool_buttons := {}
var _mode_buttons := {}
var _channel: OptionButton
var _scope: Button
var _texture: Button
var _status: Label
var _forms: Array[ParameterForm] = []
var _buttons := {}
var _template_dialog: EditorFileDialog


func setup(native_bridge: RefCounted) -> void:
	bridge = native_bridge
	name = "XogotModelerUVEditor"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	var tools := ButtonGroup.new()
	for tool in TOOLS:
		var button := _icon_button(tool[1], tr(tool[2]))
		button.toggle_mode = true
		button.button_group = tools
		var id: String = tool[0]
		button.pressed.connect(func() -> void: bridge.uv_run("tool", id))
		toolbar.add_child(button)
		_tool_buttons[id] = button
	toolbar.add_child(VSeparator.new())
	var modes := ButtonGroup.new()
	for mode in MODES:
		var button := Button.new()
		button.text = tr(mode[1])
		button.toggle_mode = true
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.button_group = modes
		var id: String = mode[0]
		button.pressed.connect(func() -> void: bridge.uv_run("mode", id))
		toolbar.add_child(button)
		_mode_buttons[id] = button
	toolbar.add_child(VSeparator.new())
	_channel = OptionButton.new()
	_channel.focus_mode = Control.FOCUS_NONE
	for channel in CHANNELS:
		_channel.add_item(channel[1])
		_channel.set_item_metadata(_channel.item_count - 1, channel[0])
	_channel.item_selected.connect(func(index: int) -> void: bridge.uv_run("channel", _channel.get_item_metadata(index)))
	toolbar.add_child(_channel)
	_scope = Button.new()
	_scope.text = tr("UV Scope")
	_scope.tooltip_text = tr("Make the viewport handles move, rotate and scale UVs instead of geometry.")
	_scope.toggle_mode = true
	_scope.flat = true
	_scope.focus_mode = Control.FOCUS_NONE
	_scope.toggled.connect(func(pressed: bool) -> void: bridge.uv_run("scope", str(pressed)))
	toolbar.add_child(_scope)
	_texture = _icon_button("Image", tr("Texture Preview"))
	_texture.toggle_mode = true
	_texture.toggled.connect(func(pressed: bool) -> void: bridge.uv_run("texture_preview", str(pressed)))
	toolbar.add_child(_texture)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	for zoom in [["ZoomLess", "Zoom Out (-)", "zoom_out"], ["ZoomReset", "Center (0)", "recenter"], ["ZoomMore", "Zoom In (+)", "zoom_in"]]:
		var button := _icon_button(zoom[0], tr(zoom[1]))
		var operation: String = zoom[2]
		button.pressed.connect(func() -> void: bridge.uv_run(operation, ""))
		toolbar.add_child(button)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	canvas = UVCanvas.new()
	canvas.setup(bridge)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(canvas)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 300 * EditorInterface.get_editor_scale()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(side)
	_build_sections(side)

	_status = Label.new()
	add_child(_status)

	_template_dialog = EditorFileDialog.new()
	_template_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_template_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_template_dialog.add_filter("*.png", tr("PNG Image"))
	_template_dialog.current_file = "UVTemplate.png"
	_template_dialog.file_selected.connect(func(path: String) -> void:
		var error: String = bridge.uv_save_template(path)
		_status.text = error if not error.is_empty() else tr("Saved %s") % path)
	add_child(_template_dialog)


func _build_sections(side: VBoxContainer) -> void:
	var selection := _section(side, tr("Selection & Grid"))
	_row(selection, [["All", "select_all"], ["None", "clear_selection"], ["Island", "select_island"], ["Face", "select_faces"]])
	_form(selection, "selection")

	var automatic := _section(side, tr("Auto UVs"))
	_row(automatic, [["Convert to Manual", "manual"], ["Convert to Auto", "auto"]])
	_form(automatic, "auto")
	_row(automatic, [["Apply Auto Settings", "apply_auto"]])
	_row(automatic, [["Join", "join_group"], ["New Group", "new_group"], ["Break", "break_groups"], ["Select Group", "select_groups"]])
	_row(automatic, [["Reset UVs", "reset"]])

	var manual := _section(side, tr("Manual UVs"))
	_row(manual, [["Planar", "project", "planar"], ["Box", "project", "box"], ["Spherical", "project", "spherical"]])
	_row(manual, [["Collapse", "collapse"], ["Split", "split"], ["Fit", "fit"]])
	_row(manual, [["Flip Horizontal", "flip", "u"], ["Flip Vertical", "flip", "v"], ["Stitch", "stitch"]])
	_row(manual, [["Copy", "copy"], ["Paste", "paste"]])
	_form(manual, "manual")
	_row(manual, [["Weld", "weld"]])

	var transform := _section(side, tr("Transform"))
	_form(transform, "transform")
	_row(transform, [["Apply Transform", "apply_transform"]])

	var lightmap := _section(side, tr("Lightmap UVs"))
	var note := Label.new()
	note.text = tr("UV2 is generated and cannot be edited here.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 200 * EditorInterface.get_editor_scale()
	lightmap.add_child(note)
	_form(lightmap, "lightmap")
	_row(lightmap, [["Apply", "apply_unwrap"], ["Reset", "reset_unwrap"], ["Rebuild UV2", "rebuild_uv2"]])

	var template := _section(side, tr("UV Template"))
	_form(template, "template")
	var export := Button.new()
	export.text = tr("Export UV Template…")
	export.focus_mode = Control.FOCUS_NONE
	export.pressed.connect(func() -> void: _template_dialog.popup_file_dialog())
	template.add_child(export)


func refresh() -> void:
	if bridge == null:
		return
	canvas.refresh()
	var info: Dictionary = bridge.uv_info()
	for id in _tool_buttons:
		_tool_buttons[id].set_pressed_no_signal(info.get("tool", "") == id)
	for id in _mode_buttons:
		_mode_buttons[id].set_pressed_no_signal(info.get("mode", "") == id)
	for index in _channel.item_count:
		if _channel.get_item_metadata(index) == info.get("channel", "uv"):
			_channel.select(index)
	_scope.set_pressed_no_signal(info.get("scope", false))
	_scope.disabled = info.get("channel", "uv") != "uv"
	_texture.set_pressed_no_signal(info.get("texture_preview", true))
	var selected: int = info.get("selected_count", 0)
	for key in ["select_island", "select_faces"]:
		_buttons[key].disabled = selected == 0
	_buttons["paste"].disabled = not info.get("has_clipboard", false)
	var status := tr("%d selected") % selected
	if info.get("missing_uv2", false):
		status += "  ·  " + tr("This mesh has no lightmap UVs.")
	var message: String = info.get("message", "")
	if not message.is_empty():
		status += "  ·  " + message
	_status.text = status
	for form in _forms:
		form.refresh()


# MARK: - Helpers

func _section(parent: VBoxContainer, title: String) -> VBoxContainer:
	var foldable := FoldableContainer.new()
	foldable.title = title
	parent.add_child(foldable)
	var column := VBoxContainer.new()
	foldable.add_child(column)
	return column


func _form(parent: VBoxContainer, section: String) -> void:
	var form := ParameterForm.new()
	form.setup(bridge, "uv:" + section)
	parent.add_child(form)
	_forms.append(form)


func _row(parent: VBoxContainer, buttons: Array) -> void:
	var row := HFlowContainer.new()
	parent.add_child(row)
	for entry in buttons:
		var button := Button.new()
		button.text = tr(entry[0])
		button.focus_mode = Control.FOCUS_NONE
		var operation: String = entry[1]
		var argument: String = entry[2] if entry.size() > 2 else ""
		button.pressed.connect(func() -> void: bridge.uv_run(operation, argument))
		row.add_child(button)
		_buttons[operation + ("_" + argument if not argument.is_empty() else "")] = button
		if not _buttons.has(operation):
			_buttons[operation] = button


func _icon_button(icon: String, tooltip: String) -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	var theme := EditorInterface.get_editor_theme()
	button.icon = theme.get_icon(icon, "EditorIcons") if theme.has_icon(icon, "EditorIcons") else null
	if button.icon == null:
		button.text = tooltip
	button.tooltip_text = tooltip
	return button
