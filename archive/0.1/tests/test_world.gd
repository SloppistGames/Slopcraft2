# Run: godot --headless --path <project> --script res://tests/test_world.gd
extends SceneTree

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: ",message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world = VoxelWorld.new()
	root.add_child(world)
	world.set_process(false)
	for dimension in ["overworld","nether","end"]:
		var start = Time.get_ticks_msec()
		world.setup(817263,dimension)
		world.set_process(false)
		print(dimension," setup_ms=",Time.get_ticks_msec()-start," chunks=",world.chunks.size()," data_chunks=",world.chunk_data.size())
		check(world.chunks.size()==9,dimension+" initial chunk count")
		var spawn = world.spawn_position()
		var height = world.surface_height(8,8)
		check(world.is_solid(world.get_block(Vector3i(8,height,8))),dimension+" spawn support")
		check(world.get_block(Vector3i(spawn))==0,dimension+" spawn clearance")
		await physics_frame
		await physics_frame
		var query = PhysicsRayQueryParameters3D.create(Vector3(8.5,height+8,8.5),Vector3(8.5,height-3,8.5),1)
		var hit = world.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty(),dimension+" ray intersects spawn collision from above")
		if not hit.is_empty():
			check(absf(hit.position.y-(height+1)) < 0.02,dimension+" collision surface matches voxel")
		var seams = [Vector3i(-1,20,-1),Vector3i(0,20,0),Vector3i(15,20,15),Vector3i(16,20,16),Vector3i(-16,20,-16),Vector3i(-17,20,-17)]
		var original: Array[int] = []
		for p in seams:
			original.append(world.get_block(p))
		world.chunk_data.clear()
		for i in range(seams.size()):
			check(world.get_block(seams[i])==original[i],dimension+" deterministic chunk seam "+str(seams[i]))
		var target = Vector3i(-1,75,15)
		world.set_block(target,146)
		check(world.get_block(target)==146,dimension+" set nontruncated high block ID")
		var edit_steps = 0
		while not world.dirty_chunks.is_empty() and edit_steps < 200:
			world._process(1.0/60.0)
			edit_steps += 1
		await physics_frame
		await physics_frame
		var edit_query = PhysicsRayQueryParameters3D.create(Vector3(-0.5,78,15.5),Vector3(-0.5,74,15.5),1)
		var edit_hit = world.get_world_3d().direct_space_state.intersect_ray(edit_query)
		check(not edit_hit.is_empty(),dimension+" edited block collision installed")
		var saved = world.get_edits()
		check(saved.get("-1,75,15",0)==146,dimension+" serializes signed block coordinates")
		world.setup(817263,dimension,saved)
		world.set_process(false)
		check(world.get_block(target)==146,dimension+" reload preserves edited block")
		world.set_block(target,0)
		world.chunk_data.clear()
		check(world.get_block(target)==0,dimension+" removal survives regeneration")
		start = Time.get_ticks_msec()
		for coord in [Vector2i(2,0),Vector2i(2,1),Vector2i(2,2)]:
			world._build_chunk(coord)
		print(dimension," avg_chunk_build_ms=",float(Time.get_ticks_msec()-start)/3.0)
		if dimension == "end":
			check(world.get_block(Vector3i(78,0,8))==0,"end void below island")
			for pillar in world.end_pillars():
				check(world.get_block(Vector3i(pillar)-Vector3i.UP)==18,"end crystal supported by spire")
		var timings: Array[float] = []
		var iterations = 0
		while (not world.pending.is_empty() or world.active_coord != world.NO_CHUNK) and iterations < 1400:
			var step_start = Time.get_ticks_usec()
			world._process(1.0/60.0)
			timings.append(float(Time.get_ticks_usec()-step_start)/1000.0)
			iterations += 1
		timings.sort()
		print(dimension," stream_steps=",iterations," step_p95_ms=",timings[int(timings.size()*0.95)]," max_ms=",timings[-1])
		check(world.chunks.size()>=49,dimension+" incremental streaming completes")
		var far_position = Vector3(2048.5,world.surface_height(2048,-1792)+9,-1791.5)
		world.ensure_ready_at(far_position)
		check(world.chunks.has(Vector2i(128,-112)),dimension+" far restore collision chunk ready")
		await physics_frame
		await physics_frame
		if dimension != "end" or world.surface_height(2048,-1792) > 0:
			var far_query = PhysicsRayQueryParameters3D.create(far_position,far_position-Vector3(0,15,0),1)
			check(not world.get_world_3d().direct_space_state.intersect_ray(far_query).is_empty(),dimension+" far restore physics support")
		await process_frame
	world.queue_free()
	await process_frame
	print("WORLD_TESTS ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
