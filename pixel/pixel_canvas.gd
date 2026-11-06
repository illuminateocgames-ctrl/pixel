@tool
extends Control

signal sprite_loaded(path: String, width: int, height: int)
signal sprite_modified
signal sprite_saved
signal zoom_changed(zoom: float)
signal color_picked(color: Color)
signal history_changed(can_undo: bool, can_redo: bool)
signal rollback_available_changed(available: bool)
signal layers_changed(active_layer: int)

const SUPPORTED_EXTENSIONS := ["png", "jpg", "jpeg"]
const CHECKER_SIZE := 16.0
const MIN_ZOOM := 0.01
const MAX_ZOOM := 256.0
const MAX_HISTORY := 50
const LAYER_COUNT := 4

var image: Image
var layers: Array[Image] = []
var active_layer_index := 0
var _selection_layer: Image
var _selection_layer_active := false
var source_path := ""
var draw_color := Color.BLACK
var active_tool := "draw"
var zoom := 1.0
var _pan_offset := Vector2.ZERO
var _texture: ImageTexture
var _is_drawing := false
var _fit_to_view_on_resize := true
var _is_dirty := false
var _hover_pixel := Vector2i(-1, -1)
var _selection := Rect2i()
var _selection_active := false
var _selection_dragging := false
var _gesture_active := false
var _moving_selection := false
var _gesture_start := Vector2i.ZERO
var _gesture_current := Vector2i.ZERO
var _move_offset := Vector2i.ZERO
var _move_source: Image
var _move_texture: ImageTexture
var _move_base: Image
var _move_base_texture: ImageTexture
var _is_panning := false
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _history_snapshot: Variant = null
var _history_action_changed := false
var _clipboard_image: Image


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	mouse_exited.connect(_on_mouse_exited)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if _fit_to_view_on_resize:
			_fit_image_to_view()
		else:
			queue_redraw()


func set_tool(tool_name: String) -> void:
	active_tool = tool_name


func set_draw_color(color: Color) -> void:
	draw_color = color


func set_active_layer(index: int) -> void:
	if index < 0 or index >= layers.size() or index == active_layer_index:
		return
	active_layer_index = index
	image = _selection_layer if _selection_layer_active else layers[active_layer_index]
	_refresh_texture()
	layers_changed.emit(active_layer_index)


func get_source_path() -> String:
	return source_path


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	for path in _get_dropped_paths(data):
		if _is_supported_sprite(path):
			return true
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	for path in _get_dropped_paths(data):
		if _is_supported_sprite(path):
			_load_sprite(path)
			return


func _get_dropped_paths(data: Variant) -> Array[String]:
	var paths: Array[String] = []
	if not data is Dictionary:
		return paths

	var files: Variant = data.get("files", [])
	if files is Array or files is PackedStringArray:
		for path in files:
			if path is String:
				paths.append(path)

	if paths.is_empty():
		var resource: Variant = data.get("resource", null)
		if resource is String:
			paths.append(resource)
		elif resource is Resource and not resource.resource_path.is_empty():
			paths.append(resource.resource_path)

	return paths


func _is_supported_sprite(path: String) -> bool:
	return path.get_extension().to_lower() in SUPPORTED_EXTENSIONS


