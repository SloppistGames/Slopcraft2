extends SceneTree
class TestLauncher extends "res://main.gd":
	func _ready() -> void: pass
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1180,760)
	root.content_scale_size = Vector2i.ZERO
	DisplayServer.window_set_position(Vector2i(100,100))
	DisplayServer.window_move_to_foreground()
	var app: TestLauncher = TestLauncher.new()
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backend: LauncherBackend = LauncherBackend.new()
	backend.root_directory = "user://test-launcher-gallery-%d" % Time.get_ticks_usec()
	backend.auto_refresh_enabled = false
	app.add_child(backend)
	app.backend = backend
	app.selected = backend.latest_version()
	app._build_shell()
	var folder: String = ProjectSettings.globalize_path("res://../../work/snapshot050/launcher-ui")
	DirAccess.make_dir_recursive_absolute(folder)
	for pair in [["Play","play"],["Versions","installations"],["Skin studio","skins"],["Settings","settings"],["Changelog","changelog"]]:
		app.page = pair[0]
		app._refresh_page()
		var scroll: Node = app.content.get_parent()
		while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
		if scroll != null: scroll.scroll_vertical = 0
		if app.skin_editor != null:
			app.skin_editor.rotate_toggle.button_pressed = false
			app.skin_editor.model.rotation.y = -0.25
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+pair[1]+".png")
		if app.content.get_global_rect().end.x > 1182: failures.append(pair[0]+" content overflows window horizontally")
		if app.page == "Play":
			if app.play_button.get_global_rect().end.y > 730: failures.append("Play action is not visible without scrolling")
		if scroll != null and scroll.get_v_scroll_bar().max_value > scroll.size.y+2:
			scroll.scroll_vertical = 10000
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/"+pair[1]+"-scrolled.png")
	for failure in failures: push_error(failure)
	print("LAUNCHER UI GALLERY: ",folder," layout failures=",failures.size())
	var temp: String = backend.root_directory
	app.queue_free()
	await process_frame
	DirAccess.remove_absolute(temp)
	quit(0 if failures.is_empty() else 1)
