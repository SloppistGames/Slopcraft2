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
var base_y = 0
var end_y = 80
var start_y = 0
var opaque: Dictionary = {}
var include_collision = true
var partial: Dictionary = {}
var torch_cells: Array[Vector3i] = []
var circuit_cells: Array[Vector3i] = []

static func build(source, chunk_coord: Vector2i, data: PackedInt32Array) -> Node3D:
	var job = VoxelChunkMesh.new()
	job.begin(source,chunk_coord,data)
	job.step(-1)
	return job.finish()

func begin(source, chunk_coord: Vector2i, data: PackedInt32Array) -> void:
	BlockAtlas.prepare()
	_ensure_materials()
	world = source
	coord = chunk_coord
	blocks = data
	verts = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	normals = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	colors = [PackedColorArray(), PackedColorArray(), PackedColorArray(), PackedColorArray()]
	uvs = [PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
	indices = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	collision = PackedVector3Array()
	include_collision = world.want_collision(coord)
	base_y = world.min_y()
	start_y = world.mesh_min_y(coord)
	end_y = world.mesh_max_y(coord)
	layer = start_y
	opaque.clear()
	partial.clear()
	torch_cells.clear()
	circuit_cells.clear()
	for id in world.solid_flags:
		opaque[id] = world.is_solid(id) and not world.is_transparent(id) and id!=183
		partial[id] = BlockShapes.is_partial(id)

func step(budget_usec: int = 4000) -> bool:
	var started = Time.get_ticks_usec()
	while layer < end_y:
		_append_layer(layer)
		layer += 1
		if budget_usec > 0 and Time.get_ticks_usec()-started >= budget_usec:
			return layer >= end_y
	return true

func _append_layer(y: int) -> void:
	for z in range(16):
		for x in range(16):
			var id = blocks[x+z*16+(y-base_y)*256]
			if id == 0: continue
			var local = Vector3i(x,y,z)
			var cell = local+Vector3i(coord.x*16,0,coord.y*16)
			if id in [28,84,155,156,157,158,159,160,161,162,163,164,177,178,179,180,183]: circuit_cells.append(cell)
			if id in [28,164]:
				_append_torch(local,id,world.get_block_state(cell))
				torch_cells.append(cell)
				continue
			if id in [165,166,168]:
				_append_plant(local,id)
				continue
			if id in [9,20]:
				_append_fluid(local,id)
				continue
			if id in [181,182]:
				_append_bed(local,id,world.get_block_state(cell))
				continue
			if id in [155,156,157,177,178,179]:
				_append_circuit(local,id,world.get_block_state(cell))
				continue
			if id in [25,26,27,91,93,94,159,160,161,162,163,183]:
				_append_oriented(local,id,world.get_block_state(cell))
				continue
			var group = 1 if id in [9,16] else (2 if id in [20,22,29,30,70,90,145,146] else 0)
			if id==158 and bool(world.get_block_state(cell).get("powered",false)): group=2
			if id==158: torch_cells.append(cell)
			var solid = world.is_solid(id)
			if partial.get(id,false):
				_append_shape(local,cell,id,world.get_block_state(cell),group)
				continue
			for face in 6:
				var neighbor = _neighbor(local+DIRECTIONS[face])
				if neighbor != 0 and (opaque.get(neighbor,false) or neighbor==id): continue
				if partial.get(neighbor,false):
					var state: Dictionary = world.get_block_state(cell+DIRECTIONS[face])
					for patch in BlockShapes.face_patches(face):
						var center: Vector3 = (patch[0]+patch[2])*0.5
						if not _covered(neighbor,state,center,face):
							_append_quad(Vector3(local),patch,face,id,group,solid)
				else:
					var points: Array = CORNERS[face].duplicate()
					_append_quad(Vector3(local),points,face,id,group,solid)

func _ensure_materials() -> void:
	if BlockAtlas.materials[0] is StandardMaterial3D:
		BlockAtlas.materials[0].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		BlockAtlas.materials[0].alpha_scissor_threshold = 0.5
	if BlockAtlas.materials.size()<4:
		var plants = StandardMaterial3D.new()
		plants.albedo_texture = BlockAtlas.texture
		plants.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		plants.vertex_color_use_as_albedo = true
		plants.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		plants.alpha_scissor_threshold = 0.5
		plants.cull_mode = BaseMaterial3D.CULL_DISABLED
		plants.roughness = 1.0
		BlockAtlas.materials.append(plants)

func _append_plant(local: Vector3i,id: int) -> void:
	var height = 0.9 if id==168 else (0.8 if id==166 else 0.85)
	var panels = [
		[Vector3(0.1,0,0.1),Vector3(0.1,height,0.1),Vector3(0.9,height,0.9),Vector3(0.9,0,0.9)],
		[Vector3(0.9,0,0.1),Vector3(0.9,height,0.1),Vector3(0.1,height,0.9),Vector3(0.1,0,0.9)]
	]
	for points in panels:
		var normal: Vector3 = (points[1]-points[0]).cross(points[2]-points[0]).normalized()
		_append_quad(Vector3(local),points,5,id,3,false,normal,true)

func _fluid_height(local: Vector3i,id: int) -> float:
	if _neighbor(local+Vector3i.UP)==id: return 1.0
	var state: Dictionary = world.get_block_state(local+Vector3i(coord.x*16,0,coord.y*16))
	if bool(state.get("fluid_falling",false)): return 1.0
	var level = int(state.get("fluid_level",0))
	if id==20: return 1.0 if level==0 else maxf(0.25,1.0-level/4.0)
	return 0.875 if level==0 else maxf(0.125,1.0-level/8.0)

func _append_fluid(local: Vector3i,id: int) -> void:
	var height = _fluid_height(local,id)
	for face in 6:
		var adjacent = local+DIRECTIONS[face]
		var neighbor = _neighbor(adjacent)
		if opaque.get(neighbor,false): continue
		var bottom = 0.0
		if neighbor==id:
			if face in [2,3]: continue
			bottom = _fluid_height(adjacent,id)
			if bottom>=height: continue
		var points: Array = []
		for point in CORNERS[face]:
			points.append(Vector3(point.x,bottom+(height-bottom)*point.y,point.z))
		_append_quad(Vector3(local),points,face,id,1 if id==9 else 2,false)

func _neighbor(p: Vector3i) -> int:
	if p.x>=0 and p.x<16 and p.z>=0 and p.z<16 and p.y>=start_y and p.y<end_y:
		return blocks[p.x+p.z*16+(p.y-base_y)*256]
	return world.get_block(p+Vector3i(coord.x*16,0,coord.y*16))

func _covered(id: int,state: Dictionary,center: Vector3,face: int) -> bool:
	var point = center-Vector3(DIRECTIONS[face])+Vector3(DIRECTIONS[face])*0.001
	return BlockShapes.contains(id,state,point)

func _append_shape(local: Vector3i,cell: Vector3i,id: int,state: Dictionary,group: int) -> void:
	for panel in BlockShapes.faces(id,state):
		var face: int = panel.face
		if panel.boundary:
			var neighbor = _neighbor(local+DIRECTIONS[face])
			if opaque.get(neighbor,false): continue
			if partial.get(neighbor,false) and _covered(neighbor,world.get_block_state(cell+DIRECTIONS[face]),panel.center,face): continue
		_append_quad(Vector3(local),panel.points,face,id,group,true)

func _part(local: Vector3i,box: AABB,id: int,group: int,solid: bool,turn: Basis = Basis.IDENTITY,tint: Color = Color.WHITE) -> void:
	for face in 6:
		var points: Array = []
		for p in CORNERS[face]: points.append(turn*(box.position+p*box.size-Vector3(.5,0,.5))+Vector3(.5,0,.5))
		var start=colors[group].size()
		_append_quad(Vector3(local),points,face,id,group,solid,turn*NORMALS[face],true)
		for v in range(start,colors[group].size()): colors[group][v]*=tint

func _append_oriented(local: Vector3i,id: int,state: Dictionary) -> void:
	var turn=Basis(Vector3.UP,-posmod(int(state.get("rotation",0)),4)*PI*.5)
	if id==183:
		_part(local,AABB(Vector3(0,0,0),Vector3(1,1,.25)),id,0,true,turn)
		_part(local,AABB(Vector3(.375,.375,.25),Vector3(.25,.25,.75)),id,0,true,turn)
	else:
		for face in 6:
			var normal=turn*NORMALS[face]
			var adjacent=Vector3i(roundi(normal.x),roundi(normal.y),roundi(normal.z))
			if opaque.get(_neighbor(local+adjacent),false): continue
			var points: Array=[]
			for p in CORNERS[face]: points.append(turn*(p-Vector3(.5,0,.5))+Vector3(.5,0,.5))
			_append_quad(Vector3(local),points,face,id,0,true,normal,true)

func _append_circuit(local: Vector3i,id: int,state: Dictionary) -> void:
	var turn=Basis(Vector3.UP,-posmod(int(state.get("rotation",0)),4)*PI*.5)
	var power=clampi(int(state.get("power",0)),0,15)
	if id==155:
		var group=2 if power>0 else 0
		var tint=Color.WHITE if power>0 else Color(.45,.35,.35)
		_part(local,AABB(Vector3(.375,.008,.375),Vector3(.25,.025,.25)),84,group,false,Basis.IDENTITY,tint)
		for link in state.get("connections",[]):
			var d=Vector3(float(link[0]),0,float(link[2]))
			var origin=Vector3(.375,.008,.375)+Vector3(minf(d.x,0)*.375,0,minf(d.z,0)*.375)
			var size=Vector3(.25+absf(d.x)*.375,.025,.25+absf(d.z)*.375)
			_part(local,AABB(origin,size),84,group,false,Basis.IDENTITY,tint)
			if int(link[1])>0:
				_part(local,AABB(Vector3(.375,.025,.375)+d*.48,Vector3(.13,.975,.13)),84,group,false,Basis.IDENTITY,tint)
		return
	var size=Vector3(.75,.12,.75)
	if id==177: size=Vector3(.4,.08 if power>0 else .16,.3)
	if id==178: size=Vector3(.88,.035 if power>0 else .09,.88)
	_part(local,AABB(Vector3(.5,0,.5)-Vector3(size.x,0,size.z)*.5,size),id,0,false,turn)
	if id==156:
		_part(local,AABB(Vector3(.44,.12,.40 if state.get("on",false) else .53),Vector3(.12,.32,.12)),5,0,false,turn)
	elif id in [157,179]:
		for z in [.24,.72]:
			_part(local,AABB(Vector3(.44,.12,z),Vector3(.12,.20,.12)),164,2 if power>0 else 0,false,turn)

func _append_bed(local: Vector3i,id: int,state: Dictionary) -> void:
	var turn = Basis(Vector3.UP,-posmod(int(state.get("rotation",0)),4)*PI*0.5)
	# UVs follow the bed's local length/width, then geometry rotates into the world.
	# Generic cube top UVs run sideways and put the pillow along a long edge.
	var boxes = BlockShapes.boxes(id,{})
	for index in boxes.size():
		var box: AABB = boxes[index]
		for face in 6:
			var points: Array = []
			var texture_points: Array = []
			for corner in CORNERS[face]:
				var p: Vector3 = box.position+corner*box.size
				points.append(turn*(p-Vector3(.5,0,.5))+Vector3(.5,0,.5))
				texture_points.append(Vector2(p.x,p.z) if face==2 and index==0 else BlockShapes.face_uv(p,face))
			_append_quad(Vector3(local),points,face if index==0 else 3,id,0,true,turn*NORMALS[face],false,texture_points)

func _append_torch(local: Vector3i,id: int,state: Dictionary) -> void:
	for face in 6:
		var points: Array = []
		for p in CORNERS[face]: points.append(BlockShapes.torch_point(p,state))
		var normal: Vector3 = (points[1]-points[0]).cross(points[2]-points[0]).normalized()
		# Model texture uses its complete narrow shaft artwork, while stairs and
		# slabs crop UVs at half blocks to preserve the base material pixel scale.
		_append_quad(Vector3(local),points,face,id,2,false,normal,true)

func _append_quad(origin: Vector3,points: Array,face: int,id: int,group: int,solid: bool,normal: Vector3 = Vector3.ZERO,full_uv: bool = false,texture_points: Array = []) -> void:
	var start: int = verts[group].size()
	var rect = BlockAtlas.tile_rect(id,face)
	var tint = Color(SHADES[face],SHADES[face],SHADES[face])
	var full = [Vector2(0,1),Vector2(0,0),Vector2(1,0),Vector2(1,1)]
	for i in 4:
		verts[group].append(origin+points[i])
		normals[group].append(NORMALS[face] if normal==Vector3.ZERO else normal)
		colors[group].append(tint)
		var uv: Vector2 = texture_points[i] if not texture_points.is_empty() else (full[i] if full_uv else BlockShapes.face_uv(points[i],face))
		uvs[group].append(rect.position+uv*rect.size)
	for i in [0,2,1,0,3,2]:
		indices[group].append(start+i)
		if solid and include_collision: collision.append(origin+points[i])

func finish() -> Node3D:
	var chunk = Node3D.new()
	chunk.name = "Chunk_%s_%s" % [coord.x, coord.y]
	chunk.set_meta("has_collision",include_collision)
	chunk.set_meta("torch_cells",torch_cells.duplicate())
	chunk.set_meta("circuit_cells",circuit_cells.duplicate())
	chunk.position = Vector3(coord.x * 16, 0, coord.y * 16)
	var mesh = ArrayMesh.new()
	for group in range(4):
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
