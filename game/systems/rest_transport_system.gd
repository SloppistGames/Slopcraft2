class_name RestTransportSystem
extends Node3D
## Two-cell beds and persistent, buoyant boats. Boat movement uses voxel hull
## probes so it also works while the renderer is streaming a neighboring chunk.

const BED_FOOT = 181
const BED_HEAD = 182
const BOAT_ITEM = 1402
const DIRECTIONS = [Vector3i(0,0,-1),Vector3i.RIGHT,Vector3i.BACK,Vector3i.LEFT]
var world
var player
var inventory
var entities
var beds: Dictionary = {}
var boats: Dictionary = {}
var next_boat_id: int = 1
var mounted_id: String = ""
var previous_item_handler: Callable
var _changing: bool = false
var _clock: float = 0.0
var _refund_clock: float = 0.0
var pending_bed_refunds: int = 0
var _wood: StandardMaterial3D
var _dark_wood: StandardMaterial3D

func setup(world_value,player_value,inventory_value,entities_value) -> void:
	world = world_value
	player = player_value
	inventory = inventory_value
	entities = entities_value
	world.set_meta("rest_transport_system",self)
	previous_item_handler = player.item_use_handler
	player.item_use_handler = Callable(self,"use_item")
	world.block_changed.connect(_block_changed)
	_wood = StandardMaterial3D.new()
	_wood.albedo_texture = ImageTexture.create_from_image(BlockAtlas.face_image(7,0))
	_wood.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_wood.roughness = 0.9
	_dark_wood = _wood.duplicate()
	_dark_wood.albedo_color = Color("9c7955")

func use_item(id: int,target: Dictionary,camera) -> bool:
	if not target.is_empty() and int(target.get("id",0)) in [BED_FOOT,BED_HEAD] and not Input.is_action_pressed("crouch"):
		interact_at(Vector3i(target.position))
		return true
	if camera != null and interact(camera.global_position,-camera.global_basis.z,4.5):
		return true
	if id in [BED_FOOT,BED_HEAD]:
		if not target.is_empty():
			var p: Vector3i = Vector3i(target.position)+Vector3i(target.get("normal",Vector3i.UP))
			place_bed(p,_rotation_from_yaw(float(player.rotation.y)),id)
		return true
	if id == BOAT_ITEM:
		if camera != null:
			var start: Vector3 = camera.global_position
			var direction: Vector3 = -camera.global_basis.z
			for step in range(1,25):
				var at: Vector3 = start+direction*float(step)*0.25
				var cell = Vector3i(at.floor())
				var block: int = world.get_block(cell)
				if block == 9:
					launch_boat(cell,float(player.rotation.y))
					return true
				if bool(world.is_solid(block)): break
		_notify("Aim at open water to launch the boat.")
		return true
	return previous_item_handler.is_valid() and bool(previous_item_handler.call(id,target,camera))

func _rotation_from_yaw(yaw: float) -> int:
	return posmod(roundi(-yaw/(PI*0.5)),4)

func place_bed(foot: Vector3i,rotation: int,item_id: int = BED_FOOT) -> bool:
	rotation = posmod(rotation,4)
	var head: Vector3i = foot+DIRECTIONS[rotation]
	for p in [foot,head]:
		if int(world.get_block(p)) not in [0,165,166] or not _supports_bed(p+Vector3i.DOWN):
			_notify("A bed needs two clear spaces on solid ground.")
			return false
		for dy in [1,2]:
			if bool(world.is_solid(world.get_block(p+Vector3i(0,dy,0)))):
				_notify("Leave headroom above both halves of the bed.")
				return false
	if not inventory.consume(item_id,1): return false
	_changing = true
	world.set_block(foot,BED_FOOT)
	world.set_block(head,BED_HEAD)
	world.set_block_state(foot,{"rotation":rotation,"bed_other":_array(head),"bed_part":"foot"})
	world.set_block_state(head,{"rotation":rotation,"bed_other":_array(foot),"bed_part":"head"})
	beds[_key(foot)] = {"foot":_array(foot),"head":_array(head),"rotation":rotation}
	_changing = false
	return true

