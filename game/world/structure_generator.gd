class_name StructureGenerator
extends RefCounted
## Pure seeded blueprints. Cached chunk overrides contain explicit air as well
## as blocks, so interiors and doorways stay clear of natural stone and trees.

const REGION_SIZE = 384
const TYPES = ["village", "temple", "mineshaft", "stronghold", "ruin", "camp", "underground_ruin", "mountain_cabin"]
var world_seed: int
var terrain
var regions: Dictionary = {}
var chunk_blocks: Dictionary = {}
var ready_chunks: Dictionary = {}
var built: Dictionary = {}
var strongholds: Array = []
var chest_loot: Dictionary = {}

func setup(seed_value: int, terrain_value) -> void:
	world_seed = seed_value
	terrain = terrain_value
	regions.clear()
	chunk_blocks.clear()
	ready_chunks.clear()
	built.clear()
	chest_loot.clear()
	strongholds.clear()
	var rotation: float = float(_hash(0, 881) % 6283) / 1000.0
	for index in range(3):
		var angle: float = rotation + index * TAU / 3.0
		var distance: float = 850.0 + _hash(index, 881) % 550
		var p = Vector3i(roundi(cos(angle) * distance), -48 - index * 13, roundi(sin(angle) * distance))
		strongholds.append(_descriptor("stronghold", p, _hash(index, 1101), 34))

func _descriptor(type: String, p: Vector3i, hash_value: int, radius: int) -> Dictionary:
	return {"id":"%s:%d:%d:%d" % [type,p.x,p.y,p.z], "type":type, "name":type.replace("_", " ").capitalize(), "position":Vector3(p), "origin":p, "variant":hash_value % 3, "rotation":(hash_value >> 5) % 4, "hash":hash_value, "radius":radius, "loot":[], "villagers":[], "min_y":p.y - 12, "max_y":p.y + 16}

func _region(coord: Vector2i) -> Array:
	if regions.has(coord):
		return regions[coord]
	var result: Array = []
	var h: int = _hash(coord.x, coord.y)
	var roll: int = h % 100
	var desired: String = "village" if roll < 27 else ("temple" if roll < 43 else ("ruin" if roll < 67 else ("camp" if roll < 88 else "mountain_cabin")))
	for attempt in range(10):
		var candidate: int = _hash(coord.x * 11 + attempt, coord.y * 13 + 317)
		var x: int = coord.x * REGION_SIZE + 58 + candidate % (REGION_SIZE - 116)
		var z: int = coord.y * REGION_SIZE + 58 + ((candidate >> 9) % (REGION_SIZE - 116))
		var col: Dictionary = terrain.column(x, z)
		var type: String = desired
		if int(col.height) < 26 or Vector2(x - 8, z - 8).length() < 68:
			continue
		if type == "village" and str(col.biome) not in ["Plains", "Meadow", "Flower Fields", "Savanna", "Desert", "Sparse Spruce Forest", "Snowy Forest"]:
			continue
		if type == "mountain_cabin" and int(col.height) < 65:
			continue
		if type == "temple" and str(col.biome) not in ["Desert", "Rocky Badlands", "Savanna", "Old-Growth Forests", "Swamp"]:
			continue
		var radius: int = 26 if type == "village" else (12 if type == "temple" else 8)
		if not _fits(x, z, radius, 6 if type == "village" else 5):
			continue
		var descriptor: Dictionary = _descriptor(type, Vector3i(x, int(col.height), z), candidate, radius)
		descriptor["biome"] = col.biome
		result.append(descriptor)
		break
	# Independent underground sites add vertical exploration without crowding
	# villages. Stronghold rooms reserve their horizontal footprint.
	for index in range(2):
		var value: int = _hash(coord.x + index * 761, coord.y + 997)
		if value % 100 > (48 if index == 0 else 24):
			continue
		var p = Vector3i(coord.x * REGION_SIZE + 70 + value % 240, -18 - ((value >> 8) % 92), coord.y * REGION_SIZE + 70 + ((value >> 16) % 240))
		var reserved: bool = false
		for stronghold in strongholds:
			if Vector2(p.x - stronghold.origin.x, p.z - stronghold.origin.z).length() < 100:
				reserved = true
		if not reserved:
			result.append(_descriptor("mineshaft" if index == 0 else "underground_ruin", p, value, 34 if index == 0 else 10))
	regions[coord] = result
	return result

