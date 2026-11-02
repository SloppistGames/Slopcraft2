# Run with Godot --headless --path <project> --script res://tests/test_world.gd
extends SceneTree
var failures: Array[String] = []
var checks = 0

func check(condition: bool,message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ",message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world = VoxelWorld.new()
	root.add_child(world)
	world.set_process(false)
	var started = Time.get_ticks_msec()
	world.setup(817263,"overworld",{},2)
	world.set_process(false)
	print("GEN2_BOOTSTRAP_MS ",Time.get_ticks_msec()-started)
	check(world.chunks.size()==9,"spawn prepares nine collision chunks")
	check(world.min_y()==-176 and world.max_y()==192,"expanded generation bounds")
	check(world.get_block(Vector3i(8,-176,8))==10,"negative bedrock boundary")
	check(world.get_block(Vector3i(8,192,8))==0,"upper bound is exclusive")
	check(world.surface_height(8,8)-world.min_y()>=200,"surface has approximately 200 blocks of underground")
	await _check_floor(world,world.spawn_position(),world.surface_height(8,8)+1,"spawn")
	var seam_points = [Vector3i(-17,-130,-17),Vector3i(-16,-130,-16),Vector3i(-1,-76,15),Vector3i(0,-76,16),Vector3i(15,-1,-1),Vector3i(16,-1,0)]
	var expected: Array[int] = []
	for p in seam_points: expected.append(world.get_block(p))
	world.chunk_data.clear()
	for i in range(seam_points.size()):
		check(world.get_block(seam_points[i])==expected[i],"deterministic negative-coordinate seam "+str(seam_points[i]))
	check(world.get_block(Vector3i(19,world.surface_height(18,8)+3,8))!=29,"no preactivated Nether gateway in generator 2")
	check(world.get_block(Vector3i(33,world.surface_height(32,8)+3,8))!=30,"no preactivated End gateway in generator 2")
	check(world.climate_at(Vector3.ZERO).has("humidity"),"climate API")
	check(not world.biome_at(Vector3.ZERO).is_empty(),"biome API")
	check(not world.cave_biome_at(Vector3(0,-100,0)).is_empty(),"cave biome API")
	# A mined chamber straddles x=-1/0 and z=15/16, below the old world bottom.
	for z in range(14,18):
		for x in range(-2,2):
			for y in range(-132,-127): world.set_block(Vector3i(x,y,z),0)
	var floor_cell = Vector3i(-1,-133,15)
	world.set_block(floor_cell,146)
	world.set_block_state(floor_cell,{"rotation":3,"top":true,"powered":true})
	var saved_edits: Dictionary = JSON.parse_string(JSON.stringify(world.get_edits()))
	var saved_states: Dictionary = JSON.parse_string(JSON.stringify(world.get_states()))
	var deep_pos = Vector3(-0.5,-129,15.5)
	world.ensure_ready_at(deep_pos)
	check(world.mesh_min_y(Vector2i(-1,0))<=-133,"vertical streaming moved to deep chamber")
	await _check_floor(world,deep_pos,-132,"deep edited boundary")
	world.setup(817263,"overworld",saved_edits,2,false)
	world.block_states = saved_states
	world.set_process(false)
	check(world.get_block(floor_cell)==146,"negative edit survives serialized reload")
	check(world.get_block(Vector3i(-1,-131,15))==0,"mined air survives reload")
	check(world.get_block_state(floor_cell).get("rotation")==3,"per-cell orientation survives serialized reload")
	world.ensure_ready_at(deep_pos)
	await _check_floor(world,deep_pos,-132,"reloaded deep collision")
	world.set_block(floor_cell,0)
	check(world.get_block(floor_cell)==0,"air is a valid removal")
	check(world.get_block_state(floor_cell).is_empty(),"replacing a block clears stale state")
	world.set_block(Vector3i(0,-176,0),0)
	check(world.get_block(Vector3i(0,-176,0))==10,"bedrock edit rejected")
	world.set_block(Vector3i(-1,191,15),200)
	check(world.get_block(Vector3i(-1,191,15))==200,"IDs above 159 and upper-height edits accepted")
	check(world.mesh_max_y(Vector2i(-1,0))==192,"high player builds expand detailed mesh bounds")
	# Distances are independent. Raising a slider enqueues work; it never builds
	# hundreds of detailed chunks inside the settings callback.
	world.ensure_ready_at(world.spawn_position())
	started = Time.get_ticks_msec()
	world.set_render_distance(32)
	world.set_block_distance(12)
	world.set_render_distance(2)
	check(world.block_distance==12 and world.pending.size()>500,"full-block radius remains 12 independently of horizon setting")
	world.set_block_distance(3)
	world.set_render_distance(32)
	var change_ms = Time.get_ticks_msec()-started
	check(change_ms<250,"rapid independent distance changes stay responsive")
	var times: Array[float] = []
	var iterations = 0
	while (not world.pending.is_empty() or world.active_coord!=world.NO_CHUNK or not world.far_pending.is_empty()) and iterations<6000:
		var tick = Time.get_ticks_usec()
		world._process(1.0/60.0)
		times.append((Time.get_ticks_usec()-tick)/1000.0)
		iterations += 1
	times.sort()
	var stats = world.streaming_stats()
	print("STREAMING ",stats," steps=",iterations," p95_ms=",times[int(times.size()*0.95)]," max_ms=",times[-1]," settings_ms=",change_ms)
	check(world.chunks.size()==49,"three-chunk detailed and collision radius completes")
	check(world.far_chunks.size()>250,"32-chunk surface horizon completes")
	check(world.pending.is_empty() and world.active_coord==world.NO_CHUNK and world.far_pending.is_empty(),"incremental queues finish")
	check(stats.data_bytes<24*1024*1024,"32-chunk horizon does not allocate far voxel volumes")
	check(times[int(times.size()*0.95)]<20,"stream generation p95 remains below a 20ms frame")
	for node in world.far_chunks.values():
		check(node.find_children("*","StaticBody3D",true,false).is_empty(),"far LOD has no collision nodes")
	world.set_block_distance(12)
	world.set_block_distance(3)
	check(world.far_pending.has(Vector2i(2,0)),"shrinking full-block radius rebuilds old LOD holes")
	world.set_render_distance(2)
	world.set_block_distance(2)
	check(world.far_chunks.is_empty() and world.far_pending.is_empty(),"32 to 2 clears far meshes and queued jobs")
	check(world._stream_radius()==3,"collision radius remains three at minimum visual setting")
	# Legacy generator remains opt-in for saves that predate versioned generation.
	world.setup(817263,"overworld",{},1,false)
	world.set_process(false)
	check(world.min_y()==0 and world.max_y()==80,"legacy world preserves original height")
	check(world.surface_height(8,8)==28,"legacy spawn terrain is unchanged")
	check(world.get_block(Vector3i(19,world.surface_height(18,8)+3,8))==29,"legacy saved-world landmark remains compatible")
	for dimension in ["nether","end"]:
		world.setup(817263,dimension,{},2)
		world.set_process(false)
		check(world.is_solid(world.get_block(Vector3i(8,world.surface_height(8,8),8))),dimension+" spawn support")
		await _check_floor(world,world.spawn_position(),world.surface_height(8,8)+1,dimension)
		check(world.get_block(Vector3i(19,world.surface_height(18,8)+3,8)) not in [29,30],dimension+" has no automatic active gate")
		if dimension=="end":
			for pillar in world.end_pillars(): check(world.get_block(Vector3i(pillar)-Vector3i.UP)==18,"End spire retained")
	world.queue_free()
	await process_frame
	print("WORLD_TESTS ","PASS" if failures.is_empty() else "FAIL", " checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _check_floor(world,origin: Vector3,expected_y: float,label: String) -> void:
	await physics_frame
	await physics_frame
	var ray = PhysicsRayQueryParameters3D.create(origin+Vector3.UP*3,origin-Vector3.UP*8,1)
	var hit = world.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty(),label+" has actual physics collision")
	if not hit.is_empty(): check(absf(hit.position.y-expected_y)<0.02,label+" collision matches world coordinates")