func interact_at(p: Vector3i) -> bool:
	if int(world.get_block(p)) not in [BED_FOOT,BED_HEAD]: return false
	var foot: Vector3i = p
	if int(world.get_block(p)) == BED_HEAD:
		var state: Dictionary = world.get_block_state(p)
		if not _valid_cell_array(state.get("bed_other",null)): return false
		foot = _cell(state.bed_other)
	if str(world.dimension) != "overworld":
		_notify("You cannot sleep in this realm.")
		return true
	if not _valid_bed(foot):
		_notify("The bed is incomplete or obstructed.")
		return true
	var exit: Vector3 = _bed_exit(foot)
	if exit == Vector3.INF:
		_notify("Leave a safe space beside your bed.")
		return true
	player.bed_spawn = _array(foot)
	player.bed_dimension = str(world.dimension)
	var night: bool = false
	var atmosphere = world.get("atmosphere")
	if is_instance_valid(atmosphere):
		var time: float = float(atmosphere.get("time_of_day"))
		night = time >= 0.50 or time < 0.04
	if night:
		for child in world.get_children():
			if child.has_method("set_time"):
				child.set_time(0.08)
				break
		if is_instance_valid(atmosphere):
			atmosphere.set("time_of_day",0.08)
			if atmosphere.has_method("_update_lighting"): atmosphere.call("_update_lighting")
		player.global_position = exit
		player.velocity = Vector3.ZERO
		_notify("You sleep until morning. Respawn point set.")
	else:
		_notify("Respawn point set. You can sleep when night falls.")
	return true

func _valid_bed(foot: Vector3i) -> bool:
	if int(world.get_block(foot)) != BED_FOOT: return false
	var state: Dictionary = world.get_block_state(foot)
	if not _valid_cell_array(state.get("bed_other",null)): return false
	var head: Vector3i = _cell(state.bed_other)
	if int(world.get_block(head)) != BED_HEAD or head.y != foot.y or (head-foot).length_squared() != 1: return false
	var reverse: Dictionary = world.get_block_state(head)
	if not _valid_cell_array(reverse.get("bed_other",null)) or _cell(reverse.bed_other) != foot: return false
	for p in [foot,head]:
		if not _supports_bed(p+Vector3i.DOWN): return false
		for dy in [1,2]:
			if bool(world.is_solid(world.get_block(p+Vector3i(0,dy,0)))): return false
	return true

func _supports_bed(p: Vector3i) -> bool:
	var id: int = world.get_block(p)
	if id in [20,145,BED_FOOT,BED_HEAD] or not bool(world.is_solid(id)): return false
	if not BlockShapes.is_partial(id): return true
	var boxes: Array[AABB] = BlockShapes.boxes(id,world.get_block_state(p))
	for x in [0.125,0.875]:
		for z in [0.125,0.875]:
			var supported: bool = false
			for box in boxes:
				if box.end.y >= 0.999 and box.has_point(Vector3(x,0.999,z)): supported = true
			if not supported: return false
	return true

func _bed_exit(foot: Vector3i) -> Vector3:
	for radius in [1,2]:
		for offset in [Vector3i(radius,0,0),Vector3i(-radius,0,0),Vector3i(0,0,radius),Vector3i(0,0,-radius)]:
			for dy in [0,1,-1]:
				var p: Vector3i = foot+offset+Vector3i(0,dy,0)
				if _safe_standing(p): return Vector3(p)+Vector3(0.5,0.05,0.5)
	return Vector3.INF

func respawn_position() -> Vector3:
	if player.bed_spawn.size() == 3 and str(player.bed_dimension) == str(world.dimension):
		var foot: Vector3i = _cell(player.bed_spawn)
		if _valid_bed(foot):
			var exit: Vector3 = _bed_exit(foot)
			if exit != Vector3.INF: return exit
		_notify("Your bed is missing or blocked. Returning to world spawn.")
	return world.spawn_position()

func _block_changed(p: Vector3i,id: int) -> void:
	if _changing: return
	for key in beds.keys():
		var record: Dictionary = beds[key]
		var foot: Vector3i = _cell(record.foot)
		var head: Vector3i = _cell(record.head)
		if p in [foot+Vector3i.DOWN,head+Vector3i.DOWN] and not _supports_bed(p):
			_changing = true
			for half in [foot,head]:
				if int(world.get_block(half)) in [BED_FOOT,BED_HEAD]: world.set_block(half,0)
			beds.erase(key)
			_changing = false
			if not bool(inventory.creative) and not inventory.add_item(BED_FOOT,1): pending_bed_refunds += 1
			return
		if (p == foot and id != BED_FOOT) or (p == head and id != BED_HEAD):
			_changing = true
			var other: Vector3i = head if p == foot else foot
			if int(world.get_block(other)) in [BED_FOOT,BED_HEAD]: world.set_block(other,0)
			beds.erase(key)
			_changing = false
			return