func _fits(x: int, z: int, radius: int, max_relief: int) -> bool:
	var low: int = 999
	var high: int = -999
	for dz in [-radius, 0, radius]:
		for dx in [-radius, 0, radius]:
			var col: Dictionary = terrain.column(x + dx, z + dz)
			low = mini(low, int(col.height))
			high = maxi(high, int(col.height))
			if int(col.height) <= 24 or bool(col.get("entrance", false)) or float(col.river) > 0.7:
				return false
	return high - low <= max_relief

func prepare_chunk(coord: Vector2i) -> Dictionary:
	# Blueprints are reproducible; discard geometry after a long expedition
	# rather than retaining every explicit-air voxel ever visited.
	if chunk_blocks.size() > 512 or ready_chunks.size() > 4096:
		chunk_blocks.clear()
		ready_chunks.clear()
		built.clear()
		chest_loot.clear()
	if ready_chunks.has(coord):
		return chunk_blocks.get(coord, {})
	var region = Vector2i(floori(coord.x * 16.0 / REGION_SIZE), floori(coord.y * 16.0 / REGION_SIZE))
	var candidates: Array = _region(region).duplicate()
	candidates.append_array(strongholds)
	for structure in candidates:
		var p: Vector3i = structure.origin
		var r: int = structure.radius
		if p.x + r < coord.x * 16 or p.x - r > coord.x * 16 + 15 or p.z + r < coord.y * 16 or p.z - r > coord.y * 16 + 15:
			continue
		_materialize(structure)
	ready_chunks[coord] = true
	return chunk_blocks.get(coord, {})

func block_at(p: Vector3i) -> int:
	var coord = Vector2i(floori(p.x / 16.0), floori(p.z / 16.0))
	return int(prepare_chunk(coord).get(p, -1))

func nearby_structures(pos: Vector3, radius: float = 128.0) -> Array:
	var result: Array = []
	var min_region = Vector2i(floori((pos.x - radius) / REGION_SIZE), floori((pos.z - radius) / REGION_SIZE))
	var max_region = Vector2i(floori((pos.x + radius) / REGION_SIZE), floori((pos.z + radius) / REGION_SIZE))
	var candidates: Array = strongholds.duplicate()
	for z in range(min_region.y, max_region.y + 1):
		for x in range(min_region.x, max_region.x + 1):
			candidates.append_array(_region(Vector2i(x, z)))
	for structure in candidates:
		var p: Vector3 = structure.position
		if Vector2(p.x - pos.x, p.z - pos.z).length() <= radius:
			_materialize(structure)
			result.append(structure)
	return result

func locate(type: String, origin: Vector3) -> Vector3:
	type = type.to_lower().replace(" ", "_").trim_suffix("s")
	if type == "ruined_building": type = "ruin"
	if type == "abandoned_temple": type = "temple"
	if type == "small_camp": type = "camp"
	if type not in TYPES:
		return Vector3.INF
	var closest = Vector3.INF
	var distance: float = INF
	if type == "stronghold":
		for structure in strongholds:
			var d: float = Vector2(structure.position.x - origin.x, structure.position.z - origin.z).length_squared()
			if d < distance:
				distance = d
				closest = structure.position + Vector3.UP
		return closest
	var base = Vector2i(floori(origin.x / REGION_SIZE), floori(origin.z / REGION_SIZE))
	for ring in range(9):
		for z in range(base.y - ring, base.y + ring + 1):
			for x in range(base.x - ring, base.x + ring + 1):
				if ring > 0 and absi(x - base.x) != ring and absi(z - base.y) != ring: continue
				for structure in _region(Vector2i(x, z)):
					if structure.type != type: continue
					var d: float = Vector2(structure.position.x - origin.x, structure.position.z - origin.z).length_squared()
					if d < distance:
						distance = d
						closest = structure.position + Vector3.UP
		if closest != Vector3.INF and ring >= 2 and sqrt(distance) < (ring - 1) * REGION_SIZE:
			break
	return closest

