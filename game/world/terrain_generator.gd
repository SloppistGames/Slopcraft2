class_name TerrainGenerator
extends RefCounted
## Generator version 2. All fields use world coordinates; chunk order never
## participates in generation. Heights are continuous before voxel rounding.

const MIN_Y = -176
const MAX_Y = 192
const SEA_LEVEL = 23
const DEEPSLATE_LEVEL = -76
const TREE_GRID = 7
const TREE_APRON = 7
const SURFACE_BIOMES = ["Plains", "Oak Forest", "Sparse Spruce Forest", "Dense Spruce Forest", "Birch Forest", "Mixed Forest", "Permafrost", "Temperate Highlands", "Frozen Highlands", "Mountain Ranges", "Desert", "Savanna", "Swamp", "Meadow", "Taiga", "Snowy Taiga", "Snowy Forest", "Rocky Badlands", "Tundra", "Alpine Peaks", "Jagged Frozen Peaks", "Coastal Cliffs", "Beaches", "River Valleys", "Flower Fields", "Old-Growth Forests"]
const CAVE_BIOMES = ["Normal Caves", "Interconnected Cave Systems", "Tight Cave Systems", "Vast Cave Systems", "Sulfuric Caves"]
const LOG_IDS = [5, 31, 33, 37, 40, 43, 45]

var world_seed: int = 1
var columns: Dictionary = {}
var decoration_chunks: Dictionary = {}
var tree_cache: Dictionary = {}
var continental: FastNoiseLite
var erosion_noise: FastNoiseLite
var temperature_noise: FastNoiseLite
var humidity_noise: FastNoiseLite
var ridge_noise: FastNoiseLite
var river_noise: FastNoiseLite
var detail_noise: FastNoiseLite
var variation_noise: FastNoiseLite
var cave_region_noise: FastNoiseLite
var geothermal_noise: FastNoiseLite
var tunnel_a: FastNoiseLite
var tunnel_b: FastNoiseLite
var cavern_noise: FastNoiseLite

func setup(seed_value: int) -> void:
	world_seed = seed_value
	columns.clear()
	decoration_chunks.clear()
	tree_cache.clear()
	continental = _noise(11, 0.0007, 2)
	erosion_noise = _noise(37, 0.0016, 2)
	temperature_noise = _noise(73, 0.00082, 1)
	humidity_noise = _noise(139, 0.00105, 1)
	ridge_noise = _noise(211, 0.0021, 2)
	river_noise = _noise(307, 0.00145, 2)
	detail_noise = _noise(401, 0.015, 3)
	variation_noise = _noise(503, 0.0028, 2)
	cave_region_noise = _noise(601, 0.0018, 2)
	geothermal_noise = _noise(709, 0.0021, 1)
	tunnel_a = _noise(809, 0.034, 1)
	tunnel_b = _noise(907, 0.039, 1)
	cavern_noise = _noise(1009, 0.013, 2)

func _noise(salt: int, frequency: float, octaves: int) -> FastNoiseLite:
	var result = FastNoiseLite.new()
	result.seed = world_seed + salt
	result.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	result.frequency = frequency
	result.fractal_type = FastNoiseLite.FRACTAL_FBM
	result.fractal_octaves = octaves
	result.fractal_gain = 0.42
	return result

