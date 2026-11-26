@tool
extends Node

## Owns the Modeler's editor UI and keeps it in sync with the native bridge.

const Toolbar := preload("toolbar.gd")
const ViewportHUD := preload("viewport_hud.gd")
const ParameterForm := preload("parameter_form.gd")
const OptionsDialog := preload("options_dialog.gd")
const UVEditor := preload("uv_editor.gd")

var plugin: EditorPlugin
var bridge: RefCounted
var toolbar: Toolbar
var uv_editor: UVEditor
## The camera of the viewport that last forwarded input; context menus open there.
var last_camera: Camera3D

var _huds: Array[ViewportHUD] = []
var _options: OptionsDialog
var _make_editable: ConfirmationDialog
var _make_editable_fields := {}
var _confirmation: ConfirmationDialog
var _confirmation_form: ParameterForm
var _confirming := ""
var _context_menu: PopupMenu
var _export: ConfirmationDialog
var _export_form: ParameterForm
var _export_message: Label
var _export_shown := false
var _overwrite: ConfirmationDialog
var _boolean: AcceptDialog
var _boolean_form: ParameterForm
var _boolean_message: Label
var _boolean_shown := false
var _snapshot := {}


func setup(editor_plugin: EditorPlugin, native_bridge: RefCounted) -> void:
	plugin = editor_plugin
	bridge = native_bridge
	name = "XogotModelerUI"
	var base := EditorInterface.get_base_control()

	toolbar = Toolbar.new()
	toolbar.setup(bridge)
	toolbar.make_editable_requested.connect(_open_make_editable)
	toolbar.options_requested.connect(open_options)
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, toolbar)

	for index in 4:
		var hud := ViewportHUD.new()
		hud.setup(bridge)
		var host := _viewport_host(index)
		if host:
			host.add_child(hud)
		_huds.append(hud)

	_options = OptionsDialog.new()
	_options.setup(bridge)
	base.add_child(_options)

	_build_make_editable_dialog()
	base.add_child(_make_editable)

	_confirmation = ConfirmationDialog.new()
	_confirmation_form = ParameterForm.new()
	_confirmation.add_child(_confirmation_form)
	_confirmation.confirmed.connect(_on_confirmed)
	_confirmation.canceled.connect(_on_confirmation_canceled)
	base.add_child(_confirmation)

	_build_export_dialogs()
	base.add_child(_export)
	base.add_child(_overwrite)
	_build_boolean_dialog()
	base.add_child(_boolean)

	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(func(id: int) -> void: bridge.activate_menu_item(id))
	base.add_child(_context_menu)

	# The UV editor fills the bottom panel control that the native side registered.
	var uv_host: Control = bridge.uv_panel_host()
	if uv_host:
		# The bottom panel takes its height from the host's minimum size.
		uv_host.custom_minimum_size.y = 320 * EditorInterface.get_editor_scale()
		uv_host.clip_contents = true
		uv_editor = UVEditor.new()
		uv_editor.setup(bridge)
		uv_host.add_child(uv_editor)
		bridge.uv_changed.connect(uv_editor.refresh)
		uv_editor.refresh()

	bridge.state_changed.connect(refresh)
	bridge.settings_requested.connect(open_options)
	bridge.context_menu_requested.connect(_show_context_menu)
	refresh()


func teardown() -> void:
	if bridge:
		bridge.state_changed.disconnect(refresh)
		bridge.settings_requested.disconnect(open_options)
		bridge.context_menu_requested.disconnect(_show_context_menu)
	if toolbar:
		plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, toolbar)
		toolbar.queue_free()
	if uv_editor:
		bridge.uv_changed.disconnect(uv_editor.refresh)
		uv_editor.queue_free()
	for hud in _huds:
		hud.queue_free()
	_huds.clear()
	for node in [_options, _make_editable, _confirmation, _context_menu, _export, _overwrite, _boolean]:
		if node:
			node.queue_free()
	bridge = null


func refresh() -> void:
	if bridge == null:
		return
	_snapshot = bridge.snapshot()
	toolbar.update_from(_snapshot)
	var active: int = _snapshot.get("active_viewport", 0)
	for index in _huds.size():
		var hud := _huds[index]
		if index == active:
			hud.update_from(_snapshot)
		else:
			hud.visible = false
	_options.refresh()
	_update_confirmation()
	_update_export()
	_update_boolean()