func launch_boat(water: Vector3i,yaw: float = 0.0) -> String:
	if int(world.get_block(water)) != 9: return ""
	var top: int = water.y+1
	while int(world.get_block(Vector3i(water.x,top,water.z))) == 9 and top < int(world.max_y())-3: top += 1
	var at = Vector3(water.x+0.5,top-0.17,water.z+0.5)
	if not _hull_clear(at,yaw):
		_notify("The boat needs a little more open water.")
		return ""
	if not inventory.consume(BOAT_ITEM,1): return ""
	while boats.has(str(next_boat_id)): next_boat_id += 1
	var id: String = str(next_boat_id)
	next_boat_id += 1
	_add_boat(id,at,yaw)
	_notify("Boat launched. Right-click it to board; crouch to dismount.")
	return id

func _add_boat(id: String,at: Vector3,yaw: float) -> void:
	var node = Node3D.new()
	node.name = "Boat_"+id
	add_child(node)
	node.global_position = at
	node.rotation.y = yaw
	_piece(node,Vector3(1.25,0.16,2.0),Vector3(0,0.08,0),_dark_wood)
	_piece(node,Vector3(0.14,0.42,2.1),Vector3(-0.69,0.28,0),_wood)
	_piece(node,Vector3(0.14,0.42,2.1),Vector3(0.69,0.28,0),_wood)
	_piece(node,Vector3(1.25,0.38,0.15),Vector3(0,0.29,-1.03),_wood)
	_piece(node,Vector3(1.25,0.38,0.15),Vector3(0,0.29,1.03),_wood)
	for z in [-0.56,0.52]: _piece(node,Vector3(1.25,0.12,0.30),Vector3(0,0.30,z),_wood)
	var oars: Array = []
	for side in [-1,1]:
		var oar = Node3D.new()
		oar.position = Vector3(side*0.72,0.35,0.15)
		node.add_child(oar)
		_piece(oar,Vector3(0.09,0.09,1.1),Vector3(side*0.22,0,0.2),_dark_wood)
		_piece(oar,Vector3(0.22,0.07,0.42),Vector3(side*0.22,0,0.9),_wood)
		oar.rotation.z = side*0.32
		oars.append(oar)
	boats[id] = {"node":node,"speed":0.0,"vertical":0.0,"oars":oars}

func _piece(parent: Node3D,size: Vector3,center: Vector3,material: Material) -> void:
	var piece = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	piece.mesh = mesh
	piece.position = center
	piece.material_override = material
	parent.add_child(piece)

func interact(origin: Vector3,direction: Vector3,reach: float = 4.5) -> bool:
	if not mounted_id.is_empty(): return false
	var found: String = ""
	var nearest: float = reach
	for id in boats:
		var at: Vector3 = boats[id].node.global_position+Vector3.UP*0.25
		var along: float = (at-origin).dot(direction)
		if along < 0.0 or along > nearest: continue
		if (origin+direction*along).distance_to(at) < 1.05:
			var blocked: bool = false
			for step in range(1,ceili(along*4.0)):
				if bool(world.is_solid(world.get_block(Vector3i((origin+direction*step*0.25).floor())))): blocked = true
			if not blocked:
				found = str(id)
				nearest = along
	if found.is_empty(): return false
	if Input.is_action_pressed("crouch"):
		if inventory.add_item(BOAT_ITEM,1):
			boats[found].node.queue_free()
			boats.erase(found)
			_notify("Boat collected.")
		return true
	return mount(found)

func mount(id: String,restoring: bool = false) -> bool:
	if not boats.has(id) or not mounted_id.is_empty(): return false
	var at: Vector3 = boats[id].node.global_position
	if not _rider_clear(at) or not _hull_clear(at,boats[id].node.rotation.y,id):
		_notify("There is not enough room to board this boat.")
		return false
	if not restoring and player.global_position.distance_to(at) > 5.5: return false
	mounted_id = id
	player.mounted_vehicle = boats[id].node
	player.flying = false
	player.velocity = Vector3.ZERO
	player.global_position = boats[id].node.global_position+Vector3.UP*0.35
	_notify("W/S rows, A/D steers. Crouch to dismount.")
	return true