func loot_at(p: Vector3i) -> Array:
	prepare_chunk(Vector2i(floori(p.x / 16.0), floori(p.z / 16.0)))
	return chest_loot.get(p, []).duplicate(true)

func village_spawn_points(pos: Vector3, radius: float = 128.0) -> Array:
	var result: Array = []
	for structure in nearby_structures(pos, radius):
		if structure.type == "village": result.append_array(structure.villagers)
	return result

func _materialize(s: Dictionary) -> void:
	if built.has(s.id): return
	built[s.id] = true
	s.loot = []
	s.villagers = []
	var blocks: Dictionary = {}
	match str(s.type):
		"village": _village(blocks, s)
		"stronghold": _stronghold(blocks, s)
		"mineshaft": _mineshaft(blocks, s)
		"temple": _temple(blocks, s)
		"ruin", "underground_ruin": _ruin(blocks, s)
		"mountain_cabin": _cabin(blocks, s)
		"camp": _camp(blocks, s)
	for p: Vector3i in blocks:
		var coord = Vector2i(floori(p.x / 16.0), floori(p.z / 16.0))
		if not chunk_blocks.has(coord): chunk_blocks[coord] = {}
		chunk_blocks[coord][p] = blocks[p]

func _world(s: Dictionary, p: Vector3i) -> Vector3i:
	match int(s.rotation):
		1: p = Vector3i(-p.z, p.y, p.x)
		2: p = Vector3i(-p.x, p.y, -p.z)
		3: p = Vector3i(p.z, p.y, -p.x)
	return Vector3i(s.origin) + p

func _put(b: Dictionary, s: Dictionary, p: Vector3i, id: int) -> void:
	b[_world(s, p)] = id

func _box(b: Dictionary, s: Dictionary, a: Vector3i, c: Vector3i, id: int) -> void:
	for y in range(a.y, c.y + 1):
		for z in range(a.z, c.z + 1):
			for x in range(a.x, c.x + 1): _put(b, s, Vector3i(x,y,z), id)

func _surface_y(s: Dictionary, x: int, z: int) -> int:
	var p: Vector3i = _world(s, Vector3i(x,0,z))
	return int(terrain.column(p.x,p.z).height) - int(s.origin.y)

func _foundation(b: Dictionary, s: Dictionary, x: int, z: int, floor_y: int, material: int) -> void:
	var ground: int = _surface_y(s,x,z)
	_box(b,s,Vector3i(x,mini(ground-2,floor_y),z),Vector3i(x,floor_y,z),material)
	_box(b,s,Vector3i(x,floor_y+1,z),Vector3i(x,maxi(ground+18,floor_y+12),z),0)

func _chest(b: Dictionary, s: Dictionary, p: Vector3i, category: String) -> void:
	_put(b,s,p,27)
	var loot: Array = []
	var variant: int = s.variant
	match category:
		"village": loot = [{"id":1201,"count":3+variant},{"id":1015,"count":5},{"id":1009,"count":1+variant}]
		"smith": loot = [{"id":1003,"count":3+variant},{"id":1001,"count":5},{"id":1143,"count":1}]
		"temple": loot = [{"id":1005,"count":2+variant},{"id":1020,"count":1},{"id":1009,"count":2},{"id":1203,"count":1}]
		"stronghold": loot = [{"id":1020,"count":2+variant},{"id":1027,"count":4},{"id":1003,"count":3},{"id":1201,"count":3}]
		"mineshaft": loot = [{"id":1003,"count":2+variant},{"id":1001,"count":7},{"id":28,"count":8},{"id":1201,"count":2}]
		"underground_ruin": loot = [{"id":1009,"count":2},{"id":1006,"count":1},{"id":1027,"count":2}]
		_: loot = [{"id":1201,"count":2},{"id":1001,"count":3},{"id":1142,"count":5+variant}]
	var world_p: Vector3i = _world(s,p)
	chest_loot[world_p] = loot
	s.loot.append({"position":world_p,"items":loot.duplicate(true)})