func open_options() -> void:
	var category := ""
	var adjustment: String = _snapshot.get("adjustment", "")
	match adjustment:
		"extrudeFaces", "extrudeEdges":
			category = "extrude"
		"insetFaces":
			category = "inset"
		"weldVertices", "collapseVertices":
			category = "weld"
		"subdivideEdges":
			category = "subdivide"
		"fillHole":
			category = "fillHole"
		"offsetElements":
			category = "offset"
	_options.open(category)


## The Control of a 3D viewport that the HUD is added to: the viewport's
## Node3DEditorViewport, which also holds the gizmo surface.
func _viewport_host(index: int) -> Control:
	var sub_viewport := EditorInterface.get_editor_viewport_3d(index)
	if sub_viewport == null:
		return null
	var container := sub_viewport.get_parent()
	if container == null:
		return null
	return container.get_parent() as Control


func _build_make_editable_dialog() -> void:
	_make_editable = ConfirmationDialog.new()
	_make_editable.title = tr("Make Editable")
	_make_editable.ok_button_text = tr("Make Editable")
	var grid := GridContainer.new()
	grid.columns = 2
	_make_editable.add_child(grid)
	for key in ["detect_quads", "keep_materials", "keep_smoothing"]:
		var label := Label.new()
		label.text = {"detect_quads": tr("Detect Quads"), "keep_materials": tr("Keep Materials"), "keep_smoothing": tr("Keep Imported Smoothing")}[key]
		grid.add_child(label)
		var check := CheckBox.new()
		check.button_pressed = true
		grid.add_child(check)
		_make_editable_fields[key] = check
	var angle_label := Label.new()
	angle_label.text = tr("Smoothing Angle")
	grid.add_child(angle_label)
	var angle := EditorSpinSlider.new()
	angle.min_value = 0
	angle.max_value = 180
	angle.step = 1
	angle.value = 60
	angle.suffix = "°"
	angle.custom_minimum_size.x = 120 * EditorInterface.get_editor_scale()
	grid.add_child(angle)
	_make_editable_fields["smoothing_angle"] = angle
	_make_editable_fields["keep_smoothing"].toggled.connect(func(pressed: bool) -> void: angle.read_only = pressed)
	angle.read_only = true
	_make_editable.confirmed.connect(func() -> void:
		bridge.make_editable(
			_make_editable_fields["detect_quads"].button_pressed,
			_make_editable_fields["keep_materials"].button_pressed,
			_make_editable_fields["keep_smoothing"].button_pressed,
			_make_editable_fields["smoothing_angle"].value))


func _open_make_editable() -> void:
	_make_editable.popup_centered()


## Actions that change the scene tree ask before they run, showing their options.
func _update_confirmation() -> void:
	var action: String = _snapshot.get("confirmation", "")
	if action == _confirming:
		return
	_confirming = action
	if action.is_empty():
		if _confirmation.visible:
			_confirmation.hide()
		return
	_confirmation.title = _snapshot.get("confirmation_title", tr("Confirm"))
	_confirmation_form.setup(bridge, "action:" + action)
	if _confirmation_form.is_empty():
		_confirmation.dialog_text = tr("Run %s?") % _confirmation.title
	else:
		_confirmation.dialog_text = ""
	_confirmation.popup_centered()


func _on_confirmed() -> void:
	_confirming = ""
	bridge.confirm_action()


func _on_confirmation_canceled() -> void:
	_confirming = ""
	bridge.cancel_confirmation()


func _show_context_menu(items: Array, position: Vector2) -> void:
	_context_menu.clear(true)
	_fill_menu(_context_menu, items)
	var screen_position := DisplayServer.mouse_get_position()
	if last_camera and is_instance_valid(last_camera):
		var container := last_camera.get_viewport().get_parent() as SubViewportContainer
		if container:
			screen_position = Vector2i(container.get_screen_position() + position * max(1, container.stretch_shrink))
	_context_menu.popup(Rect2i(screen_position, Vector2i.ZERO))