func column(x: int, z: int) -> Dictionary:
	var key = Vector2i(x, z)
	if columns.has(key):
		return columns[key]
	# Climate domains are hundreds of blocks across. The gentle coordinate warp
	# bends both river courses and mountain ridges without introducing seams.
	var variation: float = variation_noise.get_noise_2d(x, z)
	var wx: float = x + variation * 85.0
	var wz: float = z + detail_noise.get_noise_2d(x * 0.12, z * 0.12) * 65.0
	var cont: float = continental.get_noise_2d(wx, wz)
	var erosion: float = clampf(0.5 + erosion_noise.get_noise_2d(wx, wz) * 0.9, 0.0, 1.0)
	var temp: float = clampf(0.5 + temperature_noise.get_noise_2d(x, z) * 0.70, 0.0, 1.0)
	var humid: float = clampf(0.5 + humidity_noise.get_noise_2d(x, z) * 0.70, 0.0, 1.0)
	var detail: float = detail_noise.get_noise_2d(x, z)
	var ridge: float = pow(1.0 - minf(1.0, absf(ridge_noise.get_noise_2d(wx, wz)) * 1.75), 2.0)
	var mountain: float = (1.0 - smoothstep(0.28, 0.70, erosion)) * smoothstep(-0.10, 0.26, cont)
	var land: float = smoothstep(-0.40, 0.27, cont)
	var base: float = lerpf(-9.0, 47.0, land)
	var dry: float = smoothstep(0.53, 0.76, temp) * (1.0 - smoothstep(0.25, 0.47, humid))
	var cold_flat: float = (1.0 - smoothstep(0.11, 0.26, temp)) * (1.0 - mountain)
	var wetland: float = smoothstep(0.54, 0.72, temp) * smoothstep(0.63, 0.84, humid) * smoothstep(0.46, 0.74, erosion) * land
	base = lerpf(base, SEA_LEVEL + 2.0 + detail * 2.0, wetland * 0.91)
	var rolling: float = detail * lerpf(4.0, 10.0, 1.0 - erosion) * (1.0 - cold_flat * 0.83)
	var mountains: float = 125.0 * mountain * ridge
	# The badlands terrace is smoothly blended by aridity, not a height jump at
	# a named biome edge. Cold peaks gain roughness only on the high ridge crest.
	var mesa: float = dry * (1.0 - erosion) * 14.0 * smoothstep(-0.15, 0.18, variation)
	var dunes: float = dry * erosion * sin(x * 0.068 + detail * 3.0) * 2.2
	var raw_height: float = base + rolling + mountains + mesa + dunes
	raw_height += (1.0 - smoothstep(0.22, 0.45, temp)) * mountain * ridge * detail * 9.0
	var river_distance: float = absf(river_noise.get_noise_2d(wx, wz))
	var river: float = (1.0 - smoothstep(0.025, 0.115, river_distance)) * smoothstep(-0.18, 0.06, cont)
	# Broad erosion valley shoulders lead down to a narrow level stream bed.
	var valley: float = (1.0 - smoothstep(0.02, 0.24, river_distance)) * smoothstep(-0.18, 0.06, cont)
	raw_height = lerpf(raw_height, minf(raw_height, 29.0 + rolling * 0.4), valley * 0.58)
	raw_height = lerpf(raw_height, minf(raw_height, 19.5 + detail * 1.3), river)
	# Closed shallow depressions in eroded humid lowland become ponds.
	var pond: float = smoothstep(0.26, 0.47, detail) * smoothstep(0.52, 0.73, humid) * smoothstep(0.40, 0.70, erosion) * (1.0 - mountain)
	pond = smoothstep(0.05, 0.48, pond)
	raw_height = lerpf(raw_height, minf(raw_height, 21.0), pond)
	# A modest gently blended landing meadow guarantees a dry initial spawn.
	var spawn_weight: float = 1.0 - smoothstep(12.0, 48.0, Vector2(x - 8, z - 8).length())
	raw_height = lerpf(raw_height, 30.0 + detail * 1.4, spawn_weight)
	var height: int = clampi(roundi(raw_height), -10, 160)
	var biome: String = _surface_biome(height, temp, humid, cont, erosion, mountain, ridge, river, variation, wetland)
	if spawn_weight > 0.75:
		biome = "Plains"
	var surface: int = 1
	var sub: int = 2
	match biome:
		"Ocean", "Beaches", "Desert":
			surface = 8
			sub = 8 if biome != "Desert" else 50
		"Rocky Badlands":
			surface = 51 if detail < 0.13 else 52
			sub = 100
		"Permafrost", "Tundra", "Snowy Taiga", "Snowy Forest", "Frozen Highlands", "Jagged Frozen Peaks":
			surface = 15
			sub = 3 if height > 75 else 2
		"Alpine Peaks", "Mountain Ranges":
			surface = 15 if temp - maxf(0.0, height - 55) * 0.004 < 0.24 else (57 if detail > 0.15 else 3)
			sub = 3
		"Coastal Cliffs":
			surface = 3 if detail > -0.1 else 49
			sub = 3
		"River Valleys":
			surface = 49 if height <= SEA_LEVEL else 1
			sub = 48 if humid > 0.6 else 2
		"Swamp":
			surface = 48 if height < SEA_LEVEL else 47
			sub = 2
		"Temperate Highlands":
			if ridge > 0.75 and detail > 0.17:
				surface = 3
				sub = 3
	var plant: Dictionary = _vegetation(biome)
	var cave_region: float = cave_region_noise.get_noise_2d(x, z)
	var geothermal: float = geothermal_noise.get_noise_2d(x, z)
	var entrance: bool = height > SEA_LEVEL + 5 and detail > 0.44 and variation < -0.1 and spawn_weight < 0.01
	var result: Dictionary = {"height":height, "height_float":raw_height, "bottom":MIN_Y, "surface":surface, "subsurface":sub, "biome":biome, "temperature":clampf(temp - maxf(0.0, height - 64) * 0.0025, 0.0, 1.0), "humidity":humid, "continentalness":cont, "erosion":erosion, "ridge":ridge, "mountain":mountain, "river":river, "pond":pond, "water_level":SEA_LEVEL, "tree_density":plant[0], "tree_species":plant[1], "grass_density":plant[2], "flower_density":plant[3], "detail":detail, "cave_region":cave_region, "geothermal":geothermal, "pillar":absf(variation_noise.get_noise_2d(x * 5.0, z * 5.0)), "deepslate_top":DEEPSLATE_LEVEL + roundi(detail * 7.0), "entrance":entrance}
	if columns.size() > 120000:
		columns.clear()
	columns[key] = result
	return result

