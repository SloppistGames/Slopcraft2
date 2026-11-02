class_name VoxelWorld
extends Node3D

signal chunk_ready(coord: Vector2i)
signal block_changed(position: Vector3i, block_id: int)
signal block_state_changed(position: Vector3i, state: Dictionary)

const CHUNK_SIZE = 16
const MIN_Y = -176
const MAX_Y = 192
const HEIGHT = MAX_Y - MIN_Y
const SEA_LEVEL = 23
const NEAR_RADIUS = 3
const NO_CHUNK = Vector2i(2147483647,2147483647)
const FRAME_BUDGET_USEC = 3500

var dimension = "overworld"
var world_seed = 1
var generator_version = 2
var render_distance = 3
var block_distance = 3
var chunks: Dictionary = {}
var dirty_chunks: Dictionary = {}
# Fixed-size typed buffers avoid a Dictionary per voxel. Only the nearby vertical
# window is generated, and only 7x7 detailed chunks are retained at any distance.
var chunk_data: Dictionary = {}
var generated_layers: Dictionary = {}
var chunk_ranges: Dictionary = {}
var decorations: Dictionary = {}
var columns: Dictionary = {}
var edits: Dictionary = {}
var edit_map: Dictionary = {}
var built_tops: Dictionary = {}
var block_states: Dictionary = {}:
	set(value):
		block_states = value.duplicate(true)
		# Assigning restored orientation/fluid/power states invalidates existing
		# spawn meshes before ensure_ready_at enables gameplay.
		for coord in chunks:
			_rebuild_chunk(coord)
		if active_coord != NO_CHUNK:
			if not pending.has(active_coord): pending.push_front(active_coord)
			_cancel_job()
var pending: Array[Vector2i] = []
var focus_chunk = NO_CHUNK
var focus_position = Vector3(8,30,8)
var focus_section = 0
var terrain_noise = FastNoiseLite.new()
var detail_noise = FastNoiseLite.new()
var biome_noise = FastNoiseLite.new()
var cave_noise = FastNoiseLite.new()
var solid_flags: Dictionary = {}
var transparent_flags: Dictionary = {}
var atmosphere: WorldAtmosphere
var terrain_generator
var structure_provider
var initialized = false
var last_build_ms = 0
var active_mesh: VoxelChunkMesh
var state_revisions: Dictionary = {}
var active_state_revision = 0
var active_coord = NO_CHUNK
var active_started = 0
var generation_layer = 0
var far_chunks: Dictionary = {}
var far_pending: Array[Vector2i] = []
var stream_tick = 0
var last_detail_focus = NO_CHUNK
var last_detail_radius = 3

func setup(seed_value: int, new_dimension: String, saved_edits: Dictionary = {}, version: int = 2, build_initial: bool = true) -> void:
	initialized = false
	_cancel_job()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for cache in [chunks,dirty_chunks,chunk_data,generated_layers,chunk_ranges,decorations,columns,far_chunks,block_states,built_tops,state_revisions]:
		cache.clear()
	pending.clear()
	far_pending.clear()
	last_detail_focus = NO_CHUNK
	last_detail_radius = block_distance
	edits = saved_edits.duplicate(true)
	edit_map.clear()
	for key in edits:
		var parts = str(key).split(",")
		if parts.size() == 3:
			var p = Vector3i(int(parts[0]),int(parts[1]),int(parts[2]))
			edit_map[p] = int(edits[key])
			if int(edits[key])>0:
				var c = Vector2i(floori(float(p.x)/16.0),floori(float(p.z)/16.0))
				built_tops[c] = maxi(int(built_tops.get(c,MIN_Y)),p.y+1)
	world_seed = seed_value
	generator_version = clampi(version,1,2)
	dimension = new_dimension.to_lower()
	if dimension == "the end":
		dimension = "end"
	terrain_noise.seed = seed_value
	terrain_noise.frequency = 0.012
	terrain_noise.fractal_octaves = 4
	detail_noise.seed = seed_value+71
	detail_noise.frequency = 0.044
	detail_noise.fractal_octaves = 3
	biome_noise.seed = seed_value+173
	biome_noise.frequency = 0.007
	cave_noise.seed = seed_value+373
	cave_noise.frequency = 0.065
	cave_noise.fractal_octaves = 2
	terrain_generator = null
	structure_provider = null
	if _deep_world():
		var terrain_script = load("res://world/terrain_generator.gd")
		terrain_generator = terrain_script.new()
		terrain_generator.setup(seed_value)
		if ResourceLoader.exists("res://world/structure_generator.gd"):
			structure_provider = load("res://world/structure_generator.gd").new()
			structure_provider.setup(seed_value,terrain_generator)
	solid_flags.clear()
	transparent_flags.clear()
	for data in BlockDB.all_blocks():
		var id: int = data.id
		solid_flags[id] = data.get("solid",id != 0)
		transparent_flags[id] = data.get("transparent",false)
	BlockAtlas.prepare()
	atmosphere = WorldAtmosphere.new()
	add_child(atmosphere)
	atmosphere.setup(dimension)
	focus_position = spawn_position()
	focus_section = floori(focus_position.y/16.0)
	focus_chunk = NO_CHUNK
	if build_initial:
		_bootstrap(focus_position)
	initialized = true
	update_focus(focus_position)

