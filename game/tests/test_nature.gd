extends SceneTree
class TestWorld extends Node3D:
	signal block_changed(pos: Vector3i,id: int)
	var world_seed: int = 8
	var blocks: Dictionary = {}
	var states: Dictionary = {}
	func get_block(pos: Vector3i) -> int: return int(blocks.get(pos,0))
	func set_block(pos: Vector3i,id: int) -> void:
		blocks[pos] = id
		states.erase(pos)
		block_changed.emit(pos,id)
	func get_block_state(pos: Vector3i) -> Dictionary: return states.get(pos,{}).duplicate()
	func set_block_state(pos: Vector3i,state: Dictionary) -> void: states[pos] = state.duplicate()
	func surface_height(_x: int,_z: int) -> int: return -1
	func biome_at(_pos: Vector3) -> String: return "Oak Forest"
var checks: int = 0
var failures: int = 0
func _initialize() -> void: run.call_deferred()
func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func simulate(nature: NatureSystem,seconds: float) -> void:
	for frame in range(int(seconds*10)):
		nature._process(0.1)
		if nature.queries_last_tick > NatureSystem.QUERY_BUDGET:
			check(false,"leaf queries exceed per-tick budget")
func run() -> void:
	var world: TestWorld = TestWorld.new()
	root.add_child(world)
	var player: Node3D = Node3D.new()
	world.add_child(player)
	player.position = Vector3(50,0,50)
	var inventory: PlayerInventory = PlayerInventory.new()
	BlockAtlas.prepare()
	var mesher: VoxelChunkMesh = VoxelChunkMesh.new()
	mesher._ensure_materials()
	var nature: NatureSystem = NatureSystem.new()
	world.add_child(nature)
	nature.setup(world,player,inventory,null)
	nature.set_process(false)
	var log: Vector3i = Vector3i(0,4,0)
	world.blocks[log] = 5
	for x in range(1,5): world.blocks[Vector3i(x,4,0)] = 6
	nature._enqueue(Vector3i(1,4,0))
	simulate(nature,10.0)
	check(world.get_block(Vector3i(1,4,0)) == 6,"connected leaf survives")
	check(nature._decay.is_empty(),"supported leaves never queued for decay")
	world.set_block(log,0)
	simulate(nature,45.0)
	for x in range(1,5): check(world.get_block(Vector3i(x,4,0)) == 0,"unsupported leaf chain decays "+str(x))
	check(nature.decayed_count == 4,"decay propagation counted")
	world.blocks[Vector3i(9,4,0)] = 6
	nature._enqueue(Vector3i(9,4,0))
	simulate(nature,1.0)
	check(nature._decay.has(Vector3i(9,4,0)),"unsupported leaf schedules delayed decay")
	world.set_block(Vector3i(8,4,0),5)
	simulate(nature,10.0)
	check(world.get_block(Vector3i(9,4,0)) == 6,"restored support cancels decay")
	world.set_block(Vector3i(20,4,0),6)
	nature._enqueue(Vector3i(20,4,0))
	simulate(nature,10.0)
	check(world.get_block(Vector3i(20,4,0)) == 6,"player decorative leaves persistent")
	world.blocks[Vector3i(30,4,0)] = 6
	nature._enqueue(Vector3i(30,4,0))
	simulate(nature,0.3)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(nature.serialize()))
	nature.restore(saved)
	simulate(nature,10.0)
	check(world.get_block(Vector3i(30,4,0)) == 0,"pending leaf decay survives JSON restore")
	player.position = Vector3(100,4,100)
	nature._spawn_drop(Vector3(100,4,100),1000)
	nature._update_drops(0.01)
	check(inventory.count_item(1000) == 1,"leaf drop pickup grants actual stick")
	player.position = Vector3.ZERO
	nature._spawn_drop(Vector3(100,4,100),1200)
	var dropped: Dictionary = JSON.parse_string(JSON.stringify(nature.serialize()))
	nature.restore(dropped)
	check(nature._drops.size() >= 1,"uncollected drops restored")
	check(BlockAtlas.materials[0] is ShaderMaterial,"atlas uses shader foliage wind")
	check(BlockAtlas.materials[0].get_meta("nature_wind",false),"foliage shader tagged for reuse")
	check(BlockAtlas.materials[3] is ShaderMaterial and "cull_disabled" in BlockAtlas.materials[3].shader.code,"plants retain double-sided cutout wind shader")
	check(nature._drift.multimesh.instance_count == 24,"ambient leaves bounded multimesh")
	world.queue_free()
	await process_frame
	await process_frame
	print("NATURE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