func _surface_biome(h: int, t: float, m: float, c: float, e: float, mountain: float, ridge: float, river: float, v: float, wetland: float) -> String:
	if river > 0.53 and c > -0.12:
		return "River Valleys"
	if h < SEA_LEVEL - 3:
		return "Ocean"
	if h <= SEA_LEVEL + 2:
		return "Beaches"
	if c < 0.01 and e < 0.39 and h > SEA_LEVEL + 6:
		return "Coastal Cliffs"
	if h > 105 and mountain > 0.45:
		return "Jagged Frozen Peaks" if t < 0.35 and ridge > 0.50 else "Alpine Peaks"
	if h > 76 and mountain > 0.32:
		return "Mountain Ranges"
	if t > 0.64 and m < 0.37:
		return "Rocky Badlands" if e < 0.48 else "Desert"
	if h > 56:
		return "Frozen Highlands" if t < 0.34 else "Temperate Highlands"
	if t < 0.17:
		return "Permafrost"
	if t < 0.28:
		if m < 0.43:
			return "Tundra"
		return "Snowy Taiga" if m > 0.64 else "Snowy Forest"
	if t < 0.46:
		if m > 0.73:
			return "Taiga"
		return "Dense Spruce Forest" if m > 0.53 else "Sparse Spruce Forest"
	if wetland > 0.20 and h < 39:
		return "Swamp"
	if t > 0.64 and m < 0.56:
		return "Savanna"
	if m > 0.76:
		return "Old-Growth Forests"
	if m > 0.61:
		return "Mixed Forest"
	if m > 0.46:
		return "Birch Forest" if v < -0.08 else "Oak Forest"
	if m > 0.32 and v > 0.15:
		return "Flower Fields"
	if h > 36 and m > 0.32:
		return "Meadow"
	return "Plains"

