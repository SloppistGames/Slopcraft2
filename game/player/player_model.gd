class_name PlayerModel
extends Node3D
## Classic 64x64 skin net, in pixels. Shared with the launcher's live preview.
const PIXEL: float = 1.8 / 32.0
const PARTS: Dictionary = {
	"head":{"uv":Vector2i(0,0),"overlay":Vector2i(32,0),"size":Vector3i(8,8,8)},
	"body":{"uv":Vector2i(16,16),"overlay":Vector2i(16,32),"size":Vector3i(8,12,4)},
	"right_arm":{"uv":Vector2i(40,16),"overlay":Vector2i(40,32),"size":Vector3i(4,12,4)},
	"left_arm":{"uv":Vector2i(32,48),"overlay":Vector2i(48,48),"size":Vector3i(4,12,4)},
	"right_leg":{"uv":Vector2i(0,16),"overlay":Vector2i(0,32),"size":Vector3i(4,12,4)},
	"left_leg":{"uv":Vector2i(16,48),"overlay":Vector2i(0,48),"size":Vector3i(4,12,4)},
}
const NORMALS: Array[Vector3] = [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]
const CORNERS: Array = [
	[Vector3(1,0,1),Vector3(1,1,1),Vector3(1,1,0),Vector3(1,0,0)],
	[Vector3(0,0,0),Vector3(0,1,0),Vector3(0,1,1),Vector3(0,0,1)],
	[Vector3(0,1,0),Vector3(1,1,0),Vector3(1,1,1),Vector3(0,1,1)],
	[Vector3(0,0,1),Vector3(1,0,1),Vector3(1,0,0),Vector3(0,0,0)],
	[Vector3(0,0,1),Vector3(0,1,1),Vector3(1,1,1),Vector3(1,0,1)],
	[Vector3(1,0,0),Vector3(1,1,0),Vector3(0,1,0),Vector3(0,0,0)],
]
var material: StandardMaterial3D
var skin_image: Image
var pivots: Dictionary = {}
var _mask: Node3D
var _stride: float = 0.0
var holding_item: bool = false

func _init() -> void:
	material = StandardMaterial3D.new()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 1.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.1
	set_skin_image(default_skin_image())
	for part in PARTS:
		var pivot = Node3D.new()
		pivot.name = part
		add_child(pivot)
		pivots[part] = pivot
		var center: Vector3 = Vector3.ZERO
		match part:
			"head": pivot.position = Vector3(0,24 * PIXEL,0); center.y = 4 * PIXEL
			"body": pivot.position.y = 18 * PIXEL
			"right_arm": pivot.position = Vector3(-6 * PIXEL,24 * PIXEL,0); center.y = -6 * PIXEL
			"left_arm": pivot.position = Vector3(6 * PIXEL,24 * PIXEL,0); center.y = -6 * PIXEL
			"right_leg": pivot.position = Vector3(-2 * PIXEL,12 * PIXEL,0); center.y = -6 * PIXEL
			"left_leg": pivot.position = Vector3(2 * PIXEL,12 * PIXEL,0); center.y = -6 * PIXEL
		for layer in 2:
			var mesh = MeshInstance3D.new()
			mesh.mesh = part_mesh(part,layer == 1)
			mesh.material_override = material
			mesh.position = center
			pivot.add_child(mesh)
	_mask = Node3D.new()
	pivots.head.add_child(_mask)
	_mask.position.y = 4 * PIXEL
	_mask_piece(Vector3(0.46,0.18,0.11),Vector3(0,-0.10,-0.23),Color("34433b"))
	for side in [-1,1]:
		_mask_piece(Vector3(0.20,0.17,0.055),Vector3(side * 0.118,0.035,-0.26),Color("2c3530"))
		_mask_piece(Vector3(0.15,0.12,0.015),Vector3(side * 0.118,0.035,-0.293),Color("80b2a0"))
		_mask_piece(Vector3(0.085,0.055,0.46),Vector3(side * 0.225,-0.065,0),Color("30382f"))
	_mask_piece(Vector3(0.16,0.12,0.13),Vector3(0,-0.13,-0.33),Color("666e5e"))
	_mask.visible = false

func _mask_piece(size: Vector3, center: Vector3, color: Color) -> void:
	var box = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.position = center
	var paint = StandardMaterial3D.new()
	paint.albedo_color = color
	paint.roughness = 0.7
	box.material_override = paint
	_mask.add_child(box)

func set_gas_mask(wearing: bool) -> void:
	_mask.visible = wearing

func set_skin_image(image: Image) -> bool:
	if image == null or image.get_width() != 64 or image.get_height() != 64:
		return false
	skin_image = image.duplicate()
	material.albedo_texture = ImageTexture.create_from_image(skin_image)
	return true