func detach_rider() -> void:
	mounted_id = ""
	player.mounted_vehicle = null

func dismount() -> bool:
	if mounted_id.is_empty() or not boats.has(mounted_id):
		detach_rider()
		return true
	var at: Vector3 = boats[mounted_id].node.global_position
	for water_allowed in [false,true]:
		for distance in [2,3,4]:
			for offset in [Vector3i(distance,0,0),Vector3i(-distance,0,0),Vector3i(0,0,distance),Vector3i(0,0,-distance)]:
				for dy in [0,1,-1,2]:
					var p = Vector3i(at.floor())+offset+Vector3i(0,dy,0)
					var destination: Vector3 = Vector3(p)+Vector3(0.5,0.1,0.5)
					if (_safe_standing(p) or (water_allowed and int(world.get_block(p)) == 9 and int(world.get_block(p+Vector3i.UP)) == 0)) and _rider_path_clear(at,destination-Vector3.UP*0.35):
						world.ensure_ready_at(Vector3(p))
						player.global_position = Vector3(p)+Vector3(0.5,0.1,0.5)
						player.velocity = Vector3.ZERO
						detach_rider()
						return true
	_notify("There is no safe space to dismount here.")
	return false

func _safe_standing(p: Vector3i) -> bool:
	var below: int = world.get_block(p+Vector3i.DOWN)
	return below not in [20,145,181,182] and bool(world.is_solid(below)) and int(world.get_block(p)) in [0,165,166] and int(world.get_block(p+Vector3i.UP)) in [0,165,166]

func _physics_process(delta: float) -> void:
	_clock += delta
	_refund_clock += delta
	if pending_bed_refunds > 0 and _refund_clock >= 1.0:
		_refund_clock = 0.0
		if inventory.add_item(BED_FOOT,1): pending_bed_refunds -= 1
	if not mounted_id.is_empty() and bool(player.active) and Input.is_action_just_pressed("crouch"): dismount()
	for id in boats:
		var controlled: bool = str(id) == mounted_id and bool(player.active)
		var throttle: float = Input.get_axis("move_back","move_forward") if controlled else 0.0
		var steer: float = Input.get_axis("move_left","move_right") if controlled else 0.0
		step_boat(str(id),delta,throttle,steer)

func step_boat(id: String,delta: float,throttle: float,steer: float) -> void:
	if not boats.has(id): return
	# A stalled frame slows the simulation rather than tunnelling through a
	# shoreline. Each accepted move sweeps both hull and seated rider.
	delta = clampf(delta,0.0,0.25)
	throttle = clampf(throttle,-1.0,1.0)
	steer = clampf(steer,-1.0,1.0)
	var boat: Dictionary = boats[id]
	var node: Node3D = boat.node
	var surface: float = _water_surface(node.global_position)
	var afloat: bool = is_finite(surface)
	var target_y: float = node.global_position.y
	boat.speed = move_toward(float(boat.speed),throttle*(7.5 if afloat else 0.7),delta*(2.6 if afloat else 5.0))
	if afloat:
		var yaw: float = node.rotation.y-steer*delta*1.65*clampf(absf(float(boat.speed))*0.3+0.25,0.25,1.0)
		if _hull_clear(node.global_position,yaw,id): node.rotation.y = yaw
		boat.vertical = 0.0
		target_y = lerpf(node.global_position.y,surface-0.17,minf(delta*8.0,1.0))
	else:
		boat.vertical = maxf(float(boat.vertical)-12.0*delta,-12.0)
	var velocity: Vector3 = -node.global_basis.z*float(boat.speed)
	var next: Vector3 = node.global_position+velocity*delta+Vector3.UP*float(boat.vertical)*delta
	if afloat: next.y = target_y
	var start: Vector3 = node.global_position
	var steps: int = maxi(1,ceili(start.distance_to(next)/0.2))
	for index in range(1,steps+1):
		var position: Vector3 = start.lerp(next,float(index)/steps)
		if not _hull_clear(position,node.rotation.y,id) or (id == mounted_id and not _rider_clear(position)):
			boat.speed = 0.0
			boat.vertical = 0.0
			break
		node.global_position = position
	for i in boat.oars.size():
		boat.oars[i].rotation.x = sin(_clock*5.0)*0.55*clampf(absf(float(boat.speed))/4.0,0.0,1.0)
	if id == mounted_id:
		player.global_position = node.global_position+Vector3.UP*0.35
		player.velocity = Vector3.ZERO

