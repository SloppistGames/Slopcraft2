class_name CreatureModel
extends Node3D
## Shared pixel atlas, cuboid UV mapping and joint-based creature animation.
const CORNERS: Array = [
	[Vector3(1,0,0),Vector3(1,1,0),Vector3(1,1,1),Vector3(1,0,1)],
	[Vector3(0,0,1),Vector3(0,1,1),Vector3(0,1,0),Vector3(0,0,0)],
	[Vector3(0,1,1),Vector3(1,1,1),Vector3(1,1,0),Vector3(0,1,0)],
	[Vector3(0,0,0),Vector3(1,0,0),Vector3(1,0,1),Vector3(0,0,1)],
	[Vector3(1,0,1),Vector3(1,1,1),Vector3(0,1,1),Vector3(0,0,1)],
	[Vector3(0,0,0),Vector3(0,1,0),Vector3(1,1,0),Vector3(1,0,0)],
]
const NORMALS: Array[Vector3] = [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]
static var textures: Dictionary = {}
var species: String = "pig"
var profession: String = "farmer"
var limbs: Array[Node3D] = []
var head: Node3D
var tail: Node3D
var coat: StandardMaterial3D
var clock: float = 0.0

func setup(kind: String,job: String = "farmer",hot: bool = false) -> void:
	species = kind; profession = job
	coat = textured_material(kind,job,hot)
	if kind == "slime":
		part(self,Vector3(0.88,0.78,0.88),Vector3(0,0.42,0),coat,0,1)
		var gel: StandardMaterial3D = coat.duplicate()
		gel.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gel.albedo_color = Color(1,1,1,0.23)
		part(self,Vector3(1.02,0.92,1.02),Vector3(0,0.47,0),gel,5)
	elif kind == "villager":
		part(self,Vector3(0.53,0.82,0.36),Vector3(0,0.91,0),coat,0)
		head = Node3D.new(); head.position.y = 1.53; add_child(head)
		part(head,Vector3(0.5,0.53,0.48),Vector3.ZERO,coat,4,1)
		part(head,Vector3(0.13,0.24,0.15),Vector3(0,-0.08,-0.30),coat,3)
		if job == "farmer":
			part(head,Vector3(0.74,0.08,0.68),Vector3(0,0.24,0),coat,6)
			part(head,Vector3(0.48,0.13,0.44),Vector3(0,0.32,0),coat,6)
		elif job == "librarian":
			part(head,Vector3(0.52,0.12,0.50),Vector3(0,0.25,0),coat,0)
		for side in [-1,1]:
			var leg = joint(self,Vector3(side*0.14,0.54,0)); limbs.append(leg)
			part(leg,Vector3(0.23,0.54,0.25),Vector3(0,-0.27,0),coat,2)
			var arm = joint(self,Vector3(side*0.35,1.25,0)); limbs.append(arm)
			part(arm,Vector3(0.19,0.5,0.21),Vector3(0,-0.25,0),coat,0)
			part(arm,Vector3(0.20,0.15,0.22),Vector3(0,-0.48,0),coat,4)
	else:
		var wool: bool = kind == "sheep"
		part(self,Vector3(0.88 if wool else 0.82,0.7 if wool else 0.60,1.20),Vector3(0,0.81 if wool else 0.72,0),coat,0)
		head = joint(self,Vector3(0,0.94 if wool else 0.84,-0.66))
		part(head,Vector3(0.51,0.53,0.49),Vector3.ZERO,coat,4,1)
		part(head,Vector3(0.31,0.19,0.12),Vector3(0,-0.10,-0.29),coat,4,3)
		for side in [-1,1]:
			var ear = part(head,Vector3(0.12,0.22,0.13),Vector3(side*0.28,0.20,0),coat,6)
			ear.rotation.z = side*0.2
			for front in [-1,1]:
				var leg = joint(self,Vector3(side*0.29,0.51,front*0.39)); limbs.append(leg)
				part(leg,Vector3(0.19,0.40,0.21),Vector3(0,-0.2,0),coat,4)
				part(leg,Vector3(0.21,0.14,0.23),Vector3(0,-0.44,0),coat,2)
		tail = joint(self,Vector3(0,0.89,0.62))
		part(tail,Vector3(0.12,0.13,0.21),Vector3(0,0,0.08),coat,3)
		if not wool: part(tail,Vector3(0.15,0.16,0.08),Vector3(0.05,0.08,0.17),coat,3)

