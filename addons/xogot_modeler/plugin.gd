@tool
extends EditorPlugin

## Hosts the Xogot Modeler in the Godot editor. The editing logic is in the
## native extension (XogotModelerPluginBridge and the shared Modeler sources);
## this script forwards the EditorPlugin callbacks to it and owns the UI.

const ModelerUI := preload("ui/modeler_ui.gd")
const InspectorPlugin := preload("ui/inspector_plugin.gd")
const ExportFilter := preload("export_filter.gd")
const UpdateService := preload("update_service.gd")
const UpdatesDialog := preload("ui/updates_dialog.gd")
## Days before a beta build expires that the editor starts warning.
const BETA_WARNING_DAYS := 7

var bridge: RefCounted
var ui: ModelerUI
var inspector_plugin: InspectorPlugin
var export_filter: ExportFilter
var expired_dialog: AcceptDialog
var updates: UpdateService
var updates_dialog: UpdatesDialog
var update_notice: HBoxContainer
var update_label: Label


func _enter_tree() -> void:
	export_filter = ExportFilter.new()
	add_export_plugin(export_filter)
	_setup_updates()
	# Development tools can also inspect an expired or unsupported install.
	add_to_group("xogot_modeler_plugin")
	# Instantiate through ClassDB so that the script still parses when the
	# native library is missing for this platform.
	if not ClassDB.class_exists("XogotModelerPluginBridge"):
		push_error("Xogot Modeler: the native library is not loaded for this platform.")
		return
	bridge = ClassDB.instantiate("XogotModelerPluginBridge")
	var beta: Dictionary = bridge.beta_status()
	if not updates.verify_installation(beta):
		push_error("Xogot Modeler: " + updates.installation_warning)
		bridge = null
		updates_dialog.open.call_deferred()
		return
	if beta.get("expired", true):
		bridge = null
		_beta_expired(beta)
		return
	if beta.get("days_left", 0) <= BETA_WARNING_DAYS:
		push_warning("Xogot Modeler: this beta stops working after %s. Download a newer version from %s." % [beta.get("last_day"), beta.get("url")])
	bridge.attach(self)

	ui = ModelerUI.new()
	add_child(ui)
	ui.setup(self, bridge)

	inspector_plugin = InspectorPlugin.new()
	inspector_plugin.bridge = bridge
	inspector_plugin.make_editable_requested = ui._open_make_editable
	add_inspector_plugin(inspector_plugin)


func _setup_updates() -> void:
	updates = UpdateService.new()
	add_child(updates)
	# The development tools' project runs tests; those must not call the update server.
	updates.setup("", not EditorInterface.is_plugin_enabled("xogot_modeler_dev"))
	updates_dialog = UpdatesDialog.new()
	EditorInterface.get_base_control().add_child(updates_dialog)
	updates_dialog.setup(updates)
	add_tool_menu_item("Xogot Modeler — About / Beta Updates", _open_updates)
	update_notice = HBoxContainer.new()
	update_label = Label.new()
	update_notice.add_child(update_label)
	var review := Button.new()
	review.text = "View Update"
	review.pressed.connect(_open_updates)
	update_notice.add_child(review)
	var dismiss := Button.new()
	dismiss.text = "Dismiss"
	dismiss.pressed.connect(updates.dismiss)
	update_notice.add_child(dismiss)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, update_notice)
	updates.changed.connect(_refresh_update_notice)
	_refresh_update_notice()


func _refresh_update_notice() -> void:
	update_notice.visible = updates.should_notify()
	update_label.text = "Modeler beta %s available" % updates.release_info.get("latestVersion", "")


func _open_updates() -> void:
	if expired_dialog:
		expired_dialog.hide()
	updates_dialog.open()


## Each beta build stops working 30 days after it was built (ModelerBeta.swift);
## the editor then says so, and offers the download page.
func _beta_expired(beta: Dictionary) -> void:
	var message := "This beta of the Xogot Modeler stopped working after %s. Download the current version from %s." % [beta.get("last_day"), beta.get("url")]
	push_error("Xogot Modeler: " + message)
	expired_dialog = AcceptDialog.new()
	expired_dialog.title = "Xogot Modeler Beta Expired"
	expired_dialog.dialog_text = message
	expired_dialog.dialog_autowrap = true
	expired_dialog.ok_button_text = "Download"
	expired_dialog.add_cancel_button("Close")
	expired_dialog.confirmed.connect(func() -> void: OS.shell_open(updates.download_url()))
	expired_dialog.add_button("Check for Updates", true, "check")
	expired_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"check":
			_open_updates()
			updates.check())
	EditorInterface.get_base_control().add_child(expired_dialog)
	expired_dialog.popup_centered.call_deferred(Vector2i(480, 0))


func _exit_tree() -> void:
	remove_tool_menu_item("Xogot Modeler — About / Beta Updates")
	if updates:
		updates.shutdown()
		updates.changed.disconnect(_refresh_update_notice)
	if update_notice:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, update_notice)
		update_notice.queue_free()
	update_notice = null
	if updates_dialog:
		updates_dialog.queue_free()
	updates_dialog = null
	if updates:
		updates.queue_free()
	updates = null
	if expired_dialog:
		expired_dialog.queue_free()
	expired_dialog = null
	if export_filter:
		remove_export_plugin(export_filter)
	export_filter = null
	if inspector_plugin:
		remove_inspector_plugin(inspector_plugin)
	inspector_plugin = null
	if ui:
		ui.teardown()
		ui.queue_free()
	ui = null
	if bridge:
		bridge.detach()
	bridge = null


func _get_plugin_name() -> String:
	return "Xogot Modeler"


func _handles(object: Object) -> bool:
	return bridge != null and bridge.handles(object)


func _edit(object: Object) -> void:
	if bridge:
		bridge.edit(object)


func _make_visible(visible: bool) -> void:
	if bridge:
		bridge.make_visible(visible)


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if bridge == null:
		return AFTER_GUI_INPUT_PASS
	if ui:
		ui.last_camera = viewport_camera
	return bridge.forward_3d_gui_input(viewport_camera, event)


func _apply_changes() -> void:
	if bridge:
		bridge.apply_changes()


func _get_state() -> Dictionary:
	if bridge == null:
		return {}
	return bridge.editor_state()

