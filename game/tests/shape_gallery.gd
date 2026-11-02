extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
	root.size = Vector2i(1280,800)
	var fixture_script = load("res://tests/test_shapes.gd")
	var world = fixture_script.FixtureWorld.new()
	root.add_child(world)
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("a6bdc8")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("cad5de")
	env.environment.ambient_light_energy = 0.65
	world.add_child(env)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-25,0)
	sun.light_energy = 0.9
	world.add_child(sun)
	var floor_mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(18,18)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(7,0,7)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("cbbca0")
	floor_mesh.material_override = material
	world.add_child(floor_mesh)
	for row in 3:
		for column in 3:
			world.values[Vector3i(4+column,0,4+row)] = [165,166,168][column]
	world.values[Vector3i(8,0,4)] = 6
	world.values[Vector3i(8,0,6)] = BlockDB.shape_id(4,"stair")
	world.values[Vector3i(9,0,6)] = BlockDB.shape_id(4,"slab")
	world.values[Vector3i(8,0,7)] = BlockDB.shape_id(5,"stair")
	world.states[Vector3i(8,0,7)] = {"top":true,"rotation":1}
	world.values[Vector3i(3,0,5)] = 28
	world.values[Vector3i(3,0,6)] = 164
	world.values[Vector3i(3,0,7)] = 4
	world.values[Vector3i(2,0,7)] = 28
	world.states[Vector3i(2,0,7)] = {"wall":[-1,0,0]}
	world.add_child(VoxelChunkMesh.build(world,Vector2i.ZERO,world.buffer()))
	var camera = Camera3D.new()
	camera.fov = 48
	world.add_child(camera)
	camera.current = true
	var viewpoints = [Vector3(12,6,13),Vector3(1,4,1),Vector3(14,2.8,4)]
	for i in viewpoints.size():
		camera.position = viewpoints[i]
		camera.look_at(Vector3(6,0.6,6),Vector3.UP)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image = root.get_texture().get_image()
		image.save_png("res://../../work/snapshot050/shapes-angle-%d.png" % i)
	print("SHAPE_GALLERY saved three runtime views")
	quit()
