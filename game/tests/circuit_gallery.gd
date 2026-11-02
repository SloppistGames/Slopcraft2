extends SceneTree
class GalleryWorld extends "res://tests/test_redstone.gd".Fixture:
	var solid_flags: Dictionary={}
	var chunks: Dictionary={}
	var focus_position=Vector3(7,2,8)
	func _init():
		for info in BlockDB.all_blocks(): solid_flags[int(info.id)]=bool(info.get("solid",true))
	func min_y(): return 0
	func mesh_min_y(_coord): return 0
	func mesh_max_y(_coord): return 4
	func want_collision(_coord): return true
	func is_transparent(id): return BlockDB.get_block(id).get("transparent",false)
	func buffer():
		var result=PackedInt32Array(); result.resize(1024)
		for y in 4:
			for z in 16:
				for x in 16: result[x+z*16+y*256]=get_block(Vector3i(x,y,z))
		return result
func _initialize(): call_deferred("run")
func run():
	root.size=Vector2i(1280,900)
	var world=GalleryWorld.new(); root.add_child(world)
	var circuit=RedstoneSystem.new(); world.add_child(circuit); circuit.setup(world,null,null,null); circuit.set_process(false)
	world.set_block(Vector3i(2,1,4),156)
	for x in [3,4,5,7,8,9]: world.set_block(Vector3i(x,1,4),155)
	world.set_block(Vector3i(6,1,4),157); world.set_block_state(Vector3i(6,1,4),{"rotation":1})
	world.set_block(Vector3i(10,1,4),158); circuit.interact_at(Vector3i(2,1,4))
	world.set_block(Vector3i(3,1,8),27); world.set_block(Vector3i(4,1,8),179); world.set_block_state(Vector3i(4,1,8),{"rotation":1})
	circuit.storage_get=func(_p): return [{"id":7,"count":64}]
	world.set_block(Vector3i(5,1,8),155); world.set_block(Vector3i(6,1,8),158)
	world.set_block(Vector3i(9,1,9),160); world.set_block(Vector3i(10,1,9),84); world.set_block(Vector3i(9,1,8),7)
	world.set_block(Vector3i(2,1,12),181); world.set_block(Vector3i(2,1,11),182)
	world.set_block(Vector3i(5,1,12),181); world.set_block_state(Vector3i(5,1,12),{"rotation":1})
	world.set_block(Vector3i(6,1,12),182); world.set_block_state(Vector3i(6,1,12),{"rotation":1})
	world.set_block(Vector3i(8,1,13),177); world.set_block(Vector3i(10,1,13),178)
	world.set_block(Vector3i(12,1,7),28); world.set_block(Vector3i(12,1,10),164)
	world.set_block(Vector3i(1,1,6),165); world.set_block(Vector3i(1,1,7),166); world.set_block(Vector3i(1,1,8),168)
	for index in 100: circuit.step(4096,0)
	var chunk=VoxelChunkMesh.build(world,Vector2i.ZERO,world.buffer()); world.add_child(chunk); world.chunks[Vector2i.ZERO]=chunk
	var lights=TorchLights.new(); world.add_child(lights); lights.setup(world,null)
	var env=WorldEnvironment.new(); env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color("263747")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("c8d2e0"); env.environment.ambient_light_energy=.5
	world.add_child(env)
	var sun=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-50,-25,0); sun.light_energy=.7; world.add_child(sun)
	var camera=Camera3D.new(); world.add_child(camera); camera.fov=48; camera.current=true
	var views=[Vector3(18,15,22),Vector3(-6,9,16),Vector3(14,7,-5)]
	for index in views.size():
		camera.position=views[index]; camera.look_at(Vector3(6.5,.8,8),Vector3.UP)
		await process_frame; await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../../work/snapshot050/circuits-beds-angle-%d.png" % index)
	print("CIRCUIT_GALLERY saved three native views; lamps=",world.get_block_state(Vector3i(10,1,4)).get("powered",false)," piston=",world.get_block(Vector3i(9,1,8))," pooled_lights=",lights.pool.size())
	quit()
