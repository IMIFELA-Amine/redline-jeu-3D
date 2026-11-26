@tool
extends Control

## The UV canvas: draws the native UV state and turns pointer input into its
## gestures. UV v points up; the view's y points down.
##
## Drag to select, or to move, rotate or scale with the active tool. Shift
## adds to the selection, Cmd/Ctrl snaps. Scroll or the middle button pans,
## Cmd/Ctrl-scroll or a pinch zooms; 0 recenters, + and - zoom, Escape cancels.

const AUTO_COLOR := Color(0.2, 0.8, 0.95)
const MANUAL_COLOR := Color(1.0, 0.6, 0.15)
const SELECTED_COLOR := Color(1.0, 0.85, 0.1)

var bridge: RefCounted
var texture: Texture2D

var _data := {}
var _dragging := false


func setup(native_bridge: RefCounted) -> void:
	bridge = native_bridge
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(240, 200) * EditorInterface.get_editor_scale()


func refresh() -> void:
	if bridge == null:
		return
	_data = bridge.uv_canvas()
	texture = bridge.uv_texture()
	queue_redraw()


# MARK: - Mapping

func _scale() -> float:
	var zoom: float = clampf(_data.get("zoom", 1.0), 0.03, 128.0)
	return maxf(1.0, minf(size.x, size.y) * 0.8 * zoom)


func _center() -> Vector2:
	return _data.get("center", Vector2(0.5, 0.5))


func _point(uv: Vector2) -> Vector2:
	var center := _center()
	var scale := _scale()
	return Vector2(size.x / 2 + (uv.x - center.x) * scale, size.y / 2 - (uv.y - center.y) * scale)


func _uv(point: Vector2) -> Vector2:
	var scale := _scale()
	return _center() + Vector2((point.x - size.x / 2) / scale, (size.y / 2 - point.y) / scale)


func _uv_delta(delta: Vector2) -> Vector2:
	var scale := _scale()
	return Vector2(delta.x / scale, -delta.y / scale)


# MARK: - Drawing

func _draw() -> void:
	var theme := EditorInterface.get_editor_theme()
	draw_rect(Rect2(Vector2.ZERO, size), theme.get_color("dark_color_2", "Editor"))
	var low := _point(Vector2(0, 1))
	var high := _point(Vector2(1, 0))
	var unit := Rect2(low, high - low)
	if _data.get("texture_preview", true):
		if texture:
			draw_texture_rect(texture, unit, false)
		else:
			for x in 8:
				for y in 8:
					var cell := Rect2(unit.position + unit.size * Vector2(x, y) / 8.0, unit.size / 8.0)
					draw_rect(cell, Color(0.5, 0.5, 0.5, 0.12 if (x + y) % 2 == 0 else 0.25))
	if _data.get("show_grid", true):
		_draw_grid()
	draw_rect(unit, theme.get_color("font_color", "Editor").darkened(0.3), false, 1.0)

	_draw_fill(_data.get("auto_fill", PackedVector2Array()), Color(AUTO_COLOR, 0.2))
	_draw_fill(_data.get("manual_fill", PackedVector2Array()), Color(MANUAL_COLOR, 0.2))
	_draw_lines(_data.get("auto_edges", PackedVector2Array()), AUTO_COLOR, 1.0)
	_draw_lines(_data.get("manual_edges", PackedVector2Array()), MANUAL_COLOR, 1.0)
	_draw_lines(_data.get("selected_face_edges", PackedVector2Array()), SELECTED_COLOR, 2.0)
	_draw_lines(_data.get("selected_edges", PackedVector2Array()), SELECTED_COLOR, 3.0)
	for vertex in _data.get("vertices", PackedVector2Array()):
		draw_circle(_point(vertex), 2.5, AUTO_COLOR)
	for vertex in _data.get("selected_vertices", PackedVector2Array()):
		draw_circle(_point(vertex), 4.0, SELECTED_COLOR)
	if _data.has("rectangle_start"):
		var a := _point(_data["rectangle_start"])
		var b := _point(_data["rectangle_end"])
		var rect := Rect2(a, b - a).abs()
		var accent := theme.get_color("accent_color", "Editor")
		draw_rect(rect, Color(accent, 0.1))
		draw_rect(rect, accent, false, 1.0)
	if _data.has("pivot"):
		var pivot := _point(_data["pivot"])
		draw_arc(pivot, 7, 0, TAU, 24, SELECTED_COLOR, 2.0)
		draw_line(pivot - Vector2(10, 0), pivot + Vector2(10, 0), SELECTED_COLOR)
		draw_line(pivot - Vector2(0, 10), pivot + Vector2(0, 10), SELECTED_COLOR)


