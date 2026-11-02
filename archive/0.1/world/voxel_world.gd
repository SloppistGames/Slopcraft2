class_name VoxelWorld
extends Node3D

signal chunk_ready(coord: Vector2i)
signal block_changed(position: Vector3i, block_id: int)

const CHUNK_SIZE = 16
const HEIGHT = 80
const SEA_LEVEL = 23
var dimension = "overworld"
var world_seed = 1
var render_distance = 3
var chunks: Dictionary = {}
var dirty_chunks: Dictionary = {}
var chunk_data: Dictionary = {}
var columns: Dictionary = {}
var edits: Dictionary = {}
var edit_map: Dictionary = {}
var pending: Array[Vector2i] = []
var focus_chunk = Vector2i(2147483647, 2147483647)
var terrain_noise = FastNoiseLite.new()
var detail_noise = FastNoiseLite.new()
var biome_noise = FastNoiseLite.new()
var cave_noise = FastNoiseLite.new()
var solid_flags: Dictionary = {}
var transparent_flags: Dictionary = {}
var atmosphere: WorldAtmosphere
var initialized = false
var last_build_ms = 0
var active_mesh: VoxelChunkMesh
var active_coord = Vector2i(2147483647,2147483647)
var prepare_coords: Array[Vector2i] = []
var active_started = 0
const NO_CHUNK = Vector2i(2147483647,2147483647)

func setup(seed_value: int, new_dimension: String, saved_edits: Dictionary = {}) -> void:
	initialized = false
	active_mesh = null
	active_coord = NO_CHUNK
	prepare_coords.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	chunks.clear()
	dirty_chunks.clear()
	chunk_data.clear()
	columns.clear()
	pending.clear()
	edits = saved_edits.duplicate(true)
	edit_map.clear()
	for key in edits:
		var parts = str(key).split(",")
		if parts.size() == 3:
			edit_map[Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))] = int(edits[key])
	world_seed = seed_value
	dimension = new_dimension.to_lower()
	if dimension == "the end":
		dimension = "end"
	terrain_noise.seed = seed_value
	terrain_noise.frequency = 0.012
	terrain_noise.fractal_octaves = 4
	detail_noise.seed = seed_value + 71
	detail_noise.frequency = 0.044
	detail_noise.fractal_octaves = 3
	biome_noise.seed = seed_value + 173
	biome_noise.frequency = 0.007
	cave_noise.seed = seed_value + 373
	cave_noise.frequency = 0.065
	cave_noise.fractal_octaves = 2
	for id in range(160):
		var data = BlockDB.get_block(id)
		solid_flags[id] = data.get("solid", id != 0)
		transparent_flags[id] = data.get("transparent", false)
	# Fluids and gateways never catch the player's collision capsule.
	for id in [0,9,20,28,29,30]:
		solid_flags[id] = false
		transparent_flags[id] = true
	for id in [6,16,32,34,39,42,47,66,69]:
		transparent_flags[id] = true
	BlockAtlas.prepare()
	atmosphere = WorldAtmosphere.new()
	add_child(atmosphere)
	atmosphere.setup(dimension)
	focus_chunk = Vector2i.ZERO
	# A complete collidable spawn area is ready before the player appears.
	for z in range(-1, 2):
		for x in range(-1, 2):
			_build_chunk(Vector2i(x,z))
	initialized = true
	focus_chunk = Vector2i(2147483647,2147483647)
	update_focus(spawn_position())

