extends SceneTree
const Editor = preload("res://skin_editor.gd")
const Model = preload("res://player/player_model.gd")
var checks: int = 0
var failures: int = 0
var test_directory: String

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	root.size = Vector2i(1040,850)
	var backend = LauncherBackend.new()
	test_directory = "user://test-skin-%d" % Time.get_ticks_usec()
	backend.root_directory = test_directory
	root.add_child(backend)
	var background = ColorRect.new(); background.color = Color("11191b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(background)
	var margin = MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	root.add_child(margin)
	var scroll = ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; margin.add_child(scroll)
	var editor = Editor.new(); scroll.add_child(editor); editor.setup(backend)
	await process_frame
	check(editor.image.get_size() == Vector2i(64,64),"Editor starts with a real 64×64 skin")
	check(editor.image.get_data() == Model.default_skin_image().get_data(),"Default is the actual player skin")
	check(editor.model.skin_image.get_data() == editor.image.get_data(),"Preview uses editable skin pixels")
	editor._tool_buttons.eraser.pressed.emit()
	check(editor.tool == "eraser","Eraser toolbar button selects its own tool")
	editor._tool_buttons.fill.pressed.emit()
	check(editor.tool == "fill","Fill toolbar button selects its own tool")
	editor._tool_buttons.pencil.pressed.emit()
	# Drive the canvas GUI path, not just direct editing helpers.
	editor.select_color(Color.MAGENTA)
	var event = InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true
	event.position = Vector2(9.5,11.5)*8
	editor.canvas._gui_input(event)
	var motion = InputEventMouseMotion.new(); motion.position = Vector2(14.5,11.5)*8
	editor.canvas._gui_input(motion)
	event.pressed = false; event.position = motion.position
	editor.canvas._input(event)
	check(editor.undo_stack.size() == 1,"One drag creates exactly one undo action")
	for x in range(9,15): check(editor.image.get_pixel(x,11) == Color.MAGENTA,"Drag interpolates every pixel without gaps")
	check(editor.model.skin_image.get_pixel(9,11) == Color.MAGENTA,"Drawing updates the 3D preview")
	editor.undo()
	check(editor.image.get_data() == Model.default_skin_image().get_data(),"Undo restores all pixels from the stroke")
	editor.redo()
	check(editor.image.get_pixel(14,11) == Color.MAGENTA,"Redo reapplies the whole stroke")
	var shortcut = InputEventKey.new(); shortcut.physical_keycode = KEY_Z; shortcut.ctrl_pressed = true; shortcut.pressed = true
	editor._unhandled_key_input(shortcut)
	check(editor.image.get_data() == Model.default_skin_image().get_data(),"Undo shortcut works while drawing canvas is focused")
	shortcut.shift_pressed = true; editor._unhandled_key_input(shortcut)
	check(editor.image.get_pixel(14,11) == Color.MAGENTA,"Redo shortcut restores the stroke")
	editor.set_tool("eraser"); editor.begin_edit(); editor.paint_pixel(Vector2i(14,11)); editor.commit_edit()
	check(editor.image.get_pixel(14,11).a == 0.0,"Eraser produces actual transparency")
	editor.undo()
	check(editor.image.get_pixel(14,11) == Color.MAGENTA,"Transparent erasure is undoable")
	editor.set_tool("picker")
	event.pressed = true; event.position = Vector2(9.5,11.5)*8; editor.canvas._gui_input(event)
	check(editor.color == Color.MAGENTA and editor.tool == "pencil","Pick color selects the pixel and resumes pencil")
	# Fill a bounded patch and ensure differently colored adjacent pixels survive.
	editor.begin_edit()
	for y in range(50,54):
		for x in range(50,54): editor.image.set_pixel(x,y,Color.BLUE)
	editor.commit_edit()
	editor.select_color(Color.RED); editor.fill_at(Vector2i(51,51))
	check(editor.image.get_pixel(50,50) == Color.RED and editor.image.get_pixel(53,53) == Color.RED,"Fill visits the whole connected color region")
	check(editor.image.get_pixel(49,50) != Color.RED,"Fill respects region boundaries")
	editor.undo(); check(editor.image.get_pixel(50,50) == Color.BLUE,"Flood fill is one reversible edit")
	editor.reset_skin(); editor.undo()
	check(editor.image.get_pixel(50,50) == Color.BLUE,"Reset can be undone without losing custom work")
	editor.canvas.set_zoom(16)
	check(editor.canvas.custom_minimum_size == Vector2(1024,1024),"Zoom scales the pixel canvas")
	editor.canvas.set_zoom(8); editor.canvas.focus_part = "head"; editor.canvas.queue_redraw()
	var angle: float = editor.model.rotation.y; editor._process(0.5)
	check(editor.model.rotation.y != angle,"Preview rotates the actual model")
	editor.rotate_toggle.button_pressed = false
	angle = editor.model.rotation.y; editor._process(0.5)
	check(editor.model.rotation.y == angle,"Preview rotation can be paused")
	var export_path: String = test_directory.path_join("export.png")
	check(editor.export_png(export_path) == OK,"Export writes a real PNG")
	var exported = Image.load_from_file(export_path)
	check(exported.get_data() == editor.image.get_data(),"PNG export preserves every RGBA pixel")
	editor.reset_skin()
	check(editor.load_png(export_path) and editor.image.get_data() == exported.get_data(),"PNG import restores every edited pixel")
	var invalid_path: String = test_directory.path_join("invalid.png")
	Image.create(32,32,false,Image.FORMAT_RGBA8).save_png(invalid_path)
	var before: PackedByteArray = editor.image.get_data()
	check(not editor.load_png(invalid_path) and editor.image.get_data() == before,"Invalid dimensions leave current work intact")
	editor._show_file_dialog(false)
	check(editor._file_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE and editor._file_dialog.visible,"Import opens a working PNG file picker")
	editor._file_dialog.hide()
	editor._show_file_dialog(true)
	check(editor._file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE and editor._file_dialog.visible,"Export opens a working PNG save picker")
	editor._file_dialog.hide()
	editor.name_input.text = "Skin_Maker"
	check(editor.save_skin(),"Save writes the skin and launcher profile")
	check(backend.settings.player_name == "Skin_Maker" and FileAccess.file_exists(backend.settings.skin_path),"Launcher launch profile points to the saved skin")
	var saved = Image.load_from_file(backend.settings.skin_path)
	check(saved.get_data() == before and not editor.dirty,"Saved game skin matches editor pixels")
	var fresh_backend = LauncherBackend.new(); fresh_backend.root_directory = test_directory; root.add_child(fresh_backend)
	check(fresh_backend.settings.skin_path == backend.settings.skin_path and fresh_backend.settings.player_name == "Skin_Maker","Name and skin persist after launcher restart")
	var reloaded = Editor.new(); reloaded.visible = false; root.add_child(reloaded); reloaded.setup(fresh_backend)
	check(reloaded.image.get_data() == before,"Reopening Skin Studio loads the current skin")
	editor.name_input.text = "bad name!"
	check(not editor.save_skin() and backend.settings.player_name == "Skin_Maker","Invalid name cannot replace saved profile")
	editor.name_input.text = "Skin_Maker"
	# A failed settings write keeps the previously selected skin profile intact.
	var old_settings: Dictionary = backend.settings.duplicate(true)
	var settings_folder: String = test_directory.path_join("settings.json")
	DirAccess.remove_absolute(settings_folder); DirAccess.make_dir_absolute(settings_folder)
	editor.begin_edit(); editor.paint_pixel(Vector2i(15,15)); editor.commit_edit()
	check(not editor.save_skin() and backend.settings == old_settings,"Failed profile write preserves the prior selected skin")
	DirAccess.remove_absolute(settings_folder)
	if "--gallery" in OS.get_cmdline_user_args():
		editor.reset_skin(); editor.undo_stack.clear(); editor.redo_stack.clear(); editor._update_history_ui()
		editor.canvas.focus_part = ""
		editor.model.rotation.y = -0.24; editor._status("Ready. Draw on the skin, then Save & use skin.")
		for frame in 12: await process_frame
		await RenderingServer.frame_post_draw
		var path: String = ProjectSettings.globalize_path("res://../../work/snapshot050/skin-studio.png")
		root.get_texture().get_image().save_png(path)
		print("SKIN STUDIO GALLERY: ",path)
	editor.queue_free(); reloaded.queue_free(); backend.queue_free(); fresh_backend.queue_free()
	await process_frame
	remove_tree(test_directory)
	print("SKIN EDITOR: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func remove_tree(path: String) -> void:
	var directory = DirAccess.open(path)
	if directory == null: return
	for child in directory.get_directories(): remove_tree(path.path_join(child))
	for child in directory.get_files(): DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)