func _vegetation(biome: String) -> Dictionary:
	# Probability per 7x7 root cell, species, grass and flower probabilities.
	match biome:
		"Oak Forest": return {0:0.74, 1:"oak", 2:0.15, 3:0.025}
		"Sparse Spruce Forest": return {0:0.24, 1:"spruce", 2:0.12, 3:0.005}
		"Dense Spruce Forest": return {0:0.96, 1:"tall_spruce", 2:0.035, 3:0.0}
		"Birch Forest": return {0:0.69, 1:"birch", 2:0.12, 3:0.05}
		"Mixed Forest": return {0:0.82, 1:"mixed", 2:0.10, 3:0.03}
		"Old-Growth Forests": return {0:0.65, 1:"old_growth", 2:0.06, 3:0.006}
		"Taiga": return {0:0.72, 1:"spruce", 2:0.08, 3:0.004}
		"Snowy Taiga": return {0:0.66, 1:"tall_spruce", 2:0.0, 3:0.0}
		"Snowy Forest": return {0:0.48, 1:"snow_mixed", 2:0.0, 3:0.0}
		"Savanna": return {0:0.16, 1:"acacia", 2:0.20, 3:0.005}
		"Swamp": return {0:0.40, 1:"swamp_oak", 2:0.08, 3:0.015}
		"Meadow": return {0:0.045, 1:"cherry", 2:0.20, 3:0.11}
		"Flower Fields": return {0:0.025, 1:"birch", 2:0.13, 3:0.29}
		"Temperate Highlands": return {0:0.14, 1:"mixed", 2:0.09, 3:0.02}
		"Frozen Highlands": return {0:0.08, 1:"spruce", 2:0.0, 3:0.0}
		"Plains", "River Valleys": return {0:0.055, 1:"oak", 2:0.18, 3:0.04}
	return {0:0.0, 1:"none", 2:0.0, 3:0.0}

func block_at(x: int, y: int, z: int, col: Dictionary = {}) -> int:
	if y <= MIN_Y:
		return 10
	if y >= MAX_Y:
		return 0
	if col.is_empty():
		col = column(x, z)
	var height: int = col.height
	if y > height:
		if y <= SEA_LEVEL:
			return 87 if y == SEA_LEVEL and float(col.temperature) < 0.25 else 9
		return 0
	if y < MIN_Y + 4 and _hash(x, y, z) % 4 >= y - MIN_Y:
		return 10
	var roof: int = 0 if bool(col.entrance) else (5 if height <= SEA_LEVEL + 1 else 3)
	var cave_value: float = -1.0
	if y > MIN_Y + 5 and y <= height - roof:
		cave_value = _cave_value(x, y, z, col)
		if cave_value > 0.0:
			if y < -162:
				return 20
			if y <= -124 and float(col.cave_region) > 0.19 and float(col.geothermal) < 0.13:
				return 9
			return 0
	if y == height:
		return int(col.surface)
	if y >= height - 3:
		return int(col.subsurface)
	if str(col.biome) == "Rocky Badlands" and y > height - 14:
		return [100, 102, 113, 52][posmod(floori(y / 3.0), 4)]
	var deep: bool = y <= int(col.deepslate_top)
	var sulfur: bool = float(col.geothermal) > 0.25 and y < -34
	if sulfur and cave_value > -0.065:
		if _hash(x, y, z) % 61 == 0 and _cave_value(x, y + 1, z, col) > 0.0:
			return 176
		return 151
	var ore: int = _ore_at(x, y, z, height, deep, sulfur)
	if ore > 0:
		return ore
	return 58 if deep else 3

