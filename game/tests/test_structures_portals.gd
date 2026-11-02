extends SceneTree

const Terrain = preload("res://world/terrain_generator.gd")
const Structures = preload("res://world/structure_generator.gd")
const Portals = preload("res://systems/portal_system.gd")
const Inventory = preload("res://inventory/inventory.gd")
var checks: int = 0
var failures: int = 0

class TestWorld extends Node3D:
	signal block_changed(p: Vector3i,id: int)
	var dimension: String = "overworld"
	var structure_provider
	var terrain
	var edits: Dictionary = {}
	var ready_position: Vector3 = Vector3.INF
	func get_block(p: Vector3i) -> int:
		if edits.has(p): return edits[p]
		if structure_provider != null:
			var id: int = structure_provider.block_at(p)
			if id >= 0: return id
		if terrain != null: return terrain.block_at(p.x,p.y,p.z)
		return 3 if p.y <= 30 else 0
	func set_block(p: Vector3i,id: int) -> void:
		edits[p] = id
		block_changed.emit(p,id)
	func surface_height(x: int,z: int) -> int:
		return int(terrain.column(x,z).height) if terrain != null else 30
	func is_solid(id: int) -> bool:
		return bool(BlockDB.get_block(id).get("solid",id != 0))
	func max_y() -> int: return 192
	func min_y() -> int: return -176
	func spawn_position() -> Vector3: return Vector3(8.5,32.1,8.5)
	func ensure_ready_at(p: Vector3) -> void: ready_position = p

class TestPlayer extends CharacterBody3D:
	signal notify(message: String)
	var item_use_handler: Callable
	var portal_handler_active: bool = false
	var active: bool = true

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var terrain = Terrain.new()
	terrain.setup(87023)
	var generator = Structures.new()
	generator.setup(87023,terrain)
	var twin = Structures.new()
	twin.setup(87023,terrain)
	var samples: Dictionary = {}
	var counts: Dictionary = {}
	for z in range(-6,7):
		for x in range(-6,7):
			for structure in generator._region(Vector2i(x,z)):
				counts[structure.type] = int(counts.get(structure.type,0))+1
				if not samples.has(structure.type): samples[structure.type] = structure
	for type in Structures.TYPES:
		if type == "stronghold": continue
		check(samples.has(type),"reachable generated structure: "+type)
	samples.stronghold = generator.strongholds[0]
	for type in samples:
		var s: Dictionary = samples[type]
		generator._materialize(s)
		var coords: Array = []
		for dz in range(-int(s.radius),int(s.radius)+1,8):
			for dx in range(-int(s.radius),int(s.radius)+1,8):
				var coord = Vector2i(floori((s.origin.x+dx)/16.0),floori((s.origin.z+dz)/16.0))
				if not coords.has(coord): coords.append(coord)
		var block_count: int = 0
		for coord in coords:
			var blocks: Dictionary = generator.prepare_chunk(coord)
			check(blocks == twin.prepare_chunk(coord),"deterministic chunk blueprint "+str(type)+" "+str(coord))
			for p: Vector3i in blocks:
				var id: int = blocks[p]
				if id > 0: block_count += 1
				check(id not in [29,30],"no automatically active gateways")
				check(generator.block_at(p) == id,"direct structure query matches chunk override")
		check(block_count > 30,"structure contains actual placed blocks: "+str(type))
		check(not s.loot.is_empty(),"obtainable loot attached to "+str(type))
		for chest in s.loot:
			check(generator.block_at(chest.position) == 27,"loot points at chest voxel")
			check(generator.loot_at(chest.position) == chest.items,"loot is deterministic and copied")
		if type in ["village","temple","ruin","camp","mountain_cabin"]:
			check(generator._fits(s.origin.x,s.origin.z,26 if type == "village" else (12 if type == "temple" else 8),6 if type == "village" else 5),"structure fits low-relief dry land")
		if type == "village":
			check(s.villagers.size() == 4,"four village inhabitants with stable identities")
			var professions: Dictionary = {}
			for npc in s.villagers:
				professions[npc.profession] = true
				var feet = Vector3i(floori(npc.position.x),floori(npc.position.y),floori(npc.position.z))
				check(generator.block_at(feet) == 0,"NPC marker has free body space")
				check(generator.block_at(feet-Vector3i.UP) == 169,"NPC marker has supported road")
			check(professions.size() == 4,"different professions")
		print("STRUCTURE ",type," at ",s.position," blocks=",block_count," variant=",s.variant)
	var ring_helper = Portals.new()
	for s in generator.strongholds:
		generator._materialize(s)
		var frames: int = 0
		for p in ring_helper._ring(s.portal_center):
			if generator.block_at(p) == 153: frames += 1
		check(frames == 12,"stronghold has twelve inactive frames")
	ring_helper.free()
	check(generator.locate("stronghold",Vector3.ZERO) == twin.locate("stronghold",Vector3.ZERO),"Eyes locate seed-stable stronghold")
	print("STRUCTURE_COUNTS ",counts)
	_test_portals(generator,terrain)
	_test_real_world()
	await process_frame
	print("STRUCTURES_PORTALS: ",checks," checks; ",failures," failures; ",Time.get_ticks_msec()-started," ms")
	quit(0 if failures == 0 else 1)

