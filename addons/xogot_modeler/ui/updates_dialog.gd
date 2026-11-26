@tool
extends AcceptDialog

var service: Node
var _details: Label
var _status: Label
var _notes: Label
var _automatic: CheckBox
var _check: Button
var _download: Button
var _changelog: Button


func setup(updates: Node) -> void:
	service = updates
	title = "Xogot Modeler — Beta Updates"
	ok_button_text = "Close"
	var layout := VBoxContainer.new()
	layout.custom_minimum_size.x = 580 * EditorInterface.get_editor_scale()
	layout.add_theme_constant_override("separation", 12)
	add_child(layout)
	_details = Label.new()
	layout.add_child(_details)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status)
	_notes = Label.new()
	_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_notes)
	_automatic = CheckBox.new()
	_automatic.text = "Automatically check for beta updates once a day"
	_automatic.toggled.connect(service.set_automatic)
	layout.add_child(_automatic)
	var actions := HBoxContainer.new()
	layout.add_child(actions)
	_check = Button.new()
	_check.text = "Check for Updates"
	_check.pressed.connect(func() -> void: service.check())
	actions.add_child(_check)
	_download = Button.new()
	_download.text = "Download Beta"
	_download.pressed.connect(func() -> void: OS.shell_open(service.download_url()))
	actions.add_child(_download)
	_changelog = Button.new()
	_changelog.text = "Release Notes"
	_changelog.pressed.connect(func() -> void: OS.shell_open(service.release_info.get("changelog", service.DOWNLOAD_URL)))
	actions.add_child(_changelog)
	var instructions := Label.new()
	instructions.text = "Beta builds expire 30 days after they are built.\nTo update: save your work, close Godot, replace addons/xogot_modeler with the complete new package, then reopen your project."
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(instructions)
	service.changed.connect(refresh)
	refresh()


func refresh() -> void:
	_details.text = "Installed: %s (beta)" % service.version
	if not service.build_info.is_empty():
		_details.text += "\nBuilt: %s · Expires: %s (UTC)" % [service.build_info.get("buildDate", "Unknown"), service.build_info.get("expiresAt", "Unknown").replace("T00:00:00Z", " 00:00")]
	_status.text = service.installation_warning if not service.installation_warning.is_empty() else service.status
	_notes.text = service.release_info.get("description", "")
	_notes.visible = service.release_info.get("releaseAvailable", false)
	_automatic.set_pressed_no_signal(service.automatic)
	_check.disabled = service.checking
	_download.text = "Download Beta %s" % service.release_info.get("latestVersion", "") if service.update_available() else "Open Download Page"
	_changelog.visible = service.release_info.get("releaseAvailable", false)


func open() -> void:
	refresh()
	min_size.x = int(600 * EditorInterface.get_editor_scale())
	popup_centered(Vector2i(Vector2(600, 360) * EditorInterface.get_editor_scale()))
	# Wrapped labels need the final width before their minimum height is known.
	await get_tree().process_frame
	reset_size()
	move_to_center()