func _water_surface(at: Vector3) -> float:
	var base = Vector3i(at.floor())
	for y in range(base.y+2,base.y-4,-1):
		if int(world.get_block(Vector3i(base.x,y,base.z))) == 9:
			return float(y+1)
	return INF

func _hull_clear(at: Vector3,yaw: float,exclude_id: String = "") -> bool:
	for id in boats:
		if str(id) == exclude_id: continue
		var other: Vector3 = boats[id].node.global_position
		if absf(other.y-at.y) < 0.6 and Vector2(other.x-at.x,other.z-at.z).length() < 2.15: return false
	var basis = Basis(Vector3.UP,yaw)
	for z in [-0.95,0.0,0.95]:
		for x in [-0.65,0.0,0.65]:
			for y in [0.03,0.49]:
				var p = Vector3i((at+basis*Vector3(x,y,z)).floor())
				var id: int = world.get_block(p)
				if bool(world.is_solid(id)) or id == 20: return false
	return true

func _rider_clear(at: Vector3) -> bool:
	for x in [-0.3,0.3]:
		for z in [-0.3,0.3]:
			for y in [0.4,1.15,2.1]:
				var id: int = world.get_block(Vector3i((at+Vector3(x,y,z)).floor()))
				if bool(world.is_solid(id)) or id == 20: return false
	return true

func _rider_path_clear(start: Vector3,finish: Vector3) -> bool:
	var steps: int = maxi(1,ceili(start.distance_to(finish)/0.25))
	for index in range(1,steps+1):
		if not _rider_clear(start.lerp(finish,float(index)/steps)): return false
	return true

func serialize() -> Dictionary:
	var saved_boats: Array = []
	for id in boats:
		var node: Node3D = boats[id].node
		saved_boats.append({"id":str(id),"position":_array(node.global_position),"yaw":node.rotation.y})
	return {"beds":beds.duplicate(true),"boats":saved_boats,"next_boat_id":next_boat_id,"mounted_id":mounted_id,"pending_bed_refunds":pending_bed_refunds}

func restore(data: Dictionary) -> void:
	beds.clear()
	var saved_beds = data.get("beds",{})
	if saved_beds is Dictionary:
		for record in saved_beds.values():
			if not record is Dictionary or not _valid_cell_array(record.get("foot",null)) or not _valid_cell_array(record.get("head",null)): continue
			var foot: Vector3i = _cell(record.foot)
			var head: Vector3i = _cell(record.head)
			if head.y != foot.y or (head-foot).length_squared() != 1: continue
			if int(world.get_block(foot)) == BED_FOOT and int(world.get_block(head)) == BED_HEAD: beds[_key(foot)] = record.duplicate(true)
	for boat in boats.values(): boat.node.queue_free()
	boats.clear()
	detach_rider()
	next_boat_id = maxi(1,int(data.get("next_boat_id",1)))
	pending_bed_refunds = clampi(int(data.get("pending_bed_refunds",0)),0,999)
	var saved_boats = data.get("boats",[])
	if not saved_boats is Array: saved_boats = []
	for saved in saved_boats:
		if not saved is Dictionary or not _valid_cell_array(saved.get("position",null)): continue
		var at = Vector3(float(saved.position[0]),float(saved.position[1]),float(saved.position[2]))
		var yaw: float = float(saved.get("yaw",0.0))
		var id: String = str(saved.get("id",next_boat_id))
		if not at.is_finite() or not is_finite(yaw) or at.y < int(world.min_y())-8 or at.y >= int(world.max_y()) or boats.has(id) or boats.size() >= 128: continue
		_add_boat(id,at,yaw)
		if id.is_valid_int(): next_boat_id = maxi(next_boat_id,int(id)+1)
	var rider: String = str(data.get("mounted_id",""))
	if boats.has(rider): mount(rider,true)

func _valid_cell_array(value) -> bool:
	if not value is Array or value.size() != 3: return false
	for component in value:
		if not (component is int or component is float) or not is_finite(float(component)): return false
	return true

func _key(p: Vector3i) -> String: return "%d,%d,%d" % [p.x,p.y,p.z]
func _array(p) -> Array: return [p.x,p.y,p.z]
func _cell(value: Array) -> Vector3i: return Vector3i(int(value[0]),int(value[1]),int(value[2]))
func _notify(message: String) -> void:
	if player.has_signal("notify"): player.notify.emit(message)
