class_name BlockAtlas
extends RefCounted
## Original clustered pixel art. Face order: +X, -X, top, bottom, back (+Z), front (-Z).
## Utility blocks have a designated front. Every face has its own atlas slot.
const TILE: int = 16
const COLS: int = 32
const ROWS: int = 38
const BLOCK_CAPACITY: int = 200
static var texture: ImageTexture
static var materials: Array = []
static var _atlas: Image
static var _faces: Dictionary = {}
static var _icons: Dictionary = {}

static func prepare() -> void:
	if texture != null:
		return
	_atlas = Image.create(COLS*TILE,ROWS*TILE,false,Image.FORMAT_RGBA8)
	_atlas.fill(Color.TRANSPARENT)
	for id in range(BLOCK_CAPACITY):
		for face in range(6):
			var tile: int = id*6+face
			var img: Image = _paint(id,face)
			_faces[tile] = img
			_atlas.blit_rect(img,Rect2i(0,0,TILE,TILE),Vector2i((tile%COLS)*TILE,(tile/COLS)*TILE))
	texture = ImageTexture.create_from_image(_atlas)
	for group in range(3):
		var mat = StandardMaterial3D.new()
		mat.albedo_texture = texture
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.92
		if group == 1:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(1,1,1,.68)
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.roughness = .2
		if group == 2:
			mat.emission_enabled = true
			mat.emission_texture = texture
			mat.emission = Color.WHITE
			mat.emission_energy_multiplier = .6
		materials.append(mat)

static func tile_rect(id: int, face: int) -> Rect2:
	var tile: int = _base_id(id)*6+clampi(face,0,5)
	# A tiny inset prevents sampling adjacent tiles while preserving every pixel.
	return Rect2((float(tile%COLS)+.002)/COLS,(float(tile/COLS)+.002)/ROWS,.996/COLS,.996/ROWS)

static func face_image(id: int, face: int) -> Image:
	prepare()
	return _faces[_base_id(id)*6+clampi(face,0,5)].duplicate()

static func face_texture(id: int, face: int) -> AtlasTexture:
	prepare()
	var result = AtlasTexture.new()
	result.atlas = texture
	var tile: int = _base_id(id)*6+clampi(face,0,5)
	result.region = Rect2((tile%COLS)*TILE,(tile/COLS)*TILE,TILE,TILE)
	return result

static func _base_id(id: int) -> int:
	var info: Dictionary = BlockDB.get_block(id)
	return clampi(int(info.get("base_id",info.get("id",0))),0,BLOCK_CAPACITY-1)

