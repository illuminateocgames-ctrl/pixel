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

	var move_button := Button.new()
	move_button.text = "Move"
	move_button.toggle_mode = true
	move_button.button_group = tool_group
	move_button.pressed.connect(_on_tool_selected.bind("move"))
	tool_bar.add_child(move_button)

	var draw_button := Button.new()
	draw_button.text = "Draw"
	draw_button.toggle_mode = true
	draw_button.button_group = tool_group
	draw_button.button_pressed = true
	draw_button.pressed.connect(_on_tool_selected.bind("draw"))
	tool_bar.add_child(draw_button)

	var erase_button := Button.new()
	erase_button.text = "Erase"
	erase_button.toggle_mode = true
	erase_button.button_group = tool_group
	erase_button.pressed.connect(_on_tool_selected.bind("erase"))
	tool_bar.add_child(erase_button)

	var fill_button := Button.new()
	fill_button.text = "Fill"
	fill_button.toggle_mode = true
	fill_button.button_group = tool_group
	fill_button.pressed.connect(_on_tool_selected.bind("fill"))
	tool_bar.add_child(fill_button)

	var square_button := Button.new()
	square_button.text = "Square"
	square_button.toggle_mode = true
	square_button.button_group = tool_group
	square_button.pressed.connect(_on_tool_selected.bind("square"))
	tool_bar.add_child(square_button)

	var circle_button := Button.new()
	circle_button.text = "Circle"
	circle_button.toggle_mode = true
	circle_button.button_group = tool_group
	circle_button.pressed.connect(_on_tool_selected.bind("circle"))
	tool_bar.add_child(circle_button)

	var line_button := Button.new()
	line_button.text = "Line"
	line_button.toggle_mode = true
	line_button.button_group = tool_group
	line_button.pressed.connect(_on_tool_selected.bind("line"))
	tool_bar.add_child(line_button)

	var eyedropper_button := Button.new()
	eyedropper_button.text = "Eyedropper"
	eyedropper_button.toggle_mode = true
	eyedropper_button.button_group = tool_group
	eyedropper_button.pressed.connect(_on_tool_selected.bind("eyedropper"))
	tool_bar.add_child(eyedropper_button)

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
	body.add_child(canvas)


func _on_tool_selected(tool_name: String) -> void:
	canvas.call("set_tool", tool_name)


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
		status_label.text = "%s — redrawn and saved" % current_sprite_path.get_file()
		EditorInterface.get_resource_filesystem().scan()
	else:
		status_label.text = "Could not save sprite (error %d)" % result