func _load_sprite(path: String) -> int:
	var loaded_image := Image.new()
	var error := loaded_image.load(path)
	if error != OK or loaded_image.is_empty():
		push_warning("Pixel Art: Could not load sprite: %s" % path)
		return error if error != OK else ERR_FILE_CORRUPT
	if loaded_image.get_format() != Image.FORMAT_RGBA8:
		loaded_image.convert(Image.FORMAT_RGBA8)

	layers.clear()
	layers.append(loaded_image)
	for _index in range(1, LAYER_COUNT):
		var blank_layer := Image.create(loaded_image.get_width(), loaded_image.get_height(), false, Image.FORMAT_RGBA8)
		blank_layer.fill(Color.TRANSPARENT)
		layers.append(blank_layer)
	_selection_layer = Image.create(loaded_image.get_width(), loaded_image.get_height(), false, Image.FORMAT_RGBA8)
	_selection_layer.fill(Color.TRANSPARENT)
	_selection_layer_active = false
	active_layer_index = 0
	image = layers[active_layer_index]
	source_path = path
	_is_dirty = false
	_selection = Rect2i()
	_selection_active = false
	_selection_dragging = false
	_gesture_active = false
	_moving_selection = false
	_is_panning = false
	_undo_stack.clear()
	_redo_stack.clear()
	_history_snapshot = null
	_history_action_changed = false
	_pan_offset = Vector2.ZERO
	_fit_to_view_on_resize = true
	_fit_image_to_view()
	_refresh_texture()
	sprite_loaded.emit(source_path, image.get_width(), image.get_height())
	zoom_changed.emit(zoom)
	_emit_history_changed()
	rollback_available_changed.emit(has_rollback())
	layers_changed.emit(active_layer_index)
	return OK


func save_sprite() -> int:
	if image == null or source_path.is_empty():
		return ERR_UNCONFIGURED
	var backup_error := _save_rollback_copy()
	if backup_error != OK:
		return backup_error

	var extension := source_path.get_extension().to_lower()
	var error: int
	var composite := _compose_layers()
	if extension == "png":
		error = composite.save_png(source_path)
	elif extension == "jpg" or extension == "jpeg":
		error = composite.save_jpg(source_path, 1.0)
	else:
		return ERR_UNAVAILABLE

	if error == OK:
		_is_dirty = false
		sprite_saved.emit()
	return error


func has_rollback() -> bool:
	return not source_path.is_empty() and FileAccess.file_exists(_get_rollback_path(source_path))


func rollback_sprite() -> int:
	if not has_rollback():
		return ERR_DOES_NOT_EXIST
	var error := _copy_file(_get_rollback_path(source_path), source_path)
	if error != OK:
		return error
	return _load_sprite(source_path)


func _save_rollback_copy() -> int:
	if not FileAccess.file_exists(source_path):
		return ERR_FILE_NOT_FOUND
	var backup_path := _get_rollback_path(source_path)
	var backup_directory := ProjectSettings.globalize_path(backup_path.get_base_dir())
	var directory_error := DirAccess.make_dir_recursive_absolute(backup_directory)
	if directory_error != OK and not DirAccess.dir_exists_absolute(backup_directory):
		return directory_error

	var absolute_backup_path := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		var remove_error := DirAccess.remove_absolute(absolute_backup_path)
		if remove_error != OK:
			return remove_error

	var copy_error := _copy_file(source_path, backup_path)
	if copy_error == OK:
		rollback_available_changed.emit(true)
	return copy_error


func _copy_file(source: String, destination: String) -> int:
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null:
		return FileAccess.get_open_error()
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		var open_error := FileAccess.get_open_error()
		input.close()
		return open_error

	var remaining := input.get_length()
	while remaining > 0:
		var chunk_size := mini(remaining, 1024 * 1024)
		var chunk := input.get_buffer(chunk_size)
		if chunk.size() != chunk_size:
			input.close()
			output.close()
			return ERR_FILE_CANT_READ
		output.store_buffer(chunk)
		var write_error := output.get_error()
		if write_error != OK:
			input.close()
			output.close()
			return write_error
		remaining -= chunk.size()

	input.close()
	var write_error := output.get_error()
	output.close()
	return write_error


func _get_rollback_path(path: String) -> String:
	var relative_path: String
	if path.begins_with("res://"):
		relative_path = path.trim_prefix("res://")
	else:
		var external_id := path.sha256_text().substr(0, 16)
		relative_path = "external".path_join(external_id).path_join(path.get_file())
	return "res://addons/pixel/rollback".path_join(relative_path)