func _process(_delta: float) -> void:
	if not initialized:
		return
	if active_coord == NO_CHUNK:
		while not pending.is_empty():
			var candidate: Vector2i = pending.pop_front()
			if not chunks.has(candidate) or dirty_chunks.has(candidate):
				active_coord = candidate
				active_started = Time.get_ticks_msec()
				prepare_coords.assign([candidate,candidate+Vector2i.LEFT,candidate+Vector2i.RIGHT,candidate+Vector2i.UP,candidate+Vector2i.DOWN])
				break
		if active_coord == NO_CHUNK:
			return
	# Generate at most one missing terrain buffer per frame, including the apron.
	while not prepare_coords.is_empty():
		var candidate: Vector2i = prepare_coords.pop_front()
		if not chunk_data.has(candidate):
			_get_chunk_data(candidate)
			return
	if active_mesh == null:
		active_mesh = VoxelChunkMesh.new()
		active_mesh.begin(self,active_coord,_get_chunk_data(active_coord))
		return
	if active_mesh.step(3500):
		var chunk = active_mesh.finish()
		if chunks.has(active_coord):
			var old: Node = chunks[active_coord]
			remove_child(old)
			old.queue_free()
		dirty_chunks.erase(active_coord)
		add_child(chunk)
		chunks[active_coord] = chunk
		last_build_ms = Time.get_ticks_msec()-active_started
		chunk_ready.emit(active_coord)
		active_mesh = null
		active_coord = NO_CHUNK

func update_focus(pos: Vector3) -> void:
	var coord = Vector2i(floori(pos.x / CHUNK_SIZE), floori(pos.z / CHUNK_SIZE))
	if atmosphere != null:
		atmosphere.focus = pos
	if coord == focus_chunk:
		return
	focus_chunk = coord
	if active_coord != NO_CHUNK and (absi(active_coord.x-coord.x) > render_distance+1 or absi(active_coord.y-coord.y) > render_distance+1):
		active_mesh = null
		active_coord = NO_CHUNK
		prepare_coords.clear()
	if atmosphere != null:
		atmosphere.focus = pos
	pending.clear()
	for z in range(coord.y-render_distance, coord.y+render_distance+1):
		for x in range(coord.x-render_distance, coord.x+render_distance+1):
			var candidate = Vector2i(x,z)
			if not chunks.has(candidate) or dirty_chunks.has(candidate):
				pending.append(candidate)
	pending.sort_custom(func(a: Vector2i,b: Vector2i): return (a-focus_chunk).length_squared() < (b-focus_chunk).length_squared())
	for key in chunks.keys():
		if absi(key.x-coord.x) > render_distance + 1 or absi(key.y-coord.y) > render_distance + 1:
			chunks[key].queue_free()
			chunks.erase(key)
			dirty_chunks.erase(key)
	# Keep a one-chunk data apron for neighbor visibility, but release old regions.
	for key in chunk_data.keys():
		if absi(key.x-coord.x) > render_distance + 3 or absi(key.y-coord.y) > render_distance + 3:
			chunk_data.erase(key)
	if columns.size() > 70000:
		columns.clear()

func prepare_panorama(center: Vector3, radius: int = 3) -> void:
	# The title screen waits for a complete backdrop instead of showing chunks
	# arriving one at a time; normal gameplay keeps the incremental scheduler.
	active_mesh = null
	active_coord = NO_CHUNK
	prepare_coords.clear()
	radius = clampi(radius,1,6)
	var origin = Vector2i(floori(center.x/CHUNK_SIZE),floori(center.z/CHUNK_SIZE))
	for z in range(origin.y-radius,origin.y+radius+1):
		for x in range(origin.x-radius,origin.x+radius+1):
			var coord = Vector2i(x,z)
			if not chunks.has(coord):
				_build_chunk(coord)
	focus_chunk = NO_CHUNK
	update_focus(center)

func ensure_ready_at(pos: Vector3) -> void:
	# World loading must restore collision around the saved position before the
	# player's physics resumes, even when it is thousands of chunks from spawn.
	active_mesh = null
	active_coord = NO_CHUNK
	prepare_coords.clear()
	var center = Vector2i(floori(pos.x/CHUNK_SIZE),floori(pos.z/CHUNK_SIZE))
	for z in range(center.y-1,center.y+2):
		for x in range(center.x-1,center.x+2):
			var coord = Vector2i(x,z)
			if not chunks.has(coord):
				_build_chunk(coord)
	focus_chunk = NO_CHUNK
	update_focus(pos)

func set_render_distance(value: int) -> void:
	render_distance = clampi(value, 2, 6)
	var previous = focus_chunk
	focus_chunk = Vector2i(2147483647,2147483647)
	update_focus(Vector3(previous.x * 16 + 8, 0, previous.y * 16 + 8))