func _house(b: Dictionary, s: Dictionary, x: int, z: int, width: int, depth: int, style: int, front_south: bool) -> int:
	var fy: int = _surface_y(s,x+width/2,z+depth/2)
	var planks: int = 35 if str(s.get("biome","")).contains("Snow") or style == 2 else 7
	for dz in range(depth):
		for dx in range(width):
			_foundation(b,s,x+dx,z+dz,fy,4)
			_put(b,s,Vector3i(x+dx,fy,z+dz),planks)
			if dx == 0 or dx == width-1 or dz == 0 or dz == depth-1:
				_box(b,s,Vector3i(x+dx,fy+1,z+dz),Vector3i(x+dx,fy+4,z+dz),5 if (dx in [0,width-1] and dz in [0,depth-1]) else (53 if style == 1 else planks))
	var door_z: int = z+depth-1 if front_south else z
	_box(b,s,Vector3i(x+width/2,fy+1,door_z),Vector3i(x+width/2,fy+2,door_z),0)
	for dz in [2,depth-3]:
		_put(b,s,Vector3i(x,fy+2,z+dz),16)
		_put(b,s,Vector3i(x+width-1,fy+2,z+dz),16)
	for dx in range(-1,width+1):
		var roof_y: int = fy+5+mini(dx+1,width-dx)/2
		_box(b,s,Vector3i(x+dx,roof_y,z-1),Vector3i(x+dx,roof_y,z+depth),planks)
		if dx >= 0 and dx < width and roof_y > fy+5:
			_box(b,s,Vector3i(x+dx,fy+5,z),Vector3i(x+dx,roof_y-1,z),planks)
			_box(b,s,Vector3i(x+dx,fy+5,z+depth-1),Vector3i(x+dx,roof_y-1,z+depth-1),planks)
	_put(b,s,Vector3i(x+1,fy+1,z+1),26 if style == 1 else (91 if style == 2 else 25))
	_put(b,s,Vector3i(x+1,fy+3,z+depth-2),28)
	_box(b,s,Vector3i(x+width-3,fy+1,z+depth-3),Vector3i(x+width-2,fy+1,z+depth-3),131 if style == 0 else 35)
	_chest(b,s,Vector3i(x+width-2,fy+1,z+1),"smith" if style == 1 else "village")
	return fy

func _road(b: Dictionary, s: Dictionary, x: int, z: int) -> void:
	var y: int = _surface_y(s,x,z)
	_foundation(b,s,x,z,y,2)
	_put(b,s,Vector3i(x,y,z),169)

