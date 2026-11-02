class_name BlockShapes
extends RefCounted
## Shared placement, picking, rendering, and collision shape vocabulary.
## Rotation zero has its high half at +Z. Each turn maps x,z to 1-z,x.
const DIRS = [Vector3i.RIGHT,Vector3i.LEFT,Vector3i.UP,Vector3i.DOWN,Vector3i.BACK,Vector3i.FORWARD]
const NORMALS = [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]
const CORNERS = [
	[Vector3(1,0,0),Vector3(1,1,0),Vector3(1,1,1),Vector3(1,0,1)],
	[Vector3(0,0,1),Vector3(0,1,1),Vector3(0,1,0),Vector3(0,0,0)],
	[Vector3(0,1,1),Vector3(1,1,1),Vector3(1,1,0),Vector3(0,1,0)],
	[Vector3(0,0,0),Vector3(1,0,0),Vector3(1,0,1),Vector3(0,0,1)],
	[Vector3(1,0,1),Vector3(1,1,1),Vector3(0,1,1),Vector3(0,0,1)],
	[Vector3(0,0,0),Vector3(0,1,0),Vector3(1,1,0),Vector3(1,0,0)]
]
static var _faces: Dictionary = {}
static var _boxes: Dictionary = {}

static func is_partial(id: int) -> bool:
	return id==183 or str(BlockDB.get_block(id).get("shape","")) in ["stair","slab","bed"]

static func boxes(id: int,state: Dictionary = {}) -> Array[AABB]:
	if id in [155,156,157,177,178,179,183]: return _utility_boxes(id,state)
	if id in [28,164]:
		var points: Array[Vector3] = []
		for corner in [Vector3(0,0,0),Vector3(1,0,0),Vector3(0,1,0),Vector3(0,0,1),Vector3(1,1,0),Vector3(1,0,1),Vector3(0,1,1),Vector3(1,1,1)]:
			points.append(torch_point(corner,state))
		var bounds = AABB(points[0],Vector3.ZERO)
		for point in points: bounds = bounds.expand(point)
		return [bounds.grow(0.015)]
	var shape = str(BlockDB.get_block(id).get("shape",""))
	var top = bool(state.get("top",false))
	var rotation = posmod(int(state.get("rotation",0)),4)
	var key = "%s:%d:%d:%d" % [shape,int(top),rotation,id if shape=="bed" else 0]
	if _boxes.has(key): return _boxes[key]
	var result: Array[AABB] = []
	if shape == "bed":
		result.append(AABB(Vector3(0,0.1875,0),Vector3(1,0.375,1)))
		for x in [0.0625,0.8125]:
			var leg = AABB(Vector3(x,0,0.0625 if id==182 else 0.8125),Vector3(.125,.1875,.125))
			for turn in rotation:
				leg=AABB(Vector3(1-leg.end.z,leg.position.y,leg.position.x),Vector3(leg.size.z,leg.size.y,leg.size.x))
			result.append(leg)
	elif shape == "slab":
		result.append(AABB(Vector3(0,0.5 if top else 0,0),Vector3(1,0.5,1)))
	elif shape == "stair":
		result.append(AABB(Vector3(0,0.5 if top else 0,0),Vector3(1,0.5,1)))
		var upper = AABB(Vector3(0,0 if top else 0.5,0.5),Vector3(1,0.5,0.5))
		for turn in rotation:
			upper = AABB(Vector3(1-upper.end.z,upper.position.y,upper.position.x),Vector3(upper.size.z,upper.size.y,upper.size.x))
		result.append(upper)
	else:
		result.append(AABB(Vector3.ZERO,Vector3.ONE))
	_boxes[key] = result
	return result