func is_solid(id: int) -> bool:
	return solid_flags.get(id, id != 0)

func is_transparent(id: int) -> bool:
	return transparent_flags.get(id, false)

func get_block(p: Vector3i) -> int:
	if p.y < 0:
		return 0 if dimension == "end" else 10
	if p.y >= HEIGHT:
		return 0
	if edit_map.has(p):
		return edit_map[p]
	var coord = Vector2i(floori(float(p.x) / 16.0), floori(float(p.z) / 16.0))
	var data = _get_chunk_data(coord)
	var lx = posmod(p.x,16)
	var lz = posmod(p.z,16)
	return data[lx + lz * 16 + p.y * 256]

func set_block(p: Vector3i, id: int) -> void:
	if p.y < 1 or p.y >= HEIGHT:
		return
	id = clampi(id,0,159)
	# A partially generated neighbor could otherwise retain a stale boundary face.
	if active_coord != NO_CHUNK:
		if not pending.has(active_coord):
			pending.push_front(active_coord)
		active_mesh = null
		active_coord = NO_CHUNK
		prepare_coords.clear()
	var key = "%d,%d,%d" % [p.x,p.y,p.z]
	edits[key] = id
	edit_map[p] = id
	var coord = Vector2i(floori(float(p.x)/16),floori(float(p.z)/16))
	var data = _get_chunk_data(coord)
	data[posmod(p.x,16) + posmod(p.z,16)*16 + p.y*256] = id
	chunk_data[coord] = data
	_rebuild_chunk(coord)
	if posmod(p.x,16) == 0:
		_rebuild_chunk(coord + Vector2i.LEFT)
	if posmod(p.x,16) == 15:
		_rebuild_chunk(coord + Vector2i.RIGHT)
	if posmod(p.z,16) == 0:
		_rebuild_chunk(coord + Vector2i(0,-1))
	if posmod(p.z,16) == 15:
		_rebuild_chunk(coord + Vector2i(0,1))
	block_changed.emit(p,id)

func get_edits() -> Dictionary:
	return edits.duplicate(true)

func surface_height(x: int, z: int) -> int:
	return _column(x,z).height

func spawn_position() -> Vector3:
	return Vector3(8.5, surface_height(8,8) + 2.2, 8.5)

func end_pillars() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in range(8):
		var angle = float(i) * TAU / 8.0
		points.append(Vector3(roundi(8+cos(angle)*30)+0.5,48+(i%3)*5,roundi(8+sin(angle)*30)+0.5))
	return points

func _build_chunk(coord: Vector2i) -> void:
	var started = Time.get_ticks_msec()
	var data = _get_chunk_data(coord)
	var chunk = VoxelChunkMesh.build(self,coord,data)
	add_child(chunk)
	chunks[coord] = chunk
	last_build_ms = Time.get_ticks_msec() - started
	chunk_ready.emit(coord)

func _rebuild_chunk(coord: Vector2i) -> void:
	if not chunks.has(coord):
		return
	dirty_chunks[coord] = true
	pending.erase(coord)
	pending.push_front(coord)