func _cave_value(x: int, y: int, z: int, col: Dictionary) -> float:
	var region: float = col.cave_region
	var a: float = absf(tunnel_a.get_noise_3d(x, y * 0.88, z))
	var b: float = absf(tunnel_b.get_noise_3d(x, y * 0.93, z))
	var tight: float = 1.0 - smoothstep(-0.38, -0.08, region)
	var connected: float = smoothstep(-0.02, 0.20, region)
	var width: float = lerpf(0.145, 0.065, tight) + connected * 0.032
	var tunnel: float = width - sqrt(a * a + b * b)
	# A second branch direction joins the tunnel network in connected regions.
	var chamber: float = cavern_noise.get_noise_3d(x, y * 1.55, z)
	var branch: float = minf(width * 0.69 - a, width * 0.68 - absf(chamber)) - (1.0 - connected) * 0.3
	var depth_weight: float = 1.0 - smoothstep(-65.0, -18.0, y)
	var vast: float = smoothstep(0.05, 0.34, region) * depth_weight
	var sulfur: float = smoothstep(0.17, 0.43, float(col.geothermal)) * depth_weight
	var cavern: float = chamber - lerpf(0.59, 0.30, maxf(vast, sulfur * 0.9))
	# Coherent vertical rock columns interrupt big chambers, while tunnels can
	# still wind around and through their bases. No repeated sphere primitives.
	cavern -= smoothstep(0.45, 0.62, float(col.pillar)) * 0.55
	return maxf(tunnel, maxf(branch, cavern))

func cave_biome_at(pos: Vector3) -> String:
	var col: Dictionary = column(floori(pos.x), floori(pos.z))
	if pos.y >= int(col.height) - 3:
		return "Surface"
	if pos.y < -34 and float(col.geothermal) > 0.25:
		return "Sulfuric Caves"
	if pos.y < -28 and float(col.cave_region) > 0.19:
		return "Vast Cave Systems"
	if float(col.cave_region) < -0.19:
		return "Tight Cave Systems"
	if float(col.cave_region) > 0.015:
		return "Interconnected Cave Systems"
	return "Normal Caves"

func _ore_at(x: int, y: int, z: int, height: int, deep: bool, sulfur: bool) -> int:
	# Each small geological cell has a jittered contiguous vein. A voxel hash
	# only roughens its edge; ore is not independently scattered block by block.
	var gx: int = floori(x / 5.0)
	var gy: int = floori(y / 5.0)
	var gz: int = floori(z / 5.0)
	var h: int = _hash(gx, gy + 173, gz)
	var kind: int = h % 100
	if kind > 42:
		return 0
	var dx: int = posmod(x, 5) - (1 + ((h >> 5) % 3))
	var dy: int = posmod(y, 5) - (1 + ((h >> 8) % 3))
	var dz: int = posmod(z, 5) - (1 + ((h >> 11) % 3))
	if dx * dx + dy * dy + dz * dz > 3 + (h % 4):
		return 0
	if sulfur and kind < 12:
		return 152
	if kind < 12:
		return (170 if deep else 11) if y > -106 else 0
	if kind < 23:
		return (171 if deep else 12) if y > -148 and y < 86 else 0
	if kind < 28:
		return (175 if deep else 73) if y > -94 and y < 45 else 0
	if kind < 32:
		return (172 if deep else 13) if y < -18 and y > -155 else 0
	if kind < 35:
		return (173 if deep else 14) if y < -94 and y > -172 else 0
	if kind < 39:
		return (174 if deep else 75) if y < -60 else 0
	if kind < 42:
		return 76 if y < -5 and y > -122 else 0
	if kind == 42 and height > 70 and y > -20:
		return 74
	return 0