static func joint(parent: Node3D,position: Vector3) -> Node3D:
	var node = Node3D.new(); node.position = position; parent.add_child(node); return node

func animate(delta: float,speed: float,grounded: bool,swimming: bool,hurt: float,attacking: bool = false) -> void:
	clock += delta
	var stride: float = sin(clock*(minf(6.0+speed*1.4,11.0) if not swimming else 4.0))*minf(speed*0.3,0.8)
	for index in limbs.size():
		var target: float = stride*(1.0 if index%3 == 0 else -1.0)
		if swimming: target += -0.5
		elif not grounded: target = 0.25 if index%2 == 0 else -0.25
		if species == "villager":
			# Leg/arm pairs counter-swing; resting arms fold over the apron.
			target = stride * (1.0 if index in [0,3] else -1.0)
			if index%2 == 1 and speed < 0.1: target = 0.85
			limbs[index].rotation.z = lerpf(limbs[index].rotation.z,(0.30 if index == 1 else -0.30) if index%2 == 1 and speed<0.1 else 0.0,minf(delta*8,1))
		limbs[index].rotation.x = lerpf(limbs[index].rotation.x,target,minf(delta*10.0,1.0))
	if head != null:
		head.rotation.x = sin(clock*1.5)*0.045 + (-0.22 if attacking else 0.0)
		head.rotation.y = sin(clock*0.65)*0.08 if speed < 0.2 else 0.0
	if tail != null: tail.rotation.y = sin(clock*3.0)*0.2
	if species == "slime":
		var squash: float = 0.10*sin(clock*9.0) if grounded else -0.17
		if swimming: squash = 0.08*sin(clock*5.0)
		scale = scale.lerp(Vector3(1+squash,1-squash*1.4,1+squash),minf(delta*12,1))
	else:
		position.y = sin(clock*2.0)*0.014 if speed < 0.1 else absf(sin(clock*8.0))*0.02
	coat.albedo_color = Color(1.0,0.52,0.52) if hurt > 0.0 else Color.WHITE

static func textured_material(kind: String,job: String = "farmer",hot: bool = false) -> StandardMaterial3D:
	var key: String = kind+":"+job+":"+str(hot)
	if not textures.has(key): textures[key] = ImageTexture.create_from_image(_atlas(kind,job,hot))
	var material = StandardMaterial3D.new(); material.albedo_texture = textures[key]
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST; material.roughness = 0.95
	return material

