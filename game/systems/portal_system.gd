class_name PortalSystem
extends Node3D
## Frame validation, Eye guidance and persistent two-way realm links. The game
## owns realm replacement; pending_travel is its explicit handoff to arrive().

signal travel_requested(dimension: String)

const NO_CELL = Vector3i(2147483647,2147483647,2147483647)
var world
var player
var inventory
var entities
var active_frames: Dictionary = {}
var end_portals: Dictionary = {}
var links: Dictionary = {}
var pending_travel: Dictionary = {}
var last_eye_target = Vector3.INF
var eye_flights: Array = []
var throw_counter: int = 0
var cooldown: float = 3.0
var exposure: float = 0.0
var _changing: bool = false

func setup(world_value, player_value, inventory_value, entities_value) -> void:
	world = world_value
	player = player_value
	inventory = inventory_value
	entities = entities_value
	if player != null:
		player.item_use_handler = Callable(self,"use_item")
		player.portal_handler_active = true
	if world != null and world.has_signal("block_changed"):
		world.block_changed.connect(_block_changed)

func use_item(id: int, target: Dictionary, camera) -> bool:
	if id == 1143:
		if target.is_empty() or int(target.get("id",0)) != 18:
			return false
		if str(world.dimension) == "end":
			_notify("Nether frames cannot open in the End.")
			return true
		var frame: Dictionary = find_nether_frame(Vector3i(target.position))
		if frame.is_empty():
			_notify("Build an obsidian rectangle with a clear interior, at least 2 wide and 3 high.")
		else:
			activate_nether_frame(frame)
			_notify("The Nether portal awakens.")
		return true
	if id != 1021:
		return false
	if not target.is_empty() and int(target.get("id",0)) in [153,154]:
		insert_eye(Vector3i(target.position))
	else:
		throw_eye(camera)
	return true