func tree_at_grid(gx: int, gz: int) -> Dictionary:
	var key = Vector2i(gx, gz)
	if tree_cache.has(key):
		return tree_cache[key]
	var h: int = _hash(gx, 111, gz)
	var x: int = gx * TREE_GRID + 1 + h % 5
	var z: int = gz * TREE_GRID + 1 + ((h >> 6) % 5)
	var col: Dictionary = column(x, z)
	var tree: Dictionary = {}
	if float((h >> 12) % 1000) / 1000.0 >= float(col.tree_density) or int(col.height) <= SEA_LEVEL or int(col.surface) not in [1, 15, 47] or Vector2(x - 8, z - 8).length() < 9.0:
		tree_cache[key] = tree
		return tree
	var species: String = col.tree_species
	if species == "mixed":
		species = ["oak", "birch", "spruce"][h % 3]
	elif species == "snow_mixed":
		species = "birch" if h % 3 == 0 else "spruce"
	var height: int = 5 + h % 3
	var log_id: int = 5
	var leaf_id: int = 6
	var thickness: int = 1
	match species:
		"spruce", "tall_spruce":
			log_id = 31
			leaf_id = 32
			height = (10 if species == "tall_spruce" else 7) + h % 5
		"birch":
			log_id = 33
			leaf_id = 34
			height = 6 + h % 4
		"acacia":
			log_id = 37
			leaf_id = 39
			height = 5 + h % 3
		"cherry":
			log_id = 40
			leaf_id = 42
		"old_growth":
			log_id = 43
			height = 12 + h % 5
			thickness = 2
		"swamp_oak":
			height = 6 + h % 3
	var base: int = int(col.height) + 1
	# Reject cliff roots and actual cave mouths; a thick trunk is rooted in
	# every footprint column, including when its root straddles a chunk edge.
	for dz in range(thickness):
		for dx in range(thickness):
			var root: Dictionary = column(x + dx, z + dz)
			if absi(int(root.height) - (base - 1)) > 1 or int(root.surface) not in [1, 15, 47] or block_at(x + dx, int(root.height), z + dz, root) == 0:
				tree_cache[key] = {}
				return {}
	for offset in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3)]:
		if int(column(x + offset.x, z + offset.y).height) > base + 2:
			tree_cache[key] = {}
			return {}
	tree = {"position":Vector3i(x, base, z), "height":height, "species":species, "log":log_id, "leaf":leaf_id, "thickness":thickness, "hash":h}
	if tree_cache.size() > 16000:
		tree_cache.clear()
	tree_cache[key] = tree
	return tree

func prepare_decorations(coord: Vector2i) -> Dictionary:
	if decoration_chunks.has(coord):
		return decoration_chunks[coord]
	var blocks: Dictionary = {}
	var ox: int = coord.x * 16
	var oz: int = coord.y * 16
	for gz in range(floori((oz - TREE_APRON) / float(TREE_GRID)), floori((oz + 15 + TREE_APRON) / float(TREE_GRID)) + 1):
		for gx in range(floori((ox - TREE_APRON) / float(TREE_GRID)), floori((ox + 15 + TREE_APRON) / float(TREE_GRID)) + 1):
			var tree: Dictionary = tree_at_grid(gx, gz)
			if not tree.is_empty():
				_stamp_tree(blocks, coord, tree)
	for z in range(oz, oz + 16):
		for x in range(ox, ox + 16):
			var col: Dictionary = column(x, z)
			var p = Vector3i(x, int(col.height) + 1, z)
			if p.y <= SEA_LEVEL or blocks.has(p) or block_at(x, p.y - 1, z, col) == 0:
				continue
			var h: int = _hash(x, 641, z)
			var chance: float = float(h % 10000) / 10000.0
			if int(col.surface) in [1, 47] and chance < float(col.flower_density):
				blocks[p] = 166
			elif int(col.surface) in [1, 47] and chance < float(col.flower_density) + float(col.grass_density):
				blocks[p] = 165
			elif str(col.biome) == "Desert" and h % 277 == 0:
				for y in range(2 + ((h >> 8) % 3)):
					blocks[p + Vector3i(0, y, 0)] = 95
			elif str(col.biome) == "Permafrost" and h % 181 == 0:
				for y in range(2 + ((h >> 8) % 4)):
					blocks[p + Vector3i(0, y, 0)] = 88
			elif str(col.biome) in ["Old-Growth Forests", "Dense Spruce Forest", "Swamp"] and h % 73 == 0:
				blocks[p] = 144 if h % 2 == 0 else 143
	if decoration_chunks.size() > 1500:
		decoration_chunks.clear()
	decoration_chunks[coord] = blocks
	return blocks

