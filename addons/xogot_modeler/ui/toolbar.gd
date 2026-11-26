@tool
extends HBoxContainer

## The Modeler's controls in the 3D editor's toolbar: selection modes, the
## Add Mesh palette, Make Editable, the Actions menu, snapping and Options.

signal make_editable_requested
signal options_requested

const ParameterForm := preload("parameter_form.gd")
const PaintPopover := preload("paint_popover.gd")

const MODE_ICONS := {
	"object": "MeshInstance3D",
	"vertex": "res://addons/xogot_modeler/icons/mode_vertex.svg",
	"edge": "res://addons/xogot_modeler/icons/mode_edge.svg",
	"face": "res://addons/xogot_modeler/icons/mode_face.svg",
}
const MODE_TITLES := {
	"object": "Object",
	"vertex": "Vertex",
	"edge": "Edge",
	"face": "Face",
}
const SHAPE_ICONS := {
	"cube": "BoxMesh",
	"prism": "PrismMesh",
	"sprite": "QuadMesh",
	"plane": "PlaneMesh",
	"cylinder": "CylinderMesh",
	"cone": "CylinderMesh",
	"sphere": "SphereMesh",
	"pipe": "TubeTrailMesh",
	"torus": "TorusMesh",
	"arch": "CSGBox3D",
	"door": "CSGBox3D",
	"stairs": "CSGBox3D",
}
const TOOL_ICONS := {
	"polygon": "CSGPolygon3D",
	"bezier": "Curve3D",
	"bezierBlock": "Path3D",
}

var bridge: RefCounted

var _mode_buttons := {}
var _add_button: Button
var _palette: PopupPanel
var _palette_grid: GridContainer
var _make_editable_button: Button
var _actions_button: MenuButton
var _snap_button: Button
var _paint_button: Button
var _paint: PaintPopover
var _handles_button: Button
var _handles_popup: PopupPanel
var _handles_form: ParameterForm
var _handles_mode := ""
var _options_button: Button
var _snapshot := {}
var _action_ids: Array[String] = []


func setup(native_bridge: RefCounted) -> void:
	bridge = native_bridge
	name = "XogotModelerToolbar"
	add_child(VSeparator.new())

	var group := ButtonGroup.new()
	for mode in ["object", "vertex", "edge", "face"]:
		var button := Button.new()
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.button_group = group
		button.icon = _icon(MODE_ICONS[mode])
		if MODE_ICONS[mode].begins_with("res://"):
			_tint_icon(button)
		button.tooltip_text = tr("%s Mode") % tr(MODE_TITLES[mode]) + (" (H)" if mode != "object" else " (Esc)")
		button.pressed.connect(func() -> void: bridge.select_mode(mode))
		add_child(button)
		_mode_buttons[mode] = button

	_add_button = Button.new()
	_add_button.flat = true
	_add_button.focus_mode = Control.FOCUS_NONE
	_add_button.text = tr("Add Mesh")
	_add_button.icon = _icon("Add")
	_add_button.tooltip_text = tr("Draw a new mesh. Alt-click a shape to place it at once.")
	_add_button.pressed.connect(_show_palette)
	add_child(_add_button)

	_make_editable_button = Button.new()
	_make_editable_button.flat = true
	_make_editable_button.focus_mode = Control.FOCUS_NONE
	_make_editable_button.text = tr("Make Editable")
	_make_editable_button.icon = _icon("ArrayMesh")
	_make_editable_button.tooltip_text = tr("Convert the selected mesh or CSG shape to an editable mesh.")
	_make_editable_button.pressed.connect(func() -> void: make_editable_requested.emit())
	add_child(_make_editable_button)

	_actions_button = MenuButton.new()
	_actions_button.flat = true
	_actions_button.focus_mode = Control.FOCUS_NONE
	_actions_button.text = tr("Actions")
	_actions_button.icon = _icon("Tools")
	_actions_button.about_to_popup.connect(_fill_actions)
	_actions_button.get_popup().id_pressed.connect(_on_action)
	add_child(_actions_button)

	_snap_button = Button.new()
	_snap_button.flat = true
	_snap_button.focus_mode = Control.FOCUS_NONE
	_snap_button.toggle_mode = true
	_snap_button.icon = _icon("Snap")
	_snap_button.tooltip_text = tr("Snap Modeler edits and new shapes to the grid.")
	_snap_button.toggled.connect(func(pressed: bool) -> void: bridge.set_snap_enabled(pressed))
	add_child(_snap_button)

	_paint_button = Button.new()
	_paint_button.flat = true
	_paint_button.focus_mode = Control.FOCUS_NONE
	_paint_button.icon = _icon("Paint")
	_paint_button.tooltip_text = tr("Paint")
	_paint_button.pressed.connect(_show_paint)
	add_child(_paint_button)
	_paint = PaintPopover.new()
	_paint.setup(bridge)
	add_child(_paint)

	_handles_button = Button.new()
	_handles_button.flat = true
	_handles_button.focus_mode = Control.FOCUS_NONE
	_handles_button.icon = _icon("ToolSelect")
	_handles_button.tooltip_text = tr("Selection & Handles")
	_handles_button.pressed.connect(_show_handles)
	add_child(_handles_button)
	_build_handles_popup()

	_options_button = Button.new()
	_options_button.flat = true
	_options_button.focus_mode = Control.FOCUS_NONE
	_options_button.icon = _icon("GDScript")
	_options_button.tooltip_text = tr("Modeler Options")
	_options_button.pressed.connect(func() -> void: options_requested.emit())
	add_child(_options_button)

	_palette = PopupPanel.new()
	_palette_grid = GridContainer.new()
	_palette_grid.columns = 4
	_palette.add_child(_palette_grid)
	add_child(_palette)