func _deep_world() -> bool:
	return generator_version >= 2 and dimension == "overworld"

func min_y() -> int:
	return MIN_Y if _deep_world() else 0

func max_y() -> int:
	return MAX_Y if _deep_world() else 80

func data_index(x: int,y: int,z: int) -> int:
	return x+z*16+(y-min_y())*256

func is_layer_ready(coord: Vector2i,y: int) -> bool:
	if not chunk_data.has(coord) or y < min_y() or y >= max_y():
		return false
	if not _deep_world():
		return true
	return generated_layers.has(coord) and generated_layers[coord][y-min_y()] != 0

func mesh_min_y(coord: Vector2i) -> int:
	return _mesh_range(coord).x

func mesh_max_y(coord: Vector2i) -> int:
	return _mesh_range(coord).y

func _mesh_range(coord: Vector2i) -> Vector2i:
	if not _deep_world():
		return Vector2i(0,80)
	if chunk_ranges.has(coord):
		return chunk_ranges[coord]
	var bottom = maxi(min_y(),focus_section*16-32)
	var top = mini(max_y(),focus_section*16+64)
	# Above ground, include the complete local tree/peak silhouette. Underground,
	# only stream the surrounding chambers; surface proxies remain separate.
	if focus_position.y >= surface_height(floori(focus_position.x),floori(focus_position.z))-24:
		for z in range(0,17,4):
			for x in range(0,17,4):
				var local_height = surface_height(coord.x*16+x,coord.y*16+z)
				top = maxi(top,mini(max_y(),local_height+22))
				bottom = mini(bottom,maxi(min_y(),local_height-24))
	top = mini(max_y(),maxi(top,int(built_tops.get(coord,MIN_Y))))
	var result = Vector2i(bottom,top)
	chunk_ranges[coord] = result
	return result

func _process(_delta: float) -> void:
	if not initialized:
		return
	stream_tick += 1
	# A coarse tile is only a few hundred triangles. Alternate some of these
	# with nearby work so a high horizon appears while detailed chunks stream.
	if not far_pending.is_empty() and (pending.is_empty() and active_coord == NO_CHUNK or stream_tick%5 == 0):
		_build_far_tile(far_pending.pop_front())
		return
	if active_coord == NO_CHUNK:
		while not pending.is_empty():
			var candidate: Vector2i = pending.pop_front()
			if not chunks.has(candidate) or dirty_chunks.has(candidate):
				active_coord = candidate
				active_started = Time.get_ticks_msec()
				generation_layer = mesh_min_y(candidate)
				break
		if active_coord == NO_CHUNK:
			return
	if _deep_world():
		var started = Time.get_ticks_usec()
		_allocate_data(active_coord)
		while generation_layer < mesh_max_y(active_coord):
			if not is_layer_ready(active_coord,generation_layer):
				_generate_layer(active_coord,generation_layer)
			generation_layer += 1
			if Time.get_ticks_usec()-started >= FRAME_BUDGET_USEC:
				return
	if active_mesh == null:
		active_mesh = VoxelChunkMesh.new()
		active_state_revision = int(state_revisions.get(active_coord,0))
		active_mesh.begin(self,active_coord,_get_chunk_data(active_coord))
		return
	if active_mesh.step(FRAME_BUDGET_USEC):
		_install_chunk(active_coord,active_mesh.finish(),active_state_revision)
		last_build_ms = Time.get_ticks_msec()-active_started
		_cancel_job()