func decoration_at(p: Vector3i) -> int:
	var col: Dictionary = column(p.x, p.z)
	# A crown may overhang a valley much lower than its root. Only the global
	# ceiling is safe here; a local height cutoff would disagree with stamping.
	if p.y <= int(col.height) or p.y >= MAX_Y:
		return -1
	var coord = Vector2i(floori(p.x / 16.0), floori(p.z / 16.0))
	return int(prepare_decorations(coord).get(p, -1))

func decorate_chunk(data, coord: Vector2i, min_y: int = MIN_Y, max_y: int = MAX_Y) -> void:
	var blocks: Dictionary = prepare_decorations(coord)
	for p: Vector3i in blocks:
		if p.y >= min_y and p.y < max_y:
			var index: int = posmod(p.x, 16) + posmod(p.z, 16) * 16 + (p.y - min_y) * 256
			if index < data.size():
				data[index] = int(blocks[p])

func _stamp_tree(blocks: Dictionary, coord: Vector2i, tree: Dictionary) -> void:
	var p: Vector3i = tree.position
	var height: int = tree.height
	var species: String = tree.species
	var leaf: int = tree.leaf
	var log_id: int = tree.log
	if species in ["spruce", "tall_spruce"]:
		for y in range(3, height + 2):
			var radius: int = clampi(ceili((height + 1 - y) / 3.5), 0, 3)
			if y % 3 == 0 and radius > 1:
				radius -= 1
			_leaf_disc(blocks, coord, p + Vector3i(0, y, 0), radius, leaf)
	elif species == "acacia":
		var direction = Vector3i(1 if int(tree.hash) % 2 == 0 else -1, 0, 0)
		for step in range(3):
			_stamp(blocks, coord, p + direction * step + Vector3i(0, height - 1, 0), log_id)
		_leaf_disc(blocks, coord, p + direction * 2 + Vector3i(0, height, 0), 3, leaf)
		_leaf_disc(blocks, coord, p + direction * 2 + Vector3i(0, height + 1, 0), 2, leaf)
	else:
		var radius: int = 4 if species == "old_growth" else (2 if species == "birch" else 3)
		for y in range(height - 3, height + 2):
			var r: int = radius - (1 if y == height - 3 or y == height + 1 else 0)
			_leaf_disc(blocks, coord, p + Vector3i(0, y, 0), r, leaf)
	# Logs always win over leaves, independently of the root traversal order.
	for dz in range(int(tree.thickness)):
		for dx in range(int(tree.thickness)):
			var ground: int = int(column(p.x + dx, p.z + dz).height) + 1
			for y in range(ground, p.y + height):
				_stamp(blocks, coord, Vector3i(p.x + dx, y, p.z + dz), log_id)

func _leaf_disc(blocks: Dictionary, coord: Vector2i, p: Vector3i, radius: int, id: int) -> void:
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dz * dz <= radius * radius + 1:
				_stamp(blocks, coord, p + Vector3i(dx, 0, dz), id)

func _stamp(blocks: Dictionary, coord: Vector2i, p: Vector3i, id: int) -> void:
	if p.x < coord.x * 16 or p.x >= coord.x * 16 + 16 or p.z < coord.y * 16 or p.z >= coord.y * 16 + 16 or p.y >= MAX_Y:
		return
	if p.y <= maxi(int(column(p.x, p.z).height), SEA_LEVEL):
		return
	if blocks.has(p) and int(blocks[p]) in LOG_IDS and id not in LOG_IDS:
		return
	blocks[p] = id

func _hash(x: int, y: int, z: int) -> int:
	var value: int = (x * 374761393 + y * 668265263 + z * 2147483647 + world_seed * 144269) & 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	return (value ^ (value >> 16)) & 0x7fffffff
