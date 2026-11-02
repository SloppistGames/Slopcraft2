extends SceneTree
func _initialize(): call_deferred("run")
func run():
	root.size=Vector2i(1200,850)
	var world=load("res://tests/circuit_gallery.gd").GalleryWorld.new(); root.add_child(world)
	for r in 4:
		var foot=Vector3i(4+(r%2)*5,1,4+int(r/2)*5)
		var head=foot+RestTransportSystem.DIRECTIONS[r]
		world.set_block(foot,181); world.set_block(head,182)
		world.set_block_state(foot,{"rotation":r}); world.set_block_state(head,{"rotation":r})
	world.add_child(VoxelChunkMesh.build(world,Vector2i.ZERO,world.buffer()))
	var environment=WorldEnvironment.new(); environment.environment=Environment.new(); var env=environment.environment
	env.background_mode=Environment.BG_COLOR; env.background_color=Color("263747"); env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("c8d2e0"); env.ambient_light_energy=.5; world.add_child(environment)
	var sun=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-50,-25,0); sun.light_energy=.65; world.add_child(sun)
	var camera=Camera3D.new(); world.add_child(camera); camera.current=true; camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=12
	for i in 3:
		camera.position=[Vector3(16,13,19),Vector3(-4,7,15),Vector3(11,20,10)][i]; camera.look_at(Vector3(7,1,7),Vector3.UP)
		await process_frame; await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../../work/snapshot050/bed-fixed-%d.png"%i)
	BlockAtlas.export_art("res://assets/textures")
	print("BED GALLERY: all four rotations captured")
	world.queue_free(); await process_frame; quit()
