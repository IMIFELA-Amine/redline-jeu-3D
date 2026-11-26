@tool
extends PanelContainer

## The panel at the bottom of a 3D viewport. It shows the active creation
## tool, the live adjustment of an action, Bevel Mode, or a short message.

const ParameterForm := preload("parameter_form.gd")

var bridge: RefCounted

var _title: Label
var _detail: Label
var _form: ParameterForm
var _snap_button: Button
var _options_button: Button
var _tool_options: PopupPanel
var _tool_form: ParameterForm
var _tool_commands := {}
var _cancel_button: Button
var _done_button: Button
var _content := ""


func setup(native_bridge: RefCounted) -> void:
	bridge = native_bridge
	name = "XogotModelerHUD"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var scale := EditorInterface.get_editor_scale()
	offset_bottom = -16 * scale
	visible = false
	var theme := EditorInterface.get_editor_theme()
	var style := StyleBoxFlat.new()
	style.bg_color = theme.get_color("base_color", "Editor")
	style.bg_color.a = 0.94
	style.border_color = theme.get_color("dark_color_3", "Editor")
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(6 * scale))
	style.set_content_margin_all(10 * scale)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = int(4 * scale)
	add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	_title = Label.new()
	_title.add_theme_font_override("font", EditorInterface.get_editor_theme().get_font("bold", "EditorFonts"))
	column.add_child(_title)

	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size.x = 280 * scale
	column.add_child(_detail)

	_form = ParameterForm.new()
	column.add_child(_form)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	# Keep keyboard focus in the viewport: Return and Escape drive the tools.
	_snap_button = Button.new()
	_snap_button.focus_mode = Control.FOCUS_NONE
	_snap_button.toggle_mode = true
	_snap_button.icon = EditorInterface.get_editor_theme().get_icon("Snap", "EditorIcons")
	_snap_button.tooltip_text = tr("Snap")
	_snap_button.toggled.connect(func(pressed: bool) -> void: bridge.set_snap_enabled(pressed))
	buttons.add_child(_snap_button)
	_options_button = Button.new()
	_options_button.focus_mode = Control.FOCUS_NONE
	_options_button.text = tr("Options")
	_options_button.pressed.connect(_on_options)
	buttons.add_child(_options_button)
	_cancel_button = Button.new()
	_cancel_button.focus_mode = Control.FOCUS_NONE
	_cancel_button.text = tr("Cancel")
	_cancel_button.pressed.connect(_on_cancel)
	buttons.add_child(_cancel_button)
	_done_button = Button.new()
	_done_button.focus_mode = Control.FOCUS_NONE
	_done_button.text = tr("Done")
	_done_button.pressed.connect(_on_done)
	buttons.add_child(_done_button)
	_build_tool_options()