func animate(delta: float, walking_speed: float, pitch: float) -> void:
	_stride += delta * walking_speed * 2.4
	var swing: float = sin(_stride) * minf(walking_speed / 6.0,0.8)
	pivots.right_leg.rotation.x = swing
	pivots.left_leg.rotation.x = -swing
	pivots.right_arm.rotation.x = 0.28-swing*0.4 if holding_item else -swing
	pivots.left_arm.rotation.x = swing
	pivots.head.rotation.x = pitch

static func face_rects(part: String, overlay: bool = false) -> Array[Rect2]:
	var spec: Dictionary = PARTS[part]
	var uv: Vector2 = Vector2(spec.overlay if overlay else spec.uv)
	var size: Vector3i = spec.size
	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	# +X = player's left; -X = player's right. Front faces toward -Z.
	return [Rect2(uv + Vector2(d+w,d),Vector2(d,h)),Rect2(uv + Vector2(0,d),Vector2(d,h)),Rect2(uv + Vector2(d,0),Vector2(w,d)),Rect2(uv + Vector2(d+w,0),Vector2(w,d)),Rect2(uv + Vector2(2*d+w,d),Vector2(w,h)),Rect2(uv + Vector2(d,d),Vector2(w,h))]

static func part_mesh(part: String, overlay: bool = false) -> ArrayMesh:
	var spec: Dictionary = PARTS[part]
	var size: Vector3 = Vector3(spec.size) * PIXEL + (Vector3.ONE * PIXEL * 0.5 if overlay else Vector3.ZERO)
	var rectangles: Array[Rect2] = face_rects(part,overlay)
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uv = PackedVector2Array()
	var indices = PackedInt32Array()
	for face in 6:
		var rect: Rect2 = rectangles[face]
		var texcoords: Array[Vector2] = [Vector2(rect.position.x,rect.end.y),rect.position,Vector2(rect.end.x,rect.position.y),rect.end]
		for corner in 4:
			vertices.append((CORNERS[face][corner] - Vector3.ONE * 0.5) * size)
			normals.append(NORMALS[face])
			uv.append(texcoords[corner] / 64.0)
		# Godot front faces use clockwise winding viewed from outside the skin.
		for index in [0,1,2,0,2,3]:
			indices.append(face * 4 + index)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func default_skin_image() -> Image:
	var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var skin := Color("c18e6c")
	var shirt := Color("327b80")
	var trousers := Color("45516c")
	var hair := Color("4b382d")
	for part in PARTS:
		var faces: Array[Rect2] = face_rects(part)
		for face_index in faces.size():
			var rect := Rect2i(faces[face_index])
			for y in rect.size.y:
				for x in rect.size.x:
					var color: Color = skin if part == "head" else (shirt if part in ["body","right_arm","left_arm"] else trousers)
					if "arm" in part and (y>=5 or face_index==3): color = skin
					if "leg" in part and (y>=10 or face_index==3): color = Color("393c45")
					var shade: float = float(posmod(x*3+y*7,5)-2)*0.014
					if x==0 or x==rect.size.x-1: shade -= 0.035
					if "leg" in part and y in [4,8] and x==1: shade -= 0.07
					if part=="body" and y in [7,8] and x in [1,6]: shade -= 0.07
					image.set_pixel(rect.position.x+x,rect.position.y+y,color.lightened(shade) if shade>0 else color.darkened(-shade))
	# Hair wraps around the sides and back instead of a single flat top strip.
	image.fill_rect(Rect2i(8,0,8,8),hair)
	image.fill_rect(Rect2i(24,8,8,8),hair)
	image.fill_rect(Rect2i(8,8,8,2),hair)
	for rect in [Rect2i(0,8,8,3),Rect2i(16,8,8,3)]: image.fill_rect(rect,hair)
	for point in [Vector2i(9,10),Vector2i(14,10),Vector2i(1,11),Vector2i(22,11),Vector2i(10,3),Vector2i(13,6),Vector2i(26,11),Vector2i(29,14)]: image.set_pixelv(point,hair.lightened(0.12))
	for x in [9,13]:
		image.fill_rect(Rect2i(x,11,2,1),Color("e0e6da"))
		image.set_pixel(x+(1 if x==9 else 0),11,Color("456f85"))
		image.set_pixel(x,10,Color("6c4a36"))
	image.fill_rect(Rect2i(11,12,2,1),Color("a67556"))
	image.fill_rect(Rect2i(10,14,4,1),Color("835744"))
	image.fill_rect(Rect2i(11,13,2,1),skin.lightened(0.08))
	# Collar, placket, seams and belt remain part of the editable classic skin net.
	image.fill_rect(Rect2i(22,20,4,1),skin)
	image.fill_rect(Rect2i(23,21,2,1),skin)
	image.fill_rect(Rect2i(23,22,1,5),shirt.darkened(0.18))
	for y in [23,25]: image.set_pixel(24,y,Color("75a0a0"))
	image.fill_rect(Rect2i(20,30,8,2),Color("414b52"))
	image.fill_rect(Rect2i(23,30,2,1),Color("aa9670"))
	return image