func discard_edits() -> int:
	if source_path.is_empty():
		return ERR_UNCONFIGURED
	return _load_sprite(source_path)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.ctrl_pressed or event.meta_pressed):
		if event.keycode == KEY_C:
			_copy_selection()
			accept_event()
		elif event.keycode == KEY_V:
			_paste_selection()
			accept_event()
	elif event is InputEventPanGesture:
		_fit_to_view_on_resize = false
		_pan_offset += event.delta
		_hover_pixel = _position_to_pixel(event.position)
		queue_redraw()
		accept_event()
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, zoom * event.factor)
		accept_event()
	elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if event.pressed:
			var direction := 1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2
			_zoom_at(event.position, zoom * direction)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_hover_pixel = _position_to_pixel(event.position)
		queue_redraw()
		_is_drawing = false
		if event.pressed:
			grab_focus()
			var pixel := _hover_pixel
			match active_tool:
				"eyedropper":
					_pick_color_at(event.position)
				"select":
					if pixel.x >= 0 and pixel.y >= 0:
						_begin_history_action()
						_commit_floating_selection()
						_selection_active = true
						_selection_dragging = true
						_gesture_start = pixel
						_update_selection(pixel)
					else:
						if _selection_layer_active:
							_begin_history_action()
							_commit_floating_selection()
						_selection_active = false
						_selection = Rect2i()
						_selection_dragging = false
						_commit_history_action()
						queue_redraw()
				"move":
					if _selection_active and _selection.has_point(pixel):
						_moving_selection = true
						_gesture_start = pixel
						_move_offset = Vector2i.ZERO
						_move_source = image.get_region(_selection)
						_move_texture = ImageTexture.create_from_image(_move_source)
						_move_base = image.duplicate()
						_move_base.fill_rect(_selection, Color.TRANSPARENT)
						_move_base_texture = ImageTexture.create_from_image(
							_compose_layers(-1, null, _move_base)
						)
						_begin_history_action()
					else:
						_is_panning = true
						_fit_to_view_on_resize = false
				"square", "circle", "line":
					if pixel.x >= 0 and pixel.y >= 0:
						_gesture_active = true
						_gesture_start = pixel
						_gesture_current = pixel
						_begin_history_action()
				"draw", "erase":
					_is_drawing = true
					_begin_history_action()
					grab_focus()
					_paint_at(event.position)
				"fill":
					if pixel.x >= 0 and pixel.y >= 0:
						_begin_history_action()
						_fill_at(pixel)
						_commit_history_action()
		else:
			_is_drawing = false
			if _selection_dragging:
				_update_selection(_position_to_pixel_clamped(event.position))
				_selection_dragging = false
				_lift_selection_to_hidden_layer()
			elif _moving_selection:
				_update_move_offset(_position_to_pixel_clamped(event.position))
				_finish_move()
			elif _gesture_active:
				_gesture_current = _position_to_pixel_clamped(event.position)
				_finish_pixel_gesture()
			_is_panning = false
			_commit_history_action()
		accept_event()
	elif event is InputEventMouseMotion:
		_hover_pixel = _position_to_pixel(event.position)
		if _selection_dragging:
			_update_selection(_position_to_pixel_clamped(event.position))
		elif _moving_selection:
			_update_move_offset(_position_to_pixel_clamped(event.position))
		elif _gesture_active:
			_gesture_current = _position_to_pixel_clamped(event.position)
			queue_redraw()
		elif _is_panning:
			_pan_offset += event.relative
			queue_redraw()
		elif _is_drawing:
			_paint_at(event.position)
		else:
			queue_redraw()
		accept_event()


func _on_mouse_exited() -> void:
	_hover_pixel = Vector2i(-1, -1)
	queue_redraw()


func _pick_color_at(position: Vector2) -> void:
	if image == null:
		return
	var pixel := _position_to_pixel(position)
	if pixel.x < 0 or pixel.y < 0:
		return
	draw_color = image.get_pixelv(pixel)
	color_picked.emit(draw_color)


