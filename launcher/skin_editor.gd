extends VBoxContainer
const Model = preload("res://player/player_model.gd")
const Canvas = preload("res://skin_canvas.gd")
const GREEN = Color("b6e77c")
const TEXT = Color("edf4e8")
const MUTED = Color("95aaa9")
const MAX_HISTORY: int = 80
var backend: Node
var image: Image
var texture: ImageTexture
var tool: String = "pencil"
var color: Color = Color("286e77")
var undo_stack: Array[PackedByteArray] = []
var redo_stack: Array[PackedByteArray] = []
var _before: PackedByteArray = PackedByteArray()
var dirty: bool = false
var canvas: Control
var model: Node3D
var status_label: Label
var coordinate_label: Label
var color_picker: ColorPickerButton
var rotate_toggle: CheckButton
var name_input: LineEdit
var undo_button: Button
var redo_button: Button
var _file_dialog: FileDialog
var _tool_buttons: Dictionary = {}
var _saved_hash: String = ""

func setup(owner_backend: Node) -> void:
	backend = owner_backend
	image = Model.default_skin_image()
	texture = ImageTexture.create_from_image(image)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",14)
	_build_ui()
	var current: String = str(backend.settings.get("skin_path",""))
	if not current.is_empty() and FileAccess.file_exists(current):
		if not load_png(current,false): _status("Saved skin could not load. Showing the default skin.",true)
	_saved_hash = _hash_image()
	dirty = false
	_update_history_ui()
	set_process(true)

func _label(text: String,points: int = 13,tint: Color = TEXT) -> Label:
	var label = Label.new(); label.text = text
	label.add_theme_font_size_override("font_size",points)
	label.add_theme_color_override("font_color",tint)
	return label

func _button(text: String,action: Callable,accent: bool = false) -> Button:
	var button = Button.new(); button.text = text
	button.custom_minimum_size.y = 36
	var style = StyleBoxFlat.new()
	style.bg_color = GREEN if accent else Color("2b3d3d")
	style.set_corner_radius_all(6)
	style.content_margin_left = 12; style.content_margin_right = 12
	style.content_margin_top = 8; style.content_margin_bottom = 8
	button.add_theme_stylebox_override("normal",style)
	var hover: StyleBoxFlat = style.duplicate(); hover.bg_color = style.bg_color.lightened(0.12)
	button.add_theme_stylebox_override("hover",hover)
	button.add_theme_color_override("font_color",Color("18201d") if accent else TEXT)
	button.pressed.connect(action)
	return button