func find_nether_frame(target: Vector3i) -> Dictionary:
	for offset in [Vector3i.ZERO,Vector3i.UP,Vector3i.DOWN,Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
		var candidate: Vector3i = target + offset
		if int(world.get_block(candidate)) not in [0,29]: continue
		var bottom: Vector3i = candidate
		for step in range(12):
			if int(world.get_block(bottom + Vector3i.DOWN)) == 18: break
			if int(world.get_block(bottom + Vector3i.DOWN)) not in [0,29]: break
			bottom += Vector3i.DOWN
		if int(world.get_block(bottom + Vector3i.DOWN)) != 18: continue
		for axis in [Vector3i.RIGHT,Vector3i.BACK]:
			var left: Vector3i = bottom
			for step in range(10):
				if int(world.get_block(left)) == 18: break
				if int(world.get_block(left)) not in [0,29]: break
				left -= axis
			if int(world.get_block(left)) != 18: continue
			var width: int = 0
			for dx in range(1,11):
				var value: int = world.get_block(left + axis * dx)
				if value == 18:
					width = dx+1
					break
				if value not in [0,29]: break
			var origin: Vector3i = left + Vector3i.DOWN
			var height: int = 0
			for dy in range(1,13):
				var value: int = world.get_block(origin + axis + Vector3i(0,dy,0))
				if value == 18:
					height = dy+1
					break
				if value not in [0,29]: break
			var frame: Dictionary = {"origin":_array(origin),"axis":0 if axis.x == 1 else 1,"width":width,"height":height}
			if valid_nether_frame(frame): return frame
	return {}

func valid_nether_frame(frame: Dictionary) -> bool:
	var width: int = int(frame.get("width",0))
	var height: int = int(frame.get("height",0))
	if width < 4 or width > 10 or height < 5 or height > 13: return false
	var p: Vector3i = _cell(frame.origin)
	var axis = Vector3i.RIGHT if int(frame.axis) == 0 else Vector3i.BACK
	for dy in range(height):
		for dx in range(width):
			if dx in [0,width-1] and dy in [0,height-1]: continue # optional corners
			var value: int = world.get_block(p + axis * dx + Vector3i(0,dy,0))
			if dx in [0,width-1] or dy in [0,height-1]:
				if value != 18: return false
			elif value not in [0,29]: return false
	return true

func activate_nether_frame(frame: Dictionary) -> void:
	if not valid_nether_frame(frame): return
	_changing = true
	for p in _frame_interior(frame): world.set_block(p,29)
	active_frames[_key(_cell(frame.origin))] = frame.duplicate(true)
	_changing = false

func _frame_interior(frame: Dictionary) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var p: Vector3i = _cell(frame.origin)
	var axis = Vector3i.RIGHT if int(frame.axis) == 0 else Vector3i.BACK
	for dy in range(1,int(frame.height)-1):
		for dx in range(1,int(frame.width)-1): result.append(p + axis*dx + Vector3i(0,dy,0))
	return result

func _ring(center: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for n in range(-1,2):
		result.append(center + Vector3i(n,0,-2))
		result.append(center + Vector3i(n,0,2))
		result.append(center + Vector3i(-2,0,n))
		result.append(center + Vector3i(2,0,n))
	return result

func find_end_center(frame: Vector3i) -> Vector3i:
	for offset in _ring(Vector3i.ZERO):
		var center: Vector3i = frame - offset
		var complete: bool = true
		for p in _ring(center):
			if int(world.get_block(p)) not in [153,154]:
				complete = false
				break
		if complete: return center
	return NO_CELL

func insert_eye(p: Vector3i) -> bool:
	if int(world.get_block(p)) == 154:
		_notify("This frame already contains an Eye.")
		return false
	var center: Vector3i = find_end_center(p)
	if center == NO_CELL or int(world.get_block(p)) != 153:
		_notify("An End portal needs all twelve frames in a complete ring.")
		return false
	if not inventory.consume(1021,1): return false
	world.set_block(p,154)
	var filled: int = 0
	for cell in _ring(center):
		if int(world.get_block(cell)) == 154: filled += 1
	if filled == 12:
		_changing = true
		for z in range(-1,2):
			for x in range(-1,2): world.set_block(center + Vector3i(x,0,z),30)
		end_portals[_key(center)] = _array(center)
		_changing = false
		_notify("All twelve Eyes align. The End portal opens.")
	else:
		_notify("Eye inserted: %d / 12." % filled)
	return true

func throw_eye(camera) -> bool:
	if str(world.dimension) != "overworld" or world.structure_provider == null:
		_notify("Eyes seek strongholds in the Overworld.")
		return false
	var origin: Vector3 = camera.global_position if camera != null else player.global_position + Vector3.UP * 1.6
	var target: Vector3 = world.structure_provider.locate("stronghold",origin)
	if target == Vector3.INF or not inventory.consume(1021,1): return false
	last_eye_target = target
	throw_counter += 1
	var direction: Vector3 = target-origin
	if Vector2(direction.x,direction.z).length() > 18.0: direction.y = 0.0
	var destination: Vector3 = origin + direction.normalized() * minf(14.0,direction.length()) + Vector3.UP * (4.0 if direction.y == 0.0 else 0.0)
	var eye = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.24
	sphere.radial_segments = 12
	sphere.rings = 6
	eye.mesh = sphere
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("63dfae")
	material.emission_enabled = true
	material.emission = Color("1fa782")
	material.emission_energy_multiplier = 1.2
	eye.material_override = material
	add_child(eye)
	eye.global_position = origin
	eye_flights.append({"node":eye,"age":0.0,"from":origin,"to":destination,"returns":throw_counter%5 != 0})
	_notify("The Eye drifts toward the stronghold." if direction.y == 0.0 else "The Eye dives toward a stronghold below.")
	return true

func _process(delta: float) -> void:
	for flight in eye_flights.duplicate():
		flight.age = float(flight.age) + delta
		var age: float = flight.age
		if is_instance_valid(flight.node):
			flight.node.global_position = Vector3(flight.from).lerp(Vector3(flight.to),smoothstep(0.0,1.7,age)) + Vector3.UP*sin(age*7.0)*0.12
		if age >= 2.6:
			if bool(flight.returns): inventory.add_item(1021,1)
			if is_instance_valid(flight.node): flight.node.queue_free()
			eye_flights.erase(flight)
	cooldown = maxf(0.0,cooldown-delta)
	if player == null or not bool(player.active) or cooldown > 0.0: return
	var p = Vector3i(floori(player.global_position.x),floori(player.global_position.y+0.15),floori(player.global_position.z))
	var id: int = world.get_block(p)
	if id not in [29,30]:
		p += Vector3i.UP
		id = world.get_block(p)
	if id in [29,30]:
		exposure += delta
		if exposure >= 0.65: request_travel(p,id)
	else:
		exposure = 0.0

func request_travel(p: Vector3i, id: int) -> void:
	if id not in [29,30] or cooldown > 0.0: return
	var from: String = world.dimension
	var to: String = ("overworld" if from == "nether" else "nether") if id == 29 else ("overworld" if from == "end" else "end")
	var anchor: Vector3i = _anchor(p,id)
	var link: Dictionary = links.get(_key(anchor),{})
	pending_travel = {"from":from,"to":to,"kind":"nether" if id == 29 else "end","source":_array(anchor),"source_safe":_array(player.global_position),"origin_key":from+":"+_key(anchor)}
	if not link.is_empty() and str(link.get("source_dimension","")) == to:
		pending_travel["destination"] = link.source
		pending_travel["destination_safe"] = link.get("source_safe",[])
	cooldown = 12.0
	exposure = 0.0
	travel_requested.emit(to)

func _anchor(p: Vector3i, id: int) -> Vector3i:
	if id == 29:
		for frame in active_frames.values():
			var cells: Array[Vector3i] = _frame_interior(frame)
			if cells.has(p): return cells[0]
	else:
		for value in end_portals.values():
			var center: Vector3i = _cell(value)
			if p.y == center.y and absi(p.x-center.x) <= 1 and absi(p.z-center.z) <= 1: return center
	return p

func arrive(context: Dictionary) -> void:
	if context.is_empty() or str(context.get("to","")) != str(world.dimension): return
	var id: int = 29 if str(context.get("kind","nether")) == "nether" else 30
	var anchor: Vector3i = NO_CELL
	for value in links.values():
		if str(value.get("origin_key","")) == str(context.origin_key):
			var candidate: Vector3i = _cell(value.anchor)
			if int(world.get_block(candidate)) == id:
				anchor = candidate
				break
	if anchor == NO_CELL and context.has("destination"):
		var candidate: Vector3i = _cell(context.destination)
		if int(world.get_block(candidate)) == id: anchor = candidate
	if anchor == NO_CELL:
		var source: Vector3 = Vector3(_cell(context.source))
		var desired: Vector3 = world.spawn_position()
		if id == 29:
			desired = Vector3(source.x/(8.0 if str(world.dimension) == "nether" else 0.125),0,source.z/(8.0 if str(world.dimension) == "nether" else 0.125))
		if context.has("destination"): desired = Vector3(_cell(context.destination))
		var floor_cell: Vector3i = _landing(desired)
		anchor = _build_arrival(floor_cell,id)
	links[_key(anchor)] = {"anchor":_array(anchor),"origin_key":str(context.origin_key),"source":context.source,"source_safe":context.get("source_safe",[]),"source_dimension":context.from}
	var exit: Vector3 = _safe_exit(anchor)
	world.ensure_ready_at(exit)
	player.global_position = exit
	player.velocity = Vector3.ZERO
	cooldown = 4.0
	exposure = 0.0
	pending_travel.clear()

func _landing(desired: Vector3) -> Vector3i:
	for radius in [0,4,8,12,20,28]:
		for offset in [Vector2i(radius,0),Vector2i(-radius,0),Vector2i(0,radius),Vector2i(0,-radius)]:
			var x: int = floori(desired.x)+offset.x
			var z: int = floori(desired.z)+offset.y
			var y: int = world.surface_height(x,z)
			if y < 2 or y > int(world.max_y())-8 or not bool(world.is_solid(world.get_block(Vector3i(x,y,z)))): continue
			var clear: bool = true
			for dx in range(-3,6):
				for dz in range(-3,5):
					var ground: int = world.surface_height(x+dx,z+dz)
					if absi(ground-y) > 2: clear = false
					for dy in range(1,7):
						if int(world.get_block(Vector3i(x+dx,y+dy,z+dz))) not in [0,165,166,15]: clear = false
			if clear: return Vector3i(x,y,z)
	# Dense forests or rebuilt spawn areas can have no ground clearing. Search
	# upward for an empty landing volume, preserving existing player buildings.
	var spawn: Vector3 = world.spawn_position()
	var x: int = floori(spawn.x)+12
	var z: int = floori(spawn.z)
	var floor_y: int = clampi(world.surface_height(x,z)+7,3,int(world.max_y())-8)
	for y in range(floor_y,int(world.max_y())-7):
		var clear: bool = true
		for dx in range(-3,6):
			for dz in range(-3,5):
				for dy in range(7):
					if int(world.get_block(Vector3i(x+dx,y+dy,z+dz))) not in [0,165,166]: clear = false
		if clear: return Vector3i(x,y,z)
	return Vector3i(x,int(world.max_y())-8,z)

func _build_arrival(p: Vector3i, id: int) -> Vector3i:
	_changing = true
	for z in range(-3,5):
		for x in range(-3,6):
			world.set_block(p+Vector3i(x,0,z),18)
			for y in range(1,7): world.set_block(p+Vector3i(x,y,z),0)
	var anchor: Vector3i
	if id == 29:
		var frame: Dictionary = {"origin":_array(p),"axis":0,"width":4,"height":5}
		for y in range(5):
			for x in range(4):
				if x in [0,3] or y in [0,4]: world.set_block(p+Vector3i(x,y,0),18)
		_changing = false
		activate_nether_frame(frame)
		anchor = p+Vector3i(1,1,0)
	else:
		anchor = p+Vector3i(0,1,0)
		for z in range(-1,2):
			for x in range(-1,2): world.set_block(anchor+Vector3i(x,0,z),30)
		end_portals[_key(anchor)] = _array(anchor)
	_changing = false
	return anchor

func _safe_exit(anchor: Vector3i) -> Vector3:
	for distance in [2,3,4,1]:
		for offset in [Vector3i(0,0,distance),Vector3i(0,0,-distance),Vector3i(distance,0,0),Vector3i(-distance,0,0)]:
			for dy in [0,1,-1,2]:
				var p: Vector3i = anchor+offset+Vector3i(0,dy,0)
				if bool(world.is_solid(world.get_block(p+Vector3i.DOWN))) and int(world.get_block(p)) in [0,165,166] and int(world.get_block(p+Vector3i.UP)) in [0,165,166]: return Vector3(p)+Vector3(0.5,0.15,0.5)
	# A user may have obstructed every exit since last visiting. Make a tiny
	# landing beside the saved gate, retaining the gate itself and its link.
	var p: Vector3i = anchor+Vector3i(0,0,3)
	world.set_block(p+Vector3i.DOWN,18)
	world.set_block(p,0)
	world.set_block(p+Vector3i.UP,0)
	return Vector3(p)+Vector3(0.5,0.15,0.5)

func _block_changed(_p: Vector3i, _id: int) -> void:
	if _changing: return
	_changing = true
	for key in active_frames.keys():
		var frame: Dictionary = active_frames[key]
		if not valid_nether_frame(frame):
			for p in _frame_interior(frame):
				if int(world.get_block(p)) == 29: world.set_block(p,0)
			active_frames.erase(key)
	for key in end_portals.keys():
		var center: Vector3i = _cell(end_portals[key])
		# End arrival is a return platform created only after legitimate travel.
		if str(world.dimension) == "end": continue
		var complete: bool = true
		for p in _ring(center):
			if int(world.get_block(p)) != 154: complete = false
		if not complete:
			for z in range(-1,2):
				for x in range(-1,2):
					var p: Vector3i = center+Vector3i(x,0,z)
					if int(world.get_block(p)) == 30: world.set_block(p,0)
			end_portals.erase(key)
	_changing = false

func serialize() -> Dictionary:
	return {"active_frames":active_frames.duplicate(true),"end_portals":end_portals.duplicate(true),"links":links.duplicate(true),"throw_counter":throw_counter}

func restore(data: Dictionary) -> void:
	active_frames = data.get("active_frames",{}).duplicate(true)
	end_portals = data.get("end_portals",{}).duplicate(true)
	links = data.get("links",{}).duplicate(true)
	throw_counter = int(data.get("throw_counter",0))
	cooldown = 3.0
	pending_travel.clear()
	_block_changed(Vector3i.ZERO,0)

func _notify(message: String) -> void:
	if player != null and player.has_signal("notify"): player.notify.emit(message)

func _key(p: Vector3i) -> String:
	return "%d,%d,%d" % [p.x,p.y,p.z]

func _array(p) -> Array:
	return [p.x,p.y,p.z]

func _cell(value) -> Vector3i:
	if value is Vector3i: return value
	if value is Vector3: return Vector3i(value)
	if value is Array and value.size() >= 3: return Vector3i(int(value[0]),int(value[1]),int(value[2]))
	return Vector3i.ZERO