func _cancel_job() -> void:
	active_mesh = null
	active_coord = NO_CHUNK

func _distance(a: Vector2i,b: Vector2i) -> int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))

func update_focus(pos: Vector3) -> void:
	if atmosphere != null:
		atmosphere.focus = pos
	var coord = Vector2i(floori(pos.x/16.0),floori(pos.z/16.0))
	var section = floori(pos.y/16.0)
	if coord == focus_chunk and (section == focus_section or not _deep_world()):
		return
	var vertical_changed = section != focus_section and _deep_world()
	focus_position = pos
	focus_section = section
	focus_chunk = coord
	if vertical_changed:
		chunk_ranges.clear()
		for key in chunks:
			dirty_chunks[key] = true
	if active_coord != NO_CHUNK and (vertical_changed or _distance(active_coord,coord)>_stream_radius()):
		_cancel_job()
	pending.clear()
	var radius = _stream_radius()
	for z in range(coord.y-radius,coord.y+radius+1):
		for x in range(coord.x-radius,coord.x+radius+1):
			var candidate = Vector2i(x,z)
			if chunks.has(candidate):
				_update_chunk_visibility(candidate)
				if want_collision(candidate) and not chunks[candidate].get_meta("has_collision",false):
					dirty_chunks[candidate] = true
			if not chunks.has(candidate) or dirty_chunks.has(candidate):
				pending.append(candidate)
	pending.sort_custom(func(a: Vector2i,b: Vector2i): return (a-focus_chunk).length_squared() < (b-focus_chunk).length_squared())
	for key in chunks.keys():
		if _distance(key,coord)>radius:
			chunks[key].queue_free()
			chunks.erase(key)
			dirty_chunks.erase(key)
	for key in chunk_data.keys():
		if _distance(key,coord)>radius+1:
			chunk_data.erase(key)
			generated_layers.erase(key)
			chunk_ranges.erase(key)
			decorations.erase(key)
	if columns.size()>40000:
		columns.clear()
	_refresh_far_queue()

func _bootstrap(pos: Vector3) -> void:
	var center = Vector2i(floori(pos.x/16.0),floori(pos.z/16.0))
	for z in range(center.y-1,center.y+2):
		for x in range(center.x-1,center.x+2):
			var coord = Vector2i(x,z)
			if not chunks.has(coord) or dirty_chunks.has(coord):
				_build_chunk(coord)

func prepare_panorama(center: Vector3,radius: int = 3) -> void:
	_cancel_job()
	focus_position = center
	focus_section = floori(center.y/16.0)
	chunk_ranges.clear()
	radius = clampi(radius,1,3)
	var origin = Vector2i(floori(center.x/16.0),floori(center.z/16.0))
	for z in range(origin.y-radius,origin.y+radius+1):
		for x in range(origin.x-radius,origin.x+radius+1):
			if not chunks.has(Vector2i(x,z)):
				_build_chunk(Vector2i(x,z))
	focus_chunk = NO_CHUNK
	update_focus(center)

func ensure_ready_at(pos: Vector3) -> void:
	_cancel_job()
	# Refresh vertical ranges before rebuilding collision at a restored/teleported
	# position; absolute Y never aliases the original surface buffer.
	update_focus(pos)
	_bootstrap(pos)
	focus_chunk = NO_CHUNK
	update_focus(pos)

func set_block_distance(value: int) -> void:
	block_distance = clampi(value,2,12)
	_cancel_job()
	focus_chunk = NO_CHUNK
	update_focus(focus_position)