static func icon_texture(id: int) -> ImageTexture:
	prepare()
	if _icons.has(id):
		return _icons[id]
	var output = Image.create(48,48,false,Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	var depth: PackedFloat32Array = PackedFloat32Array()
	depth.resize(48*48)
	depth.fill(-1000.0)
	var shape: String = str(BlockDB.get_block(id).get("shape","cube"))
	if id in [165,166,168]:
		output = face_image(id,5)
		output.resize(48,48,Image.INTERPOLATE_NEAREST)
	elif shape == "bed":
		# The inventory item represents the complete two-block bed.
		var scale_factor=.65
		var offset=Vector2(16,5)
		_icon_box(output,depth,181,Vector3(0,3,0),Vector3(16,9,16),scale_factor,offset)
		_icon_box(output,depth,182,Vector3(0,3,-16),Vector3(16,9,0),scale_factor,offset,Vector3(0,0,-16))
		for x in [1,13]:
			for z in [-15,13]: _icon_box(output,depth,7,Vector3(x,0,z),Vector3(x+2,3,z+2),scale_factor,offset,Vector3(0,0,-16 if z<0 else 0))
	elif shape == "slab":
		_icon_box(output,depth,id,Vector3.ZERO,Vector3(16,8,16))
	elif shape == "stair":
		_icon_box(output,depth,id,Vector3.ZERO,Vector3(16,8,16))
		_icon_box(output,depth,id,Vector3(0,8,8),Vector3(16,16,16))
	elif id in [28,164]:
		_icon_box(output,depth,id,Vector3(6,0,6),Vector3(10,14,10))
	elif id in [155,157,177,178,179]:
		_icon_box(output,depth,id,Vector3(1,0,1),Vector3(15,3,15))
	else:
		_icon_box(output,depth,id,Vector3.ZERO,Vector3(16,16,16))
	var result = ImageTexture.create_from_image(output)
	_icons[id] = result
	return result

static func _project_icon(p: Vector3) -> Vector2:
	return Vector2((p.x+p.z)*1.5,(p.x-p.z)*.75+(16-p.y)*1.5+12)

static func _icon_box(out: Image,depth: PackedFloat32Array,id: int,lo: Vector3,hi: Vector3,scale_factor: float=1.0,offset: Vector2=Vector2.ZERO,texture_origin: Vector3=Vector3.ZERO) -> void:
	var panels: Array = [
		[2,Vector3(lo.x,hi.y,hi.z),Vector3(hi.x,hi.y,hi.z),Vector3(lo.x,hi.y,lo.z)],
		[5,Vector3(lo.x,hi.y,lo.z),Vector3(hi.x,hi.y,lo.z),Vector3(lo.x,lo.y,lo.z)],
		[0,Vector3(hi.x,hi.y,lo.z),Vector3(hi.x,hi.y,hi.z),Vector3(hi.x,lo.y,lo.z)]]
	for panel in panels:
		var face: int = panel[0]
		var a: Vector3 = panel[1]
		var b: Vector3 = panel[2]
		var c: Vector3 = panel[3]
		var origin: Vector2 = _project_icon(a)*scale_factor+offset
		var edge_u: Vector2 = _project_icon(b)*scale_factor+offset-origin
		var edge_v: Vector2 = _project_icon(c)*scale_factor+offset-origin
		var determinant: float = edge_u.x*edge_v.y-edge_u.y*edge_v.x
		var img: Image = _faces[_base_id(id)*6+face]
		for y in 48:
			for x in 48:
				var rel: Vector2 = Vector2(x+.5,y+.5)-origin
				var u: float = (rel.x*edge_v.y-rel.y*edge_v.x)/determinant
				var v: float = (edge_u.x*rel.y-edge_u.y*rel.x)/determinant
				if u < 0 or v < 0 or u >= 1 or v >= 1:
					continue
				var pos: Vector3 = a+(b-a)*u+(c-a)*v
				var d: float = pos.x-pos.z+2*pos.y
				if d < depth[y*48+x]:
					continue
				var tex: Vector3 = pos-texture_origin
				var tx: int = clampi(int(tex.x if face != 0 else tex.z),0,15)
				var ty: int = clampi(int((tex.z if id in [181,182] else 15-tex.z) if face == 2 else 16-tex.y),0,15)
				var color: Color = img.get_pixel(tx,ty)
				if color.a > .01:
					out.set_pixel(x,y,color*Color(1,1,1,1) if face == 2 else color*Color(.84,.84,.84,1) if face == 5 else color*Color(.65,.65,.65,1))
					depth[y*48+x] = d

static func _paint(id: int, face: int) -> Image:
	var info: Dictionary = BlockDB.get_block(id)
	var c: Color = info.get("color",Color("888888"))
	var kind: String = str(info.get("texture_kind","stone"))
	var img = Image.create(TILE,TILE,false,Image.FORMAT_RGBA8)
	img.fill(c)
	if id == 0 or not BlockDB.is_block(id):
		img.fill(Color.TRANSPARENT)
		return img
	if id >= 147:
		_snapshot_block(img,id,face,c)
	elif kind.ends_with("_ore"):
		_ore(img,id,c)
	elif id == 1:
		_grass(img,face)
	elif id == 2:
		_dirt(img)
	elif id in [5,31,33,37,40,43,45,64,67]:
		_log(img,id,face)
	elif kind == "planks":
		_planks(img,c,id)
	elif id in [6,32,34,39,42,47,66,69]:
		_foliage(img,id,c)
	elif id == 58:
		_deepslate(img,face)
	elif id in [3,55,56,57]:
		_stone(img,id,c)
	elif id in [4,60,85]:
		_cobble(img,c,id)
	elif id == 10:
		_bedrock(img)
	elif id in [8,21,48,49,51,96]:
		_sediment(img,id,c)
	elif id in [50,52]:
		_sandstone(img,face,c)
	elif id == 9:
		_water(img)
	elif id in [20,145]:
		_lava(img,id == 145)
	elif id == 15:
		_snow(img,face)
	elif id in [16,87,88,98,99]:
		_glass(img,id,c)
	elif id in [17,24,53,54,59,62,63,72,138]:
		_bricks(img,id,c)
	elif id == 18:
		_obsidian(img)
	elif id == 19:
		_netherrack(img)
	elif id in [22,70,90,146]:
		_light(img,id,c,face)
	elif id == 23:
		_endstone(img)
	elif id == 25:
		_crafting(img,face)
	elif id == 26:
		_furnace(img,face)
	elif id == 27:
		_chest(img,face)
	elif id == 28:
		_torch(img,face)
	elif id in [29,30]:
		_portal(img,id)
	elif id in [61,139]:
		_pillar(img,face,c,id)
	elif id == 71:
		_quartz(img,face)
	elif kind == "metal":
		_metal(img,id,c)
	elif id in [86,140]:
		_crystal(img,id,c)
	elif id == 89:
		_prismarine(img)
	elif id == 91:
		_bookshelf(img,face)
	elif id == 92:
		_hay(img,face)
	elif id in [93,94]:
		_gourd(img,id,face)
	elif id == 95:
		_cactus(img,face)
	elif id == 97:
		_tnt(img,face)
	elif id >= 100 and id <= 116:
		_terracotta(img,c,id)
	elif id >= 117 and id <= 132:
		_wool(img,c)
	elif id >= 133 and id <= 137:
		_concrete(img,c)
	elif id == 141:
		_debris(img,face)
	elif id in [143,144]:
		_mushroom(img,id,face)
	else:
		_stone(img,id,c)
	if id in [6,32,34,39,42]:
		for p in [[0,4],[4,0],[7,6],[13,3],[2,12],[10,14],[15,10]]:
			_px(img,p[0],p[1],Color.TRANSPARENT)
			if id!=32: _px(img,p[0]+1,p[1],Color.TRANSPARENT)
	# Natural materials are isotropic, but their visible grain should not repeat in
	# exactly the same place on every adjoining face of a cube.
	if id in [2,3,4,6,8,10,11,12,13,14,18,19,21,23,32,34,39,42,47,48,49,51,55,56,57,58,60,66,69,73,74,75,76,85,86,89,96,140,145]:
		if face in [1,4,3]:
			img.flip_x()
		if face in [0,2,4]:
			img.rotate_90(CLOCKWISE)
	return img

static func _px(img: Image,x: int,y: int,c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x,y,c)

static func _rect(img: Image,x: int,y: int,w: int,h: int,c: Color) -> void:
	for py in range(maxi(0,y),mini(img.get_height(),y+h)):
		for px in range(maxi(0,x),mini(img.get_width(),x+w)):
			img.set_pixel(px,py,c)

static func _line(img: Image,x0: int,y0: int,x1: int,y1: int,c: Color) -> void:
	var steps: int = maxi(absi(x1-x0),absi(y1-y0))
	for i in range(steps+1):
		var t: float = float(i)/maxi(1,steps)
		_px(img,roundi(lerpf(x0,x1,t)),roundi(lerpf(y0,y1,t)),c)

static func _cluster(img: Image,x: int,y: int,w: int,h: int,c: Color,highlight: Color) -> void:
	_rect(img,x+1,y,w-2,h,c)
	_rect(img,x,y+1,w,h-2,c)
	_line(img,x+1,y,x+w-2,y,highlight)

static func _stone(img: Image,id: int,c: Color) -> void:
	img.fill(c.darkened(.04))
	var shapes: Array = [[0,1,6,3],[8,0,5,4],[4,5,7,3],[12,7,5,4],[-2,10,6,4],[5,11,6,5]]
	for i in shapes.size():
		var s: Array = shapes[i]
		var tone: Color = c.lightened(.10) if i%3 == 0 else c.darkened(.10)
		_cluster(img,s[0],s[1],s[2],s[3],tone,tone.lightened(.055))
	if id == 55:
		for p in [[2,2],[7,6],[12,1],[1,12],[11,11],[6,14]]:
			_rect(img,p[0],p[1],2,2,Color("6c514c"))
			_px(img,p[0]+1,p[1],Color("d1a58b"))
	elif id == 56:
		for p in [[1,2],[7,1],[11,5],[5,8],[1,12],[12,13],[8,14]]:
			_rect(img,p[0],p[1],3,2,Color("85898a"))
			_px(img,p[0],p[1],Color("eef0df"))
	elif id == 58:
		for y in [3,7,12]:
			_line(img,0,y,6,y,Color("343943"))
			_line(img,8,y+1,15,y+1,Color("343943"))
	else:
		_line(img,1,9,4,9,c.darkened(.18))
		_line(img,10,4,13,4,c.darkened(.16))
		_px(img,14,13,c.lightened(.13))

static func _dirt(img: Image) -> void:
	img.fill(Color("79543b"))
	for s in [[0,0,5,4],[6,2,5,3],[12,0,5,4],[2,6,6,4],[10,6,5,3],[0,12,4,4],[6,12,7,4]]:
		_cluster(img,s[0],s[1],s[2],s[3],Color("886043"),Color("99704d"))
	for p in [[3,3],[10,4],[1,9],[12,12],[7,13]]:
		_rect(img,p[0],p[1],2,1,Color("644530"))
	for p in [[5,5],[13,8],[3,13]]:
		_rect(img,p[0],p[1],2,2,Color("99917e"))
		_px(img,p[0]+1,p[1],Color("b1a68d"))

static func _grass(img: Image,face: int) -> void:
	if face == 3:
		_dirt(img)
		return
	if face != 2:
		_dirt(img)
		var lengths: Array = [3,4,3,5,5,3,4,3,3,5,4,3,5,4,3,4]
		for x in 16:
			for y in int(lengths[x]):
				_px(img,x,y,Color("628f3a") if (x+y)%4 < 2 else Color("75a148"))
			_px(img,x,lengths[x],Color("495e2e"))
		for x in [3,7,12]:
			_line(img,x,4,x-1,6,Color("5f7537"))
		return
	img.fill(Color("689541"))
	for p in [[0,1],[5,2],[11,0],[3,7],[9,6],[14,9],[0,12],[7,13]]:
		_cluster(img,p[0],p[1],4,3,Color("5c8737"),Color("81ab50"))
	for p in [[2,4],[9,2],[6,9],[12,13]]:
		_px(img,p[0],p[1],Color("9abc61"))
		_px(img,p[0]+1,p[1]+1,Color("78a449"))

static func _planks(img: Image,c: Color,seed: int) -> void:
	img.fill(c)
	for row in 4:
		var y: int = row*4
		var start: int = posmod(row*5+seed,16)
		_line(img,0,y,15,y,c.darkened(.34))
		_line(img,0,y+1,15,y+1,c.lightened(.13))
		_line(img,start,y,start,y+3,c.darkened(.30))
		_line(img,posmod(start+3,16),y+3,mini(15,start+7),y+3,c.darkened(.10))
		_px(img,posmod(start+1,16),y+2,c.darkened(.23))
		_px(img,posmod(start+13,16),y+2,c.darkened(.23))

static func _log(img: Image,id: int,face: int) -> void:
	var bark: Color = BlockDB.item_color(id)
	var wood: Color = Color("ad8854")
	match id:
		31: wood=Color("987344")
		33: wood=Color("d1c18c")
		37: wood=Color("c98550")
		40: wood=Color("c59088")
		43: wood=Color("7c5e37")
		45: wood=Color("bd926a")
		64: wood=Color("b15a6d")
		67: wood=Color("54aa96")
	if face in [2,3]:
		img.fill(bark.darkened(.22))
		_rect(img,1,1,14,14,wood)
		for y in range(2,14):
			for x in range(2,14):
				var d: int = maxi(absi(x-7+(1 if y<5 else 0)),absi(y-8+(1 if x>10 else 0)))
				if d in [2,5]:
					_px(img,x,y,wood.darkened(.24))
				elif d in [1,4]:
					_px(img,x,y,wood.lightened(.12))
		_line(img,8,8,12,12,wood.darkened(.28))
		_px(img,7,7,wood.darkened(.35))
		return
	img.fill(bark)
	if id == 33:
		img.fill(Color("dedbc3"))
		for s in [[1,2,5,1],[10,0,4,2],[5,6,6,2],[0,10,3,2],[10,12,6,1],[3,15,4,1]]:
			_rect(img,s[0],s[1],s[2],s[3],Color("514c42"))
			_px(img,s[0]+1,s[1]-1,Color("b4b29e"))
		_line(img,13,4,13,9,Color("c3c3ac"))
		return
	for x in [0,3,7,11,14]:
		var shift: int = (id+x)%3
		_line(img,x,0,x,6+shift,bark.darkened(.32))
		_line(img,x+1,7+shift,x+1,15,bark.darkened(.27))
		_line(img,x+1,1,x+1,5,bark.lightened(.15))
		_line(img,x+2,9,x+2,14,bark.lightened(.10))
	if id in [64,67]:
		var sap: Color = Color("d86479") if id == 64 else Color("50c9b1")
		_line(img,6,3,6,7,sap)
		_line(img,5,7,5,10,sap.darkened(.15))
		_line(img,13,11,13,14,sap)
	else:
		_rect(img,8,8,3,4,bark.darkened(.23))
		_rect(img,9,9,1,2,bark.lightened(.10))

static func _foliage(img: Image,id: int,c: Color) -> void:
	if id == 42:
		img.fill(Color("8d5d70"))
		for p in [[0,0],[6,0],[12,2],[2,6],[8,7],[-1,12],[11,12]]:
			_cluster(img,p[0],p[1],5,4,Color("d8a2b7"),Color("efd0d9"))
			_px(img,p[0]+2,p[1]+2,Color("b97294"))
			_px(img,p[0]+3,p[1]+1,Color("f4d5db"))
		return
	if id == 32:
		# Flat, interlocking sprays of pine needles, instead of oak leaves tinted blue.
		img.fill(Color("244338"))
		for p in [[1,0],[8,1],[13,5],[-1,7],[5,8],[9,13]]:
			_line(img,p[0],p[1],p[0]+3,p[1]+4,Color("497355"))
			_line(img,p[0]-2,p[1]+2,p[0]+1,p[1]+2,Color("3c6448"))
			_line(img,p[0]+1,p[1]+3,p[0]+4,p[1]+3,Color("57815b"))
			_line(img,p[0],p[1]+4,p[0]+2,p[1]+5,Color("345b43"))
		return
	if id == 47:
		# Soft moss carpet: short tufts and damp pockets without tree-leaf holes.
		img.fill(Color("687f3d"))
		for p in [[0,1],[5,0],[10,2],[2,5],[8,6],[13,7],[0,11],[5,12],[11,13]]:
			_rect(img,p[0],p[1],3,2,Color("556d36"))
			_line(img,p[0],p[1],p[0]+2,p[1],Color("87994f"))
			_px(img,p[0]+1,p[1]-1,Color("9ba65c"))
			_px(img,p[0]+2,p[1]+2,Color("738b41"))
		return
	if id in [66,69]:
		# Fungal blocks have fleshy lobes or twisting blue hyphae, not leaf clumps.
		img.fill(Color("6c2539") if id == 66 else Color("245e64"))
		if id == 66:
			for s in [[-1,1,6,5],[7,-1,6,5],[11,6,6,5],[3,7,5,6],[0,13,4,4],[10,13,5,4]]:
				_cluster(img,s[0],s[1],s[2],s[3],Color("a53f50"),Color("c1555f"))
				_line(img,s[0]+1,s[1]+2,s[0]+2,s[1]+3,Color("792e43"))
				_px(img,s[0]+3,s[1]+1,Color("d36b69"))
		else:
			for p in [[1,0],[8,1],[13,7],[3,9],[8,12]]:
				_line(img,p[0],p[1],p[0]+3,p[1]+2,Color("48a18e"))
				_line(img,p[0]+3,p[1]+2,p[0]+1,p[1]+5,Color("3c8e86"))
				_line(img,p[0]+1,p[1]+5,p[0]+4,p[1]+6,Color("326d77"))
				_px(img,p[0]+2,p[1]+1,Color("79bea5"))
				_px(img,p[0],p[1]+3,Color("686280"))
		return
	if id == 34:
		img.fill(Color("4e6c32"))
		for p in [[0,1],[4,0],[10,2],[14,0],[2,6],[7,5],[12,7],[-1,11],[5,11],[10,12],[15,13]]:
			_cluster(img,p[0],p[1],3,4,Color("709749"),Color("91b163"))
			_px(img,p[0]+1,p[1]+2,Color("597b38"))
		return
	if id == 39:
		img.fill(Color("4f6336"))
		for p in [[-1,1],[7,0],[12,4],[2,6],[8,9],[-1,12],[13,13]]:
			_cluster(img,p[0],p[1],6,3,Color("768b49"),Color("8fa35b"))
			_line(img,p[0]+2,p[1]+2,p[0]+4,p[1]+2,Color("5e763c"))
		return
	img.fill(c.darkened(.30))
	for p in [[0,0],[5,-1],[11,1],[-2,5],[4,5],[9,7],[1,11],[6,13],[13,12]]:
		_cluster(img,p[0],p[1],5,4,c,c.lightened(.16))
		_line(img,p[0]+2,p[1]+2,p[0]+3,p[1]+3,c.darkened(.16))
		_px(img,p[0]+1,p[1]+1,c.lightened(.07))

static func _cobble(img: Image,c: Color,id: int) -> void:
	img.fill(c.darkened(.38))
	var cells: Array = [[-1,-1,6,5],[6,0,5,4],[12,-1,5,6],[0,5,5,6],[6,5,6,5],[13,6,4,6],[-1,12,7,5],[7,11,5,6],[13,13,5,4]]
	for i in cells.size():
		var s: Array = cells[i]
		var tone: Color = c.lightened(.07) if i%3 == 0 else c.darkened(.03+i%2*.06)
		_cluster(img,s[0],s[1],s[2],s[3],tone,tone.lightened(.14))
		_line(img,s[0]+2,s[1]+s[3]-1,s[0]+s[2]-2,s[1]+s[3]-1,tone.darkened(.17))
	if id == 85:
		_line(img,2,7,4,8,Color("485057"))
		_px(img,10,3,Color("565e63"))

static func _bricks(img: Image,id: int,c: Color) -> void:
	if id == 54:
		c = Color("92928a")
	var mortar: Color = c.darkened(.35)
	if id == 17:
		mortar = Color("a59b89")
	img.fill(mortar)
	var height: int = 4 if id in [17,62,63] else 8
	for row in range(16/height):
		var offset: int = 4 if row%2 else 0
		for col in range(-1,3):
			var x: int = col*8+offset
			var y: int = row*height
			var tone: Color = c.lightened(.06) if posmod(row+col,3)==0 else c.darkened(.04)
			_rect(img,x+1,y+1,7,height-1,tone)
			_line(img,x+1,y+1,x+7,y+1,tone.lightened(.13))
			_line(img,x+1,y+height-1,x+7,y+height-1,tone.darkened(.14))
			_px(img,x+6,y+2,tone.darkened(.10))
	if id in [53,54,59,138]:
		_line(img,3,3,4,4,c.darkened(.20))
		_line(img,4,4,4,5,c.darkened(.20))
		_line(img,12,11,14,11,c.darkened(.18))
	if id == 54:
		for p in [[0,0],[4,7],[12,8],[14,14]]:
			_cluster(img,p[0],p[1],4,3,Color("5d7642"),Color("7e9854"))
			_px(img,p[0]+3,p[1]+2,Color("3e5c36"))
		_line(img,6,8,9,8,Color("526b3e"))
		_px(img,11,7,Color("77844e"))
		_px(img,2,15,Color("93a363"))
	if id == 24:
		for p in [[4,4],[12,4],[0,12],[8,12]]:
			_rect(img,p[0]-1,p[1]-1,2,2,c.lightened(.13))

static func _ore(img: Image,id: int,c: Color,deepslate: bool = false) -> void:
	if deepslate:
		_deepslate(img,0)
	else:
		_stone(img,3,Color("85898a"))
	var placements: Array = [[2,2,4,3],[10,1,3,3],[6,7,4,4],[1,12,3,3],[12,11,4,3]]
	match id:
		11: placements = [[1,1,5,4],[9,3,4,3],[3,8,4,4],[10,11,5,4]]
		12: placements = [[2,1,3,3],[7,3,4,3],[12,7,3,3],[2,10,4,3],[7,13,3,3]]
		13: placements = [[1,2,4,3],[5,4,3,4],[9,8,4,3],[3,12,3,3],[12,1,3,3]]
		14: placements = [[2,2,3,4],[10,0,4,4],[6,7,4,4],[0,12,4,3],[12,11,3,4]]
		73: placements = [[0,3,5,3],[4,5,4,3],[9,1,4,4],[11,10,5,3],[3,12,4,3]]
		74: placements = [[3,0,3,5],[11,4,3,5],[4,9,3,5]]
		75: placements = [[0,2,3,3],[4,4,3,3],[7,6,3,4],[10,9,3,3],[2,12,3,3],[12,1,3,3]]
		76: placements = [[1,1,5,4],[9,3,4,4],[2,10,5,4],[10,11,4,4]]
	for s in placements:
		_cluster(img,s[0],s[1],s[2],s[3],c.darkened(.15),c.lightened(.27))
		_px(img,s[0]+1,s[1]+1,c)
		_px(img,s[0]+s[2]-2,s[1]+s[3]-1,c.darkened(.38))
		if id in [14,74]:
			_line(img,s[0]+1,s[1],s[0]+1,s[1]+s[3]-2,c.lightened(.45))
		elif id == 76:
			_px(img,s[0]+2,s[1]+2,Color("a1b0c6"))
	if id == 73:
		for p in [[2,3],[7,8],[13,12]]:
			_px(img,p[0],p[1],Color("53a898"))

static func _bedrock(img: Image) -> void:
	img.fill(Color("55565a"))
	for s in [[0,1,7,3],[8,0,4,4],[4,5,7,4],[12,5,5,3],[0,10,5,4],[7,11,8,4]]:
		_cluster(img,s[0],s[1],s[2],s[3],Color("30343a"),Color("727573"))
	_line(img,1,8,6,8,Color("858785"))
	_line(img,9,9,15,9,Color("20242a"))

static func _sediment(img: Image,id: int,c: Color) -> void:
	if id == 49:
		img.fill(Color("716e69"))
		for p in [[0,0],[5,1],[10,0],[2,5],[8,6],[13,5],[0,11],[5,12],[11,11]]:
			_cluster(img,p[0],p[1],4,4,Color("96938b"),Color("b5b0a5"))
		return
	img.fill(c)
	for p in [[1,2],[6,0],[11,4],[3,7],[8,8],[14,10],[1,13],[7,14]]:
		_rect(img,p[0],p[1],3,1,c.darkened(.10))
		_px(img,p[0]+1,p[1]+1,c.lightened(.12))
	if id == 21:
		for p in [[2,2],[10,9]]:
			_cluster(img,p[0],p[1],4,5,c.darkened(.27),c.lightened(.08))
			_px(img,p[0]+1,p[1]+2,c.darkened(.50))
			_px(img,p[0]+3,p[1]+2,c.darkened(.50))
	elif id == 96:
		for p in [[1,1],[8,2],[4,7],[12,8],[1,12],[9,13]]:
			_cluster(img,p[0],p[1],3,3,Color("928b35"),Color("e5d56a"))
	elif id == 48:
		_line(img,1,5,8,5,c.darkened(.11))
		_line(img,6,11,14,11,c.lightened(.11))

static func _sandstone(img: Image,face: int,c: Color) -> void:
	_sediment(img,8,c)
	if face in [2,3]:
		_line(img,3,4,6,4,c.darkened(.14))
		_line(img,6,4,6,8,c.darkened(.14))
		return
	for y in [3,9,14]:
		_line(img,0,y,15,y,c.darkened(.14))
		_line(img,0,y+1,15,y+1,c.lightened(.08))
	_line(img,3,4,3,8,c.darkened(.1))
	_line(img,11,10,11,13,c.darkened(.1))

static func _snow(img: Image,face: int) -> void:
	img.fill(Color("e5edf0"))
	for p in [[1,2],[8,1],[4,8],[11,11],[1,14]]:
		_line(img,p[0],p[1],p[0]+3,p[1],Color("d1e0e5"))
		_px(img,p[0]+1,p[1]-1,Color("f7fbf5"))
	if face != 2:
		_line(img,0,13,15,13,Color("cfdee3"))
		_line(img,2,14,11,14,Color("becfd9"))

static func _water(img: Image) -> void:
	img.fill(Color("357eb8"))
	for row in [[0,2,5],[7,5,7],[2,9,6],[10,13,6],[0,15,4]]:
		_line(img,row[0],row[1],row[0]+row[2],row[1],Color("4b98c9"))
		_line(img,row[0]+1,row[1]+1,row[0]+row[2]-1,row[1]+1,Color("3b88bd"))
	_line(img,1,6,4,6,Color("2a6ca6"))
	_line(img,8,10,13,10,Color("2a6ca6"))

static func _lava(img: Image,magma: bool) -> void:
	img.fill(Color("f39a24") if not magma else Color("ed7b20"))
	var cells: Array = [[0,0,5,5],[7,-1,5,5],[12,3,5,6],[3,6,6,5],[-2,10,5,5],[9,11,6,5]]
	for i in cells.size():
		var s: Array = cells[i]
		var color: Color = Color("803626") if magma else Color("dc5520")
		_cluster(img,s[0],s[1],s[2],s[3],color,Color("ba4825") if magma else Color("ef7421"))
		_rect(img,s[0]+2,s[1]+2,2,2,Color("442c2b") if magma else Color("c43d1f"))
	for p in [[6,3],[1,7],[10,9],[6,13],[14,0]]:
		_line(img,p[0],p[1],p[0]+1,p[1]+1,Color("ffe284"))

static func _glass(img: Image,id: int,c: Color) -> void:
	if id == 16:
		img.fill(Color("86b3c0"))
		_rect(img,1,1,14,14,Color("a7cbd0"))
		_line(img,0,0,15,0,Color("e5f1e7"))
		_line(img,0,0,0,15,Color("d6e8de"))
		_line(img,15,1,15,15,Color("68929e"))
		_line(img,1,15,15,15,Color("68929e"))
		_line(img,3,6,6,3,Color("e8f4ef"))
		_line(img,8,12,12,8,Color("cfe5e4"))
		return
	img.fill(c)
	if id in [87,88]:
		for s in [[2,7,8,1],[5,12,11,6],[11,15,15,11]]:
			_line(img,s[0],s[1],s[2],s[3],c.lightened(.30))
			_line(img,s[0]+1,s[1],s[2]+1,s[3],c.darkened(.12))
	else:
		_rect(img,1,1,14,14,c.lightened(.13))
		_rect(img,3,3,10,10,c)
		_rect(img,4,3,3,2,c.lightened(.25))
		_rect(img,10,10,2,2,c.darkened(.20))
		if id == 98:
			_rect(img,4,6,2,2,c.darkened(.18))
			_rect(img,10,6,2,2,c.darkened(.18))
			_line(img,6,11,9,11,c.darkened(.20))

static func _obsidian(img: Image) -> void:
	img.fill(Color("211d30"))
	for s in [[0,1,6,4],[8,-1,7,5],[3,6,8,4],[12,8,5,5],[-2,12,7,5],[6,12,5,4]]:
		_cluster(img,s[0],s[1],s[2],s[3],Color("30263d"),Color("47334e"))
	_line(img,1,7,3,7,Color("665071"))
	_line(img,10,4,12,4,Color("57405f"))
	_px(img,8,13,Color("725480"))

static func _netherrack(img: Image) -> void:
	img.fill(Color("632c32"))
	for s in [[0,0,6,4],[8,1,7,4],[2,6,6,4],[10,7,5,5],[-2,12,7,5],[6,13,4,4]]:
		_cluster(img,s[0],s[1],s[2],s[3],Color("803a3d"),Color("9d4b46"))
	for p in [[2,2],[11,3],[4,8],[12,10],[1,14]]:
		_px(img,p[0],p[1],Color("4b2630"))

static func _endstone(img: Image) -> void:
	img.fill(Color("c7c793"))
	for p in [[1,1],[8,0],[12,5],[4,7],[0,12],[9,12]]:
		_cluster(img,p[0],p[1],4,3,Color("b5b681"),Color("dedbad"))
		_px(img,p[0]+2,p[1]+1,Color("929b6f"))
	for p in [[6,3],[11,9],[5,14]]:
		_px(img,p[0],p[1],Color("e8e1b9"))

static func _light(img: Image,id: int,c: Color,face: int) -> void:
	if id == 90:
		img.fill(Color("5a978e"))
		_rect(img,1,1,14,14,Color("a9d7bf"))
		_rect(img,3,3,10,10,Color("e3edcb"))
		_rect(img,5,5,6,6,Color("f2f1d9"))
		for p in [[1,1],[12,1],[1,12],[12,12]]:
			_rect(img,p[0],p[1],3,3,Color("77b1a1"))
		return
	if id == 146:
		_obsidian(img)
		if face in [2,3]:
			_rect(img,2,2,12,12,Color("4a3657"))
			_rect(img,4,4,8,8,Color("282338"))
			_rect(img,6,6,4,4,Color("664c79") if face == 2 else Color("353042"))
			return
		_rect(img,3,3,10,10,Color("694383"))
		_rect(img,5,4,6,8,Color("b989d4"))
		_rect(img,7,5,2,6,Color("e8c9f1"))
		return
	img.fill(Color("94713e") if id == 22 else Color("b97839"))
	for p in [[0,0],[6,0],[12,2],[2,5],[8,6],[0,11],[6,12],[12,11]]:
		_cluster(img,p[0],p[1],5,4,c,c.lightened(.30))
		_rect(img,p[0]+2,p[1]+1,2,2,Color("f7e8a7") if id == 22 else Color("ffda8a"))

static func _crafting(img: Image,face: int) -> void:
	_planks(img,Color("a87843"),25)
	if face == 3:
		return
	_rect(img,0,0,16,2,Color("5b3d28"))
	_rect(img,0,0,2,16,Color("5b3d28"))
	_rect(img,14,0,2,16,Color("5b3d28"))
	if face == 2:
		_rect(img,2,2,12,12,Color("bc955a"))
		for x in [2,6,10,13]:
			_line(img,x,2,x,13,Color("67472e"))
		for y in [2,6,10,13]:
			_line(img,2,y,13,y,Color("67472e"))
		_line(img,2,14,13,14,Color("d0ab71"))
	else:
		_rect(img,2,3,12,10,Color("8b6038"))
		if face in [4,5]:
			_line(img,4,5,4,11,Color("d6b37b"))
			_line(img,3,5,6,5,Color("bfc0ac"))
			_line(img,10,7,10,12,Color("563d2a"))
			_rect(img,9,4,3,4,Color("9baba6"))
			_px(img,9,4,Color("d3d7bc"))
		else:
			_rect(img,3,5,10,2,Color("c0965a"))
			_line(img,4,7,4,12,Color("65462e"))
			_line(img,11,7,11,12,Color("65462e"))
			_line(img,5,9,10,9,Color("aeb5a8"))
			for x in [6,8,10]:
				_px(img,x,10,Color("bbc1b0"))
		_rect(img,0,13,16,3,Color("63452e"))

static func _furnace(img: Image,face: int) -> void:
	_stone(img,3,Color("838783"))
	_rect(img,0,0,16,1,Color("b2b6a9"))
	_rect(img,0,15,16,1,Color("4b5254"))
	_rect(img,0,1,1,14,Color("9ba399"))
	_rect(img,15,1,1,14,Color("515958"))
	if face in [2,3]:
		_rect(img,2,2,12,12,Color("747d7a"))
		_line(img,2,2,13,2,Color("a3aa9d"))
		_line(img,2,2,2,13,Color("929b92"))
		_line(img,3,13,13,13,Color("535d5c"))
		if face == 2:
			_line(img,5,5,10,5,Color("66716e"))
			_line(img,10,5,10,10,Color("66716e"))
	elif face == 5:
		# The mouth exists on the front only. Top, rear and sides are intact stone.
		_rect(img,3,3,10,4,Color("4d5554"))
		_rect(img,4,3,8,3,Color("232e31"))
		_rect(img,3,9,10,5,Color("434c4c"))
		_rect(img,4,9,8,4,Color("202a2e"))
		_line(img,4,13,11,13,Color("958773"))
		for x in [5,8,10]:
			_px(img,x,12,Color("745445"))
	else:
		_line(img,2,7,13,7,Color("646e6b"))
		_line(img,2,8,13,8,Color("959d91"))
		_line(img,8,2,8,6,Color("68716c"))
		_line(img,5,9,5,13,Color("68716c"))

static func _chest(img: Image,face: int) -> void:
	_planks(img,Color("b48342"),27)
	var trim: Color = Color("553b26")
	if face in [2,3]:
		_rect(img,0,0,16,2,trim)
		_rect(img,0,14,16,2,trim)
		_rect(img,0,0,2,16,trim)
		_rect(img,14,0,2,16,trim)
		_line(img,2,2,13,2,Color("d1a85f"))
		_line(img,3,8,12,8,Color("997039"))
		return
	_rect(img,0,0,16,2,trim)
	_rect(img,0,14,16,2,trim)
	_rect(img,0,0,2,16,trim)
	_rect(img,14,0,2,16,trim)
	_line(img,2,5,13,5,Color("3d3025"))
	_line(img,2,6,13,6,Color("dbac62"))
	for p in [[1,1],[14,1],[1,14],[14,14]]:
		_px(img,p[0],p[1],Color("9a9071"))
	if face == 5:
		_rect(img,6,4,4,6,Color("4d4133"))
		_rect(img,7,4,2,5,Color("c8c3a1"))
		_px(img,7,4,Color("f4e9c6"))
		_px(img,8,7,Color("70694f"))
	elif face == 4:
		_rect(img,3,4,3,3,Color("756e54"))
		_rect(img,10,4,3,3,Color("756e54"))

static func _bookshelf(img: Image,face: int) -> void:
	_planks(img,Color("b4894d"),91)
	if face in [2,3]:
		return
	if face in [0,1]:
		_rect(img,1,1,14,14,Color("74532f"))
		_rect(img,2,2,12,12,Color("ac7e45"))
		_line(img,3,3,12,3,Color("c79d5c"))
		_line(img,7,4,7,12,Color("926637"))
		_line(img,3,12,12,12,Color("61472b"))
		return
	img.fill(Color("352c29"))
	var book_colors: Array = [Color("aa5d4b"),Color("537e89"),Color("c3a368"),Color("6f8a58"),Color("8b657d"),Color("cf8751")]
	for row in 2:
		var baseline: int = 6+row*8
		for i in 6:
			var x: int = 1+i*2
			var height: int = 3+posmod(i+row+face,3)
			var color: Color = book_colors[posmod(i+row*3+face-5,book_colors.size())]
			_rect(img,x,baseline-height,2,height,color)
			_line(img,x,baseline-height,x,baseline-1,color.lightened(.18))
			_px(img,x,baseline-2,Color("d7bc7f"))
		_rect(img,0,baseline+1,16,2,Color("a97d42"))
		_line(img,0,baseline+1,15,baseline+1,Color("d0a25e"))
		_line(img,0,baseline,15,baseline,Color("503b27"))
	_rect(img,0,0,16,1,Color("c99f5d"))
	_rect(img,0,0,1,16,Color("8c6336"))
	_rect(img,15,0,1,16,Color("73512f"))

static func _torch(img: Image,face: int) -> void:
	img.fill(Color("a76b31"))
	if face == 2:
		_rect(img,1,1,14,14,Color("e79a30"))
		_rect(img,4,4,8,8,Color("ffda70"))
		_rect(img,6,6,4,4,Color("fff1bc"))
	else:
		for x in [1,5,10,14]:
			_line(img,x,4,x,15,Color("76502f"))
		_rect(img,0,0,16,5,Color("f1a039"))
		_rect(img,3,0,10,3,Color("ffe18c"))

static func _portal(img: Image,id: int) -> void:
	var c: Color = Color("67358c") if id == 29 else Color("174b57")
	img.fill(c.darkened(.35))
	for ring in [1,4,7]:
		var color: Color = c.lightened(float(ring)/25.0)
		_line(img,ring,ring,15-ring,ring,color)
		_line(img,15-ring,ring,15-ring,15-ring,color)
		_line(img,ring+1,15-ring,15-ring,15-ring,color)
		_line(img,ring+1,ring+2,ring+1,15-ring,color)
	for p in [[2,4],[11,2],[6,12],[14,10]]:
		_px(img,p[0],p[1],Color("d8b1ed") if id == 29 else Color("9ed9cd"))

static func _pillar(img: Image,face: int,c: Color,id: int) -> void:
	if face in [2,3]:
		_stone(img,id,c)
		for d in [1,4]:
			_line(img,d,d,15-d,d,c.lightened(.13))
			_line(img,15-d,d,15-d,15-d,c.darkened(.17))
			_line(img,d,15-d,15-d,15-d,c.darkened(.17))
			_line(img,d,d,d,15-d,c.lightened(.13))
	else:
		img.fill(c)
		for x in range(0,16,4):
			_line(img,x,0,x,15,c.darkened(.27))
			_line(img,x+1,0,x+1,15,c.lightened(.17))
			_line(img,x+3,0,x+3,15,c.darkened(.08))

static func _quartz(img: Image,face: int) -> void:
	img.fill(Color("e0dace"))
	_line(img,0,0,15,0,Color("f6f0df"))
	_line(img,0,0,0,15,Color("eee8d8"))
	_line(img,15,0,15,15,Color("b9b3a7"))
	_line(img,0,15,15,15,Color("c7c0b3"))
	if face != 3:
		_line(img,4,5,7,4,Color("d1c9bb"))
		_line(img,7,4,10,6,Color("d1c9bb"))
		_line(img,8,11,12,10,Color("eee7d6"))

static func _metal(img: Image,id: int,c: Color) -> void:
	if id == 83:
		img.fill(Color("2c4b85"))
		for s in [[0,1,6,4],[8,0,7,4],[3,6,7,4],[-1,12,6,4],[9,11,7,5]]:
			_cluster(img,s[0],s[1],s[2],s[3],Color("365e9d"),Color("4a76b4"))
		for p in [[3,3],[11,2],[7,9],[13,13]]:
			_px(img,p[0],p[1],Color("ad9e69"))
			_px(img,p[0]+1,p[1],Color("7d805c"))
		return
	if id == 84:
		img.fill(Color("762f39"))
		for s in [[0,0,6,5],[8,0,7,4],[3,6,7,5],[-1,12,5,4],[11,9,5,6]]:
			_cluster(img,s[0],s[1],s[2],s[3],Color("b13e43"),Color("d95b52"))
			_px(img,s[0]+2,s[1]+2,Color("8b303b"))
		return
	img.fill(c)
	_line(img,0,0,15,0,c.lightened(.32))
	_line(img,0,0,0,15,c.lightened(.20))
	_line(img,15,0,15,15,c.darkened(.32))
	_line(img,0,15,15,15,c.darkened(.24))
	_rect(img,2,2,12,12,c.darkened(.04))
	_line(img,2,2,13,2,c.lightened(.12))
	_line(img,3,3,9,3,c.lightened(.15))
	_line(img,3,4,6,4,c.lightened(.10))
	_line(img,6,12,12,12,c.darkened(.10))
	for p in [[1,1],[14,1],[1,14],[14,14]]:
		_px(img,p[0],p[1],c.darkened(.21))
	if id == 81:
		for p in [[2,7],[9,3],[10,11]]:
			_cluster(img,p[0],p[1],4,3,Color("4d8f80"),Color("74b5a0"))
	elif id == 79:
		for y in range(3,13):
			for x in range(3,13):
				var d: int = absi(x-7)+absi(y-7)
				if d < 7:
					_px(img,x,y,Color("8ce0d6") if x+y < 14 else Color("36a2aa"))
		_line(img,4,7,7,4,Color("b6f2e3"))
		_line(img,8,11,11,8,Color("2e8899"))
	elif id == 82:
		_rect(img,4,3,8,10,Color("2b8e64"))
		_rect(img,5,4,6,8,Color("5cc988"))
		_line(img,5,4,5,10,Color("a0e4aa"))
		_line(img,10,5,10,11,Color("247a64"))
	elif id == 77:
		_line(img,1,7,14,7,Color("adb7b7"))
		_line(img,1,8,14,8,Color("e0e5d9"))
	elif id == 142:
		_line(img,1,4,14,4,Color("6d636e"))
		_line(img,1,11,14,11,Color("2f303b"))
		for p in [[3,3],[12,3],[3,12],[12,12]]:
			_px(img,p[0],p[1],Color("93818b"))

static func _crystal(img: Image,id: int,c: Color) -> void:
	img.fill(c.darkened(.30))
	for p in [[0,0],[7,1],[3,7],[11,9],[-2,12]]:
		for y in 6:
			for x in 6:
				if absi(x-2)+absi(y-2) < 4:
					_px(img,p[0]+x,p[1]+y,c.lightened(.22) if x+y < 5 else c.darkened(.05))
		_px(img,p[0]+2,p[1],c.lightened(.5))
	if id == 140:
		for p in [[3,3],[10,5],[7,12]]:
			_px(img,p[0],p[1],Color("8c5c9f"))

static func _prismarine(img: Image) -> void:
	_cobble(img,Color("5e9a89"),89)
	for p in [[2,3],[9,1],[6,9],[12,13]]:
		_line(img,p[0],p[1],p[0]+2,p[1],Color("98bca0"))
		_px(img,p[0]+1,p[1]+1,Color("306c6d"))

static func _hay(img: Image,face: int) -> void:
	img.fill(Color("bfa146"))
	for x in range(0,16,2):
		_line(img,x,0,x,15,Color("e0c66a") if x%4==0 else Color("9f8136"))
		for y in [2,8,13]:
			_px(img,x+1,y,Color("d5b950"))
	if face not in [2,3]:
		for y in [3,12]:
			_rect(img,0,y,16,2,Color("8c5036"))
			_line(img,0,y,15,y,Color("b07742"))

static func _gourd(img: Image,id: int,face: int) -> void:
	var c: Color = Color("bc762d") if id == 93 else Color("78a342")
	img.fill(c)
	if face in [2,3]:
		for d in [1,4]:
			_line(img,d,d,15-d,d,c.lightened(.14))
			_line(img,d,15-d,15-d,15-d,c.darkened(.17))
			_line(img,d,d,d,15-d,c.lightened(.08))
			_line(img,15-d,d,15-d,15-d,c.darkened(.17))
		if face == 2:
			_rect(img,6,6,4,4,Color("69703c"))
			_rect(img,7,5,2,4,Color("8b8e4b"))
		return
	for x in [1,5,9,13]:
		_line(img,x,0,x,15,c.darkened(.26))
		_line(img,x+1,0,x+1,15,c.darkened(.17))
		_line(img,x+2,0,x+2,15,c.lightened(.13))
	if id == 93 and face == 5:
		_rect(img,3,4,3,3,Color("684c29"))
		_rect(img,10,4,3,3,Color("684c29"))
		_line(img,4,11,11,11,Color("684c29"))
		_px(img,5,10,Color("684c29"))
		_px(img,10,12,Color("684c29"))

static func _cactus(img: Image,face: int) -> void:
	img.fill(Color("4e8741"))
	if face in [2,3]:
		_rect(img,1,1,14,14,Color("7ba15b"))
		_rect(img,3,3,10,10,Color("9db973"))
		_rect(img,5,5,6,6,Color("adc680"))
		_px(img,7,7,Color("c4d795"))
		for p in [[2,2],[12,2],[2,12],[12,12]]:
			_px(img,p[0],p[1],Color("3b6637"))
		return
	for x in [1,5,10,14]:
		_line(img,x,0,x,15,Color("2f6537"))
		_line(img,x+1,0,x+1,15,Color("75a254"))
	for p in [[3,2],[11,4],[7,9],[2,12],[13,13]]:
		_px(img,p[0],p[1],Color("c8d39a"))
		_px(img,p[0]-1,p[1]+1,Color("d7dfae"))
		_px(img,p[0],p[1]+1,Color("2e5631"))

static func _tnt(img: Image,face: int) -> void:
	img.fill(Color("ad4837"))
	if face in [2,3]:
		for p in [[0,0],[8,0],[0,8],[8,8]]:
			_rect(img,p[0]+1,p[1]+1,6,6,Color("d16343"))
			_rect(img,p[0]+2,p[1]+2,4,4,Color("8e3c31"))
			_px(img,p[0]+3,p[1]+3,Color("d8b184"))
		_rect(img,0,7,16,2,Color("6c523b"))
		_rect(img,7,0,2,16,Color("6c523b"))
		if face == 2:
			_line(img,8,7,10,4,Color("e1c38c"))
			_px(img,10,3,Color("3e3530"))
		return
	for x in [0,4,8,12]:
		_line(img,x,0,x,15,Color("782f2c"))
		_line(img,x+1,0,x+1,15,Color("d36a4c"))
	_rect(img,0,5,16,6,Color("e3d5b3"))
	_rect(img,0,5,16,1,Color("f3e6c5"))
	_glyph(img,"T",2,6,Color("3c3530"))
	_glyph(img,"N",6,6,Color("3c3530"))
	_glyph(img,"T",10,6,Color("3c3530"))

static func _terracotta(img: Image,c: Color,id: int) -> void:
	img.fill(c)
	for p in [[1,3],[7,1],[11,9],[4,12]]:
		_line(img,p[0],p[1],p[0]+3,p[1],c.lightened(.055))
		_px(img,p[0]+2,p[1]+1,c.darkened(.045))
	if id == 100:
		_line(img,1,7,5,8,c.darkened(.10))
		_line(img,9,14,14,13,c.darkened(.08))

static func _wool(img: Image,c: Color) -> void:
	img.fill(c)
	for y in range(0,16,4):
		for x in range(0,16,4):
			_line(img,x,y+1,x+2,y+1,c.lightened(.12))
			_line(img,x+2,y+2,x+2,y+3,c.darkened(.12))
			_px(img,x,y+3,c.darkened(.055))

static func _concrete(img: Image,c: Color) -> void:
	img.fill(c)
	for p in [[2,4],[10,2],[7,11],[14,14]]:
		_rect(img,p[0],p[1],2,1,c.lightened(.025))
	for p in [[5,1],[13,7],[1,12]]:
		_px(img,p[0],p[1],c.darkened(.04))

static func _debris(img: Image,face: int) -> void:
	img.fill(Color("694d45"))
	if face in [2,3]:
		for d in [0,3,6]:
			_line(img,d,d,15-d,d,Color("a7836b"))
			_line(img,d,d,d,15-d,Color("92715d"))
			_line(img,d,15-d,15-d,15-d,Color("433b3b"))
			_line(img,15-d,d,15-d,15-d,Color("433b3b"))
	else:
		for y in [1,5,9,13]:
			_line(img,0,y,15,y,Color("a6826d"))
			_line(img,0,y+1,15,y+1,Color("4a3c3a"))
		_line(img,5,2,5,4,Color("413738"))
		_line(img,11,6,11,8,Color("413738"))

static func _mushroom(img: Image,id: int,face: int) -> void:
	if face == 3:
		img.fill(Color("d9c8a8"))
		for x in range(1,16,3):
			_line(img,x,0,x,15,Color("b9a68b"))
		return
	img.fill(Color("bf5346") if id == 143 else Color("a88e6a"))
	for p in [[1,1],[9,2],[4,9],[13,12]]:
		_cluster(img,p[0],p[1],3,3,Color("e1d4b6") if id==143 else Color("c5b08b"),Color("eee2c8"))

static func _enchanting(img: Image,face: int) -> void:
	_obsidian(img)
	if face == 2:
		_rect(img,1,1,14,14,Color("843c50"))
		_rect(img,3,3,10,10,Color("aa5966"))
		for p in [[1,1],[12,1],[1,12],[12,12]]:
			_rect(img,p[0],p[1],3,3,Color("62c2bc"))
		_line(img,5,7,7,5,Color("e5c477"))
		_line(img,7,5,10,8,Color("e5c477"))
		_line(img,10,8,8,11,Color("e5c477"))
		_line(img,8,11,5,7,Color("e5c477"))
	elif face != 3:
		_rect(img,0,0,16,3,Color("963e52"))
		_line(img,0,3,15,3,Color("e2bc71"))
		_rect(img,6,6,4,5,Color("66b6b4"))
		_px(img,7,7,Color("a0e1d0"))

static func _glyph(img: Image,character: String,x: int,y: int,color: Color) -> void:
	var glyphs: Dictionary = {
		"A":["010","101","111","101","101"],"B":["110","101","110","101","110"],"C":["011","100","100","100","011"],"D":["110","101","101","101","110"],"E":["111","100","110","100","111"],"F":["111","100","110","100","100"],"G":["011","100","101","101","011"],"H":["101","101","111","101","101"],"I":["111","010","010","010","111"],"J":["001","001","001","101","010"],"K":["101","101","110","101","101"],"L":["100","100","100","100","111"],"M":["101","111","111","101","101"],"N":["101","111","111","111","101"],"O":["010","101","101","101","010"],"P":["110","101","110","100","100"],"Q":["010","101","101","111","011"],"R":["110","101","110","101","101"],"S":["011","100","010","001","110"],"T":["111","010","010","010","010"],"U":["101","101","101","101","111"],"V":["101","101","101","101","010"],"W":["101","101","111","111","101"],"X":["101","101","010","101","101"],"Y":["101","101","010","010","010"],"Z":["111","001","010","100","111"],
		"0":["111","101","101","101","111"],"1":["010","110","010","010","111"],"2":["110","001","010","100","111"],"3":["110","001","010","001","110"],"4":["101","101","111","001","001"],"5":["111","100","110","001","110"],"6":["011","100","111","101","111"],"7":["111","001","010","010","010"],"8":["111","101","111","101","111"],"9":["111","101","111","001","110"],"-":["000","000","111","000","000"],"/":["001","001","010","100","100"],"+":["000","010","111","010","000"]
	}
	if not glyphs.has(character):
		return
	var rows: Array = glyphs[character]
	for py in 5:
		for px in 3:
			if rows[py][px] == "1":
				_px(img,x+px,y+py,color)

static func _text(img: Image,text: String,x: int,y: int,color: Color) -> void:
	for i in text.length():
		_glyph(img,text[i].to_upper(),x+i*4,y,color)

static func export_art(directory: String) -> Error:
	prepare()
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error
	error = _atlas.save_png(directory.path_join("blocks_atlas.png"))
	if error != OK:
		return error
	var base_ids: Array[int] = []
	for entry in BlockDB.all_blocks():
		if int(entry.id) > 0 and not entry.has("base_id"):
			base_ids.append(int(entry.id))
	base_ids.sort()
	var count: int = base_ids.size()
	var rows: int = ceili(float(count)/8.0)
	var sheet = Image.create(1024,rows*84+38,false,Image.FORMAT_RGBA8)
	sheet.fill(Color("20282a"))
	_text(sheet,"SLOPCRAFT 2 / ORIGINAL 16X16 BLOCK TEXTURES",16,12,Color("e7dfba"))
	_text(sheet,"TOP  FRONT  SIDE / ONE MATERIAL SIX FACES",16,23,Color("93ada5"))
	for index in base_ids.size():
		var id: int = base_ids[index]
		var x: int = (index%8)*128+8
		var y: int = (index/8)*84+40
		_rect(sheet,x-3,y-3,122,77,Color("2b3536"))
		for f in 3:
			var face: int = [2,5,0][f]
			var tile: Image = face_image(id,face)
			tile.resize(32,32,Image.INTERPOLATE_NEAREST)
			sheet.blit_rect(tile,Rect2i(0,0,32,32),Vector2i(x+f*37,y))
		_text(sheet,"%03d"%id,x,y+39,Color("9bc9ad"))
		var name: String = BlockDB.item_name(id).to_upper()
		_text(sheet,name.left(28),x,y+49,Color("e2dfcd"))
		_text(sheet,"T       F        S",x,y+62,Color("839b98"))
	error = sheet.save_png(directory.path_join("blocks_contact_sheet.png"))
	if error != OK:
		return error
	var utility_ids: Array = [1,5,25,26,27,54,91,93,94,95,97,146,153,154,159,160,161,162,163,180]
	var utility = Image.create(640,utility_ids.size()*88+30,false,Image.FORMAT_RGBA8)
	utility.fill(Color("20282a"))
	_text(utility,"SIX FACES / RIGHT LEFT TOP BOTTOM BACK FRONT",10,10,Color("e7dfba"))
	for row in utility_ids.size():
		var id: int = utility_ids[row]
		var y: int = 30+row*88
		_text(utility,"%03d %s"%[id,BlockDB.item_name(id)],10,y,Color("e3ddc8"))
		for face in 6:
			var tile: Image = face_image(id,face)
			tile.resize(64,64,Image.INTERPOLATE_NEAREST)
			utility.blit_rect(tile,Rect2i(0,0,64,64),Vector2i(10+face*103,y+11))
	return utility.save_png(directory.path_join("utility_faces.png"))

static func _bed(img: Image,id: int,face: int) -> void:
	if face == 3:
		_planks(img,Color("997244"),7)
		return
	img.fill(Color("91313f"))
	if face == 2:
		# X is bed width, Y is distance from its head (-Z). Both halves join
		# continuously at their common edge; the pillow occurs only at the head.
		_rect(img,1,0,14,16,Color("b9434e"))
		_line(img,1,0,1,15,Color("d76363"))
		_line(img,14,0,14,15,Color("7b2c3a"))
		for y in [3,9,14]:
			_line(img,4,y,10,y,Color("b13c49"))
			_px(img,5,y-1,Color("c85055"))
		if id == 182:
			_rect(img,1,0,14,8,Color("bcc0b6"))
			_rect(img,2,1,12,6,Color("eee9dc"))
			_line(img,3,1,12,1,Color("fff7e6"))
			_line(img,3,6,12,6,Color("d0d4c9"))
			_px(img,2,2,Color("dbe0d6"))
			_line(img,1,8,14,8,Color("d65d5f"))
			_line(img,1,9,14,9,Color("a13747"))
		else:
			_line(img,1,15,14,15,Color("7b2c3a"))
	else:
		# Side mapping samples Y=7..12: four pixels of mattress and two
		# pixels of oak frame, preserving the world's 16 texels/block scale.
		_line(img,0,7,15,7,Color("d15b5d"))
		_line(img,0,10,15,10,Color("702735"))
		_rect(img,0,11,16,5,Color("795234"))
		_line(img,0,11,15,11,Color("b98a52"))
		_line(img,0,12,15,12,Color("67452e"))
		for x in [2,9]: _line(img,x,12,x+3,12,Color("90673e"))
		if id == 182:
			if face in [0,1]:
				var start=0 if face==0 else 8
				_rect(img,start,7,8,3,Color("d6d9ce"))
				_line(img,start,7,start+7,7,Color("f2eee0"))
			elif face==5:
				_rect(img,0,7,16,3,Color("d6d9ce"))
				_line(img,1,7,14,7,Color("f2eee0"))

static func _snapshot_block(img: Image,id: int,face: int,c: Color) -> void:
	match id:
		181,182:
			_bed(img,id,face)
		183:
			_piston(img,159,face)
		147:
			_cobble(img,Color("4f555d"),147)
			_line(img,1,7,4,7,Color("797a7c"))
			_line(img,8,12,11,12,Color("343a44"))
		148:
			_deepslate(img,face,true)
		149:
			_bricks(img,59,Color("48505a"))
			for pair in [[3,1,4,4],[4,4,2,6],[11,8,10,11],[10,11,12,14]]:
				_line(img,pair[0],pair[1],pair[2],pair[3],Color("242c37"))
		150:
			img.fill(Color("272e38"))
			for row in 4:
				for col in range(-1,4):
					var x: int = col*6+(3 if row%2 else 0)
					_rect(img,x+1,row*4+1,5,3,Color("444e58"))
					_line(img,x+1,row*4+1,x+5,row*4+1,Color("606973"))
					_line(img,x+2,row*4+3,x+5,row*4+3,Color("343e48"))
		151,152,176:
			_sulfur(img,id,face)
		153,154:
			_end_frame(img,id,face)
		155,156,157,177,178,179:
			_circuit(img,id,face)
		158:
			_redstone_lamp(img,face)
		159,160:
			_piston(img,id,face)
		161,162,163:
			_machine(img,id,face)
		164:
			_torch(img,face)
			if face == 2:
				img.fill(Color("9d3037"))
				_rect(img,3,3,10,10,Color("e16b5c"))
				_rect(img,5,5,5,5,Color("f9b092"))
			elif face != 3:
				_rect(img,0,0,16,5,Color("b64742"))
				_rect(img,3,0,10,3,Color("f08a6d"))
		165,166,168:
			_plant(img,id)
		167,169:
			_dirt(img)
			if face == 2:
				if id == 167:
					img.fill(Color("715037"))
					for x in [1,5,9,13]:
						_line(img,x,0,x,15,Color("433e2f"))
						_line(img,x+1,0,x+1,15,Color("9b7149"))
						for y in [2,8,13]:
							_px(img,x+2,y,Color("b18a5e"))
				else:
					_sediment(img,8,Color("ac9368"))
					for p in [[1,2],[7,7],[12,12]]:
						_cluster(img,p[0],p[1],3,2,Color("8a795b"),Color("c3ac80"))
			elif face != 3:
				_rect(img,0,0,16,3,Color("785a3d") if id == 167 else Color("aa9165"))
		170,171,172,173,174,175:
			var base: int = {170:11,171:12,172:13,173:14,174:75,175:73}[id]
			_ore(img,base,c,true)
		180:
			_hopper(img,face)
		_:
			_stone(img,id,c)

static func _deepslate(img: Image,face: int,polished: bool = false) -> void:
	img.fill(Color("404751"))
	for row in 4:
		var y: int = row*4
		var off: int = row*3%7
		_line(img,0,y,15,y,Color("303843"))
		_line(img,off,y+1,mini(off+7,15),y+1,Color("626b73"))
		_line(img,0,y+3,6,y+3,Color("4f5863"))
		_line(img,9,y+2,15,y+2,Color("454d58"))
		_line(img,off+6,y+1,off+6,y+3,Color("343d49"))
	if face in [2,3]:
		_line(img,2,5,5,3,Color("788087"))
		_line(img,9,10,13,10,Color("2d3642"))
	if polished:
		_line(img,0,0,15,0,Color("7c8389"))
		_line(img,0,0,0,15,Color("636d77"))
		_line(img,15,0,15,15,Color("2c3441"))
		_line(img,0,15,15,15,Color("303844"))
		_line(img,2,2,8,2,Color("6e7780"))

static func _sulfur(img: Image,id: int,face: int) -> void:
	if id in [152,176]:
		_deepslate(img,face)
	else:
		img.fill(Color("9fa540"))
	var deposits: Array = [[0,1,6,4],[9,0,5,5],[3,7,6,5],[11,9,5,4],[0,13,4,3]]
	for s in deposits:
		_cluster(img,s[0],s[1],s[2],s[3],Color("bac455"),Color("dce28a"))
		_line(img,s[0]+1,s[1]+2,s[0]+3,s[1]+2,Color("d4d86a"))
		_px(img,s[0]+2,s[1]+3,Color("858d32"))
	if id == 176:
		if face == 2:
			_cluster(img,3,3,10,10,Color("656e35"),Color("a8b14c"))
			_cluster(img,5,5,6,7,Color("313d32"),Color("505d37"))
			_rect(img,7,7,3,4,Color("202f2c"))
		elif face != 3:
			_line(img,3,1,5,8,Color("7d8d3d"))
			_line(img,11,3,9,12,Color("69753a"))

static func _end_frame(img: Image,id: int,face: int) -> void:
	_endstone(img)
	if face == 3:
		return
	var edge: Color = Color("365b58")
	if face == 2:
		img.fill(edge)
		_rect(img,1,1,14,14,Color("789d84"))
		_rect(img,3,3,10,10,Color("234449"))
		_rect(img,5,5,6,6,Color("152d36"))
		for p in [[1,1],[12,1],[1,12],[12,12]]:
			_rect(img,p[0],p[1],3,3,Color("b7c49a"))
		if id == 154:
			_cluster(img,4,5,8,6,Color("62a479"),Color("a7d28e"))
			_rect(img,7,5,2,6,Color("192d32"))
			_px(img,6,6,Color("e2e9b3"))
		return
	_rect(img,0,0,16,5,edge)
	_rect(img,0,0,16,1,Color("a6b99a"))
	for x in [1,6,11]:
		_rect(img,x,1,3,3,Color("6a8b76"))
	_line(img,0,5,15,5,Color("849b7e"))
	_line(img,3,8,5,8,Color("8f9f70"))
	_line(img,5,8,5,11,Color("8f9f70"))
	_line(img,11,10,13,10,Color("8f9f70"))

static func _circuit(img: Image,id: int,face: int) -> void:
	_stone(img,3,Color("999d99"))
	if id in [177,178]:
		if face == 2:
			_rect(img,1,1,14,14,Color("a0a39b"))
			_line(img,1,1,14,1,Color("c5c7b8"))
			_line(img,14,2,14,14,Color("6c7577"))
			_line(img,2,14,14,14,Color("6c7577"))
		return
	if id == 155:
		img.fill(Color.TRANSPARENT)
		_rect(img,0,6,16,4,Color("632e35"))
		_rect(img,6,0,4,16,Color("632e35"))
		_line(img,0,7,15,7,Color("b44747"))
		_line(img,7,0,7,15,Color("a23c43"))
		_rect(img,5,5,6,6,Color("8e343c"))
		_rect(img,6,6,3,3,Color("c4584e"))
		return
	if id == 156:
		if face == 2:
			_rect(img,3,3,10,10,Color("666e72"))
			_rect(img,5,4,5,8,Color("423d37"))
			_rect(img,6,3,3,8,Color("a38255"))
			_line(img,6,3,6,10,Color("d0ae73"))
		else:
			_rect(img,6,2,4,11,Color("876440"))
			_line(img,6,2,6,12,Color("b9955f"))
		return
	if face == 2:
		img.fill(Color("c4c4b7"))
		_rect(img,0,0,16,1,Color("e0ddc8"))
		_rect(img,0,15,16,1,Color("787f7f"))
		_rect(img,6,1,4,14,Color("78363c"))
		_line(img,7,1,7,14,Color("b44848"))
		for pos in ([Vector2i(6,3),Vector2i(6,10)] if id == 157 else [Vector2i(3,3),Vector2i(10,3),Vector2i(6,10)]):
			_rect(img,pos.x-1,pos.y-1,5,5,Color("5a4c43"))
			_rect(img,pos.x,pos.y,3,3,Color("bc574a"))
			_px(img,pos.x,pos.y,Color("ed9473"))
	elif face != 3:
		_rect(img,0,0,16,3,Color("c8c6b8"))
		_rect(img,0,3,16,2,Color("787e7e"))

static func _redstone_lamp(img: Image,face: int) -> void:
	img.fill(Color("483d30"))
	_rect(img,1,1,14,14,Color("b18643"))
	for p in [[2,2],[9,2],[2,9],[9,9]]:
		_rect(img,p[0],p[1],5,5,Color("c79e52"))
		_line(img,p[0],p[1],p[0]+3,p[1],Color("e7c477"))
		_line(img,p[0]+4,p[1]+1,p[0]+4,p[1]+4,Color("866438"))
	_rect(img,7,0,2,16,Color("69513a"))
	_rect(img,0,7,16,2,Color("69513a"))
	if face in [2,3]:
		_rect(img,5,5,6,6,Color("7d6340"))
		_rect(img,7,7,2,2,Color("c6a262"))

static func _piston(img: Image,id: int,face: int) -> void:
	if face == 5:
		_planks(img,Color("b5955b"),159)
		_rect(img,0,0,16,2,Color("645c4c"))
		_rect(img,0,14,16,2,Color("645c4c"))
		_rect(img,0,0,2,16,Color("6e7169"))
		_rect(img,14,0,2,16,Color("6e7169"))
		for p in [[1,1],[14,1],[1,14],[14,14]]:
			_px(img,p[0],p[1],Color("c2c2a8"))
		if id == 160:
			for s in [[2,2,6,5],[8,4,5,6],[3,9,7,5]]:
				_cluster(img,s[0],s[1],s[2],s[3],Color("7da852"),Color("a3c770"))
		return
	_stone(img,3,Color("777d7c"))
	if face == 4:
		_rect(img,3,3,10,10,Color("464d53"))
		_rect(img,5,5,6,6,Color("7c8381"))
		_line(img,6,6,9,6,Color("a7ada0"))
		return
	_rect(img,0,0,16,4,Color("a78a56"))
	_line(img,0,0,15,0,Color("d0b478"))
	_line(img,0,4,15,4,Color("40494f"))
	_rect(img,6,5,4,10,Color("454d52"))
	_rect(img,7,5,2,10,Color("bac0b5"))
	_line(img,1,12,5,12,Color("4f575c"))
	_line(img,10,12,14,12,Color("4f575c"))

static func _machine(img: Image,id: int,face: int) -> void:
	_furnace(img,0)
	if face == 5:
		_rect(img,2,2,12,12,Color("7d8585"))
		_line(img,2,2,13,2,Color("b1b7a7"))
		if id == 161:
			_rect(img,3,5,3,3,Color("252f37"))
			_rect(img,10,5,3,3,Color("252f37"))
			_px(img,4,5,Color("596779"))
			_px(img,11,5,Color("596779"))
			_line(img,5,11,10,11,Color("39464b"))
		else:
			_cluster(img,4,4,8,8,Color("414c53"),Color("b0b6aa"))
			_rect(img,6,6,4,4,Color("202b34"))
			if id == 163:
				_rect(img,5,10,6,2,Color("272f36"))
			else:
				_px(img,7,6,Color("667783"))
	elif face == 4 and id == 161:
		_rect(img,4,4,8,8,Color("414a50"))
		_rect(img,6,6,4,4,Color("a74243"))
		_px(img,6,6,Color("df7664"))
	elif face == 2:
		_furnace(img,2)
		if id == 161:
			_line(img,7,3,7,12,Color("ad4148"))
			_line(img,7,3,4,6,Color("ad4148"))
			_line(img,7,3,10,6,Color("ad4148"))

static func _plant(img: Image,id: int) -> void:
	img.fill(Color.TRANSPARENT)
	if id == 165:
		for p in [[2,7,5,15],[7,3,8,15],[12,5,10,15],[15,9,12,15],[1,12,6,15]]:
			_line(img,p[0],p[1],p[2],p[3],Color("61833c"))
			_line(img,p[0]+1,p[1]+1,p[2]+1,p[3],Color("91aa59"))
	elif id == 166:
		_line(img,7,5,7,15,Color("527a43"))
		_line(img,7,11,4,9,Color("87a55b"))
		_line(img,8,13,11,10,Color("6c964b"))
		for p in [[5,2],[8,2],[4,5],[9,5],[6,7]]:
			_cluster(img,p[0],p[1],3,3,Color("d692ad"),Color("f0c8d3"))
		_rect(img,6,4,3,3,Color("e9c773"))
		_px(img,7,4,Color("f9e2a4"))
	else:
		for p in [[3,4],[8,1],[12,5]]:
			_line(img,p[0],p[1],p[0],15,Color("a3943e"))
			for y in range(p[1],p[1]+7,2):
				_line(img,p[0]-2,y,p[0],y+1,Color("d2b755"))
				_line(img,p[0],y+1,p[0]+2,y-1,Color("e1c875"))
			_line(img,p[0],13,p[0]+3,10,Color("789645"))

static func _hopper(img: Image,face: int) -> void:
	img.fill(Color("535d65"))
	_line(img,0,0,15,0,Color("929b9c"))
	_line(img,0,0,0,15,Color("7b878e"))
	_line(img,15,0,15,15,Color("333e49"))
	_line(img,0,15,15,15,Color("333e49"))
	if face == 2:
		_rect(img,2,2,12,12,Color("2d3841"))
		_rect(img,3,3,10,10,Color("424d57"))
		_rect(img,5,5,6,6,Color("222d36"))
		_rect(img,6,6,4,4,Color("17252d"))
		_line(img,2,2,13,2,Color("a1a9a3"))
	elif face == 3:
		_rect(img,5,5,6,6,Color("28343e"))
		_rect(img,6,6,4,4,Color("17252d"))
	else:
		_rect(img,0,3,16,2,Color("303d48"))
		_line(img,2,6,5,12,Color("74818a"))
		_line(img,13,6,10,12,Color("333f4a"))
		_line(img,5,12,10,12,Color("333f4a"))