## Shows what the snapshot describes. Returns whether the panel is visible.
func update_from(snapshot: Dictionary) -> bool:
	var content := ""
	if snapshot.has("bevel"):
		content = "bevel"
	elif snapshot.has("tool"):
		content = "tool:" + snapshot["tool"]["id"]
	elif snapshot.has("adjustment"):
		content = "adjustment:" + snapshot["adjustment"]
	elif not str(snapshot.get("feedback", "")).is_empty() or not str(snapshot.get("message", "")).is_empty():
		content = "message"

	if content != _content:
		_content = content
		match content.get_slice(":", 0):
			"bevel":
				_form.setup(bridge, "bevel_session")
			"adjustment":
				_form.setup(bridge, "action:" + snapshot["adjustment"])
			"tool":
				_form.setup(bridge, "tool_hud")
			_:
				_form.setup(bridge, "")
	else:
		_form.refresh()

	_options_button.visible = false
	_snap_button.visible = false
	_cancel_button.visible = true
	_done_button.visible = true
	_done_button.disabled = false
	_detail.remove_theme_color_override("font_color")
	match content.get_slice(":", 0):
		"bevel":
			var bevel: Dictionary = snapshot["bevel"]
			_title.text = tr("Bevel Mode")
			_detail.text = bevel.get("summary", "")
			if bevel.has("status"):
				_detail.text += "\n" + bevel["status"]
			_done_button.text = tr("Apply")
			_done_button.disabled = not bevel.get("can_commit", false)
		"tool":
			var tool: Dictionary = snapshot["tool"]
			_title.text = tool.get("title", "")
			var readout := PackedStringArray()
			for key in ["measurement", "plane"]:
				if not str(tool.get(key, "")).is_empty():
					readout.append(tool[key])
			_detail.text = tool.get("instruction", "")
			if not readout.is_empty():
				_detail.text += "\n" + "   ".join(readout)
			if tool.get("invalid", false):
				_detail.add_theme_color_override("font_color", EditorInterface.get_editor_theme().get_color("warning_color", "Editor"))
			_snap_button.visible = true
			_snap_button.set_pressed_no_signal(tool.get("snap_enabled", false))
			_options_button.visible = tool.get("shows_options", false)
			_done_button.text = tool.get("primary_title", tr("Done"))
			_done_button.disabled = not tool.get("can_complete", false)
			_update_tool_options(tool)
		"adjustment":
			_title.text = snapshot.get("adjustment_title", "")
			_detail.text = tr("Adjust the values; the viewport shows a preview.")
			_options_button.visible = true
			_done_button.text = tr("Done")
		"message":
			var message: String = snapshot.get("message", "")
			_title.text = tr("Modeler")
			_detail.text = message if not message.is_empty() else snapshot.get("feedback", "")
			if not message.is_empty():
				_detail.add_theme_color_override("font_color", EditorInterface.get_editor_theme().get_color("error_color", "Editor"))
			_cancel_button.visible = false
			_done_button.text = tr("Dismiss")
	if content.get_slice(":", 0) != "tool" and _tool_options.visible:
		_tool_options.hide()
	_form.visible = not _form.is_empty()
	visible = not content.is_empty()
	reset_size()
	return visible


func _on_done() -> void:
	match _content.get_slice(":", 0):
		"bevel":
			bridge.commit_bevel()
		"tool":
			bridge.complete_tool()
		"adjustment":
			bridge.commit_adjustment()
		"message":
			bridge.clear_message()


func _on_cancel() -> void:
	match _content.get_slice(":", 0):
		"bevel":
			bridge.cancel_bevel()
		"tool":
			bridge.cancel_tool()
		"adjustment":
			bridge.cancel_adjustment()


func _on_options() -> void:
	if _content.begins_with("tool:"):
		_tool_form.setup(bridge, "tool_options")
		var rect := _options_button.get_screen_transform() * Rect2(Vector2.ZERO, _options_button.size)
		_tool_options.popup(Rect2i(Vector2i(rect.position.x, rect.position.y), Vector2i.ZERO))
		return
	bridge.settings_requested.emit()


## The Options of the active creation tool, with its point and hole commands.
func _build_tool_options() -> void:
	_tool_options = PopupPanel.new()
	var column := VBoxContainer.new()
	_tool_options.add_child(column)
	_tool_form = ParameterForm.new()
	column.add_child(_tool_form)
	var row := HFlowContainer.new()
	column.add_child(row)
	for command in [["outline", "Outline"], ["add_hole", "Add Hole"], ["remove_hole", "Remove Hole"], ["add_point", "Add Point"], ["remove_point", "Remove Point"], ["clear_points", "Clear Points"]]:
		var button := Button.new()
		button.text = tr(command[1])
		button.focus_mode = Control.FOCUS_NONE
		var name: String = command[0]
		button.pressed.connect(func() -> void: bridge.tool_command(name))
		row.add_child(button)
		_tool_commands[name] = button
	add_child(_tool_options)


func _update_tool_options(tool: Dictionary) -> void:
	var id: String = tool.get("id", "")
	var polygon := id == "polygon"
	var bezier := id == "bezier" or id == "bezierBlock"
	var points: int = tool.get("point_count", 0)
	_tool_commands["outline"].visible = polygon and tool.get("editing_hole", false)
	_tool_commands["add_hole"].visible = polygon
	_tool_commands["add_hole"].disabled = not tool.get("can_add_hole", false)
	_tool_commands["remove_hole"].visible = polygon and tool.get("editing_hole", false)
	_tool_commands["add_point"].visible = bezier
	_tool_commands["remove_point"].disabled = points == 0
	_tool_commands["clear_points"].disabled = points == 0
	if _tool_options.visible:
		_tool_form.refresh()
		_tool_options.reset_size()
