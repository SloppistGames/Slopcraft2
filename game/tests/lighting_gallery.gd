extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1200,720)
	root.content_scale_size=Vector2i.ZERO
	DisplayServer.window_set_position(Vector2i(100,100))
	DisplayServer.window_move_to_foreground()
	var world: VoxelWorld = VoxelWorld.new()
	root.add_child(world)
	world.setup(842019,"overworld",{},2,false)
	world.set_block_distance(4)
	world.set_render_distance(10)
	var focus: Vector3 = Vector3(8,world.surface_height(8,8),8)
	world.prepare_panorama(focus,4)
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.position=focus+Vector3(35,17,40)
	camera.look_at(focus+Vector3(-28,4,-35))
	camera.fov=74
	camera.current=true
	var nature: NatureSystem = NatureSystem.new()
	world.add_child(nature)
	nature.setup(world,null,null)
	for frame in 200: await process_frame
	world.atmosphere.set_process(false)
	var output: String = ProjectSettings.globalize_path("res://../../work/snapshot050/weather")
	for state in ["day","dawn","night","storm"]:
		world.atmosphere.time_of_day = 0.25 if state=="day" or state=="storm" else (0.015 if state=="dawn" else 0.75)
		world.atmosphere.set_weather_state(0.96 if state=="storm" else 0.0,0.025 if state=="storm" else 0.0015,0.0,1.0 if state=="storm" else 0.15)
		world.atmosphere._process(0.0)
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/lighting-"+state+".png")
	print("LIGHTING GALLERY ",output)
	world.queue_free()
	await process_frame
	quit()