func update_from(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	var attached: bool = snapshot.get("attached", false)
	var modes: PackedStringArray = snapshot.get("modes", PackedStringArray())
	var show_modes: bool = attached and snapshot.get("has_commands", false)
	for mode in _mode_buttons:
		var button: Button = _mode_buttons[mode]
		button.visible = show_modes and mode in modes
		button.set_pressed_no_signal(snapshot.get("mode", "") == mode)
	_add_button.visible = attached
	_add_button.disabled = not snapshot.get("can_create", false)
	_make_editable_button.visible = attached and snapshot.get("can_convert", false)
	_actions_button.visible = attached and snapshot.get("has_commands", false)
	_snap_button.visible = attached
	_snap_button.set_pressed_no_signal(snapshot.get("snap_enabled", false))
	_handles_button.visible = attached and snapshot.get("is_editable", false)
	_paint_button.visible = attached and snapshot.get("is_editable", false)
	if _paint.visible:
		_paint.refresh()
	if _handles_popup.visible:
		# Soft Selection appears only in Vertex mode.
		if snapshot.get("mode", "") != _handles_mode:
			_handles_mode = snapshot.get("mode", "")
			_handles_form.rebuild()
		else:
			_handles_form.refresh()
	_options_button.visible = attached


func _show_paint() -> void:
	var rect := _paint_button.get_screen_transform() * Rect2(Vector2.ZERO, _paint_button.size)
	_paint.popup(Rect2i(Vector2i(rect.position.x, rect.end.y), Vector2i.ZERO))
	_paint.refresh()


## The Selection & Handles popover, as in Xogot's edit HUD.
func _build_handles_popup() -> void:
	_handles_popup = PopupPanel.new()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(8 * EditorInterface.get_editor_scale()))
	_handles_popup.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = tr("Selection & Handles")
	title.add_theme_font_override("font", EditorInterface.get_editor_theme().get_font("bold", "EditorFonts"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var all_options := LinkButton.new()
	all_options.text = tr("All Options")
	all_options.focus_mode = Control.FOCUS_NONE
	all_options.pressed.connect(func() -> void:
		_handles_popup.hide()
		options_requested.emit())
	header.add_child(all_options)
	_handles_form = ParameterForm.new()
	column.add_child(_handles_form)
	add_child(_handles_popup)


func _show_handles() -> void:
	_handles_mode = _snapshot.get("mode", "")
	_handles_form.setup(bridge, "selection_handles")
	var rect := _handles_button.get_screen_transform() * Rect2(Vector2.ZERO, _handles_button.size)
	_handles_popup.popup(Rect2i(Vector2i(rect.position.x, rect.end.y), Vector2i.ZERO))


func _show_palette() -> void:
	for child in _palette_grid.get_children():
		_palette_grid.remove_child(child)
		child.queue_free()
	var last_used: String = _snapshot.get("last_used_shape", "")
	for shape in _snapshot.get("shapes", []):
		var id: String = shape["id"]
		var tile := _make_tile(shape["title"], SHAPE_ICONS.get(id, "MeshInstance3D"), shape.get("enabled", true))
		if id == last_used:
			tile.add_theme_color_override("font_color", EditorInterface.get_editor_theme().get_color("accent_color", "Editor"))
		tile.pressed.connect(func() -> void:
			_palette.hide()
			bridge.activate_shape(id, Input.is_key_pressed(KEY_ALT)))
		_palette_grid.add_child(tile)
	for tool in _snapshot.get("tools", []):
		var tool_id: String = tool["id"]
		var tile := _make_tile(tool["title"], TOOL_ICONS.get(tool_id, "MeshInstance3D"), tool.get("enabled", true))
		tile.pressed.connect(func() -> void:
			_palette.hide()
			bridge.start_tool(tool_id))
		_palette_grid.add_child(tile)
	var rect := _add_button.get_screen_transform() * Rect2(Vector2.ZERO, _add_button.size)
	_palette.popup(Rect2i(Vector2i(rect.position.x, rect.end.y), Vector2i.ZERO))


func _make_tile(title: String, icon_name: String, enabled: bool) -> Button:
	var tile := Button.new()
	tile.focus_mode = Control.FOCUS_NONE
	tile.text = title
	tile.icon = _icon(icon_name)
	tile.disabled = not enabled
	tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	tile.expand_icon = false
	tile.custom_minimum_size = Vector2(88, 64) * EditorInterface.get_editor_scale()
	return tile


func _fill_actions() -> void:
	var popup := _actions_button.get_popup()
	popup.clear()
	_action_ids.clear()
	for section in bridge.command_sections():
		var title: String = section.get("title", "")
		popup.add_separator(title)
		for command in section["commands"]:
			popup.add_item(command["title"], _action_ids.size())
			var index := popup.item_count - 1
			popup.set_item_disabled(index, not command["enabled"])
			var reason: String = command.get("reason", "")
			if not reason.is_empty():
				popup.set_item_tooltip(index, reason)
			_action_ids.append(command["id"])


func _on_action(id: int) -> void:
	if id >= 0 and id < _action_ids.size():
		bridge.execute(_action_ids[id])


## The add-on's icons are white; color them like the editor's own icons.
func _tint_icon(button: Button) -> void:
	var theme := EditorInterface.get_editor_theme()
	var normal := theme.get_color("font_color", "Editor")
	var accent := theme.get_color("accent_color", "Editor")
	button.add_theme_color_override("icon_normal_color", normal)
	button.add_theme_color_override("icon_hover_color", normal)
	button.add_theme_color_override("icon_focus_color", normal)
	button.add_theme_color_override("icon_pressed_color", accent)
	button.add_theme_color_override("icon_hover_pressed_color", accent)


func _icon(name_or_path: String) -> Texture2D:
	if name_or_path.begins_with("res://"):
		# Rasterize the SVG at the editor scale. This needs no import, which
		# has not run yet when the add-on is first enabled.
		var image := Image.new()
		if image.load_svg_from_string(FileAccess.get_file_as_string(name_or_path), EditorInterface.get_editor_scale()) == OK:
			return ImageTexture.create_from_image(image)
		return null
	var theme := EditorInterface.get_editor_theme()
	if theme.has_icon(name_or_path, "EditorIcons"):
		return theme.get_icon(name_or_path, "EditorIcons")
	return theme.get_icon("MeshInstance3D", "EditorIcons")