static func _atlas(kind: String,job: String,hot: bool) -> Image:
	var image := Image.create(128,16,false,Image.FORMAT_RGBA8)
	var base: Color = {"pig":Color("d59b97"),"sheep":Color("dedbca"),"slime":Color("83b94f"),"villager":Color("8a6c49"),"dragon":Color("35303f")}.get(kind,Color.WHITE)
	if kind == "slime" and hot: base = Color("dd642f")
	if kind == "villager": base = {"farmer":Color("917543"),"smith":Color("51626a"),"librarian":Color("986369"),"mason":Color("788472")}.get(job,base)
	for tile in 8:
		var paint: Color = base
		if tile == 2: paint = Color("493d3c")
		if tile in [1,3,4] and kind in ["villager","sheep"]: paint = Color("b89a7a") if kind == "villager" else Color("ae9b83")
		if tile == 3 and kind == "pig": paint = Color("c37d87")
		if tile == 6: paint = Color("bea365") if kind == "villager" else base.lightened(0.14)
		if kind == "dragon" and tile == 6: paint = Color("8b8096")
		if kind == "dragon" and tile == 7: paint = Color("51445f")
		for y in 16:
			for x in 16:
				var tint: float = float((x*7+y*11+tile*3)%7-3)*0.005
				if kind == "sheep" and tile == 0:
					var wool_x: int = posmod(x+(y/4)%2*2,4)
					tint += 0.06 if wool_x in [1,2] and y%4 == 1 else (-0.10 if wool_x == 0 or y%4 == 3 else 0.0)
				elif kind == "dragon":
					tint += -0.17 if y%4 == 3 or (x+y/4*2)%6 == 0 else (0.05 if y%4 == 0 else 0.0)
				elif kind == "pig":
					tint += -0.065 if (x/3*3+y/3*7)%11 == 0 else 0.0
				elif kind == "villager" and tile == 0:
					tint += -0.11 if x in [1,5,10,14] and y>3 else 0.0
				elif kind == "slime":
					tint += 0.12 if x in [2,3] and y in [2,3,4] else (-0.09 if x>12 or y>12 else 0.0)
				image.set_pixel(tile*16+x,y,paint.lightened(tint) if tint>0 else paint.darkened(-tint))
	var eye := Color("292536") if kind != "slime" else Color("24432a")
	if kind == "dragon":
		image.fill_rect(Rect2i(16,0,16,16),Color("44244d"))
		image.fill_rect(Rect2i(17,5,14,6),Color("b37bdb"))
		image.fill_rect(Rect2i(22,5,4,6),Color("efe0f6"))
	else:
		for x in [2,11]:
			image.fill_rect(Rect2i(16+x,5,3,3),Color("eee9d7") if kind != "slime" else eye)
			image.fill_rect(Rect2i(16+x+(1 if x == 2 else 0),6,2,2),eye)
		image.fill_rect(Rect2i(22,12,4,1),eye)
	if kind == "villager":
		image.fill_rect(Rect2i(18,3,12,2),Color("594231"))
		image.fill_rect(Rect2i(20,9,8,1),Color("9a755c"))
		image.fill_rect(Rect2i(1,12,14,2),Color("4b3e35")) # belt across robe
		image.fill_rect(Rect2i(7,12,2,2),Color("c3a471"))
		image.fill_rect(Rect2i(5,0,6,3),Color("b89a7a")) # collar
		for y in range(2,16,4): image.fill_rect(Rect2i(96,y,16,1),Color("9d804e"))
		if job == "smith":
			image.fill_rect(Rect2i(3,4,10,8),Color("665244")); image.fill_rect(Rect2i(6,6,4,3),Color("806951"))
		elif job == "librarian":
			for x in [17,25]:
				image.fill_rect(Rect2i(x,4,6,1),eye); image.fill_rect(Rect2i(x,8,6,1),eye)
				image.fill_rect(Rect2i(x,4,1,5),eye); image.fill_rect(Rect2i(x+5,4,1,5),eye)
			image.fill_rect(Rect2i(23,6,2,1),eye)
	if kind == "pig":
		for x in [51,58]: image.fill_rect(Rect2i(x,6,3,4),Color("814b56"))
		image.fill_rect(Rect2i(50,3,12,1),Color("e8a3aa"))
	elif kind == "sheep":
		image.fill_rect(Rect2i(48+6,5,4,3),Color("746355"))
		image.fill_rect(Rect2i(48+4,10,8,1),Color("625a50"))
	if kind == "dragon":
		for x in range(0,16,4):
			image.fill_rect(Rect2i(112+x,0,1,16),Color("74617f"))
			image.fill_rect(Rect2i(112+x+1,0,1,16),Color("3b3046"))
	return image

static func part(parent: Node3D,size: Vector3,position: Vector3,material: Material,tile: int,front_tile: int = -1) -> MeshInstance3D:
	var vertices = PackedVector3Array(); var normals = PackedVector3Array(); var uv = PackedVector2Array(); var indices = PackedInt32Array()
	for face in 6:
		var selected: int = front_tile if face == 5 and front_tile >= 0 else tile
		var rect = Rect2((selected*16+0.2)/128.0,0.2/16.0,15.6/128.0,15.6/16.0)
		var tex: Array[Vector2] = [Vector2(rect.position.x,rect.end.y),rect.position,Vector2(rect.end.x,rect.position.y),rect.end]
		for corner in 4:
			vertices.append((CORNERS[face][corner]-Vector3.ONE*0.5)*size); normals.append(NORMALS[face]); uv.append(tex[corner])
		for index in [0,2,1,0,3,2]: indices.append(face*4+index)
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals; arrays[Mesh.ARRAY_TEX_UV] = uv; arrays[Mesh.ARRAY_INDEX] = indices
	var mesh = ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var instance = MeshInstance3D.new(); instance.mesh = mesh; instance.material_override = material; instance.position = position; parent.add_child(instance)
	return instance
