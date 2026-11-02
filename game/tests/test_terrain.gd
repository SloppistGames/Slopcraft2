extends SceneTree

const Generator = preload("res://world/terrain_generator.gd")
var checks: int = 0
var failures: int = 0
var samples: Dictionary = {}

func _init() -> void:
	var started: int = Time.get_ticks_msec()
	var terrain = Generator.new()
	terrain.setup(87023)
	var twin = Generator.new()
	twin.setup(87023)
	var alternate = Generator.new()
	alternate.setup(87024)
	var counts: Dictionary = {}
	var max_height: int = -1000
	var min_height: int = 1000
	var continuity_total: int = 0
	var continuity_same: int = 0
	var divergent: int = 0
	var ponds: int = 0
	var entrances: int = 0
	for z in range(-8000, 8001, 64):
		for x in range(-8000, 8001, 64):
			var col: Dictionary = terrain.column(x, z)
			var biome: String = col.biome
			counts[biome] = int(counts.get(biome, 0)) + 1
			if not samples.has(biome):
				samples[biome] = Vector2i(x, z)
			max_height = maxi(max_height, int(col.height))
			min_height = mini(min_height, int(col.height))
			if float(col.pond) > 0.95 and float(col.river) < 0.10 and float(col.continentalness) > 0.05 and int(col.height) < Generator.SEA_LEVEL:
				ponds += 1
			if bool(col.entrance) and terrain.block_at(x, int(col.height), z, col) == 0:
				entrances += 1
			if posmod(x, 512) == 0 and posmod(z, 512) == 0:
				check(col == twin.column(x, z), "identical seeded column at %s" % Vector2i(x, z))
				if int(alternate.column(x, z).height) != int(col.height):
					divergent += 1
				continuity_total += 1
				if str(terrain.column(x + 12, z + 12).biome) == biome:
					continuity_same += 1
	for biome in Generator.SURFACE_BIOMES:
		check(counts.has(biome), "reachable biome: " + biome)
	check(max_height >= 145 and max_height <= 160, "connected mountains reach 145..160: %d" % max_height)
	check(min_height < Generator.SEA_LEVEL - 10, "continental seafloor below coast")
	check(divergent > 100, "changing seed changes terrain")
	check(float(continuity_same) / maxi(1, continuity_total) > 0.68, "biomes coherent at 12-block diagonal: %.3f" % (float(continuity_same) / maxi(1, continuity_total)))
	check(terrain.column(8, 8).height > Generator.SEA_LEVEL, "spawn above sea")
	check(ponds > 5, "inland ponds generate independently of river channels: %d" % ponds)
	check(entrances > 2, "natural cave openings reach surface: %d" % entrances)
	print("BIOMES ", counts)
	print("BIOME_SAMPLES ", samples)
	print("HEIGHT_RANGE ", min_height, "..", max_height)
	print("REGIONAL_COHERENCE ", float(continuity_same) / maxi(1, continuity_total), "; INLAND_PONDS ", ponds, "; SURFACE_ENTRANCES ", entrances)
	_test_seams(terrain, twin)
	_test_depths(terrain)
	_test_caves_and_ores(terrain)
	_test_decorations(terrain, twin)
	var elapsed: int = Time.get_ticks_msec() - started
	print("TERRAIN: ", checks, " checks; ", failures, " failures; ", elapsed, " ms")
	quit(0 if failures == 0 else 1)

func _test_seams(terrain, twin) -> void:
	var largest_step: int = 0
	for edge in [-1024, -512, -16, 0, 16, 512, 1024]:
		for offset in range(-16, 17):
			var x: int = edge + offset
			var z: int = edge * 3 - offset
			var col: Dictionary = terrain.column(x, z)
			largest_step = maxi(largest_step, absi(int(col.height) - int(terrain.column(x + 1, z).height)))
			for y in [-176, -175, -166, -130, -80, -76, -70, -20, 0, 23, 50, 160]:
				check(terrain.block_at(x, y, z, col) == twin.block_at(x, y, z), "seed and uncached query agree across signed seam")
	check(largest_step <= 7, "adjacent height continuity at seams: %d" % largest_step)
	var reverse = Generator.new()
	reverse.setup(87023)
	for x in range(128, -129, -1):
		reverse.column(x, -16)
	for x in range(-128, 129):
		check(reverse.column(x, -16) == terrain.column(x, -16), "column result independent of traversal order")

func _test_depths(terrain) -> void:
	var upper_stone: int = 0
	var lower_slate: int = 0
	for z in range(-256, 257, 11):
		for x in range(-256, 257, 11):
			var col: Dictionary = terrain.column(x, z)
			check(terrain.block_at(x, -176, z, col) == 10, "continuous bottom bedrock")
			var above: int = terrain.block_at(x, -65, z, col)
			var below: int = terrain.block_at(x, -87, z, col)
			if above == 3:
				upper_stone += 1
			if below == 58:
				lower_slate += 1
	check(upper_stone > 500, "stone above transition")
	check(lower_slate > 500, "deepslate below transition")
	check(Generator.SEA_LEVEL - Generator.MIN_Y == 199, "reference surface has 199 blocks to bedrock")

