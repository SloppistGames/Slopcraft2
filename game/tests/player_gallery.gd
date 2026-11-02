extends SceneTree
## Native renderer evidence of both skinned models and physical gas-mask geometry.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1000,720)
	var scene = Node3D.new(); root.add_child(scene)
	var environment = WorldEnvironment.new()
	var settings = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("1c2932")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c3d8e0")
	settings.ambient_light_energy = 0.7
	environment.environment = settings; scene.add_child(environment)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-35,0); light.light_energy = 1.0
	scene.add_child(light)
	for side in [-1,1]:
		var model = PlayerModel.new()
		model.position.x = side * 0.65
		model.rotation.y = 0.15 if side == -1 else -0.25
		model.set_gas_mask(side == 1)
		scene.add_child(model)
	var camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(2.4,2.4,-5.0)
	camera.look_at(Vector3(0,0.9,0)); camera.current = true; camera.fov = 42
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	var output: String = ProjectSettings.globalize_path("res://../../work/snapshot050/player-appearance.png")
	var error: Error = root.get_texture().get_image().save_png(output)
	print("PLAYER GALLERY: ",output," status ",error)
	quit(error)