func _column(x: int,z: int) -> Dictionary:
	var key = Vector2i(x,z)
	if columns.has(key):
		return columns[key]
	var broad = terrain_noise.get_noise_2d(x,z)
	var detail = detail_noise.get_noise_2d(x,z)
	var biome = biome_noise.get_noise_2d(x,z)
	var height = 0
	var bottom = 0
	var surface = 1
	var distance = Vector2(x-8,z-8).length()
	if dimension == "nether":
		height = clampi(roundi(26 + broad*27 + detail*9),11,61)
		var spires = absf(detail_noise.get_noise_2d(x*0.65,z*0.65))
		if spires > 0.52:
			height = mini(68,height+roundi((spires-0.52)*75))
		surface = 21 if biome > 0.18 else 19
		if distance < 12:
			height = roundi(lerpf(27,height,smoothstep(7,12,distance)))
	elif dimension == "end":
		var island = distance < 65 or (distance > 82 and broad > 0.08)
		if not island:
			height = -1
			bottom = 80
		else:
			var edge = clampf((65.0-distance)/18.0,0.0,1.0) if distance < 65 else clampf(broad*3.0,0.0,1.0)
			height = roundi(30 + detail*6 + broad*5)
			bottom = height - maxi(2,roundi(17*edge + detail*4))
		surface = 23
	else:
		var mountains = maxf(0.0,biome+0.08)*55.0
		height = clampi(roundi(28 + broad*25 + detail*5 + mountains),8,67)
		if distance < 18:
			height = roundi(lerpf(28,height,smoothstep(8,18,distance)))
		if height <= SEA_LEVEL+1 or biome < -0.33:
			surface = 8
		elif height > 49:
			surface = 15
		elif height > 43 and detail > 0.15:
			surface = 3
	var result = {"height":height,"bottom":bottom,"surface":surface,"biome":biome}
	columns[key] = result
	return result

func _get_chunk_data(coord: Vector2i) -> PackedInt32Array:
	if chunk_data.has(coord):
		return chunk_data[coord]
	var data = PackedInt32Array()
	data.resize(16*16*HEIGHT)
	var ox = coord.x*16
	var oz = coord.y*16
	for z in range(16):
		for x in range(16):
			var wx = ox+x
			var wz = oz+z
			var col = _column(wx,wz)
			var height: int = col.height
			var top = mini(HEIGHT-1,maxi(height,18 if dimension == "nether" else (SEA_LEVEL if dimension == "overworld" else -1)))
			for y in range(top+1):
				var id = 0
				if dimension == "end":
					if y >= col.bottom and y <= height:
						id = 23
				elif y == 0:
					id = 10
				elif y <= height:
					if dimension == "nether":
						id = col.surface if y >= height-2 else 19
						if y < height-5 and y > 4 and cave_noise.get_noise_3d(wx,y,wz) > 0.51:
							id = 0
						elif _hash(wx,y,wz) % 97 == 0:
							id = 22 if y > 25 else 13
					else:
						id = col.surface if y == height else (2 if y >= height-3 and col.surface == 1 else (8 if col.surface == 8 and y >= height-3 else 3))
						if y < height-4 and y > 3:
							if cave_noise.get_noise_3d(wx,y,wz) > 0.48:
								id = 0
							else:
								var ore = _hash(wx,y,wz) % 420
								if ore < 11:
									id = 11
								elif ore < 18:
									id = 12
								elif ore < 21 and y < 20:
									id = 13
								elif ore < 23 and y < 12:
									id = 14
				elif dimension == "nether" and y <= 18:
					id = 20
				elif dimension == "overworld" and y <= SEA_LEVEL:
					id = 9
				data[x+z*16+y*256] = id
	if dimension == "overworld":
		_decorate_trees(data,coord)
	elif dimension == "nether":
		_decorate_fungi(data,coord)
	elif dimension == "end":
		for pillar in end_pillars():
			for x in range(int(pillar.x)-2,int(pillar.x)+3):
				for z in range(int(pillar.z)-2,int(pillar.z)+3):
					if Vector2(x-pillar.x+0.5,z-pillar.z+0.5).length() <= 2.5:
						for y in range(25,int(pillar.y)):
							_put(data,coord,Vector3i(x,y,z),18)
	_decorate_gateways(data,coord)
	# Saved changes take precedence over terrain, trees and landmarks.
	for p in edit_map:
		if p.x >= ox and p.x < ox+16 and p.z >= oz and p.z < oz+16 and p.y >= 0 and p.y < HEIGHT:
			data[(p.x-ox)+(p.z-oz)*16+p.y*256] = edit_map[p]
	chunk_data[coord] = data
	return data

