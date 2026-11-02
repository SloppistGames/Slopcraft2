extends SceneTree
const Rest = preload("res://systems/rest_transport_system.gd")
var checks: int = 0
var failures: int = 0

class Atmosphere extends Node3D:
	var time_of_day: float = 0.72
	func _update_lighting() -> void: pass

class World extends Node3D:
	signal block_changed(p: Vector3i,id: int)
	var dimension: String = "overworld"
	var cells: Dictionary = {}
	var states: Dictionary = {}
	var atmosphere = Atmosphere.new()
	var prepared = Vector3.INF
	func _ready() -> void: add_child(atmosphere)
	func get_block(p: Vector3i) -> int: return int(cells.get(p,3 if p.y <= 0 else 0))
	func set_block(p: Vector3i,id: int) -> void:
		if get_block(p) == id: return
		cells[p] = id
		states.erase(p)
		block_changed.emit(p,id)
	func get_block_state(p: Vector3i) -> Dictionary: return states.get(p,{}).duplicate(true)
	func set_block_state(p: Vector3i,state: Dictionary) -> void: states[p] = state.duplicate(true)
	func min_y() -> int: return -176
	func max_y() -> int: return 192
	func is_solid(id: int) -> bool: return bool(BlockDB.get_block(id).get("solid",false))
	func ensure_ready_at(p: Vector3) -> void: prepared = p
	func spawn_position() -> Vector3: return Vector3(0.5,1.1,0.5)