func _village(b: Dictionary, s: Dictionary) -> void:
	for n in range(-23,24):
		for width in range(-1,2):
			_road(b,s,n,width)
			_road(b,s,width,n)
	var houses: Array = [[-19,-18,9,8,0,true,"farmer"],[10,-17,9,9,1,true,"smith"],[-19,9,9,9,2,false,"librarian"],[10,10,9,7,0,false,"mason"]]
	for house in houses:
		var fy: int = _house(b,s,house[0],house[1],house[2],house[3],house[4],house[5])
		var door_z: int = int(house[1])+int(house[3]) if bool(house[5]) else int(house[1])-1
		var door_x: int = int(house[0])+int(house[2])/2
		for z in range(mini(0,door_z),maxi(0,door_z)+1):
			_road(b,s,door_x,z)
		var marker: Vector3i = _world(s,Vector3i(door_x,_surface_y(s,door_x,door_z)+1,door_z))
		s.villagers.append({"id":str(s.id)+":"+str(house[6]),"position":Vector3(marker)+Vector3(0.5,0.1,0.5),"profession":house[6],"village_id":s.id,"name":["Alder","Hazel","Rowan","Wren"][s.villagers.size()]})
	# Irrigated farm, central well, shared storage and street lanterns.
	var farm_y: int = _surface_y(s,4,14)
	for z in range(8,21):
		for x in range(3,8):
			_foundation(b,s,x,z,farm_y,2)
			_put(b,s,Vector3i(x,farm_y,z),9 if x == 5 else 167)
			if x != 5: _put(b,s,Vector3i(x,farm_y+1,z),168)
	for z in range(-3,4):
		for x in range(-3,4):
			_foundation(b,s,x,z,0,4)
			if absi(x) <= 1 and absi(z) <= 1: _put(b,s,Vector3i(x,0,z),9)
	for x in [-3,3]:
		for z in [-3,3]: _box(b,s,Vector3i(x,1,z),Vector3i(x,4,z),5)
	_box(b,s,Vector3i(-4,5,-4),Vector3i(4,5,4),7)
	_foundation(b,s,-7,5,_surface_y(s,-7,5),4)
	_chest(b,s,Vector3i(-7,_surface_y(s,-7,5)+1,5),"village")
	for p in [Vector2i(-5,-5),Vector2i(5,-5),Vector2i(-5,5),Vector2i(5,5)]:
		var y: int = _surface_y(s,p.x,p.y)
		_box(b,s,Vector3i(p.x,y+1,p.y),Vector3i(p.x,y+3,p.y),5)
		_put(b,s,Vector3i(p.x,y+4,p.y),28)

func _room(b: Dictionary, s: Dictionary, a: Vector3i, c: Vector3i, material: int) -> void:
	_box(b,s,a,c,material)
	_box(b,s,a+Vector3i.ONE,c-Vector3i.ONE,0)

func _stronghold(b: Dictionary, s: Dictionary) -> void:
	_room(b,s,Vector3i(-7,0,-7),Vector3i(7,8,7),53)
	_room(b,s,Vector3i(7,0,-2),Vector3i(22,5,2),54)
	_room(b,s,Vector3i(18,0,-7),Vector3i(32,7,7),53)
	_box(b,s,Vector3i(7,1,-1),Vector3i(22,3,1),0)
	for x in range(-1,2):
		_put(b,s,Vector3i(x,1,-2),153)
		_put(b,s,Vector3i(x,1,2),153)
	for z in range(-1,2):
		_put(b,s,Vector3i(-2,1,z),153)
		_put(b,s,Vector3i(2,1,z),153)
	_box(b,s,Vector3i(-1,0,-1),Vector3i(1,0,1),18)
	s["portal_center"] = _world(s,Vector3i(0,1,0))
	for p in [Vector3i(-5,2,-5),Vector3i(5,2,5),Vector3i(20,2,5),Vector3i(30,2,-5)]: _put(b,s,p,28)
	for x in range(20,31,2):
		_box(b,s,Vector3i(x,1,-6),Vector3i(x,4,-5),91)
		_box(b,s,Vector3i(x,1,5),Vector3i(x,4,6),91)
	_chest(b,s,Vector3i(29,1,0),"stronghold")
	# Distinct third room or collapsed gallery, selected by seed.
	if int(s.variant) > 0:
		_room(b,s,Vector3i(-3,0,7),Vector3i(3,5,20),54)
		_box(b,s,Vector3i(-1,1,7),Vector3i(1,3,18),0)
		_chest(b,s,Vector3i(0,1,18),"stronghold")

