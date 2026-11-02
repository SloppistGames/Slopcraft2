class_name TerrainLOD
extends RefCounted

# Each 64x64 tile has at most 128 triangles per material. Far terrain never
# allocates voxels, structures, physics bodies, or underground geometry.
static func build(world,tile: Vector2i) -> Node3D:
	var node = Node3D.new()
	node.name = "Horizon_%d_%d" % [tile.x,tile.y]
	node.position = Vector3(tile.x*64,0,tile.y*64)
	var vertices = [PackedVector3Array(),PackedVector3Array()]
	var normals = [PackedVector3Array(),PackedVector3Array()]
	var colors = [PackedColorArray(),PackedColorArray()]
	var uvs = [PackedVector2Array(),PackedVector2Array()]
	var indices = [PackedInt32Array(),PackedInt32Array()]
	var samples: Dictionary = {}
	for cz in range(4):
		for cx in range(4):
			var coord = tile*4+Vector2i(cx,cz)
			if world.has_detailed_visual(coord) or world._distance(coord,world.focus_chunk)>world.render_distance:
				continue
			for z in range(cz*16,cz*16+16,8):
				for x in range(cx*16,cx*16+16,8):
					var locations = [Vector2i(x,z),Vector2i(x+8,z),Vector2i(x+8,z+8),Vector2i(x,z+8)]
					var points: Array[Vector3] = []
					var first_col: Dictionary = {}
					var missing = false
					for location in locations:
						if not samples.has(location):
							samples[location] = world._column(tile.x*64+location.x,tile.y*64+location.y)
						var col: Dictionary = samples[location]
						if first_col.is_empty(): first_col = col
						if int(col.height)<0 and world.dimension == "end": missing = true
						var height = float(col.height)+1.0
						if world.dimension == "overworld": height = maxf(height,float(col.get("water_level",world.SEA_LEVEL))+0.88)
						if world.dimension == "nether": height = maxf(height,18.88)
						points.append(Vector3(location.x,height,location.y))
					if missing: continue
					var water = world.dimension == "overworld" and int(first_col.height)<=int(first_col.get("water_level",world.SEA_LEVEL))
					var id = 9 if water else int(first_col.surface)
					var group = 1 if water else 0
					var rect = BlockAtlas.tile_rect(id,2)
					var texcoords = [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
					var normal = (points[3]-points[0]).cross(points[1]-points[0]).normalized()
					var start: int = vertices[group].size()
					for i in range(4):
						vertices[group].append(points[i])
						normals[group].append(normal)
						uvs[group].append(texcoords[i])
						colors[group].append(Color(0.93,0.93,0.93))
					for i in [0,1,2,0,2,3]: indices[group].append(start+i)
	var mesh = ArrayMesh.new()
	for group in range(2):
		if vertices[group].is_empty(): continue
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices[group]
		arrays[Mesh.ARRAY_NORMAL] = normals[group]
		arrays[Mesh.ARRAY_COLOR] = colors[group]
		arrays[Mesh.ARRAY_TEX_UV] = uvs[group]
		arrays[Mesh.ARRAY_INDEX] = indices[group]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(mesh.get_surface_count()-1,BlockAtlas.materials[group])
	if mesh.get_surface_count()>0:
		var display = MeshInstance3D.new()
		display.mesh = mesh
		display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(display)
	return node