func _draw_grid() -> void:
	var a := _uv(Vector2.ZERO)
	var b := _uv(size)
	var low := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var high := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var step := maxf(clampf(_data.get("grid_increment", 0.125), 0.02, 2.0), 12.0 / _scale())
	var lines := PackedVector2Array()
	var x := floorf(low.x / step) * step
	while x <= high.x and lines.size() < 2000:
		lines.append(_point(Vector2(x, low.y)))
		lines.append(_point(Vector2(x, high.y)))
		x += step
	var y := floorf(low.y / step) * step
	while y <= high.y and lines.size() < 4000:
		lines.append(_point(Vector2(low.x, y)))
		lines.append(_point(Vector2(high.x, y)))
		y += step
	if not lines.is_empty():
		draw_multiline(lines, Color(0.5, 0.5, 0.5, 0.2))


func _draw_fill(triangles: PackedVector2Array, color: Color) -> void:
	for index in range(0, triangles.size() - 2, 3):
		draw_colored_polygon(PackedVector2Array([_point(triangles[index]), _point(triangles[index + 1]), _point(triangles[index + 2])]), color)


func _draw_lines(segments: PackedVector2Array, color: Color, width: float) -> void:
	if segments.is_empty():
		return
	var points := PackedVector2Array()
	points.resize(segments.size())
	for index in segments.size():
		points[index] = _point(segments[index])
	draw_multiline(points, color, width)


# MARK: - Input

func _gui_input(event: InputEvent) -> void:
	if bridge == null:
		return
	var button := event as InputEventMouseButton
	if button:
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				grab_focus()
				var command := button.ctrl_pressed or button.meta_pressed
				if button.pressed:
					_dragging = true
					bridge.uv_begin(_uv(button.position), 12.0 / _scale(), button.shift_pressed, command)
				elif _dragging:
					_dragging = false
					bridge.uv_end(_uv(button.position), 8.0 / _scale())
				accept_event()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					var factor := 1.1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1
					if button.ctrl_pressed or button.meta_pressed:
						bridge.uv_zoom(factor, _uv(button.position))
					else:
						var direction := 1.0 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
						bridge.uv_pan(_uv_delta(Vector2(0, 40 * direction)))
				accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion:
		if motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			bridge.uv_pan(_uv_delta(motion.relative))
			accept_event()
		elif _dragging and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			bridge.uv_update(_uv(motion.position), motion.ctrl_pressed or motion.meta_pressed)
			accept_event()
		return
	var pan := event as InputEventPanGesture
	if pan:
		if pan.ctrl_pressed or pan.meta_pressed:
			bridge.uv_zoom(1.0 - pan.delta.y * 0.05, _uv(pan.position))
		else:
			bridge.uv_pan(_uv_delta(-pan.delta * 20.0))
		accept_event()
		return
	var magnify := event as InputEventMagnifyGesture
	if magnify:
		bridge.uv_zoom(magnify.factor, _uv(magnify.position))
		accept_event()
		return
	var key := event as InputEventKey
	if key and key.pressed:
		match key.keycode:
			KEY_ESCAPE:
				_dragging = false
				bridge.uv_cancel()
			KEY_0:
				bridge.uv_run("recenter", "")
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				bridge.uv_run("zoom_in", "")
			KEY_MINUS, KEY_KP_SUBTRACT:
				bridge.uv_run("zoom_out", "")
			_:
				return
		accept_event()
