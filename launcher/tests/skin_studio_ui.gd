extends SceneTree
## Uses the real launcher shell while keeping all profile IO in an isolated folder.
class TestLauncher extends "res://main.gd":
	func _ready() -> void: pass

func _initialize() -> void: run.call_deferred()

func run() -> void:
	root.size = Vector2i(1180,760)
	var app = TestLauncher.new()
	root.add_child(app); app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backend = LauncherBackend.new()
	backend.root_directory = "user://test-skin-ui-%d" % Time.get_ticks_usec()
	app.add_child(backend); app.backend = backend
	app._build_shell(); app.page = "Skin studio"; app._refresh_page()
	app.skin_editor.rotate_toggle.button_pressed = false
	app.skin_editor.model.rotation.y = -0.25
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	var path: String = ProjectSettings.globalize_path("res://../../work/snapshot050/launcher-skin-studio.png")
	root.get_texture().get_image().save_png(path)
	var scroll: Node = app.content.get_parent()
	while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
	if scroll != null:
		scroll.scroll_vertical = 10000
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(path.replace(".png","-scrolled.png"))
	print("SKIN STUDIO UI: ",path)
	DirAccess.remove_absolute(backend.root_directory)
	app.queue_free(); await process_frame
	quit()
