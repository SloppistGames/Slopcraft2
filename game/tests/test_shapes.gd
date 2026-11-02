extends SceneTree
var checks = 0
var failures: Array[String] = []
class FixtureWorld:
	extends Node3D
	var solid_flags: Dictionary = {}
	var states: Dictionary = {}
	var values: Dictionary = {}
	func _init():
		for info in BlockDB.all_blocks(): solid_flags[int(info.id)] = bool(info.get("solid",true))
	func min_y(): return 0
	func mesh_min_y(_coord): return 0
	func mesh_max_y(_coord): return 2
	func want_collision(_coord): return true
	func is_solid(id): return solid_flags.get(id,false)
	func is_transparent(id): return BlockDB.get_block(id).get("transparent",false)
	func get_block(p): return values.get(p,0)
	func get_block_state(p): return states.get(p,{})
	func buffer():
		var result = PackedInt32Array()
		result.resize(512)
		for p in values:
			if p.x>=0 and p.x<16 and p.z>=0 and p.z<16 and p.y>=0 and p.y<2:
				result[p.x+p.z*16+p.y*256] = values[p]
		return result

func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL ",message)

func _initialize(): call_deferred("_run")

func _run():
	BlockAtlas.prepare()
	for base in BlockDB.shape_families():
		for shape in ["slab","stair"]:
			var id = BlockDB.shape_id(base,shape)
			for top in [false,true]:
				for rotation in 4:
					var state = {"top":top,"rotation":rotation}
					var volume = 0.0
					for box in BlockShapes.boxes(id,state): volume += box.get_volume()
					check(is_equal_approx(volume,0.5 if shape=="slab" else 0.75),"family shape volume "+str(id))
					var area = 0.0
					for panel in BlockShapes.faces(id,state):
						var points: Array = panel.points
						area += (points[1]-points[0]).cross(points[3]-points[0]).length()
					check(is_equal_approx(area,4.0 if shape=="slab" else 5.5),"union exposes no internal faces "+str(id))
	var world = FixtureWorld.new()
	root.add_child(world)
	var stair = BlockDB.shape_id(4,"stair")
	var slab = BlockDB.shape_id(4,"slab")
	var cell = Vector3i(1,0,1)
	for top in [false,true]:
		for rotation in 4:
			world.values = {cell:stair}
			world.states = {cell:{"top":top,"rotation":rotation}}
			var chunk = VoxelChunkMesh.build(world,Vector2i.ZERO,world.buffer())
			world.add_child(chunk)
			await physics_frame
			await physics_frame
			for x in [0.25,0.75]:
				for z in [0.25,0.75]:
					var upper = 0.0
					var lower = 1.0
					for box in BlockShapes.boxes(stair,world.states[cell]):
						if x>=box.position.x and x<box.end.x and z>=box.position.z and z<box.end.z:
							upper = maxf(upper,box.end.y)
							lower = minf(lower,box.position.y)
					var query = PhysicsRayQueryParameters3D.create(Vector3(1+x,2,1+z),Vector3(1+x,-1,1+z),1)
					var hit = world.get_world_3d().direct_space_state.intersect_ray(query)
					check(not hit.is_empty() and is_equal_approx(hit.get("position",Vector3.ZERO).y,upper),"rotated stair upper collision")
					query = PhysicsRayQueryParameters3D.create(Vector3(1+x,-1,1+z),Vector3(1+x,2,1+z),1)
					hit = world.get_world_3d().direct_space_state.intersect_ray(query)
					check(not hit.is_empty() and is_equal_approx(hit.get("position",Vector3.ONE).y,lower),"rotated stair underside collision")
			world.remove_child(chunk)
			chunk.free()
	world.values = {cell:4,cell+Vector3i.RIGHT:slab}
	world.states = {}
	var job = VoxelChunkMesh.new()
	job.begin(world,Vector2i.ZERO,world.buffer())
	job.step(-1)
	check(is_equal_approx(_area(job),9.0),"cube face clips precisely against adjoining half slab")
	world.values = {cell:slab,cell+Vector3i.RIGHT:slab}
	job.begin(world,Vector2i.ZERO,world.buffer())
	job.step(-1)
	check(is_equal_approx(_area(job),7.0),"equal adjacent slabs omit only their shared half face")
	for id in [165,166,168]:
		world.values = {cell:id}
		job.begin(world,Vector2i.ZERO,world.buffer())
		job.step(-1)
		check(job.verts[3].size()==8 and job.indices[3].size()==12,"plant is two crossed quads "+str(id))
		check(job.collision.is_empty(),"plant has no physical cube "+str(id))
		check(job.verts[0].is_empty(),"plant avoids opaque cube material "+str(id))
		var image = BlockAtlas.face_image(id,5)
		var clear = 0
		var ink = 0
		for y in 16:
			for x in 16:
				if image.get_pixel(x,y).a<0.5: clear += 1
				else: ink += 1
		check(clear>64 and ink>8,"plant image has real cutout background "+str(id))
	check(BlockAtlas.materials[3].cull_mode==BaseMaterial3D.CULL_DISABLED,"plants render from both sides")
	check(BlockAtlas.materials[3].transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,"plant group uses alpha cutout")
	world.values = {cell:6}
	job.begin(world,Vector2i.ZERO,world.buffer())
	job.step(-1)
	check(job.verts[0].size()==24 and job.verts[3].is_empty(),"leaves retain six-face block geometry")
	for id in [28,164]:
		for wall in [[0,1,0],[1,0,0],[-1,0,0],[0,0,1],[0,0,-1]]:
			world.values = {cell:id}
			world.states = {cell:{"wall":wall}}
			job.begin(world,Vector2i.ZERO,world.buffer())
			job.step(-1)
			check(job.verts[2].size()==24 and job.collision.is_empty(),"torch uses narrow noncolliding shaft")
			check(BlockShapes.boxes(id,world.states[cell])[0].get_volume()<0.08,"torch selection is narrow")
			check(job.torch_cells==[cell],"torch metadata supports bounded lights")
	world.values = {cell:9,cell+Vector3i.RIGHT:9}
	world.states = {cell:{"fluid_level":0},cell+Vector3i.RIGHT:{"fluid_level":7}}
	job.begin(world,Vector2i.ZERO,world.buffer()); job.step(-1)
	var step_face = false
	for i in range(0,job.verts[1].size(),4):
		if job.normals[1][i]==Vector3.RIGHT and is_equal_approx(job.verts[1][i].x,2.0): step_face = true
	check(step_face,"water level step has an exposed vertical edge")
	world.free()
	await _test_lights()
	print("SHAPE_TESTS ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _area(job) -> float:
	var area = 0.0
	for group in job.verts.size():
		for i in range(0,job.verts[group].size(),4):
			area += (job.verts[group][i+1]-job.verts[group][i]).cross(job.verts[group][i+3]-job.verts[group][i]).length()
	return area

func _test_lights():
	var world = VoxelWorld.new()
	root.add_child(world)
	world.setup(817263,"overworld",{},2,false)
	world.set_process(false)
	var player = Node3D.new()
	world.add_child(player)
	player.position = Vector3(8,40,8)
	var lights = load("res://systems/torch_lights.gd").new()
	world.add_child(lights)
	lights.setup(world,player)
	for i in 20: world.set_block(Vector3i(2+i%10,40,2+i/10),28)
	lights._refresh()
	check(lights.pool.size()==12 and lights.selected.size()==12,"torch lights stay within pool budget")
	var removed: Vector3i = lights.selected[0]
	world.set_block(removed,0)
	lights._refresh()
	check(not lights.selected.has(removed),"broken torch loses light immediately")
	var disabled: Vector3i = lights.selected[0]
	world.set_block_state(disabled,{"lit":false})
	lights._refresh()
	check(not lights.selected.has(disabled),"unlit torch does not emit light")
	player.position = Vector3(1000,40,1000)
	lights._refresh()
	check(lights.selected.is_empty(),"distant torches release pooled lights")
	check(lights.flame_frames.size()==4,"torch flame animates through pixel frames")
	world.queue_free()
	await process_frame