func _copy_selection() -> void:
	if image == null or not _selection_active or _selection.size.x <= 0 or _selection.size.y <= 0:
		return
	_clipboard_image = _compose_layers().get_region(_selection)


func _paste_selection() -> void:
	if image == null or _clipboard_image == null or _clipboard_image.is_empty():
		return

	var paste_size := Vector2i(
		mini(_clipboard_image.get_width(), image.get_width()),
		mini(_clipboard_image.get_height(), image.get_height())
	)
	var source_image := _clipboard_image
	if paste_size != Vector2i(_clipboard_image.get_width(), _clipboard_image.get_height()):
		source_image = _clipboard_image.get_region(Rect2i(Vector2i.ZERO, paste_size))

	var anchor := _hover_pixel
	if anchor.x < 0 or anchor.y < 0:
		anchor = _selection.position if _selection_active else Vector2i(image.get_width() / 2, image.get_height() / 2)
	var paste_position := anchor - paste_size / 2
	paste_position.x = clampi(paste_position.x, 0, image.get_width() - paste_size.x)
	paste_position.y = clampi(paste_position.y, 0, image.get_height() - paste_size.y)

	_begin_history_action()
	_commit_floating_selection()
	_selection_layer.fill(Color.TRANSPARENT)
	_selection_layer.blend_rect(
		source_image,
		Rect2i(Vector2i.ZERO, paste_size),
		paste_position
	)
	_selection_layer_active = true
	image = _selection_layer
	_selection = Rect2i(paste_position, paste_size)
	_selection_active = true
	_mark_image_dirty()
	_refresh_texture()
	queue_redraw()
	_commit_history_action()


func _lift_selection_to_hidden_layer() -> void:
	if not _selection_active or _selection.size.x <= 0 or _selection.size.y <= 0:
		return
	var composite_region := _compose_layers().get_region(_selection)
	for layer in layers:
		layer.fill_rect(_selection, Color.TRANSPARENT)
	_selection_layer.fill_rect(_selection, Color.TRANSPARENT)
	_selection_layer.blit_rect(
		composite_region,
		Rect2i(Vector2i.ZERO, composite_region.get_size()),
		_selection.position
	)
	_selection_layer_active = true
	image = _selection_layer
	_mark_image_dirty()
	_refresh_texture()


func _commit_floating_selection() -> void:
	if not _selection_layer_active:
		return
	var composite_region := _compose_layers().get_region(_selection)
	for layer in layers:
		layer.fill_rect(_selection, Color.TRANSPARENT)
	_selection_layer.fill_rect(_selection, Color.TRANSPARENT)
	layers[0].blit_rect(
		composite_region,
		Rect2i(Vector2i.ZERO, composite_region.get_size()),
		_selection.position
	)
	_selection_layer_active = false
	image = layers[active_layer_index]
	_mark_image_dirty()
	_refresh_texture()


func _update_selection(pixel: Vector2i) -> void:
	var left := mini(_gesture_start.x, pixel.x)
	var top := mini(_gesture_start.y, pixel.y)
	var width := absi(_gesture_start.x - pixel.x) + 1
	var height := absi(_gesture_start.y - pixel.y) + 1
	_selection = Rect2i(Vector2i(left, top), Vector2i(width, height))
	queue_redraw()


func _update_move_offset(pixel: Vector2i) -> void:
	var requested := pixel - _gesture_start
	var min_x := -_selection.position.x
	var min_y := -_selection.position.y
	var max_x := image.get_width() - _selection.end.x
	var max_y := image.get_height() - _selection.end.y
	_move_offset = Vector2i(
		clampi(requested.x, min_x, max_x),
		clampi(requested.y, min_y, max_y)
	)
	queue_redraw()


