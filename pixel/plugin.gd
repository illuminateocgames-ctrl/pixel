@tool
extends EditorPlugin

const SCREEN_NAME := "Pixel"
const PixelCanvasScript = preload("res://addons/pixel/pixel_canvas.gd")
const ICON_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><rect x="1.25" y="1.25" width="13.5" height="13.5" rx="3" fill="none" stroke="#e6e6e6" stroke-width="1.5"/></svg>"""
const PALETTE_SIZE := 16
const PALETTE_CONFIG_PATH := "user://pixel_palette.cfg"

var workspace: VBoxContainer
var canvas: Control
var redraw_button: Button
var discard_button: Button
var undo_button: Button
var redo_button: Button
var rollback_button: Button
var status_label: Label
var zoom_label: Label
var color_picker: ColorPickerButton
var pixel_icon: Texture2D
var current_sprite_path := ""
var current_draw_color := Color.BLACK
var palette_colors: Array[Color] = []
var palette_used: Array[bool] = []
var palette_buttons: Array[Button] = []
var timeline_bar: VBoxContainer
var frame_strip_container: HBoxContainer
var frame_buttons: Array[Button] = []
var frame_button_group: ButtonGroup
var play_button: Button
var onion_check: CheckBox
var new_frame_button: Button
var duplicate_frame_button: Button
var delete_frame_button: Button
var move_left_button: Button
var move_right_button: Button
var duration_spin: SpinBox
var fps_label: Label
var frame_counter_label: Label
var tool_buttons: Dictionary = {}


func _enter_tree() -> void:
	_build_workspace()
	EditorInterface.get_editor_main_screen().add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	call_deferred("_open_workspace")


func _exit_tree() -> void:
	if workspace:
		workspace.get_parent().remove_child(workspace)
		workspace.queue_free()


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return SCREEN_NAME


func _get_plugin_icon() -> Texture2D:
	if pixel_icon == null:
		var icon_image := Image.new()
		if icon_image.load_svg_from_string(ICON_SVG) == OK:
			pixel_icon = ImageTexture.create_from_image(icon_image)
	return pixel_icon


func _make_visible(visible: bool) -> void:
	if workspace:
		workspace.visible = visible


func _open_workspace() -> void:
	EditorInterface.set_main_screen_editor(SCREEN_NAME)


func _build_workspace() -> void:
	workspace = VBoxContainer.new()
	workspace.name = SCREEN_NAME
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.visible = false
	workspace.clip_contents = true
	workspace.add_theme_constant_override("separation", 0)

	var top_bar := HBoxContainer.new()
	top_bar.custom_minimum_size.y = 42
	top_bar.add_theme_constant_override("separation", 8)
	workspace.add_child(top_bar)

	var redraw_left_padding := Control.new()
	redraw_left_padding.custom_minimum_size.x = 8
	redraw_left_padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(redraw_left_padding)

	redraw_button = Button.new()
	redraw_button.text = "Redraw"
	redraw_button.disabled = true
	redraw_button.pressed.connect(_on_redraw_pressed)
	top_bar.add_child(redraw_button)

	discard_button = Button.new()
	discard_button.text = "Discard"
	discard_button.disabled = true
	discard_button.pressed.connect(_on_discard_pressed)
	top_bar.add_child(discard_button)

	undo_button = Button.new()
	undo_button.text = "Undo"
	undo_button.disabled = true
	undo_button.pressed.connect(_on_undo_pressed)
	top_bar.add_child(undo_button)

	redo_button = Button.new()
	redo_button.text = "Redo"
	redo_button.disabled = true
	redo_button.pressed.connect(_on_redo_pressed)
	top_bar.add_child(redo_button)

	rollback_button = Button.new()
	rollback_button.text = "Rollback"
	rollback_button.disabled = true
	rollback_button.pressed.connect(_on_rollback_pressed)
	top_bar.add_child(rollback_button)

	status_label = Label.new()
	status_label.text = "Drop a PNG or JPEG sprite into the canvas"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar.add_child(status_label)

	zoom_label = Label.new()
	zoom_label.text = "100%"
	zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar.add_child(zoom_label)

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	workspace.add_child(body)

	var tool_margin := MarginContainer.new()
	tool_margin.add_theme_constant_override("margin_left", 8)
	tool_margin.add_theme_constant_override("margin_right", 8)
	tool_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tool_margin)

	var tool_bar := VBoxContainer.new()
	tool_bar.custom_minimum_size.x = 132
	tool_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_bar.add_theme_constant_override("separation", 6)
	tool_margin.add_child(tool_bar)

	var tool_group := ButtonGroup.new()
	var select_top_padding := Control.new()
	select_top_padding.custom_minimum_size.y = 12
	select_top_padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tool_bar.add_child(select_top_padding)

	var select_button := Button.new()
	select_button.text = "Select"
	select_button.toggle_mode = true
	select_button.button_group = tool_group
	select_button.pressed.connect(_on_tool_selected.bind("select"))
	tool_bar.add_child(select_button)
	tool_buttons["select"] = select_button

	var move_button := Button.new()
	move_button.text = "Move"
	move_button.toggle_mode = true
	move_button.button_group = tool_group
	move_button.pressed.connect(_on_tool_selected.bind("move"))
	tool_bar.add_child(move_button)
	tool_buttons["move"] = move_button

	var draw_button := Button.new()
	draw_button.text = "Draw"
	draw_button.toggle_mode = true
	draw_button.button_group = tool_group
	draw_button.button_pressed = true
	draw_button.pressed.connect(_on_tool_selected.bind("draw"))
	tool_bar.add_child(draw_button)
	tool_buttons["draw"] = draw_button

	var erase_button := Button.new()
	erase_button.text = "Erase"
	erase_button.toggle_mode = true
	erase_button.button_group = tool_group
	erase_button.pressed.connect(_on_tool_selected.bind("erase"))
	tool_bar.add_child(erase_button)
	tool_buttons["erase"] = erase_button

	var fill_button := Button.new()
	fill_button.text = "Fill"
	fill_button.toggle_mode = true
	fill_button.button_group = tool_group
	fill_button.pressed.connect(_on_tool_selected.bind("fill"))
	tool_bar.add_child(fill_button)
	tool_buttons["fill"] = fill_button

	var square_button := Button.new()
	square_button.text = "Square"
	square_button.toggle_mode = true
	square_button.button_group = tool_group
	square_button.pressed.connect(_on_tool_selected.bind("square"))
	tool_bar.add_child(square_button)
	tool_buttons["square"] = square_button

	var circle_button := Button.new()
	circle_button.text = "Circle"
	circle_button.toggle_mode = true
	circle_button.button_group = tool_group
	circle_button.pressed.connect(_on_tool_selected.bind("circle"))
	tool_bar.add_child(circle_button)
	tool_buttons["circle"] = circle_button

	var line_button := Button.new()
	line_button.text = "Line"
	line_button.toggle_mode = true
	line_button.button_group = tool_group
	line_button.pressed.connect(_on_tool_selected.bind("line"))
	tool_bar.add_child(line_button)
	tool_buttons["line"] = line_button

	var eyedropper_button := Button.new()
	eyedropper_button.text = "Eyedropper"
	eyedropper_button.toggle_mode = true
	eyedropper_button.button_group = tool_group
	eyedropper_button.pressed.connect(_on_tool_selected.bind("eyedropper"))
	tool_bar.add_child(eyedropper_button)
	tool_buttons["eyedropper"] = eyedropper_button

	var color_label := Label.new()
	color_label.text = "Draw color"
	tool_bar.add_child(color_label)

	color_picker = ColorPickerButton.new()
	color_picker.color = Color.BLACK
	color_picker.custom_minimum_size = Vector2(0, 32)
	color_picker.color_changed.connect(_on_color_changed)
	tool_bar.add_child(color_picker)

	var palette_label := Label.new()
	palette_label.text = "Palette"
	palette_label.tooltip_text = "Right-click a swatch to save the current draw color"
	tool_bar.add_child(palette_label)

	var palette_grid := GridContainer.new()
	palette_grid.columns = 4
	palette_grid.add_theme_constant_override("h_separation", 4)
	palette_grid.add_theme_constant_override("v_separation", 4)
	tool_bar.add_child(palette_grid)
	_load_palette()
	for index in range(PALETTE_SIZE):
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(25, 25)
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.text = "+"
		swatch.tooltip_text = "Right-click to save the current draw color"
		swatch.pressed.connect(_on_palette_swatch_pressed.bind(index))
		swatch.gui_input.connect(_on_palette_swatch_gui_input.bind(index))
		palette_buttons.append(swatch)
		palette_grid.add_child(swatch)
		_refresh_palette_swatch(index)

	canvas = PixelCanvasScript.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.connect("sprite_loaded", _on_sprite_loaded)
	canvas.connect("sprite_modified", _on_sprite_modified)
	canvas.connect("sprite_saved", _on_sprite_saved)
	canvas.connect("color_picked", _on_color_picked)
	canvas.connect("history_changed", _on_history_changed)
	canvas.connect("rollback_available_changed", _on_rollback_available_changed)
	canvas.connect("zoom_changed", _on_zoom_changed)
	canvas.connect("animation_loaded", _on_animation_loaded)
	canvas.connect("frame_changed", _on_frame_changed)
	canvas.connect("frames_changed", _on_frames_changed)
	canvas.connect("playback_changed", _on_playback_changed)
	canvas.connect("tool_changed", _on_tool_changed)
	body.add_child(canvas)
	_build_timeline()


func _build_timeline() -> void:
	timeline_bar = VBoxContainer.new()
	timeline_bar.add_theme_constant_override("separation", 4)
	workspace.add_child(timeline_bar)

	var controls_margin := MarginContainer.new()
	controls_margin.add_theme_constant_override("margin_left", 8)
	controls_margin.add_theme_constant_override("margin_right", 8)
	timeline_bar.add_child(controls_margin)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	controls_margin.add_child(controls)

	play_button = Button.new()
	play_button.text = "Play"
	play_button.disabled = true
	play_button.pressed.connect(_on_play_pressed)
	controls.add_child(play_button)

	onion_check = CheckBox.new()
	onion_check.text = "Onion"
	onion_check.disabled = true
	onion_check.toggled.connect(_on_onion_toggled)
	controls.add_child(onion_check)

	new_frame_button = Button.new()
	new_frame_button.text = "New Frame"
	new_frame_button.disabled = true
	new_frame_button.pressed.connect(_on_new_frame_pressed)
	controls.add_child(new_frame_button)

	duplicate_frame_button = Button.new()
	duplicate_frame_button.text = "Duplicate"
	duplicate_frame_button.disabled = true
	duplicate_frame_button.pressed.connect(_on_duplicate_frame_pressed)
	controls.add_child(duplicate_frame_button)

	delete_frame_button = Button.new()
	delete_frame_button.text = "Delete"
	delete_frame_button.disabled = true
	delete_frame_button.pressed.connect(_on_delete_frame_pressed)
	controls.add_child(delete_frame_button)

	move_left_button = Button.new()
	move_left_button.text = "<"
	move_left_button.tooltip_text = "Move frame left"
	move_left_button.disabled = true
	move_left_button.pressed.connect(_on_move_frame_pressed.bind(-1))
	controls.add_child(move_left_button)

	move_right_button = Button.new()
	move_right_button.text = ">"
	move_right_button.tooltip_text = "Move frame right"
	move_right_button.disabled = true
	move_right_button.pressed.connect(_on_move_frame_pressed.bind(1))
	controls.add_child(move_right_button)

	var duration_label := Label.new()
	duration_label.text = "Duration"
	duration_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	controls.add_child(duration_label)

	duration_spin = SpinBox.new()
	duration_spin.min_value = 1.0
	duration_spin.max_value = 10000.0
	duration_spin.step = 10.0
	duration_spin.suffix = " ms"
	duration_spin.value_changed.connect(_on_duration_changed)
	controls.add_child(duration_spin)

	fps_label = Label.new()
	fps_label.text = "—"
	fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	controls.add_child(fps_label)

	var controls_spacer := Control.new()
	controls_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(controls_spacer)

	frame_counter_label = Label.new()
	frame_counter_label.text = "0 / 0"
	frame_counter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	controls.add_child(frame_counter_label)

	var strip_scroll := ScrollContainer.new()
	strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip_scroll.custom_minimum_size.y = 84
	timeline_bar.add_child(strip_scroll)

	frame_strip_container = HBoxContainer.new()
	frame_strip_container.add_theme_constant_override("separation", 4)
	frame_strip_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_scroll.add_child(frame_strip_container)
	frame_button_group = ButtonGroup.new()

	_rebuild_frame_strip()
	_refresh_timeline_state()


func _rebuild_frame_strip() -> void:
	for child in frame_strip_container.get_children():
		frame_strip_container.remove_child(child)
		child.free()
	frame_buttons.clear()

	var frame_count: int = canvas.call("get_frame_count")
	var active_index: int = canvas.call("get_active_frame_index")
	for index in range(frame_count):
		var frame_button := Button.new()
		frame_button.toggle_mode = true
		frame_button.button_group = frame_button_group
		frame_button.focus_mode = Control.FOCUS_NONE
		frame_button.custom_minimum_size = Vector2(56, 64)
		frame_button.text = str(index + 1)
		var duration: int = canvas.call("get_frame_duration", index)
		frame_button.tooltip_text = "Frame %d — %d ms" % [index + 1, duration]
		var composite: Image = canvas.call("get_frame_composite", index)
		if composite != null:
			frame_button.icon = ImageTexture.create_from_image(composite)
			frame_button.expand_icon = true
			frame_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			frame_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		frame_button.pressed.connect(_on_frame_button_pressed.bind(index))
		frame_button.button_pressed = index == active_index
		_bind_frame_reordering(frame_button, index)
		frame_strip_container.add_child(frame_button)
		frame_buttons.append(frame_button)


func _bind_frame_reordering(frame_button: Button, index: int) -> void:
	frame_button.set_drag_forwarding(
		_get_frame_drag_data.bind(index),
		_can_drop_frame.bind(index),
		_drop_frame.bind(index)
	)


func _get_frame_drag_data(_at_position: Vector2, index: int) -> Variant:
	return {"pixel_frame_index": index}


func _can_drop_frame(_at_position: Vector2, data: Variant, _index: int) -> bool:
	return data is Dictionary and data.has("pixel_frame_index")


func _drop_frame(at_position: Vector2, data: Variant, index: int) -> void:
	if not (data is Dictionary and data.has("pixel_frame_index")):
		return
	var from_index: int = data["pixel_frame_index"]
	var to_index: int = index + 1 if at_position.x > frame_buttons[index].size.x * 0.5 else index
	canvas.call("move_frame_to", from_index, to_index)


func _refresh_timeline_state() -> void:
	var frame_count: int = canvas.call("get_frame_count")
	var active_index: int = canvas.call("get_active_frame_index")
	var has_frames := frame_count > 0

	play_button.disabled = not has_frames
	onion_check.disabled = frame_count < 2
	new_frame_button.disabled = not has_frames
	duplicate_frame_button.disabled = not has_frames
	delete_frame_button.disabled = not canvas.call("can_delete_frame")
	move_left_button.disabled = not canvas.call("can_move_frame", -1)
	move_right_button.disabled = not canvas.call("can_move_frame", 1)
	frame_counter_label.text = "%d / %d" % [active_index + 1, frame_count]

	if has_frames:
		var duration: int = canvas.call("get_frame_duration", active_index)
		duration_spin.set_value_no_signal(float(duration))
		fps_label.text = "%d fps" % roundi(1000.0 / maxf(1.0, float(duration)))
	else:
		duration_spin.set_value_no_signal(0.0)
		fps_label.text = "—"

	for index in range(frame_buttons.size()):
		frame_buttons[index].button_pressed = index == active_index


func _update_frame_thumbnail(index: int) -> void:
	if index < 0 or index >= frame_buttons.size():
		return
	var composite: Image = canvas.call("get_frame_composite", index)
	if composite != null:
		frame_buttons[index].icon = ImageTexture.create_from_image(composite)


func _on_play_pressed() -> void:
	canvas.call("set_playing", not bool(canvas.get("is_playing")))


func _on_playback_changed(playing: bool) -> void:
	play_button.text = "Pause" if playing else "Play"


func _on_onion_toggled(enabled: bool) -> void:
	canvas.call("set_onion_skin", enabled)


func _on_new_frame_pressed() -> void:
	canvas.call("add_empty_frame")


func _on_duplicate_frame_pressed() -> void:
	canvas.call("duplicate_frame")


func _on_delete_frame_pressed() -> void:
	canvas.call("delete_frame")


func _on_move_frame_pressed(offset: int) -> void:
	canvas.call("move_frame", offset)


func _on_frame_button_pressed(index: int) -> void:
	canvas.call("set_frame", index)


func _on_duration_changed(value: float) -> void:
	var active_index: int = canvas.call("get_active_frame_index")
	canvas.call("set_frame_duration", active_index, int(value))


func _on_animation_loaded(frame_count: int) -> void:
	if frame_count > 1:
		status_label.text = "Animation — %d frames" % frame_count
	_rebuild_frame_strip()
	_refresh_timeline_state()


func _on_frame_changed(index: int) -> void:
	_refresh_timeline_state()


func _on_frames_changed() -> void:
	_rebuild_frame_strip()
	_refresh_timeline_state()


func _on_tool_selected(tool_name: String) -> void:
	canvas.call("set_tool", tool_name)


func _on_tool_changed(tool_name: String) -> void:
	if tool_buttons.has(tool_name) and tool_buttons[tool_name] is Button:
		tool_buttons[tool_name].button_pressed = true


func _on_color_changed(color: Color) -> void:
	current_draw_color = color
	canvas.call("set_draw_color", color)


func _on_color_picked(color: Color) -> void:
	current_draw_color = color
	color_picker.color = color
	canvas.call("set_draw_color", color)


func _on_palette_swatch_pressed(index: int) -> void:
	if not palette_used[index]:
		return
	current_draw_color = palette_colors[index]
	color_picker.color = current_draw_color
	canvas.call("set_draw_color", current_draw_color)


func _on_palette_swatch_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		palette_colors[index] = current_draw_color
		palette_used[index] = true
		_save_palette()
		_refresh_palette_swatch(index)
		palette_buttons[index].accept_event()


func _load_palette() -> void:
	palette_colors.resize(PALETTE_SIZE)
	palette_used.resize(PALETTE_SIZE)
	var config := ConfigFile.new()
	if config.load(PALETTE_CONFIG_PATH) != OK:
		return
	var saved_colors: Variant = config.get_value("palette", "colors", PackedColorArray())
	var saved_used: Variant = config.get_value("palette", "used", PackedInt32Array())
	if saved_colors is PackedColorArray:
		for index in range(mini(PALETTE_SIZE, saved_colors.size())):
			palette_colors[index] = saved_colors[index]
	if saved_used is PackedInt32Array:
		for index in range(mini(PALETTE_SIZE, saved_used.size())):
			palette_used[index] = saved_used[index] != 0


func _save_palette() -> void:
	var config := ConfigFile.new()
	var colors := PackedColorArray()
	var used := PackedInt32Array()
	for index in range(PALETTE_SIZE):
		colors.append(palette_colors[index])
		used.append(1 if palette_used[index] else 0)
	config.set_value("palette", "colors", colors)
	config.set_value("palette", "used", used)
	var error := config.save(PALETTE_CONFIG_PATH)
	if error != OK:
		push_warning("Pixel: Could not save the color palette (error %d)" % error)


func _refresh_palette_swatch(index: int) -> void:
	var swatch := palette_buttons[index]
	var fill_color := palette_colors[index] if palette_used[index] else Color("#292b2f")
	var border_color := Color("#75787e") if not palette_used[index] else Color("#d0d2d5")
	swatch.text = "" if palette_used[index] else "+"
	swatch.tooltip_text = (
		"Left-click to use; right-click to replace this color"
		if palette_used[index]
		else "Right-click to save the current draw color"
	)
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = fill_color
	normal_style.border_color = border_color
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(3)
	swatch.add_theme_stylebox_override("normal", normal_style)
	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = fill_color.lightened(0.15)
	swatch.add_theme_stylebox_override("hover", hover_style)
	var pressed_style := normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = fill_color.darkened(0.15)
	swatch.add_theme_stylebox_override("pressed", pressed_style)


func _on_sprite_loaded(path: String, width: int, height: int) -> void:
	current_sprite_path = path
	redraw_button.disabled = false
	discard_button.disabled = true
	undo_button.disabled = true
	redo_button.disabled = true
	status_label.text = "%s — %d × %d" % [path.get_file(), width, height]


func _on_sprite_modified() -> void:
	if not redraw_button.disabled:
		discard_button.disabled = false
		status_label.text = "%s — unsaved edits" % current_sprite_path.get_file()
	_update_frame_thumbnail(int(canvas.call("get_active_frame_index")))


func _on_sprite_saved() -> void:
	discard_button.disabled = true


func _on_discard_pressed() -> void:
	var result: int = canvas.call("discard_edits")
	if result == OK:
		status_label.text = "%s — edits discarded" % current_sprite_path.get_file()
	else:
		status_label.text = "Could not reload sprite (error %d)" % result


func _on_undo_pressed() -> void:
	canvas.call("undo")


func _on_redo_pressed() -> void:
	canvas.call("redo")


func _on_rollback_pressed() -> void:
	var result: int = canvas.call("rollback_sprite")
	if result == OK:
		status_label.text = "%s — rolled back" % current_sprite_path.get_file()
		EditorInterface.get_resource_filesystem().scan()
	else:
		status_label.text = "Could not roll back sprite (error %d)" % result


func _on_history_changed(can_undo: bool, can_redo: bool) -> void:
	undo_button.disabled = not can_undo
	redo_button.disabled = not can_redo


func _on_rollback_available_changed(available: bool) -> void:
	rollback_button.disabled = not available


func _on_zoom_changed(value: float) -> void:
	zoom_label.text = "%d%%" % roundi(value * 100.0)


func _on_redraw_pressed() -> void:
	var result: int = canvas.call("save_sprite")
	if result == OK:
		var frame_count: int = canvas.call("get_frame_count")
		status_label.text = "%d frame(s) redrawn and saved" % frame_count
		current_sprite_path = String(canvas.call("get_source_path"))
		EditorInterface.get_resource_filesystem().scan()
	else:
		status_label.text = "Could not save sprite (error %d)" % result
