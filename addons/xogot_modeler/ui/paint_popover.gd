@tool
extends PopupPanel

## Paint: material slots, colour presets and smoothing groups, as in Xogot.
## Click a tile to paint the selected faces; right-click it for more.

const SECTIONS := [["material", "Material"], ["colour", "Colour"], ["smoothing", "Smoothing"]]

var bridge: RefCounted

var _summary: Label
var _section_buttons := {}
var _content: VBoxContainer
var _menu: PopupMenu
var _menu_actions: Array[Callable] = []
var _textures := {}


func setup(native_bridge: RefCounted) -> void:
	bridge = native_bridge
	var scale := EditorInterface.get_editor_scale()
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 380 * scale
	column.add_theme_constant_override("separation", int(8 * scale))
	add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	var title := Label.new()
	title.text = tr("Paint")
	title.add_theme_font_override("font", _theme().get_font("bold", "EditorFonts"))
	titles.add_child(title)
	_summary = Label.new()
	_summary.add_theme_color_override("font_color", _theme().get_color("font_disabled_color", "Editor"))
	titles.add_child(_summary)
	var sample := Button.new()
	sample.flat = true
	sample.focus_mode = Control.FOCUS_NONE
	sample.icon = _theme().get_icon("ColorPick", "EditorIcons")
	sample.tooltip_text = tr("Sample from Selection")
	sample.pressed.connect(_sample)
	header.add_child(sample)
	var options := MenuButton.new()
	options.flat = true
	options.focus_mode = Control.FOCUS_NONE
	options.icon = _theme().get_icon("GuiTabMenuHl", "EditorIcons")
	options.tooltip_text = tr("Paint Options")
	var popup := options.get_popup()
	popup.add_item(tr("Load Palette…"), 0)
	popup.add_item(tr("Save Palette…"), 1)
	popup.add_item(tr("Reset Palette"), 2)
	popup.add_separator()
	popup.add_item(tr("Add Material Slot…"), 3)
	popup.id_pressed.connect(func(id: int) -> void:
		bridge.paint(["load_palette", "save_palette", "reset_palette", "add_material_slot"][id], -1))
	header.add_child(options)

	var sections := HBoxContainer.new()
	sections.add_theme_constant_override("separation", 0)
	column.add_child(sections)
	var group := ButtonGroup.new()
	for section in SECTIONS:
		var button := Button.new()
		button.text = tr(section[1])
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id: String = section[0]
		button.pressed.connect(func() -> void: bridge.set_paint_value("section", id))
		sections.add_child(button)
		_section_buttons[id] = button

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", int(8 * scale))
	column.add_child(_content)

	_menu = PopupMenu.new()
	_menu.id_pressed.connect(func(id: int) -> void:
		if id < _menu_actions.size():
			_menu_actions[id].call())
	add_child(_menu)


func refresh() -> void:
	if not visible or bridge == null:
		return
	var paint: Dictionary = bridge.paint_state()
	_summary.text = paint.get("summary", "")
	var section: String = paint.get("section", "material")
	for id in _section_buttons:
		_section_buttons[id].set_pressed_no_signal(id == section)
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	match section:
		"colour":
			_build_colours(paint)
		"smoothing":
			_build_smoothing(paint)
		_:
			_build_materials(paint)
	reset_size()


func _sample() -> void:
	var section: String = bridge.paint_state().get("section", "material")
	match section:
		"colour":
			bridge.paint("match_color", -1)
		"smoothing":
			bridge.paint("match_smoothing", -1)
		_:
			bridge.paint("match_material", -1)


# MARK: - Materials