func _fill_menu(menu: PopupMenu, items: Array) -> void:
	for item in items:
		if item.get("separator", false):
			menu.add_separator()
		elif item.has("children"):
			var submenu := PopupMenu.new()
			submenu.id_pressed.connect(func(id: int) -> void: bridge.activate_menu_item(id))
			_fill_menu(submenu, item["children"])
			menu.add_submenu_node_item(item["title"], submenu)
		else:
			menu.add_item(item["title"], item["id"])
			menu.set_item_disabled(menu.item_count - 1, not item.get("enabled", true))


## Export Mesh: options, then the destination file (from the native side),
## then a confirmation when companion files would be replaced.
func _build_export_dialogs() -> void:
	_export = ConfirmationDialog.new()
	_export.title = tr("Export Mesh")
	_export.ok_button_text = tr("Export…")
	var column := VBoxContainer.new()
	_export.add_child(column)
	_export_form = ParameterForm.new()
	column.add_child(_export_form)
	_export_message = Label.new()
	_export_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_export_message.custom_minimum_size.x = 320 * EditorInterface.get_editor_scale()
	column.add_child(_export_message)
	_export.confirmed.connect(func() -> void:
		_export_shown = false
		bridge.export_run()
		bridge.export_closed())
	_export.canceled.connect(func() -> void:
		_export_shown = false
		bridge.export_closed())

	_overwrite = ConfirmationDialog.new()
	_overwrite.title = tr("Replace Export Companion Files?")
	_overwrite.ok_button_text = tr("Replace Files")
	_overwrite.confirmed.connect(func() -> void: bridge.export_confirm_overwrite())
	_overwrite.canceled.connect(func() -> void: bridge.export_cancel_overwrite())


func _update_export() -> void:
	var export: Dictionary = _snapshot.get("export", {})
	if export.is_empty():
		if _export.visible:
			_export_shown = false
			_export.hide()
			bridge.export_closed()
		if _overwrite.visible:
			_overwrite.hide()
		return
	var files: PackedStringArray = export.get("overwrite_files", PackedStringArray())
	if not files.is_empty():
		if not _overwrite.visible:
			_overwrite.dialog_text = tr("These files already exist. Replacing them cannot be undone:\n%s") % ", ".join(files)
			_overwrite.popup_centered()
		return
	if not _export_shown:
		_export_shown = true
		_export_form.setup(bridge, "export")
		bridge.export_shown()
		_export.popup_centered()
	else:
		_export_form.refresh()
	_export_message.text = export.get("message", "")
	_export_message.visible = not _export_message.text.is_empty()
	_export.get_ok_button().disabled = not export.get("can_export", false)


## Boolean (experimental): combines two meshes into a new one.
func _build_boolean_dialog() -> void:
	_boolean = AcceptDialog.new()
	_boolean.title = tr("Boolean")
	_boolean.ok_button_text = tr("Apply")
	_boolean.dialog_hide_on_ok = false
	var column := VBoxContainer.new()
	_boolean.add_child(column)
	_boolean_form = ParameterForm.new()
	column.add_child(_boolean_form)
	_boolean_message = Label.new()
	_boolean_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_boolean_message.custom_minimum_size.x = 320 * EditorInterface.get_editor_scale()
	column.add_child(_boolean_message)
	_boolean.add_button(tr("Refresh Meshes"), false, "refresh")
	_boolean.add_cancel_button(tr("Close"))
	_boolean.custom_action.connect(func(action: StringName) -> void:
		if action == &"refresh":
			bridge.boolean_refresh())
	_boolean.confirmed.connect(func() -> void: bridge.boolean_apply())
	_boolean.canceled.connect(func() -> void:
		_boolean_shown = false
		bridge.boolean_closed())


func _update_boolean() -> void:
	var boolean: Dictionary = _snapshot.get("boolean", {})
	if boolean.is_empty():
		if _boolean.visible:
			_boolean_shown = false
			_boolean.hide()
		return
	if not _boolean_shown:
		_boolean_shown = true
		_boolean_form.setup(bridge, "boolean")
		_boolean.popup_centered()
	else:
		_boolean_form.refresh()
	_boolean_message.text = boolean.get("message", "")
	_boolean_message.visible = not _boolean_message.text.is_empty()
	_boolean.get_ok_button().disabled = not boolean.get("can_apply", false)