class Rider extends CharacterBody3D:
	signal notify(message: String)
	var item_use_handler: Callable
	var mounted_vehicle: Node3D
	var bed_spawn: Array = []
	var bed_dimension: String = ""
	var active: bool = true
	var flying: bool = false

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var world = World.new()
	root.add_child(world)
	var player = Rider.new()
	world.add_child(player)
	var bag = PlayerInventory.new()
	bag.setup(false)
	bag.add_item(181,12)
	var system = Rest.new()
	world.add_child(system)
	system.setup(world,player,bag,null)
	system.set_physics_process(false)
	for rotation in range(4):
		var foot = Vector3i(-16+rotation*6,1,3)
		var head: Vector3i = foot+Rest.DIRECTIONS[rotation]
		var count: int = bag.count_item(181)
		check(system.place_bed(foot,rotation),"bed places across negative and positive coordinates")
		check(world.get_block(head) == 182 and int(world.get_block_state(head).rotation) == rotation,"head follows all four rotations")
		check(bag.count_item(181) == count-1,"paired bed consumes one item")
		world.set_block(head+Vector3i.DOWN,0)
		check(world.get_block(foot) == 0 and world.get_block(head) == 0,"support removal collapses both halves")
		check(bag.count_item(181) == count,"unsupported pair refunds one bed")
		world.set_block(foot+Vector3i.DOWN,0)
		check(bag.count_item(181) == count,"second removed support cannot duplicate bed")
	var foot = Vector3i(6,1,3)
	var head = foot+Vector3i.FORWARD
	var slab: int = BlockDB.shape_id(7,"slab")
	for p in [foot,head]: world.set_block(p+Vector3i.DOWN,slab)
	check(not system.place_bed(foot,0),"bottom slabs do not leave bed floating")
	for p in [foot,head]: world.set_block_state(p+Vector3i.DOWN,{"top":true})
	check(system.place_bed(foot,0),"top slabs support every bed leg")
	world.atmosphere.time_of_day = 0.25
	system.interact_at(head)
	check(player.bed_spawn == [6,1,3] and world.atmosphere.time_of_day == 0.25,"daytime rest sets spawn without advancing day")
	world.atmosphere.time_of_day = 0.75
	system.interact_at(foot)
	check(is_equal_approx(world.atmosphere.time_of_day,0.08),"night rest advances to dawn")
	check(system.respawn_position().distance_to(Vector3(foot)) < 3.0,"valid bed spawn has safe neighboring space")
	world.set_block(head+Vector3i.UP,3)
	check(system.respawn_position() == world.spawn_position(),"blocked bed headroom falls back to spawn")
	world.set_block(head+Vector3i.UP,0)
	# A full backpack must not delete the recovered bed or duplicate it later.
	for slot in bag.slots:
		slot.id = 3
		slot.count = 64
	world.set_block(foot+Vector3i.DOWN,0)
	check(system.pending_bed_refunds == 1,"full inventory retains one recoverable bed")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(system.serialize()))
	system.restore(saved)
	check(system.pending_bed_refunds == 1,"pending bed recovery survives save")
	bag.slots[0] = {"id":0,"count":0}
	system._physics_process(1.1)
	check(system.pending_bed_refunds == 0 and bag.count_item(181) == 1,"recovery delivered exactly once when room opens")
	# Broad pond with a one-voxel wall across its center.
	bag.slots[1] = {"id":1402,"count":1}
	bag.slots[2] = {"id":1402,"count":1}
	for x in range(10,31):
		for z in range(-25,16):
			for y in [1,2]: world.set_block(Vector3i(x,y,z),9)
	var id: String = system.launch_boat(Vector3i(20,2,5))
	check(not id.is_empty(),"boat launches on open water")
	var count: int = bag.count_item(1402)
	check(system.launch_boat(Vector3i(20,2,5)).is_empty() and bag.count_item(1402) == count,"overlapping boat rejected without spending item")
	player.position = Vector3.ZERO
	check(not system.mount(id),"cannot mount a distant boat")
	player.position = system.boats[id].node.position+Vector3.RIGHT*2.0
	var roof = Vector3i(20,4,5)
	world.set_block(roof,3)
	check(not system.mount(id),"cannot board beneath insufficient headroom")
	world.set_block(roof,0)
	check(system.mount(id),"nearby unobstructed boat mounts")
	for x in range(10,31):
		for y in range(1,6): world.set_block(Vector3i(x,y,1),3)
	system.boats[id].speed = 7.5
	for iteration in range(8): system.step_boat(id,1.0,1.0,0.0)
	check(system.boats[id].node.position.z > 2.8,"swept hull stops before thin wall even on stalled frames")
	check(system._hull_clear(system.boats[id].node.position,system.boats[id].node.rotation.y,id),"stopped hull remains outside terrain")
	check(absf(system.boats[id].node.position.y-2.83) < 0.05,"boat remains buoyant during collision")
	check(system.dismount() and player.mounted_vehicle == null,"safe dismount reaches shore or open water")
	check(world.prepared != Vector3.INF,"dismount prepares target collision")
	# A low bridge stops the seated rider even when the hull alone fits.
	system.boats[id].node.position = Vector3(20.5,2.83,-10.5)
	system.boats[id].node.rotation.y = 0.0
	player.position = Vector3(22.5,3,-10.5)
	check(system.mount(id),"boat remounts away from wall")
	for x in range(18,24): world.set_block(Vector3i(x,4,-14),3)
	system.boats[id].speed = 7.5
	for iteration in range(6): system.step_boat(id,0.25,1.0,0.0)
	check(system.boats[id].node.position.z > -12.8,"rider headroom stops movement under low bridge")
	var serialized: Dictionary = JSON.parse_string(JSON.stringify(system.serialize()))
	serialized.next_boat_id = 1
	system.restore(serialized)
	check(system.mounted_id == id and player.mounted_vehicle == system.boats[id].node,"mounted state restored with validated seat")
	check(system.next_boat_id > int(id),"next boat ID advances beyond restored IDs")
	system.detach_rider()
	var other: String = system.launch_boat(Vector3i(27,2,-5))
	check(not other.is_empty() and other != id and system.boats.size() == 2,"new launch cannot replace saved boat")
	serialized = system.serialize()
	serialized.boats.append(serialized.boats[0].duplicate(true))
	serialized.boats.append({"id":"bad","position":[1,2],"yaw":0})
	serialized.boats.append({"id":"below","position":[1,-999,2],"yaw":0})
	serialized.beds = {"bad":{"foot":[1],"head":"broken"}}
	system.restore(serialized)
	check(system.boats.size() == 2 and system.beds.is_empty(),"malformed and duplicate restored records are ignored")
	world.queue_free()
	await process_frame
	print("REST_TRANSPORT: ",checks," checks, ",failures," failures")
	quit(failures)

func check(condition: bool,message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ",message)