func _stream_radius() -> int:
	return maxi(block_distance,NEAR_RADIUS)

func want_collision(coord: Vector2i) -> bool:
	var center = Vector2i(floori(focus_position.x/16.0),floori(focus_position.z/16.0))
	return _distance(coord,center)<=NEAR_RADIUS

func has_detailed_visual(coord: Vector2i) -> bool:
	return chunks.has(coord) and _distance(coord,focus_chunk)<=block_distance

func set_render_distance(value: int) -> void:
	render_distance = clampi(value,2,32)
	_cancel_job()
	focus_chunk = NO_CHUNK
	update_focus(focus_position)

func is_solid(id: int) -> bool:
	return solid_flags.get(id,id != 0)

func is_transparent(id: int) -> bool:
	return transparent_flags.get(id,false)

func get_block(p: Vector3i) -> int:
	if p.y < min_y():
		return 0 if dimension == "end" else 10
	if p.y >= max_y():
		return 0
	if edit_map.has(p):
		return edit_map[p]
	var coord = Vector2i(floori(float(p.x)/16.0),floori(float(p.z)/16.0))
	if is_layer_ready(coord,p.y):
		return chunk_data[coord][data_index(posmod(p.x,16),p.y,posmod(p.z,16))]
	if not _deep_world():
		return _get_chunk_data(coord)[data_index(posmod(p.x,16),p.y,posmod(p.z,16))]
	return _natural_block(p)

func _natural_block(p: Vector3i) -> int:
	if structure_provider != null:
		var override_id: int = structure_provider.block_at(p)
		if override_id >= 0:
			return override_id
	var col = _column(p.x,p.z)
	if p.y > int(col.height):
		var decoration_id: int = terrain_generator.decoration_at(p)
		if decoration_id >= 0:
			return decoration_id
	return terrain_generator.block_at(p.x,p.y,p.z,col)

func set_block(p: Vector3i,id: int) -> void:
	if p.y <= min_y() or p.y >= max_y() or (id != 0 and not BlockDB.is_block(id)):
		return
	if get_block(p) == id:
		return
	edits[_state_key(p)] = id
	edit_map[p] = id
	block_states.erase(_state_key(p))
	var coord = Vector2i(floori(float(p.x)/16.0),floori(float(p.z)/16.0))
	if id>0 and p.y+1>int(built_tops.get(coord,MIN_Y)):
		built_tops[coord] = p.y+1
		chunk_ranges.erase(coord)
	if chunk_data.has(coord):
		var data: PackedInt32Array = chunk_data[coord]
		data[data_index(posmod(p.x,16),p.y,posmod(p.z,16))] = id
		chunk_data[coord] = data
	_invalidate_at(p)
	block_changed.emit(p,id)

func _state_key(p: Vector3i) -> String:
	return "%d,%d,%d" % [p.x,p.y,p.z]

func get_block_state(p: Vector3i) -> Dictionary:
	return block_states.get(_state_key(p),{}).duplicate(true)

func set_block_state(p: Vector3i,state: Dictionary) -> void:
	var key = _state_key(p)
	var previous: Dictionary = block_states.get(key,{})
	if previous == state: return
	if state.is_empty():
		block_states.erase(key)
	else:
		block_states[key] = state.duplicate(true)
	# Timers are simulation bookkeeping. Only visible changes need a new mesh.
	var before = previous.duplicate(true)
	var after = state.duplicate(true)
	for field in ["pending_due","pending_power","pulse_until","pulse_pending"]:
		before.erase(field); after.erase(field)
	if before != after: _invalidate_at(p,false)
	block_state_changed.emit(p,state.duplicate(true))

func get_states() -> Dictionary:
	return block_states.duplicate(true)

func get_edits() -> Dictionary:
	return edits.duplicate(true)

