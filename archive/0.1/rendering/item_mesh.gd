class_name HeldItemMesh
extends RefCounted
## A pixel sprite with real depth: front/back pixels and only exposed perimeter
## edges. One cached mesh and material per item, never one node per pixel.

const DEPTH: float = 0.055
static var _meshes: Dictionary = {}

static func for_item(id: int) -> ArrayMesh:
	if _meshes.has(id):
		return _meshes[id]
	var texture: Texture2D = ItemGlyphs.texture_for(id)
	var image: Image = texture.get_image()
	var mesh: ArrayMesh = from_image(image)
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.vertex_color_use_as_albedo = true
	# Sprite palettes already contain their own deliberate highlights and shadows.
	# Contour faces supply extra directional shade without muddying the pixel art.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.roughness = 1.0
	mesh.surface_set_material(0, material)
	_meshes[id] = mesh
	return mesh

static func from_image(image: Image) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var width: int = image.get_width()
	var height: int = image.get_height()
	var pixel: float = 1.0 / float(maxi(width, height))
	var dimensions := Vector3(width * pixel, height * pixel, DEPTH)
	var neighbors: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]
	var shades: Array[float] = [0.64, 0.78, 0.96, 0.56, 1.0, 0.90]
	for y in range(height):
		for x in range(width):
			if not _opaque(image, x, y):
				continue
			var origin := Vector3(x * pixel, (height - y - 1) * pixel, 0.0) - dimensions * 0.5
			for face in range(6):
				if face < 4 and _opaque(image, x + neighbors[face].x, y + neighbors[face].y):
					continue
				var start: int = vertices.size()
				for corner in range(4):
					var unit: Vector3 = VoxelChunkMesh.CORNERS[face][corner]
					vertices.append(origin + unit * Vector3(pixel, pixel, DEPTH))
					normals.append(VoxelChunkMesh.NORMALS[face])
					# Front/back map directly to the source sprite (y is inverted
					# in 3D). Edges sample the middle of their owning pixel.
					if face >= 4:
						uvs.append(Vector2((x + unit.x) / width, (y + 1.0 - unit.y) / height))
					else:
						uvs.append(Vector2((x + 0.5) / width, (y + 0.5) / height))
					var shade: float = shades[face]
					colors.append(Color(shade, shade, shade, 1.0))
				for index in [0, 2, 1, 0, 3, 2]:
					indices.append(start + index)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _opaque(image: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height() and image.get_pixel(x, y).a >= 0.5