func _test_portals(generator,terrain) -> void:
	var world = TestWorld.new()
	root.add_child(world)
	var player = TestPlayer.new()
	world.add_child(player)
	player.position = Vector3(1.5,31.1,0.5)
	var inventory = Inventory.new()
	inventory.setup(false)
	inventory.add_item(1021,16)
	var system = Portals.new()
	world.add_child(system)
	system.setup(world,player,inventory,null)
	system.set_process(false)
	check(player.portal_handler_active and player.item_use_handler.is_valid(),"player routes portal interactions")
	var origin = Vector3i(-17,30,15)
	_build_frame(world,origin,Vector3i.RIGHT)
	var frame: Dictionary = system.find_nether_frame(origin+Vector3i.RIGHT)
	check(not frame.is_empty(),"valid X-oriented obsidian rectangle found across signed seam")
	system.activate_nether_frame(frame)
	check(world.get_block(origin+Vector3i(1,1,0)) == 29,"frame ignition fills portal")
	world.set_block(origin+Vector3i(0,2,0),0)
	check(world.get_block(origin+Vector3i(1,1,0)) == 0,"breaking frame extinguishes interior")
	check(system.find_nether_frame(origin).is_empty(),"broken rectangle cannot ignite")
	var other = Vector3i(20,30,-17)
	_build_frame(world,other,Vector3i.BACK)
	var zframe: Dictionary = system.find_nether_frame(other+Vector3i.BACK)
	check(not zframe.is_empty() and int(zframe.axis) == 1,"Z-oriented frame accepted")
	system.activate_nether_frame(zframe)
	var saved: Dictionary = system.serialize()
	system.restore(saved)
	check(system.active_frames.size() == 1,"portal frame state survives restore")
	var target: Vector3i = other+Vector3i(0,1,1)
	player.position = Vector3(target)+Vector3(0.5,0.1,0.5)
	system.cooldown = 0.0
	system.request_travel(target,29)
	var outbound: Dictionary = system.pending_travel.duplicate(true)
	check(str(outbound.to) == "nether","Nether travel request has explicit destination")
	var nether = TestWorld.new()
	nether.dimension = "nether"
	root.add_child(nether)
	var nether_player = TestPlayer.new()
	nether.add_child(nether_player)
	var return_system = Portals.new()
	nether.add_child(return_system)
	return_system.setup(nether,nether_player,inventory,null)
	return_system.set_process(false)
	return_system.arrive(outbound)
	check(return_system.links.size() == 1,"arrival creates one saved return link")
	check(nether.ready_position == nether_player.global_position,"arrival collision prepared at exit")
	var arrival: Vector3i = return_system._cell(return_system.links.values()[0].anchor)
	check(nether.get_block(arrival) == 29,"arrival has usable return gateway")
	var edits: int = nether.edits.size()
	return_system.arrive(outbound)
	check(nether.edits.size() == edits and return_system.links.size() == 1,"repeated arrival reuses gate instead of duplication")
	return_system.cooldown = 0.0
	return_system.request_travel(arrival,29)
	var inbound: Dictionary = return_system.pending_travel.duplicate(true)
	check(str(inbound.to) == "overworld" and return_system._cell(inbound.destination) == target,"return preserves original realm and exact gateway")
	system.arrive(inbound)
	check(player.global_position.distance_to(Vector3(target)) < 6.0,"round trip exits beside original gate")
	# Generated End room starts inactive, consumes precisely twelve Eyes and
	# deactivates if its filled ring is subsequently broken.
	world.structure_provider = generator
	world.terrain = terrain
	var stronghold: Dictionary = generator.strongholds[0]
	var center: Vector3i = stronghold.portal_center
	var before: int = inventory.count_item(1021)
	var index: int = 0
	for p in system._ring(center):
		check(system.insert_eye(p),"Eye inserts into complete generated ring")
		index += 1
		if index < 12: check(world.get_block(center) != 30,"incomplete Eye ring stays inactive")
	check(world.get_block(center) == 30,"all twelve Eyes activate End portal")
	check(inventory.count_item(1021) == before-12,"End activation consumes exactly twelve Eyes")
	var filled: Vector3i = system._ring(center)[0]
	check(not system.insert_eye(filled),"filled frame does not consume a second Eye")
	world.set_block(filled,0)
	check(world.get_block(center) == 0,"broken End ring closes portal")
	var camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(8,35,8)
	check(system.throw_eye(camera),"Eye throws using actual item inventory")
	check(system.last_eye_target == generator.locate("stronghold",camera.global_position),"Eye guides toward generated stronghold")
	check(system.eye_flights.size() == 1,"Eye has a moving world visual")
	player.active = false
	system._process(2.7)
	check(system.eye_flights.is_empty(),"Eye flight ends and returns or breaks")
	world.queue_free()
	nether.queue_free()

func _build_frame(world,origin: Vector3i,axis: Vector3i) -> void:
	for y in range(5):
		for x in range(4):
			world.set_block(origin+axis*x+Vector3i(0,y,0),18 if x in [0,3] or y in [0,4] else 0)

func _test_real_world() -> void:
	var script = load("res://world/voxel_world.gd")
	var world = script.new()
	root.add_child(world)
	world.setup(87023,"overworld",{},2,false)
	world.set_process(false)
	check(world.structure_provider != null,"VoxelWorld integrates structure provider")
	var stronghold: Vector3 = world.structure_provider.locate("stronghold",Vector3.ZERO)
	var center = Vector3i(stronghold)
	var player = TestPlayer.new()
	world.add_child(player)
	var inventory = Inventory.new()
	inventory.setup(false)
	inventory.add_item(1021,12)
	var system = Portals.new()
	world.add_child(system)
	system.setup(world,player,inventory,null)
	system.set_process(false)
	for p in system._ring(center):
		check(world.get_block(p) == 153,"real world queries generated underground frame")
		check(system.insert_eye(p),"real world accepts inserted Eye")
	check(world.get_block(center) == 30,"real VoxelWorld End activation integrated")
	check(world.get_edits().has(system._key(center)),"portal activation persists as world edits")
	check(world.chunk_data.is_empty(),"far structure queries avoid full chunk generation")
	world.queue_free()

func check(condition: bool,message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ",message)