func _invalidate_at(p: Vector3i,cancel_active: bool = true) -> void:
	var coord = Vector2i(floori(float(p.x)/16.0),floori(float(p.z)/16.0))
	var affected: Array[Vector2i] = [coord]
	if posmod(p.x,16)==0: affected.append(coord+Vector2i.LEFT)
	if posmod(p.x,16)==15: affected.append(coord+Vector2i.RIGHT)
	if posmod(p.z,16)==0: affected.append(coord+Vector2i.UP)
	if posmod(p.z,16)==15: affected.append(coord+Vector2i.DOWN)
	if cancel_active and active_coord in affected:
		if not pending.has(active_coord): pending.push_front(active_coord)
		_cancel_job()
	for key in affected:
		state_revisions[key] = int(state_revisions.get(key,0))+1
		_rebuild_chunk(key)

func surface_height(x: int,z: int) -> int:
	return _column(x,z).height

func biome_at(pos: Vector3) -> String:
	if _deep_world(): return str(_column(floori(pos.x),floori(pos.z)).biome)
	return "Nether Wastes" if dimension == "nether" else ("End Highlands" if dimension == "end" else "Legacy Overworld")

func climate_at(pos: Vector3) -> Dictionary:
	if _deep_world():
		var col = _column(floori(pos.x),floori(pos.z))
		return {"temperature":col.temperature,"humidity":col.humidity}
	return {"temperature":1.0 if dimension == "nether" else 0.5,"humidity":0.0 if dimension == "nether" else 0.5}

func cave_biome_at(pos: Vector3) -> String:
	return terrain_generator.cave_biome_at(pos) if _deep_world() else "Normal Caves"

func spawn_position() -> Vector3:
	return Vector3(8.5,surface_height(8,8)+2.2,8.5)

func end_pillars() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in range(8):
		var angle = float(i)*TAU/8.0
		points.append(Vector3(roundi(8+cos(angle)*30)+0.5,48+(i%3)*5,roundi(8+sin(angle)*30)+0.5))
	return points

func _build_chunk(coord: Vector2i) -> void:
	var started = Time.get_ticks_msec()
	_install_chunk(coord,VoxelChunkMesh.build(self,coord,_get_chunk_data(coord)))
	last_build_ms = Time.get_ticks_msec()-started

func _install_chunk(coord: Vector2i,chunk: Node3D,built_revision: int = -1) -> void:
	if chunks.has(coord):
		remove_child(chunks[coord])
		chunks[coord].queue_free()
	add_child(chunk)
	chunks[coord] = chunk
	_update_chunk_visibility(coord)
	dirty_chunks.erase(coord)
	# Fast clocks must not perpetually cancel the current build. Install its
	# completed result, then refresh if states changed while it was being built.
	if built_revision >= 0 and built_revision != int(state_revisions.get(coord,0)):
		_rebuild_chunk(coord)
	_invalidate_far_tile(coord)
	chunk_ready.emit(coord)

func _update_chunk_visibility(coord: Vector2i) -> void:
	var center = Vector2i(floori(focus_position.x/16.0),floori(focus_position.z/16.0))
	for child in chunks[coord].get_children():
		if child is MeshInstance3D:
			child.visible = _distance(coord,center)<=block_distance
		elif child is StaticBody3D:
			child.collision_layer = 1 if want_collision(coord) else 0

func _rebuild_chunk(coord: Vector2i) -> void:
	if not chunks.has(coord): return
	dirty_chunks[coord] = true
	pending.erase(coord)
	pending.push_front(coord)

func _column(x: int,z: int) -> Dictionary:
	return terrain_generator.column(x,z) if _deep_world() else _legacy_column(x,z)

func _allocate_data(coord: Vector2i) -> void:
	if chunk_data.has(coord): return
	var data = PackedInt32Array()
	data.resize((max_y()-min_y())*256)
	chunk_data[coord] = data
	var layers = PackedByteArray()
	layers.resize(max_y()-min_y())
	generated_layers[coord] = layers

func _generate_layer(coord: Vector2i,y: int) -> void:
	var data: PackedInt32Array = chunk_data[coord]
	for z in range(16):
		for x in range(16):
			var p = Vector3i(coord.x*16+x,y,coord.y*16+z)
			data[data_index(x,y,z)] = edit_map[p] if edit_map.has(p) else _natural_block(p)
	chunk_data[coord] = data
	var layers: PackedByteArray = generated_layers[coord]
	layers[y-min_y()] = 1
	generated_layers[coord] = layers