static func _utility_boxes(id: int,state: Dictionary) -> Array[AABB]:
	var result: Array[AABB]=[]
	var powered=int(state.get("power",0))>0
	if id==183:
		result=[AABB(Vector3.ZERO,Vector3(1,1,.25)),AABB(Vector3(.375,.375,.25),Vector3(.25,.25,.75))]
	elif id==155:
		result.append(AABB(Vector3(.375,.008,.375),Vector3(.25,.025,.25)))
		for link in state.get("connections",[]):
			if not link is Array or link.size()!=3: continue
			var d=Vector3(float(link[0]),0,float(link[2]))
			result.append(AABB(Vector3(.375,.008,.375)+Vector3(minf(d.x,0)*.375,0,minf(d.z,0)*.375),Vector3(.25+absf(d.x)*.375,.025,.25+absf(d.z)*.375)))
			if int(link[1])>0: result.append(AABB(Vector3(.375,.025,.375)+d*.48,Vector3(.13,.975,.13)))
		return result
	else:
		var size=Vector3(.75,.12,.75)
		if id==177: size=Vector3(.4,.08 if powered else .16,.3)
		if id==178: size=Vector3(.88,.035 if powered else .09,.88)
		result.append(AABB(Vector3(.5,0,.5)-Vector3(size.x,0,size.z)*.5,size))
		if id==156: result.append(AABB(Vector3(.44,.12,.40 if state.get("on",false) else .53),Vector3(.12,.32,.12)))
		elif id in [157,179]:
			for z in [.24,.72]: result.append(AABB(Vector3(.44,.12,z),Vector3(.12,.20,.12)))
	for index in result.size():
		var box: AABB=result[index]
		for turn in posmod(int(state.get("rotation",0)),4):
			box=AABB(Vector3(1-box.end.z,box.position.y,box.position.x),Vector3(box.size.z,box.size.y,box.size.x))
		result[index]=box
	return result

static func contains(id: int,state: Dictionary,p: Vector3) -> bool:
	for box in boxes(id,state):
		if box.has_point(p): return true
	return false

static func faces(id: int,state: Dictionary = {}) -> Array:
	var shape = str(BlockDB.get_block(id).get("shape",""))
	if shape == "bed":
		var panels: Array = []
		for box in boxes(id,state):
			for face in 6:
				var points: Array[Vector3] = []
				for corner in CORNERS[face]: points.append(box.position+corner*box.size)
				panels.append({"face":face,"points":points,"center":(points[0]+points[2])*0.5,"boundary":false})
		return panels
	var key = "%s:%d:%d" % [shape,int(bool(state.get("top",false))),posmod(int(state.get("rotation",0)),4)]
	if _faces.has(key): return _faces[key]
	var occupied: Dictionary = {}
	for y in 2:
		for z in 2:
			for x in 2:
				var cell = Vector3i(x,y,z)
				if contains(id,state,(Vector3(cell)+Vector3.ONE*0.5)*0.5): occupied[cell] = true
	var result: Array = []
	for cell in occupied:
		for face in 6:
			if occupied.has(cell+DIRS[face]): continue
			var points: Array[Vector3] = []
			for corner in CORNERS[face]: points.append((Vector3(cell)+corner)*0.5)
			var center = (points[0]+points[2])*0.5
			var axis = 0 if face<2 else (1 if face<4 else 2)
			var boundary = is_equal_approx(center[axis],1.0 if face%2==0 else 0.0)
			result.append({"face":face,"points":points,"center":center,"boundary":boundary})
	_faces[key] = result
	return result

static func face_patches(face: int) -> Array:
	# Four half-face patches align exactly with every slab/stair boundary.
	var result: Array = []
	var a: Vector3 = CORNERS[face][0]
	var b: Vector3 = CORNERS[face][1]
	var d: Vector3 = CORNERS[face][3]
	for v in 2:
		for u in 2:
			var origin = a+(b-a)*u*0.5+(d-a)*v*0.5
			result.append([origin,origin+(b-a)*0.5,origin+(b-a+d-a)*0.5,origin+(d-a)*0.5])
	return result

static func face_uv(p: Vector3,face: int) -> Vector2:
	match face:
		0: return Vector2(p.z,1-p.y)
		1: return Vector2(1-p.z,1-p.y)
		2: return Vector2(1-p.z,1-p.x)
		3: return Vector2(p.z,1-p.x)
		4: return Vector2(1-p.x,1-p.y)
	return Vector2(p.x,1-p.y)

static func wall_normal(state: Dictionary) -> Vector3:
	var value = state.get("wall",[0,1,0])
	if value is Array and value.size()==3:
		var normal = Vector3(float(value[0]),float(value[1]),float(value[2]))
		if absf(normal.x)+absf(normal.z)>0.5:
			return Vector3(signf(normal.x),0,signf(normal.z)).normalized()
	return Vector3.ZERO

static func torch_point(p: Vector3,state: Dictionary) -> Vector3:
	var wall = wall_normal(state)
	var base = Vector3(0.5,0.0,0.5) if wall==Vector3.ZERO else Vector3(0.5,0.2,0.5)-wall*0.4
	return base+Vector3((p.x-0.5)*0.125,p.y*0.7,(p.z-0.5)*0.125)+wall*p.y*0.25

static func torch_tip(state: Dictionary) -> Vector3:
	return torch_point(Vector3(0.5,1,0.5),state)
