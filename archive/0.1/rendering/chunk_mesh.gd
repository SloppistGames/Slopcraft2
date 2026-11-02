class_name VoxelChunkMesh
extends RefCounted

const DIRECTIONS = [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(0,0,1), Vector3i(0,0,-1)]
const NORMALS = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
const CORNERS = [
	[Vector3(1,0,0), Vector3(1,1,0), Vector3(1,1,1), Vector3(1,0,1)],
	[Vector3(0,0,1), Vector3(0,1,1), Vector3(0,1,0), Vector3(0,0,0)],
	[Vector3(0,1,1), Vector3(1,1,1), Vector3(1,1,0), Vector3(0,1,0)],
	[Vector3(0,0,0), Vector3(1,0,0), Vector3(1,0,1), Vector3(0,0,1)],
	[Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1), Vector3(0,0,1)],
	[Vector3(0,0,0), Vector3(0,1,0), Vector3(1,1,0), Vector3(1,0,0)]
]
const SHADES = [0.84, 0.79, 1.0, 0.55, 0.90, 0.72]

# The same mesher can complete synchronously at spawn or yield between layers
# during exploration. No background thread touches the scene tree or noise caches.
var world
var coord = Vector2i.ZERO
var blocks = PackedInt32Array()
var verts: Array = []
var normals: Array = []
var colors: Array = []
var uvs: Array = []
var indices: Array = []
var collision = PackedVector3Array()
var layer = 0

static func build(source, chunk_coord: Vector2i, data: PackedInt32Array) -> Node3D:
	var job = VoxelChunkMesh.new()
	job.begin(source,chunk_coord,data)
	job.step(-1)
	return job.finish()

func begin(source, chunk_coord: Vector2i, data: PackedInt32Array) -> void:
	BlockAtlas.prepare()
	world = source
	coord = chunk_coord
	blocks = data
	verts = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	normals = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	colors = [PackedColorArray(), PackedColorArray(), PackedColorArray()]
	uvs = [PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
	indices = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	collision = PackedVector3Array()
	layer = 0

func step(budget_usec: int = 4000) -> bool:
	var started = Time.get_ticks_usec()
	while layer < world.HEIGHT:
		_append_layer(layer)
		layer += 1
		if budget_usec > 0 and Time.get_ticks_usec()-started >= budget_usec:
			return layer >= world.HEIGHT
	return true

func _append_layer(y: int) -> void:
	for z in range(16):
		for x in range(16):
			var id = blocks[x + z * 16 + y * 256]
			if id == 0:
				continue
			var group = 1 if id in [9, 16] else (2 if id in [20, 22, 28, 29, 30, 70, 90, 145, 146] else 0)
			var solid = world.is_solid(id)
			var origin = Vector3(x, y, z)
			for f in range(6):
				var n: Vector3i = Vector3i(x, y, z) + DIRECTIONS[f]
				var neighbor = 0
				if n.y >= 0 and n.y < world.HEIGHT and n.x >= 0 and n.x < 16 and n.z >= 0 and n.z < 16:
					neighbor = blocks[n.x + n.z * 16 + n.y * 256]
				else:
					neighbor = world.get_block(Vector3i(n.x + coord.x * 16, n.y, n.z + coord.y * 16))
				if neighbor != 0 and (world.is_solid(neighbor) and not world.is_transparent(neighbor) or neighbor == id):
					continue
				var start: int = verts[group].size()
				var rect = BlockAtlas.tile_rect(id, f)
				var uv = [Vector2(rect.position.x, rect.end.y), rect.position, Vector2(rect.end.x, rect.position.y), rect.end]
				var tint = Color(SHADES[f], SHADES[f], SHADES[f])
				var points: Array = []
				for i in range(4):
					var p: Vector3 = origin + CORNERS[f][i]
					if id == 9 and CORNERS[f][i].y > 0 and world.get_block(Vector3i(x + coord.x * 16, y+1, z + coord.y * 16)) != 9:
						p.y -= 0.12
					points.append(p)
					verts[group].append(p)
					normals[group].append(NORMALS[f])
					colors[group].append(tint)
					uvs[group].append(uv[i])
				for i in [0, 2, 1, 0, 3, 2]:
					indices[group].append(start + i)
					if solid:
						collision.append(points[i])

func finish() -> Node3D:
	var chunk = Node3D.new()
	chunk.name = "Chunk_%s_%s" % [coord.x, coord.y]
	chunk.position = Vector3(coord.x * 16, 0, coord.y * 16)
	var mesh = ArrayMesh.new()
	for group in range(3):
		if verts[group].is_empty():
			continue
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts[group]
		arrays[Mesh.ARRAY_NORMAL] = normals[group]
		arrays[Mesh.ARRAY_COLOR] = colors[group]
		arrays[Mesh.ARRAY_TEX_UV] = uvs[group]
		arrays[Mesh.ARRAY_INDEX] = indices[group]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count()-1, BlockAtlas.materials[group])
	var display = MeshInstance3D.new()
	display.mesh = mesh
	chunk.add_child(display)
	if not collision.is_empty():
		var body = StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape_node = CollisionShape3D.new()
		var shape = ConcavePolygonShape3D.new()
		shape.set_faces(collision)
		shape_node.shape = shape
		body.add_child(shape_node)
		chunk.add_child(body)
	return chunk
