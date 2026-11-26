@tool
extends GridContainer

## Builds controls for the parameters that the native bridge describes with
## `parameters(scope)`, and writes edits back with `set_parameter`.
## Each descriptor has `key`, `label`, `type` (bool, int, float, choice or
## vector3), `value`, and the type's limits or choices.

var bridge: RefCounted
var scope := ""
## Optional data source instead of the bridge: `getter.call()` returns the
## descriptors and `setter.call(key, value)` applies an edit.
var getter: Callable
var setter: Callable

var _controls := {}
var _updating := false


func _init() -> void:
	columns = 2
	add_theme_constant_override("h_separation", 8)


func setup(native_bridge: RefCounted, parameter_scope: String) -> void:
	bridge = native_bridge
	scope = parameter_scope
	rebuild()


## Uses callables for the descriptors and the edits instead of the bridge.
func setup_with(descriptor_getter: Callable, value_setter: Callable) -> void:
	getter = descriptor_getter
	setter = value_setter
	scope = "custom"
	rebuild()


func _descriptors() -> Array:
	if getter.is_valid():
		return getter.call()
	if bridge == null or scope.is_empty():
		return []
	return bridge.parameters(scope)


## Recreates the controls. Call it when the scope's parameter list changes.
func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_controls.clear()
	for descriptor in _descriptors():
		var label := Label.new()
		label.text = descriptor["label"]
		label.tooltip_text = descriptor.get("help", "")
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(label)
		var control := _make_control(descriptor)
		control.tooltip_text = descriptor.get("help", "")
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(control)
		_controls[descriptor["key"]] = control
	refresh()


## Reads the current values without emitting edits. Rebuilds the controls
## when the scope's parameters changed, such as the options of another
## export format.
func refresh() -> void:
	if scope.is_empty():
		return
	var descriptors: Array = _descriptors()
	var keys := descriptors.map(func(descriptor: Dictionary) -> String: return descriptor["key"])
	if keys != _controls.keys():
		rebuild()
		return
	_updating = true
	for descriptor in descriptors:
		var control: Control = _controls.get(descriptor["key"])
		if control:
			_set_value(control, descriptor)
			_set_disabled(control, descriptor.get("disabled", false))
	_updating = false


func is_empty() -> bool:
	return _controls.is_empty()


func _make_control(descriptor: Dictionary) -> Control:
	var key: String = descriptor["key"]
	match descriptor["type"]:
		"bool":
			var check := CheckBox.new()
			check.toggled.connect(func(pressed: bool) -> void: _edit(key, pressed))
			return check
		"int", "float":
			var slider := EditorSpinSlider.new()
			slider.min_value = descriptor.get("min", 0)
			slider.max_value = descriptor.get("max", 100)
			slider.step = 1 if descriptor["type"] == "int" else descriptor.get("step", 0.001)
			slider.allow_greater = descriptor["type"] == "float"
			slider.allow_lesser = descriptor["type"] == "float" and descriptor.get("min", 0) < 0
			# A slider is only useful over a short range.
			slider.hide_slider = descriptor.get("max", 100) - descriptor.get("min", 0) > 200
			slider.custom_minimum_size.x = 120 * EditorInterface.get_editor_scale()
			var is_int: bool = descriptor["type"] == "int"
			slider.value_changed.connect(func(value: float) -> void: _edit(key, int(value) if is_int else value))
			return slider
		"choice" when descriptor.get("segmented", false):
			var segments := HBoxContainer.new()
			segments.add_theme_constant_override("separation", 0)
			var group := ButtonGroup.new()
			for choice in descriptor.get("choices", []):
				var segment := Button.new()
				segment.text = choice["label"]
				segment.toggle_mode = true
				segment.button_group = group
				segment.focus_mode = Control.FOCUS_NONE
				segment.set_meta("choice", choice["id"])
				var id: String = choice["id"]
				segment.pressed.connect(func() -> void: _edit(key, id))
				segments.add_child(segment)
			return segments
		"choice":
			var option := OptionButton.new()
			for choice in descriptor.get("choices", []):
				option.add_item(choice["label"])
				option.set_item_metadata(option.item_count - 1, choice["id"])
			option.item_selected.connect(func(index: int) -> void: _edit(key, option.get_item_metadata(index)))
			return option
		"color":
			var picker := ColorPickerButton.new()
			picker.custom_minimum_size = Vector2(60, 24) * EditorInterface.get_editor_scale()
			picker.color_changed.connect(func(color: Color) -> void: _edit(key, color))
			return picker
		"vector3":
			var row := HBoxContainer.new()
			for axis in ["x", "y", "z"]:
				var component := EditorSpinSlider.new()
				component.label = axis
				component.step = 0.001
				component.allow_greater = true
				component.allow_lesser = true
				component.min_value = -10000
				component.max_value = 10000
				component.hide_slider = true
				component.custom_minimum_size.x = 60 * EditorInterface.get_editor_scale()
				component.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				component.value_changed.connect(func(_value: float) -> void: _edit(key, _vector_value(row)))
				row.add_child(component)
			return row
	return Label.new()


func _set_value(control: Control, descriptor: Dictionary) -> void:
	var value: Variant = descriptor["value"]
	match descriptor["type"]:
		"bool":
			(control as CheckBox).set_pressed_no_signal(bool(value))
		"int", "float":
			(control as EditorSpinSlider).set_value_no_signal(float(value))
		"choice" when descriptor.get("segmented", false):
			for segment in control.get_children():
				(segment as Button).set_pressed_no_signal(segment.get_meta("choice") == value)
		"choice":
			var option := control as OptionButton
			for index in option.item_count:
				if option.get_item_metadata(index) == value:
					option.select(index)
		"color":
			(control as ColorPickerButton).color = value
		"vector3":
			var vector: Vector3 = value
			var components := control.get_children()
			for index in 3:
				(components[index] as EditorSpinSlider).set_value_no_signal(vector[index])


func _set_disabled(control: Control, disabled: bool) -> void:
	if control is BaseButton:
		(control as BaseButton).disabled = disabled
	elif control is EditorSpinSlider:
		(control as EditorSpinSlider).read_only = disabled
	else:
		for child in control.get_children():
			if child is Control:
				_set_disabled(child, disabled)


func _vector_value(row: Control) -> Vector3:
	var components := row.get_children()
	return Vector3(components[0].value, components[1].value, components[2].value)


func _edit(key: String, value: Variant) -> void:
	if _updating:
		return
	if setter.is_valid():
		setter.call(key, value)
	elif bridge:
		bridge.set_parameter(key, value)