func _mineshaft(b: Dictionary, s: Dictionary) -> void:
	var length: int = 23+int(s.variant)*5
	for axis in range(2):
		for n in range(-length,length+1):
			for width in range(-1,2):
				var p = Vector3i(n,0,width) if axis == 0 else Vector3i(width,0,n)
				_put(b,s,p,7)
				_box(b,s,p+Vector3i.UP,p+Vector3i(0,4,0),0)
			if posmod(n,6) == 0:
				for side in [-2,2]:
					var p = Vector3i(n,0,side) if axis == 0 else Vector3i(side,0,n)
					_box(b,s,p,p+Vector3i(0,4,0),5)
				for side in range(-2,3): _put(b,s,Vector3i(n,4,side) if axis == 0 else Vector3i(side,4,n),7)
				_put(b,s,Vector3i(n,3,1) if axis == 0 else Vector3i(1,3,n),28)
	_chest(b,s,Vector3i(length-2,1,0),"mineshaft")
	_chest(b,s,Vector3i(0,1,-length+2),"mineshaft")

func _temple(b: Dictionary, s: Dictionary) -> void:
	var stone: int = 50 if str(s.get("biome","")).contains("Desert") else 54
	for z in range(-9,10):
		for x in range(-9,10): _foundation(b,s,x,z,0,stone)
	_room(b,s,Vector3i(-6,0,-6),Vector3i(6,6,6),stone)
	for y in range(7,10): _box(b,s,Vector3i(y-12,y,y-12),Vector3i(12-y,y,12-y),stone)
	_box(b,s,Vector3i(-1,1,-6),Vector3i(1,3,-3),0)
	for x in [-4,4]:
		for z in [-4,4]: _box(b,s,Vector3i(x,1,z),Vector3i(x,5,z),52 if stone == 50 else 53)
	_put(b,s,Vector3i(0,1,0),100+int(s.variant))
	_put(b,s,Vector3i(0,4,4),28)
	_chest(b,s,Vector3i(-3,1,4),"temple")
	if int(s.variant) != 0: _chest(b,s,Vector3i(3,1,4),"temple")

func _ruin(b: Dictionary, s: Dictionary) -> void:
	var underground: bool = str(s.type) == "underground_ruin"
	if underground: _room(b,s,Vector3i(-8,-1,-8),Vector3i(8,7,8),58)
	for z in range(-5,6):
		for x in range(-6,7):
			if not underground: _foundation(b,s,x,z,0,4)
			_put(b,s,Vector3i(x,0,z),54)
			if absi(x) == 6 or absi(z) == 5:
				var height: int = 1+_hash(x+int(s.hash),z)%4
				_box(b,s,Vector3i(x,1,z),Vector3i(x,height,z),53 if height%2 == 0 else 54)
	_box(b,s,Vector3i(-1,1,-5),Vector3i(1,3,-5),0)
	_chest(b,s,Vector3i(4,1,3),str(s.type))
	if underground: _put(b,s,Vector3i(-4,2,3),28)

func _cabin(b: Dictionary, s: Dictionary) -> void:
	_house(b,s,-4,-4,9+int(s.variant)*2,8,2,true)
	for x in range(-4,5):
		_foundation(b,s,x,5,0,4)
		_put(b,s,Vector3i(x,0,5),35)
	_box(b,s,Vector3i(3,1,-2),Vector3i(3,10,-2),4)
	_put(b,s,Vector3i(-3,1,5),28)

func _camp(b: Dictionary, s: Dictionary) -> void:
	for z in range(-5,6):
		for x in range(-6,7): _foundation(b,s,x,z,0,2)
	for z in range(-4,1):
		for x in range(-3,4):
			var y: int = 4-absi(x)
			_put(b,s,Vector3i(x,y,z),[131,124,121][int(s.variant)])
	_box(b,s,Vector3i(0,1,-4),Vector3i(0,3,-4),5)
	_put(b,s,Vector3i(0,1,3),26)
	_put(b,s,Vector3i(0,2,3),28)
	_chest(b,s,Vector3i(3,1,3),"camp")
	_box(b,s,Vector3i(-3,1,3),Vector3i(-3,1,4),5)

func _hash(x: int, z: int) -> int:
	var value: int = (x*374761393 + z*668265263 + world_seed*144269 + 1907) & 0x7fffffff
	value = ((value ^ (value >> 13))*1274126177) & 0x7fffffff
	return (value ^ (value >> 16)) & 0x7fffffff