func _finish_move() -> void:
	if _move_offset != Vector2i.ZERO:
		if _selection_layer_active:
			_selection_layer = _move_base
			image = _selection_layer
		else:
			image = _move_base
			layers[active_layer_index] = image
		var source_rect := Rect2i(Vector2i.ZERO, _move_source.get_size())
		image.blit_rect(_move_source, source_rect, _selection.position + _move_offset)
		_selection = Rect2i(_selection.position + _move_offset, _selection.size)
		_mark_image_dirty()
		_refresh_texture()
	_moving_selection = false
	_move_source = null
	_move_texture = null
	_move_base = null
	_move_base_texture = null
	_move_offset = Vector2i.ZERO
	queue_redraw()


func _finish_pixel_gesture() -> void:
	var changed := false
	if active_tool == "line":
		changed = _draw_line_pixels(_gesture_start, _gesture_current, draw_color)
	elif active_tool == "circle":
		changed = _draw_circle_pixels(_gesture_start, _gesture_current, draw_color)
	elif active_tool == "square":
		var top_left := Vector2i(
			mini(_gesture_start.x, _gesture_current.x),
			mini(_gesture_start.y, _gesture_current.y)
		)
		var bottom_right := Vector2i(
			maxi(_gesture_start.x, _gesture_current.x),
			maxi(_gesture_start.y, _gesture_current.y)
		)
		changed = _draw_line_pixels(top_left, Vector2i(bottom_right.x, top_left.y), draw_color) or changed
		changed = _draw_line_pixels(Vector2i(bottom_right.x, top_left.y), bottom_right, draw_color) or changed
		changed = _draw_line_pixels(bottom_right, Vector2i(top_left.x, bottom_right.y), draw_color) or changed
		changed = _draw_line_pixels(Vector2i(top_left.x, bottom_right.y), top_left, draw_color) or changed
	_gesture_active = false
	if changed:
		_mark_image_dirty()
		_refresh_texture()


func _draw_line_pixels(start: Vector2i, finish: Vector2i, color: Color) -> bool:
	var changed := false
	for pixel in _line_pixel_points(start, finish):
		changed = _set_image_pixel(pixel, color) or changed
	return changed