func _build_materials(paint: Dictionary) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	_content.add_child(grid)
	var has_target: bool = paint.get("has_target", false)
	for material in paint.get("materials", []):
		var index: int = material["index"]
		var tile := _tile(material["label"], _material_icon(material), material.get("last_applied", false))
		tile.tooltip_text = material["path"] if not material["empty"] else tr("Empty slot: click to choose a material")
		tile.gui_input.connect(func(event: InputEvent) -> void:
			var button := event as InputEventMouseButton
			if button == null or not button.pressed:
				return
			if button.button_index == MOUSE_BUTTON_RIGHT:
				_material_menu(material)
			elif button.button_index == MOUSE_BUTTON_LEFT:
				tile.accept_event()
				if material["empty"]:
					bridge.paint("choose_material", index)
				elif button.alt_pressed:
					bridge.paint("match_material", index)
				elif has_target:
					bridge.paint("apply_material", index))
		grid.add_child(tile)
	var add := _tile(tr("Add Slot"), _theme().get_icon("Add", "EditorIcons"), false)
	add.pressed.connect(func() -> void: bridge.paint("add_material_slot", -1))
	grid.add_child(add)
	var footer := HBoxContainer.new()
	_content.add_child(footer)
	var hint := Label.new()
	hint.text = tr("Click to paint. Alt-click takes the selection's material.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapping label needs a width, or it measures one word per line.
	hint.custom_minimum_size.x = 240 * EditorInterface.get_editor_scale()
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_color_override("font_color", _theme().get_color("font_disabled_color", "Editor"))
	footer.add_child(hint)
	var browse := Button.new()
	browse.text = tr("Browse…")
	browse.focus_mode = Control.FOCUS_NONE
	browse.disabled = not has_target
	browse.pressed.connect(func() -> void: bridge.paint("choose_material", -1))
	footer.add_child(browse)


func _material_menu(material: Dictionary) -> void:
	var index: int = material["index"]
	var path: String = material["path"]
	var items := [
		[tr("Replace…"), func() -> void: bridge.paint("choose_material", index)],
		[tr("Set from Selection"), func() -> void: bridge.paint("match_material", index)],
	]
	if not material["empty"]:
		items.append([tr("Select Faces Using This"), func() -> void: bridge.paint("select_material", index)])
		items.append([tr("Inspect"), func() -> void:
			if ResourceLoader.exists(path):
				EditorInterface.edit_resource(load(path))])
		items.append([tr("Clear"), func() -> void: bridge.paint("clear_material", index)])
	_show_menu(items)


func _material_icon(material: Dictionary) -> Texture2D:
	if material.has("image"):
		var key := "%s:%d" % [material["path"], (material["image"] as PackedByteArray).size()]
		if not _textures.has(key):
			var image := Image.new()
			if image.load_png_from_buffer(material["image"]) == OK:
				image.resize(48, 48)
				_textures[key] = ImageTexture.create_from_image(image)
		if _textures.has(key):
			return _textures[key]
	if material.has("color"):
		return _swatch(material["color"])
	if material["empty"]:
		return null
	return _theme().get_icon("StandardMaterial3D", "EditorIcons")


# MARK: - Colours

func _build_colours(paint: Dictionary) -> void:
	var row := HBoxContainer.new()
	_content.add_child(row)
	var picker := ColorPickerButton.new()
	picker.color = paint.get("selected_color", Color.WHITE)
	picker.custom_minimum_size = Vector2(52, 36) * EditorInterface.get_editor_scale()
	picker.color_changed.connect(func(color: Color) -> void: bridge.set_paint_value("selected_color", color))
	row.add_child(picker)
	var hex := Label.new()
	var color: Color = paint.get("selected_color", Color.WHITE)
	hex.text = "#%s  %d%%" % [color.to_html(false).to_upper(), roundi(color.a * 100)]
	hex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hex)
	var apply := Button.new()
	apply.text = tr("Paint")
	apply.focus_mode = Control.FOCUS_NONE
	apply.disabled = not paint.get("has_target", false)
	apply.pressed.connect(func() -> void: bridge.paint("apply_color", -1))
	row.add_child(apply)

	var grid := GridContainer.new()
	grid.columns = 5
	_content.add_child(grid)
	for preset in paint.get("colors", []):
		var index: int = preset["index"]
		var label: String = preset["label"]
		var tile := _tile(label if not label.is_empty() else str(index + 1), _swatch(preset["color"]) if not preset["empty"] else _theme().get_icon("Add", "EditorIcons"), preset.get("last_applied", false))
		tile.custom_minimum_size = Vector2(64, 52) * EditorInterface.get_editor_scale()
		tile.gui_input.connect(func(event: InputEvent) -> void:
			var button := event as InputEventMouseButton
			if button == null or not button.pressed:
				return
			if button.button_index == MOUSE_BUTTON_RIGHT:
				_colour_menu(preset)
			elif button.button_index == MOUSE_BUTTON_LEFT:
				tile.accept_event()
				if preset["empty"]:
					bridge.paint("replace_color", index)
				else:
					bridge.paint("apply_color", index))
		grid.add_child(tile)
	var hint := Label.new()
	hint.text = tr("Click to paint. Right-click to replace a colour or select the faces that use it.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 360 * EditorInterface.get_editor_scale()
	hint.add_theme_color_override("font_color", _theme().get_color("font_disabled_color", "Editor"))
	_content.add_child(hint)


func _colour_menu(preset: Dictionary) -> void:
	var index: int = preset["index"]
	var items := [[tr("Replace with Current Colour"), func() -> void: bridge.paint("replace_color", index)]]
	if not preset["empty"]:
		items.append([tr("Use as Current Colour"), func() -> void: bridge.paint("use_color", index)])
		items.append([tr("Select Faces Using This"), func() -> void: bridge.paint("select_color", index)])
		items.append([tr("Clear"), func() -> void: bridge.paint("clear_color", index)])
	_show_menu(items)


# MARK: - Smoothing

func _build_smoothing(paint: Dictionary) -> void:
	var has_target: bool = paint.get("has_target", false)
	var shading := HBoxContainer.new()
	_content.add_child(shading)
	for intent in [["smooth", "Smooth", "shade_smooth"], ["faceted", "Faceted", "shade_faceted"]]:
		var button := Button.new()
		button.text = tr(intent[1])
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 40 * EditorInterface.get_editor_scale()
		button.set_pressed_no_signal(paint.get("shading", "") == intent[0])
		button.disabled = not has_target
		var command: String = intent[2]
		button.pressed.connect(func() -> void: bridge.paint(command, -1))
		shading.add_child(button)

	var header := HBoxContainer.new()
	_content.add_child(header)
	var caption := Label.new()
	caption.text = tr("Groups in This Mesh")
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(caption)
	var groups: Array = paint.get("groups", [])
	var create := Button.new()
	create.text = tr("New from Selection")
	create.focus_mode = Control.FOCUS_NONE
	create.disabled = not has_target or groups.size() >= 23
	create.pressed.connect(func() -> void: bridge.paint("new_group", -1))
	header.add_child(create)
	if groups.is_empty():
		var none := Label.new()
		none.text = tr("No smoothing groups in this mesh.")
		none.add_theme_color_override("font_color", _theme().get_color("font_disabled_color", "Editor"))
		_content.add_child(none)
	else:
		var chips := HFlowContainer.new()
		_content.add_child(chips)
		for group in groups:
			var chip := Button.new()
			chip.text = "%s (%d)" % [group["label"], group["face_count"]]
			chip.toggle_mode = true
			chip.focus_mode = Control.FOCUS_NONE
			chip.set_pressed_no_signal(group.get("selected", false))
			var index: int = group["index"]
			chip.gui_input.connect(func(event: InputEvent) -> void:
				var button := event as InputEventMouseButton
				if button == null or not button.pressed:
					return
				if button.button_index == MOUSE_BUTTON_RIGHT:
					_group_menu(group, groups)
				elif button.button_index == MOUSE_BUTTON_LEFT:
					chip.accept_event()
					bridge.paint("select_group", index))
			chips.add_child(chip)

	var tint := CheckBox.new()
	tint.text = tr("Tint Faces by Group")
	tint.focus_mode = Control.FOCUS_NONE
	tint.set_pressed_no_signal(paint.get("smoothing_preview", false))
	tint.toggled.connect(func(pressed: bool) -> void: bridge.set_paint_value("smoothing_preview", pressed))
	_content.add_child(tint)
	var normals := CheckBox.new()
	normals.text = tr("Show Normals")
	normals.focus_mode = Control.FOCUS_NONE
	normals.set_pressed_no_signal(paint.get("show_normals", false))
	normals.toggled.connect(func(pressed: bool) -> void: bridge.set_paint_value("show_normals", pressed))
	_content.add_child(normals)
	if paint.get("show_normals", false):
		var length := EditorSpinSlider.new()
		length.label = tr("Normal Length")
		length.min_value = 0.001
		length.max_value = 10
		length.step = 0.001
		length.allow_greater = true
		length.value = paint.get("normal_length", 0.1)
		length.value_changed.connect(func(value: float) -> void: bridge.set_paint_value("normal_length", value))
		_content.add_child(length)


func _group_menu(group: Dictionary, groups: Array) -> void:
	var index: int = group["index"]
	var items := [[tr("Select Faces"), func() -> void: bridge.paint("select_group", index)]]
	for other in groups:
		if other["index"] != index:
			var destination: int = other["index"]
			items.append([tr("Merge into %s") % other["label"], func() -> void: bridge.paint_merge_group(index, destination)])
	items.append([tr("Clear Group"), func() -> void: bridge.paint("clear_group", index)])
	_show_menu(items)


# MARK: - Helpers

func _tile(text: String, icon: Texture2D, highlighted: bool) -> Button:
	var tile := Button.new()
	tile.text = text
	tile.icon = icon
	tile.focus_mode = Control.FOCUS_NONE
	tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	tile.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tile.custom_minimum_size = Vector2(88, 72) * EditorInterface.get_editor_scale()
	if highlighted:
		tile.add_theme_color_override("font_color", _theme().get_color("accent_color", "Editor"))
	return tile


func _swatch(color: Color) -> Texture2D:
	var key := "swatch:" + color.to_html()
	if not _textures.has(key):
		var image := Image.create(40, 40, false, Image.FORMAT_RGBA8)
		image.fill(color)
		_textures[key] = ImageTexture.create_from_image(image)
	return _textures[key]


func _show_menu(items: Array) -> void:
	_menu.clear()
	_menu_actions.clear()
	for item in items:
		_menu.add_item(item[0], _menu_actions.size())
		_menu_actions.append(item[1])
	_menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


func _theme() -> Theme:
	return EditorInterface.get_editor_theme()