func _decorate_trees(data: PackedInt32Array,coord: Vector2i) -> void:
	for gz in range(floori(float(coord.y*16-4)/7),floori(float(coord.y*16+19)/7)+1):
		for gx in range(floori(float(coord.x*16-4)/7),floori(float(coord.x*16+19)/7)+1):
			var hash_value = _hash(gx,111,gz)
			if hash_value % 5 == 0:
				continue
			var x = gx*7 + hash_value%5
			var z = gz*7 + int(hash_value/13)%5
			if Vector2(x-8,z-8).length() < 10 or (z >= 3 and z <= 13 and x > 12 and x < 36):
				continue
			var col = _column(x,z)
			if col.surface not in [1,15] or col.height <= SEA_LEVEL:
				continue
			var height = 4+hash_value%3
			var base: int = col.height+1
			var log_id = 31 if col.surface == 15 else (33 if hash_value%6 == 1 else 5)
			var leaf_id = 32 if log_id == 31 else (34 if log_id == 33 else 6)
			for ly in range(height-2,height+2):
				var radius = 2 if ly < height+1 else 1
				if log_id == 31:
					radius = 2 if ly < height else 1
				for dx in range(-radius,radius+1):
					for dz in range(-radius,radius+1):
						if absi(dx) == radius and absi(dz) == radius and (hash_value+ly)%3 != 0:
							continue
						_put(data,coord,Vector3i(x+dx,base+ly,z+dz),leaf_id,true)
			for ly in range(height):
				_put(data,coord,Vector3i(x,base+ly,z),log_id)

func _decorate_fungi(data: PackedInt32Array,coord: Vector2i) -> void:
	for gz in range(floori(float(coord.y*16-4)/10),floori(float(coord.y*16+19)/10)+1):
		for gx in range(floori(float(coord.x*16-4)/10),floori(float(coord.x*16+19)/10)+1):
			var hash_value = _hash(gx,424,gz)
			if hash_value%3 == 0:
				continue
			var x = gx*10+hash_value%6
			var z = gz*10+int(hash_value/17)%6
			var col = _column(x,z)
			if col.height < 20 or Vector2(x-8,z-8).length() < 10:
				continue
			var height = 5+hash_value%5
			var base: int = col.height+1
			for ly in range(height):
				_put(data,coord,Vector3i(x,base+ly,z),67 if hash_value%2==0 else 64)
			for ly in range(height-1,height+2):
				for dx in range(-3,4):
					for dz in range(-3,4):
						if dx*dx+dz*dz < (12 if ly < height+1 else 7):
							_put(data,coord,Vector3i(x+dx,base+ly,z+dz),69 if hash_value%2==0 else 66,true)
			_put(data,coord,Vector3i(x+1,base+height-2,z),22)

func _decorate_gateways(data: PackedInt32Array,coord: Vector2i) -> void:
	var positions = [Vector3i(18,surface_height(18,8)+1,8),Vector3i(32,surface_height(32,8)+1,8)] if dimension == "overworld" else [Vector3i(18,surface_height(18,8)+1,8)]
	for index in range(positions.size()):
		var p: Vector3i = positions[index]
		var id = 30 if (dimension == "end" or index == 1) else 29
		for dx in range(-1,5):
			for dz in range(-2,3):
				_put(data,coord,p+Vector3i(dx,-1,dz),24 if id == 30 else 4)
		for dx in range(4):
			for dy in range(5):
				_put(data,coord,p+Vector3i(dx,dy,0),18 if dx == 0 or dx == 3 or dy == 0 or dy == 4 else id)
		_put(data,coord,p+Vector3i(-1,0,-1),22)
		_put(data,coord,p+Vector3i(4,0,-1),22)

func _put(data: PackedInt32Array,coord: Vector2i,p: Vector3i,id: int,only_air: bool = false) -> void:
	var lx = p.x-coord.x*16
	var lz = p.z-coord.y*16
	if lx < 0 or lx >= 16 or lz < 0 or lz >= 16 or p.y < 0 or p.y >= HEIGHT:
		return
	var index = lx+lz*16+p.y*256
	if not only_air or data[index] == 0:
		data[index] = id

func _hash(x: int,y: int,z: int) -> int:
	return absi((x*374761393+y*668265263+z*2147483647+world_seed*144269) ^ ((x+z+y)*1274126177))