func _line_pixel_points(start: Vector2i, finish: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var x := start.x
	var y := start.y
	var dx := absi(finish.x - start.x)
	var dy := absi(finish.y - start.y)
	var step_x := 1 if start.x < finish.x else -1
	var step_y := 1 if start.y < finish.y else -1
	var error := dx - dy
	while true:
		points.append(Vector2i(x, y))
		if x == finish.x and y == finish.y:
			break
		var doubled_error := error * 2
		if doubled_error > -dy:
			error -= dy
			x += step_x
		if doubled_error < dx:
			error += dx
			y += step_y
	return points


func _draw_circle_pixels(center: Vector2i, edge: Vector2i, color: Color) -> bool:
	var changed := false
	for pixel in _circle_pixel_points(center, edge):
		changed = _set_image_pixel(pixel, color) or changed
	return changed


func _circle_pixel_points(center: Vector2i, edge: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var radius := roundi(Vector2(center - edge).length())
	var x := radius
	var y := 0
	var decision := 1 - radius
	while x >= y:
		points.append(center + Vector2i(x, y))
		points.append(center + Vector2i(y, x))
		points.append(center + Vector2i(-y, x))
		points.append(center + Vector2i(-x, y))
		points.append(center + Vector2i(-x, -y))
		points.append(center + Vector2i(-y, -x))
		points.append(center + Vector2i(y, -x))
		points.append(center + Vector2i(x, -y))
		y += 1
		if decision <= 0:
			decision += 2 * y + 1
		else:
			x -= 1
			decision += 2 * (y - x) + 1
	return points


func _set_image_pixel(pixel: Vector2i, color: Color) -> bool:
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= image.get_width() or pixel.y >= image.get_height():
		return false
	if _selection_active and not _selection.has_point(pixel):
		return false
	if image.get_pixelv(pixel) == color:
		return false
	image.set_pixelv(pixel, color)
	return true


func _fill_at(start: Vector2i) -> void:
	if start.x < 0 or start.y < 0 or start.x >= image.get_width() or start.y >= image.get_height():
		return
	if _selection_active and not _selection.has_point(start):
		return

	var target_color := image.get_pixelv(start)
	if target_color == draw_color:
		return

	var width := image.get_width()
	var height := image.get_height()
	var visited := PackedByteArray()
	visited.resize(width * height)
	var stack: Array[Vector2i] = [start]
	visited[start.y * width + start.x] = 1
	var changed := false
	while not stack.is_empty():
		var pixel: Vector2i = stack.pop_back()
		if image.get_pixelv(pixel) != target_color:
			continue
		image.set_pixelv(pixel, draw_color)
		changed = true
		for neighbor in [pixel + Vector2i.LEFT, pixel + Vector2i.RIGHT, pixel + Vector2i.UP, pixel + Vector2i.DOWN]:
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= width or neighbor.y >= height:
				continue
			if _selection_active and not _selection.has_point(neighbor):
				continue
			var neighbor_index: int = neighbor.y * width + neighbor.x
			if visited[neighbor_index] == 0 and image.get_pixelv(neighbor) == target_color:
				visited[neighbor_index] = 1
				stack.append(neighbor)

	if changed:
		_mark_image_dirty()
		_refresh_texture()


func _mark_image_dirty() -> void:
	if _history_snapshot != null:
		_history_action_changed = true
	if not _is_dirty:
		_is_dirty = true
		sprite_modified.emit()


func _begin_history_action() -> void:
	if image == null:
		return
	_history_snapshot = _snapshot_layer_state()
	_history_action_changed = false


func _commit_history_action() -> void:
	if _history_snapshot == null:
		return
	if _history_action_changed:
		_undo_stack.append(_history_snapshot)
		if _undo_stack.size() > MAX_HISTORY:
			_undo_stack.pop_front()
		_redo_stack.clear()
	_history_snapshot = null
	_history_action_changed = false
	_emit_history_changed()


func undo() -> void:
	if _history_snapshot != null:
		_commit_history_action()
	if _undo_stack.is_empty():
		return
	_redo_stack.append(_snapshot_layer_state())
	_restore_layer_state(_undo_stack.pop_back())
	_mark_image_dirty()
	_emit_history_changed()


func redo() -> void:
	if _history_snapshot != null:
		_commit_history_action()
	if _redo_stack.is_empty():
		return
	_undo_stack.append(_snapshot_layer_state())
	_restore_layer_state(_redo_stack.pop_back())
	_mark_image_dirty()
	_emit_history_changed()


func _snapshot_layer_state() -> Dictionary:
	var layer_copies: Array[Image] = []
	for layer in layers:
		layer_copies.append(layer.duplicate())
	return {
		"layers": layer_copies,
		"active_layer": active_layer_index,
		"selection_layer": _selection_layer.duplicate() if _selection_layer != null else null,
		"selection_layer_active": _selection_layer_active,
		"selection": _selection,
		"selection_active": _selection_active,
	}


func _restore_layer_state(state: Dictionary) -> void:
	layers.clear()
	for saved_layer in state["layers"]:
		layers.append(saved_layer)
	active_layer_index = state["active_layer"]
	_selection_layer = state["selection_layer"]
	_selection_layer_active = state["selection_layer_active"]
	_selection = state["selection"]
	_selection_active = state["selection_active"]
	image = _selection_layer if _selection_layer_active else layers[active_layer_index]
	_refresh_texture()
	layers_changed.emit(active_layer_index)


func _emit_history_changed() -> void:
	history_changed.emit(not _undo_stack.is_empty(), not _redo_stack.is_empty())


func _zoom_at(screen_position: Vector2, requested_zoom: float) -> void:
	if image == null:
		return

	_fit_to_view_on_resize = false
	var previous_rect := _image_rect()
	var image_position := (screen_position - previous_rect.position) / zoom
	zoom = clampf(requested_zoom, MIN_ZOOM, MAX_ZOOM)
	var centered_position := (size - Vector2(image.get_width(), image.get_height()) * zoom) * 0.5
	_pan_offset = screen_position - image_position * zoom - centered_position
	_hover_pixel = _position_to_pixel(screen_position)
	queue_redraw()
	zoom_changed.emit(zoom)


func _fit_image_to_view() -> void:
	if image == null or size.x <= 0.0 or size.y <= 0.0:
		queue_redraw()
		return

	var available := size * 0.75
	available.x = maxf(1.0, available.x)
	available.y = maxf(1.0, available.y)
	var fit_zoom := minf(
		MAX_ZOOM,
		minf(available.x / image.get_width(), available.y / image.get_height())
	)
	zoom = maxf(MIN_ZOOM, fit_zoom)
	_pan_offset = Vector2.ZERO
	queue_redraw()
	zoom_changed.emit(zoom)


func _paint_at(position: Vector2) -> void:
	if image == null or active_tool == "eyedropper":
		return

	var pixel := _position_to_pixel(position)
	if pixel.x < 0 or pixel.y < 0:
		return

	var color := Color.TRANSPARENT if active_tool == "erase" else draw_color
	if _set_image_pixel(pixel, color):
		_refresh_texture()
		_mark_image_dirty()


func _position_to_pixel(position: Vector2) -> Vector2i:
	var rect := _image_rect()
	if not rect.has_point(position):
		return Vector2i(-1, -1)

	var scale := rect.size / Vector2(image.get_width(), image.get_height())
	var pixel_x := int(floor((position.x - rect.position.x) / scale.x))
	var pixel_y := int(floor((position.y - rect.position.y) / scale.y))
	return Vector2i(pixel_x, pixel_y)


func _position_to_pixel_clamped(position: Vector2) -> Vector2i:
	if image == null:
		return Vector2i(-1, -1)
	var rect := _image_rect()
	var local_position := position - rect.position
	var pixel_x := clampi(int(floor(local_position.x / zoom)), 0, image.get_width() - 1)
	var pixel_y := clampi(int(floor(local_position.y / zoom)), 0, image.get_height() - 1)
	return Vector2i(pixel_x, pixel_y)


func _image_rect() -> Rect2:
	if image == null or image.is_empty():
		return Rect2()

	var draw_size := Vector2(image.get_width(), image.get_height()) * zoom
	return Rect2((size - draw_size) * 0.5 + _pan_offset, draw_size)


func _refresh_texture() -> void:
	if not layers.is_empty():
		_texture = ImageTexture.create_from_image(_compose_layers())
	elif image != null:
		_texture = ImageTexture.create_from_image(image)
	queue_redraw()


func _compose_layers(
	override_index: int = -1,
	override_image: Image = null,
	selection_override: Image = null
) -> Image:
	if layers.is_empty():
		return image.duplicate() if image != null else null
	var composite := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	composite.fill(Color.TRANSPARENT)
	var source_rect := Rect2i(Vector2i.ZERO, Vector2i(image.get_width(), image.get_height()))
	for index in range(layers.size()):
		var layer := layers[index]
		if index == override_index and override_image != null:
			layer = override_image
		composite.blend_rect(layer, source_rect, Vector2i.ZERO)
	if _selection_layer_active:
		var floating_layer := _selection_layer if selection_override == null else selection_override
		composite.blend_rect(floating_layer, source_rect, Vector2i.ZERO)
	return composite


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#202124"))
	if image == null:
		var message := "Drop a PNG or JPEG sprite here"
		draw_string(
			ThemeDB.fallback_font,
			Vector2(16.0, size.y * 0.5),
			message,
			HORIZONTAL_ALIGNMENT_CENTER,
			size.x - 32.0,
			16,
			Color("#a0a0a0")
		)
		return

	var rect := _image_rect()
	var visible_rect := rect.intersection(Rect2(Vector2.ZERO, size))
	if visible_rect.has_area():
		var first_column := maxi(0, int(floor((visible_rect.position.x - rect.position.x) / CHECKER_SIZE)))
		var last_column := int(ceil((visible_rect.end.x - rect.position.x) / CHECKER_SIZE))
		var first_row := maxi(0, int(floor((visible_rect.position.y - rect.position.y) / CHECKER_SIZE)))
		var last_row := int(ceil((visible_rect.end.y - rect.position.y) / CHECKER_SIZE))
		for y in range(first_row, last_row):
			for x in range(first_column, last_column):
				var shade := Color("#303236") if (x + y) % 2 == 0 else Color("#3a3c40")
				var tile := Rect2(
					rect.position + Vector2(x, y) * CHECKER_SIZE,
					Vector2(CHECKER_SIZE, CHECKER_SIZE)
				)
				draw_rect(tile.intersection(visible_rect), shade)

	var displayed_texture := _move_base_texture if _moving_selection else _texture
	if displayed_texture:
		draw_texture_rect(displayed_texture, rect, false)
	if _moving_selection and _move_texture:
		var moved_position := _selection.position + _move_offset
		var moved_rect := Rect2(
			rect.position + Vector2(moved_position) * zoom,
			Vector2(_selection.size) * zoom
		)
		draw_texture_rect(_move_texture, moved_rect, false)

	if _selection_active:
		var selection_position := _selection.position
		if _moving_selection:
			selection_position += _move_offset
		var selection_rect := Rect2(
			rect.position + Vector2(selection_position) * zoom,
			Vector2(_selection.size) * zoom
		)
		draw_rect(selection_rect, Color(0.2, 0.75, 1.0, 0.1))
		draw_rect(selection_rect, Color(0.45, 0.85, 1.0, 0.95), false, 1.0)

	if _gesture_active:
		var preview_color := draw_color
		preview_color.a = 0.6
		for pixel in _gesture_preview_pixels():
			if pixel.x < 0 or pixel.y < 0 or pixel.x >= image.get_width() or pixel.y >= image.get_height():
				continue
			if _selection_active and not _selection.has_point(pixel):
				continue
			var preview_rect := Rect2(
				rect.position + Vector2(pixel) * zoom,
				Vector2.ONE * zoom
			)
			draw_rect(preview_rect, preview_color)

	if _hover_pixel.x >= 0 and _hover_pixel.y >= 0:
		var pixel_rect := Rect2(
			rect.position + Vector2(_hover_pixel) * zoom,
			Vector2.ONE * zoom
		)
		var cursor_color := Color("#67d5ff")
		if active_tool == "draw":
			cursor_color = draw_color
			cursor_color.a = 0.55
		elif active_tool == "erase":
			cursor_color = Color(1.0, 0.24, 0.2, 0.6)
		draw_rect(pixel_rect, cursor_color)
		draw_rect(pixel_rect.grow(1.0), Color.WHITE, false, 1.0)


func _gesture_preview_pixels() -> Array[Vector2i]:
	if active_tool == "line":
		return _line_pixel_points(_gesture_start, _gesture_current)
	if active_tool == "circle":
		return _circle_pixel_points(_gesture_start, _gesture_current)

	var top_left := Vector2i(
		mini(_gesture_start.x, _gesture_current.x),
		mini(_gesture_start.y, _gesture_current.y)
	)
	var bottom_right := Vector2i(
		maxi(_gesture_start.x, _gesture_current.x),
		maxi(_gesture_start.y, _gesture_current.y)
	)
	var pixels: Array[Vector2i] = []
	pixels.append_array(_line_pixel_points(top_left, Vector2i(bottom_right.x, top_left.y)))
	pixels.append_array(_line_pixel_points(Vector2i(bottom_right.x, top_left.y), bottom_right))
	pixels.append_array(_line_pixel_points(bottom_right, Vector2i(top_left.x, bottom_right.y)))
	pixels.append_array(_line_pixel_points(Vector2i(top_left.x, bottom_right.y), top_left))
	return pixels