func _build_ui() -> void:
	var profile = HBoxContainer.new(); profile.add_theme_constant_override("separation",10); add_child(profile)
	profile.add_child(_label("PLAYER NAME",12,GREEN))
	name_input = LineEdit.new(); name_input.text = str(backend.settings.get("player_name","Player")); name_input.max_length = 24
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL; name_input.custom_minimum_size.y = 40; profile.add_child(name_input)
	profile.add_child(_button("Save & use skin",save_skin,true))
	var tools = HFlowContainer.new(); tools.add_theme_constant_override("h_separation",7); add_child(tools)
	for entry in [["pencil","Pencil"],["eraser","Eraser"],["fill","Fill"],["picker","Pick color"]]:
		var key: String = entry[0]
		var button: Button = _button(entry[1],func(): set_tool(key))
		button.toggle_mode = true; _tool_buttons[key] = button; tools.add_child(button)
	_tool_buttons.pencil.button_pressed = true
	undo_button = _button("Undo",undo); tools.add_child(undo_button)
	redo_button = _button("Redo",redo); tools.add_child(redo_button)
	undo_button.tooltip_text = "Undo (⌘/Ctrl Z)"
	redo_button.tooltip_text = "Redo (⌘/Ctrl Shift Z)"
	color_picker = ColorPickerButton.new(); color_picker.color = color; color_picker.custom_minimum_size = Vector2(56,36)
	color_picker.color_changed.connect(select_color); tools.add_child(color_picker)
	var palette = HFlowContainer.new(); palette.add_theme_constant_override("h_separation",6); add_child(palette)
	palette.add_child(_label("PALETTE",11,MUTED))
	for value in ["172025","35464a","697678","a5b0a7","edf4e8","443126","80543c","c8906a","e7ba91","286e77","4c9a9e","3c425b","676e9a","91b35b","b6e77c","c97165","dfab56","a376ac"]:
		var tint = Color(value)
		var swatch = Button.new(); swatch.custom_minimum_size = Vector2(24,26); swatch.tooltip_text = "#"+value
		var style = StyleBoxFlat.new(); style.bg_color = tint; style.set_corner_radius_all(4)
		swatch.add_theme_stylebox_override("normal",style); swatch.add_theme_stylebox_override("hover",style)
		swatch.pressed.connect(func(): select_color(tint)); palette.add_child(swatch)
	var controls = HFlowContainer.new(); controls.add_theme_constant_override("h_separation",8); add_child(controls)
	var parts = OptionButton.new(); parts.custom_minimum_size.y = 34
	var names: Array[String] = ["Full skin","Head","Torso","Right arm","Left arm","Right leg","Left leg"]
	var keys: Array[String] = ["","head","body","right_arm","left_arm","right_leg","left_leg"]
	for name in names: parts.add_item(name)
	parts.item_selected.connect(func(index): canvas.focus_part = keys[index]; canvas.queue_redraw())
	controls.add_child(parts)
	var outer = CheckButton.new(); outer.text = "Outer layer"; outer.toggled.connect(func(value): canvas.focus_overlay = value; canvas.queue_redraw()); controls.add_child(outer)
	var grid = CheckButton.new(); grid.text = "Grid"; grid.button_pressed = true
	grid.toggled.connect(func(value): canvas.show_grid = value; canvas.queue_redraw()); controls.add_child(grid)
	var zoom = OptionButton.new(); zoom.custom_minimum_size.y = 34
	for amount in [4,6,8,12,16]: zoom.add_item(str(amount)+"× zoom",amount)
	zoom.select(2); zoom.item_selected.connect(func(index): canvas.set_zoom(zoom.get_item_id(index))); controls.add_child(zoom)
	coordinate_label = _label("64 × 64 pixels",12,MUTED); controls.add_child(coordinate_label)
	var workspace = HBoxContainer.new(); workspace.add_theme_constant_override("separation",14); add_child(workspace)
	var grid_scroll = ScrollContainer.new(); grid_scroll.custom_minimum_size = Vector2(280,512)
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; workspace.add_child(grid_scroll)
	canvas = Canvas.new(); canvas.editor = self; canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; grid_scroll.add_child(canvas)
	var preview_box = VBoxContainer.new(); preview_box.custom_minimum_size.x = 210; workspace.add_child(preview_box)
	preview_box.add_child(_label("LIVE PREVIEW",12,GREEN))
	_build_preview(preview_box)
	rotate_toggle = CheckButton.new(); rotate_toggle.text = "Rotate preview"; rotate_toggle.button_pressed = true; preview_box.add_child(rotate_toggle)
	var angle = HSlider.new(); angle.min_value = -180; angle.max_value = 180; angle.step = 1
	angle.value_changed.connect(func(value): rotate_toggle.button_pressed = false; model.rotation.y = deg_to_rad(value)); preview_box.add_child(angle)
	var note = _label("Classic skin · 6 body parts\nBase + transparent outer layer\n\nSelect a part to highlight its faces.\nThe checkerboard is transparent.",11,MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; preview_box.add_child(note)
	var files = HFlowContainer.new(); files.add_theme_constant_override("h_separation",8); add_child(files)
	files.add_child(_button("Load saved",load_saved))
	files.add_child(_button("Import PNG",func(): _show_file_dialog(false)))
	files.add_child(_button("Export PNG",func(): _show_file_dialog(true)))
	files.add_child(_button("Reset to default",reset_skin))
	status_label = _label("Ready. Draw on the skin, then Save & use skin.",13,MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(status_label)

func _build_preview(parent: Node) -> void:
	var container = SubViewportContainer.new(); container.custom_minimum_size = Vector2(210,285); container.stretch = true
	parent.add_child(container)
	var viewport = SubViewport.new(); viewport.size = Vector2i(210,285)
	viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; container.add_child(viewport)
	var world = Node3D.new(); viewport.add_child(world)
	var environment = WorldEnvironment.new(); var settings = Environment.new()
	settings.background_mode = Environment.BG_COLOR; settings.background_color = Color("152326")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; settings.ambient_light_color = Color("d5e4db"); settings.ambient_light_energy = 0.85
	environment.environment = settings; world.add_child(environment)
	var light = DirectionalLight3D.new(); light.rotation_degrees = Vector3(-30,-30,0); light.light_energy = 1.0; world.add_child(light)
	model = Model.new(); world.add_child(model)
	var camera = Camera3D.new(); world.add_child(camera)
	camera.position = Vector3(0,1.2,-3.5); camera.look_at(Vector3(0,0.9,0)); camera.fov = 36; camera.current = true

func _process(delta: float) -> void:
	if is_instance_valid(model) and rotate_toggle != null and rotate_toggle.button_pressed:
		model.rotation.y += delta * 0.45

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or not (event.ctrl_pressed or event.meta_pressed): return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit: return
	match event.physical_keycode:
		KEY_Z:
			if event.shift_pressed: redo()
			else: undo()
		KEY_Y: redo()
		KEY_S: save_skin()
		_: return
	get_viewport().set_input_as_handled()

func set_tool(value: String) -> void:
	if value not in ["pencil","eraser","fill","picker"]: return
	canvas.finish_stroke()
	tool = value
	for key in _tool_buttons: _tool_buttons[key].button_pressed = key == value

func select_color(value: Color) -> void:
	color = value
	if color_picker != null: color_picker.color = value
	if tool == "picker": set_tool("pencil")

func begin_edit() -> void:
	if _before.is_empty(): _before = image.get_data()

func paint_pixel(point: Vector2i,refresh: bool = true) -> void:
	if point.x < 0 or point.x >= 64 or point.y < 0 or point.y >= 64: return
	image.set_pixelv(point,Color.TRANSPARENT if tool == "eraser" else color)
	if refresh: refresh_pixels()

func commit_edit() -> void:
	if not _before.is_empty() and _before != image.get_data():
		undo_stack.append(_before)
		if undo_stack.size() > MAX_HISTORY: undo_stack.pop_front()
		redo_stack.clear()
	_before = PackedByteArray()
	dirty = _hash_image() != _saved_hash
	_update_history_ui()
	if dirty: _status("Unsaved changes. Save & use skin applies this skin to your next game.")

func refresh_pixels() -> void:
	texture.update(image)
	if is_instance_valid(model): model.set_skin_image(image)
	if canvas != null: canvas.queue_redraw()

func fill_at(point: Vector2i) -> void:
	if point.x < 0 or point.x >= 64 or point.y < 0 or point.y >= 64: return
	var target: Color = image.get_pixelv(point)
	if target == color: return
	begin_edit()
	var queue: Array[Vector2i] = [point]
	image.set_pixelv(point,color)
	var cursor: int = 0
	while cursor < queue.size():
		var current: Vector2i = queue[cursor]; cursor += 1
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i = current+offset
			if next.x >= 0 and next.x < 64 and next.y >= 0 and next.y < 64 and image.get_pixelv(next) == target:
				image.set_pixelv(next,color); queue.append(next)
	refresh_pixels(); commit_edit()

func undo() -> void:
	canvas.finish_stroke()
	if undo_stack.is_empty(): return
	redo_stack.append(image.get_data())
	image = Image.create_from_data(64,64,false,Image.FORMAT_RGBA8,undo_stack.pop_back())
	refresh_pixels(); dirty = _hash_image() != _saved_hash; _update_history_ui(); _status("Undo applied.")

func redo() -> void:
	if redo_stack.is_empty(): return
	undo_stack.append(image.get_data())
	image = Image.create_from_data(64,64,false,Image.FORMAT_RGBA8,redo_stack.pop_back())
	refresh_pixels(); dirty = _hash_image() != _saved_hash; _update_history_ui(); _status("Redo applied.")

func reset_skin() -> void:
	canvas.finish_stroke(); begin_edit(); image = Model.default_skin_image(); refresh_pixels(); commit_edit()
	_status("Default skin restored. Undo is available.")

func load_saved() -> void:
	var path: String = str(backend.settings.get("skin_path",""))
	if path.is_empty(): _status("No custom skin saved yet. Use Reset for the default skin."); return
	if load_png(path): _status("Saved skin loaded. Undo restores your previous drawing.")

func load_png(path: String,record_history: bool = true) -> bool:
	if not FileAccess.file_exists(path): _status("Skin file could not be found.",true); return false
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null: _status("Skin file could not be opened.",true); return false
	if file.get_length() > 2097152: file.close(); _status("Choose a 64×64 PNG smaller than 2 MB.",true); return false
	var bytes: PackedByteArray = file.get_buffer(file.get_length()); file.close()
	var loaded = Image.new()
	if loaded.load_png_from_buffer(bytes) != OK or loaded.get_width() != 64 or loaded.get_height() != 64:
		_status("This skin needs a 64×64 PNG using the classic skin layout.",true); return false
	loaded.convert(Image.FORMAT_RGBA8)
	if record_history: canvas.finish_stroke(); begin_edit()
	image = loaded; refresh_pixels()
	if record_history: commit_edit()
	_status("Imported 64×64 PNG. Save & use skin to apply it.")
	return true

func export_png(path: String) -> Error:
	if path.get_extension().to_lower() != "png": path += ".png"
	var error: Error = image.save_png(path)
	_status("PNG exported." if error == OK else "Could not export this PNG. Check the destination folder.",error != OK)
	return error

func save_skin() -> bool:
	canvas.finish_stroke()
	if not LauncherBackend.valid_player_name(name_input.text): _status("Player name needs 3–24 letters, numbers or underscores.",true); return false
	var folder: String = str(backend.root_directory).path_join("skins")
	if DirAccess.make_dir_recursive_absolute(folder) != OK: _status("Could not create the skin folder.",true); return false
	# Content-specific filenames keep the previously selected skin intact if settings fail.
	var path: String = folder.path_join("skin-"+_hash_image().left(16)+".png")
	var temporary: String = path+".tmp"
	var error: Error = image.save_png(temporary)
	if error == OK: error = DirAccess.rename_absolute(temporary,path)
	if error != OK: _status("Could not save the skin. Check available storage.",true); return false
	var previous: Dictionary = backend.settings.duplicate(true)
	backend.settings.skin_path = ProjectSettings.globalize_path(path)
	backend.settings.player_name = name_input.text
	if backend.save_settings() != OK:
		backend.settings = previous; _status("The skin was written, but player settings could not be saved.",true); return false
	_saved_hash = _hash_image(); dirty = false
	_status("Saved for "+name_input.text+". Your next game will use this skin.")
	return true

func _show_file_dialog(exporting: bool) -> void:
	canvas.finish_stroke()
	if is_instance_valid(_file_dialog): _file_dialog.queue_free()
	_file_dialog = FileDialog.new(); _file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if exporting else FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.title = "Export skin as PNG" if exporting else "Import a 64×64 skin PNG"
	_file_dialog.filters = PackedStringArray(["*.png ; PNG skin"])
	_file_dialog.current_file = "slopcraft-skin.png" if exporting else ""
	_file_dialog.file_selected.connect(func(path):
		if exporting: export_png(path)
		else: load_png(path)
	)
	add_child(_file_dialog); _file_dialog.popup_centered_ratio(0.72)

func _hash_image() -> String:
	var context = HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(image.get_data())
	return context.finish().hex_encode()

func _update_history_ui() -> void:
	if undo_button != null: undo_button.disabled = undo_stack.is_empty()
	if redo_button != null: redo_button.disabled = redo_stack.is_empty()

func _status(message: String,error: bool = false) -> void:
	if status_label != null: status_label.text = message; status_label.modulate = Color("efba92") if error else MUTED