func _test_caves_and_ores(terrain) -> void:
	var cave_air: Dictionary = {}
	var ores: Dictionary = {}
	var sulfur_wall: int = 0
	var liquid: int = 0
	var largest_vast_span: int = 0
	for z in range(-1400, 1401, 40):
		for x in range(-1400, 1401, 40):
			var col: Dictionary = terrain.column(x, z)
			var span: int = 0
			for y in range(-169, mini(45, int(col.height) - 6)):
				var id: int = terrain.block_at(x, y, z, col)
				if id in [0, 9, 20]:
					var cave: String = terrain.cave_biome_at(Vector3(x, y, z))
					cave_air[cave] = int(cave_air.get(cave, 0)) + 1
					if cave == "Vast Cave Systems":
						span += 1
						largest_vast_span = maxi(span, largest_vast_span)
					else:
						span = 0
					if id in [9, 20]:
						liquid += 1
				else:
					span = 0
				if id in [11,12,13,14,73,74,75,76,170,171,172,173,174,175,152]:
					ores[id] = int(ores.get(id, 0)) + 1
				if id in [151,176]:
					sulfur_wall += 1
				if id in [14,173]:
					check(y < -94 and y > -172, "diamond deep distribution")
				if id in [170,171,172,173,174,175]:
					check(y <= int(col.deepslate_top), "deepslate ore in deepslate geology")
	for cave in Generator.CAVE_BIOMES:
		check(int(cave_air.get(cave, 0)) > 20, "actual carved air in " + cave)
	for id in [11,12,13,73,75,76,170,171,172,173,174,175,152]:
		check(ores.has(id), "ore generated: %d" % id)
	check(largest_vast_span >= 24, "vast chambers have tall connected air: %d" % largest_vast_span)
	check(sulfur_wall > 30, "sulfur minerals line cave walls")
	check(liquid > 20, "deep cave aquifers and lava")
	print("CAVE_AIR ", cave_air, "; VAST_MAX_SPAN ", largest_vast_span, "; ORES ", ores)

func _test_decorations(terrain, twin) -> void:
	var species: Dictionary = {}
	var roots: int = 0
	var leaves: int = 0
	for biome in ["Oak Forest", "Birch Forest", "Dense Spruce Forest", "Old-Growth Forests", "Savanna", "Snowy Forest", "Meadow", "Flower Fields"]:
		if not samples.has(biome):
			continue
		var sample: Vector2i = samples[biome]
		var coord = Vector2i(floori(sample.x / 16.0), floori(sample.y / 16.0))
		var blocks: Dictionary = terrain.prepare_decorations(coord)
		check(blocks == twin.prepare_decorations(coord), "deterministic decorated chunk: " + biome)
		var neighborhood: Dictionary = {}
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				neighborhood.merge(terrain.prepare_decorations(coord + Vector2i(dx, dz)))
		var supported: Dictionary = {}
		var frontier: Array[Vector3i] = []
		for p: Vector3i in neighborhood:
			if int(neighborhood[p]) in Generator.LOG_IDS:
				frontier.append(p)
				supported[p] = true
		var cursor: int = 0
		while cursor < frontier.size():
			var p: Vector3i = frontier[cursor]
			cursor += 1
			for d in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.UP,Vector3i.DOWN,Vector3i.FORWARD,Vector3i.BACK]:
				var q: Vector3i = p + d
				if not supported.has(q) and int(neighborhood.get(q, -1)) in [6,32,34,39,42]:
					supported[q] = true
					frontier.append(q)
		var buffer = PackedInt32Array()
		buffer.resize(16 * 16 * (Generator.MAX_Y - Generator.MIN_Y))
		terrain.decorate_chunk(buffer, coord)
		for p: Vector3i in blocks:
			check(terrain.decoration_at(p) == int(blocks[p]), "decoration direct query matches cached chunk")
			var index: int = posmod(p.x, 16) + posmod(p.z, 16) * 16 + (p.y - Generator.MIN_Y) * 256
			check(buffer[index] == int(blocks[p]), "decorator uses negative-y buffer offset")
			if int(blocks[p]) in [6,32,34,39,42]:
				leaves += 1
				check(supported.has(p), "every central leaf component connects to a rooted log across chunk seams")
				var attached: bool = false
				for d in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.UP,Vector3i.DOWN,Vector3i.FORWARD,Vector3i.BACK]:
					var neighbor: int = terrain.decoration_at(p + d)
					if neighbor in [5,31,33,37,40,43,45,6,32,34,39,42]:
						attached = true
				check(attached, "no isolated generated leaf voxel")
		for gz in range(floori(sample.y / 7.0) - 4, floori(sample.y / 7.0) + 5):
			for gx in range(floori(sample.x / 7.0) - 4, floori(sample.x / 7.0) + 5):
				var tree: Dictionary = terrain.tree_at_grid(gx, gz)
				if tree.is_empty():
					continue
				species[tree.species] = true
				var p: Vector3i = tree.position
				var col: Dictionary = terrain.column(p.x, p.z)
				check(p.y == int(col.height) + 1 and terrain.block_at(p.x, p.y - 1, p.z, col) != 0, "tree rooted at true solid surface")
				roots += 1
	check(roots > 20 and leaves > 50, "trees and foliage actually generated")
	for type in ["oak", "birch", "tall_spruce", "old_growth", "acacia"]:
		check(species.has(type), "distinct tree species: " + type)
	print("TREE_SPECIES ", species, "; ROOTS ", roots, "; LEAVES ", leaves)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