func _get_chunk_data(coord: Vector2i) -> PackedInt32Array:
	if not _deep_world(): return _legacy_chunk_data(coord)
	_allocate_data(coord)
	for y in range(mesh_min_y(coord),mesh_max_y(coord)):
		if not is_layer_ready(coord,y): _generate_layer(coord,y)
	return chunk_data[coord]

func _far_tile_of(coord: Vector2i) -> Vector2i:
	return Vector2i(floori(float(coord.x)/4.0),floori(float(coord.y)/4.0))

func _refresh_far_queue() -> void:
	far_pending.clear()
	var wanted: Dictionary = {}
	if render_distance > block_distance:
		var low = _far_tile_of(focus_chunk-Vector2i(render_distance,render_distance))
		var high = _far_tile_of(focus_chunk+Vector2i(render_distance,render_distance))
		for z in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var tile = Vector2i(x,z)
				wanted[tile] = true
				# Near tiles' holes change as the detailed collision ring moves.
				if not far_chunks.has(tile) or _distance(tile*4+Vector2i(2,2),focus_chunk)<block_distance+6 or (last_detail_focus != NO_CHUNK and _distance(tile*4+Vector2i(2,2),last_detail_focus)<last_detail_radius+6):
					far_pending.append(tile)
	for key in far_chunks.keys():
		if not wanted.has(key):
			far_chunks[key].queue_free()
			far_chunks.erase(key)
	far_pending.sort_custom(func(a: Vector2i,b: Vector2i): return (a*4-focus_chunk).length_squared()<(b*4-focus_chunk).length_squared())
	last_detail_focus = focus_chunk
	last_detail_radius = block_distance

func _invalidate_far_tile(coord: Vector2i) -> void:
	if render_distance<=block_distance: return
	var tile = _far_tile_of(coord)
	if not far_pending.has(tile): far_pending.push_front(tile)

func _build_far_tile(tile: Vector2i) -> void:
	if render_distance<=block_distance: return
	var node = TerrainLOD.build(self,tile)
	if far_chunks.has(tile):
		far_chunks[tile].queue_free()
	add_child(node)
	far_chunks[tile] = node

func streaming_stats() -> Dictionary:
	var bytes = 0
	for data in chunk_data.values(): bytes += data.size()*4
	return {"detail_chunks":chunks.size(),"data_bytes":bytes,"far_tiles":far_chunks.size(),"near_pending":pending.size(),"far_pending":far_pending.size(),"near_radius":NEAR_RADIUS,"block_distance":block_distance}

func _legacy_column(x: int,z: int) -> Dictionary:
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

func _legacy_chunk_data(coord: Vector2i) -> PackedInt32Array:
	if chunk_data.has(coord):
		return chunk_data[coord]
	var data = PackedInt32Array()
	data.resize(16*16*80)
	var ox = coord.x*16
	var oz = coord.y*16
	for z in range(16):
		for x in range(16):
			var wx = ox+x
			var wz = oz+z
			var col = _column(wx,wz)
			var height: int = col.height
			var top = mini(80-1,maxi(height,18 if dimension == "nether" else (SEA_LEVEL if dimension == "overworld" else -1)))
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
	if generator_version == 1:
		_decorate_gateways(data,coord)
	# Saved changes take precedence over terrain, trees and landmarks.
	for p in edit_map:
		if p.x >= ox and p.x < ox+16 and p.z >= oz and p.z < oz+16 and p.y >= 0 and p.y < 80:
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
	if lx < 0 or lx >= 16 or lz < 0 or lz >= 16 or p.y < 0 or p.y >= 80:
		return
	var index = lx+lz*16+p.y*256
	if not only_air or data[index] == 0:
		data[index] = id

func _hash(x: int,y: int,z: int) -> int:
	return absi((x*374761393+y*668265263+z*2147483647+world_seed*144269) ^ ((x+z+y)*1274126177))
