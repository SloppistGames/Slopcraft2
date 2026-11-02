class_name ItemGlyphs
extends RefCounted
## Original 16-pixel item sprites. Cached and shared by every inventory slot.
## Draw with TEXTURE_FILTER_NEAREST at an integer multiple of 16 pixels.

static var _cache: Dictionary = {}
const INK := Color("25232b")
const WOOD := Color("946439")
const WOOD_LIGHT := Color("c2985e")

static func texture_for(id: int) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var image := Image.create(16,16,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var data: Dictionary = BlockDB.get_item(id)
	var color: Color = data.get("color",Color("c4b8a1"))
	var kind: String = str(data.get("kind","material"))
	var item_name: String = str(data.get("name","")).to_lower()
	if kind in ["pickaxe","axe","shovel","sword","hoe"]:
		_tool(image,kind,color)
	elif kind == "bow":
		_bow(image)
	elif kind == "armor":
		_armor(image,item_name,color)
	elif kind == "food":
		_food(image,id,item_name,color)
	elif kind == "bucket":
		_bucket(image,id)
	elif kind == "compass" or kind == "clock":
		_dial(image,kind == "clock")
	elif kind == "shears":
		_line(image,Vector2i(5,10),Vector2i(12,2),Color("bec7cb"),2)
		_line(image,Vector2i(10,10),Vector2i(4,2),Color("e2e5dd"),2)
		_ellipse(image,Rect2i(2,9,5,5),Color("777d80"))
		_ellipse(image,Rect2i(8,9,5,5),Color("939b9d"))
		_rect(image,Rect2i(3,10,2,2),Color.TRANSPARENT)
		_rect(image,Rect2i(10,10,2,2),Color.TRANSPARENT)
		_pixel(image,7,8,Color("eee7c9"))
	elif kind == "igniter":
		_poly(image,[Vector2(2,4),Vector2(5,2),Vector2(9,3),Vector2(11,7),Vector2(9,11),Vector2(5,12),Vector2(3,9)],Color("a7b5b9"))
		_poly(image,[Vector2(4,5),Vector2(6,4),Vector2(8,5),Vector2(9,8),Vector2(7,10),Vector2(5,9)],Color.TRANSPARENT)
		_poly(image,[Vector2(9,8),Vector2(12,6),Vector2(14,9),Vector2(12,13),Vector2(8,13)],Color("51505b"))
		_line(image,Vector2i(10,9),Vector2i(12,8),Color("8a8b93"))
	elif "potion" in item_name:
		_potion(image,color)
	elif "fish" in item_name or "salmon" in item_name or "cod" in item_name:
		_fish(image,color)
	else:
		_material(image,id,color)
	_outline(image)
	var texture := ImageTexture.create_from_image(image)
	_cache[id] = texture
	return texture

static func _tool(img: Image,kind: String,color: Color) -> void:
	var light: Color = color.lightened(.3)
	var dark: Color = color.darkened(.3)
	_line(img,Vector2i(3,13),Vector2i(10,6),WOOD,2)
	_line(img,Vector2i(3,12),Vector2i(9,6),WOOD_LIGHT)
	match kind:
		"pickaxe":
			_poly(img,[Vector2(3,3),Vector2(6,1),Vector2(10,1),Vector2(14,5),Vector2(14,9),Vector2(12,8),Vector2(11,5),Vector2(8,3),Vector2(5,4)],color)
			_line(img,Vector2i(5,2),Vector2i(9,2),light)
			_line(img,Vector2i(10,3),Vector2i(13,6),light)
			_line(img,Vector2i(12,6),Vector2i(13,8),dark)
		"axe":
			_poly(img,[Vector2(6,3),Vector2(9,1),Vector2(13,2),Vector2(14,6),Vector2(11,9),Vector2(8,7),Vector2(7,5)],color)
			_poly(img,[Vector2(10,2),Vector2(13,3),Vector2(13,6),Vector2(11,8),Vector2(10,6)],light)
			_line(img,Vector2i(7,4),Vector2i(9,6),dark)
		"shovel":
			_poly(img,[Vector2(7,5),Vector2(10,2),Vector2(13,2),Vector2(14,5),Vector2(11,9),Vector2(9,9)],color)
			_line(img,Vector2i(9,5),Vector2i(12,3),light,2)
			_line(img,Vector2i(10,8),Vector2i(13,5),dark)
		"hoe":
			_poly(img,[Vector2(4,3),Vector2(6,2),Vector2(11,3),Vector2(13,5),Vector2(12,8),Vector2(10,7),Vector2(10,5),Vector2(6,4)],color)
			_line(img,Vector2i(5,3),Vector2i(10,4),light)
		"sword":
			img.fill(Color.TRANSPARENT)
			_line(img,Vector2i(3,13),Vector2i(6,10),WOOD,2)
			_pixel(img,2,13,light)
			_poly(img,[Vector2(6,8),Vector2(11,2),Vector2(14,1),Vector2(14,4),Vector2(8,10)],color)
			_line(img,Vector2i(7,8),Vector2i(13,2),light)
			_line(img,Vector2i(9,8),Vector2i(13,4),dark)
			_line(img,Vector2i(4,7),Vector2i(9,12),color,2)
			_line(img,Vector2i(4,7),Vector2i(8,11),light)

static func _bow(img: Image) -> void:
	var points: Array[Vector2i] = [Vector2i(5,1),Vector2i(8,2),Vector2i(11,5),Vector2i(12,8),Vector2i(11,11),Vector2i(8,13),Vector2i(5,14)]
	for i in range(points.size()-1):
		_line(img,points[i],points[i+1],WOOD,2)
		_pixel(img,points[i].x,points[i].y,WOOD_LIGHT)
	_line(img,Vector2i(5,2),Vector2i(5,13),Color("d6d9c7"))
	_line(img,Vector2i(3,8),Vector2i(12,8),Color("b7a57c"))
	_poly(img,[Vector2(11,6),Vector2(14,8),Vector2(11,10)],Color("d8dedd"))
	_pixel(img,3,7,Color("f0eee0"))
	_pixel(img,3,9,Color("b4b9b5"))

static func _armor(img: Image,name_text: String,color: Color) -> void:
	var light: Color = color.lightened(.27)
	var dark: Color = color.darkened(.25)
	if "helmet" in name_text:
		_poly(img,[Vector2(4,3),Vector2(11,3),Vector2(13,5),Vector2(13,11),Vector2(10,11),Vector2(10,8),Vector2(5,8),Vector2(5,11),Vector2(2,11),Vector2(2,5)],color)
		_line(img,Vector2i(4,4),Vector2i(10,4),light)
		_rect(img,Rect2i(11,6,2,5),dark)
		_pixel(img,4,6,light)
	elif "chestplate" in name_text:
		_poly(img,[Vector2(3,2),Vector2(6,2),Vector2(6,5),Vector2(9,5),Vector2(9,2),Vector2(12,2),Vector2(14,5),Vector2(12,8),Vector2(11,7),Vector2(11,13),Vector2(4,13),Vector2(4,7),Vector2(2,8),Vector2(1,5)],color)
		_line(img,Vector2i(3,3),Vector2i(2,5),light,2)
		_rect(img,Rect2i(5,6,2,5),light)
		_rect(img,Rect2i(9,7,2,6),dark)
	elif "leggings" in name_text:
		_poly(img,[Vector2(3,2),Vector2(12,2),Vector2(12,14),Vector2(9,14),Vector2(9,7),Vector2(6,7),Vector2(6,14),Vector2(3,14)],color)
		_line(img,Vector2i(4,3),Vector2i(11,3),light)
		_line(img,Vector2i(4,5),Vector2i(4,12),light)
		_line(img,Vector2i(11,5),Vector2i(11,13),dark)
	else:
		_poly(img,[Vector2(3,3),Vector2(6,3),Vector2(6,13),Vector2(1,13),Vector2(1,10),Vector2(3,9)],color)
		_poly(img,[Vector2(9,3),Vector2(12,3),Vector2(12,9),Vector2(14,10),Vector2(14,13),Vector2(9,13)],color)
		_line(img,Vector2i(4,4),Vector2i(4,10),light)
		_line(img,Vector2i(10,4),Vector2i(10,11),light)
		_line(img,Vector2i(2,12),Vector2i(5,12),dark)
		_line(img,Vector2i(10,12),Vector2i(13,12),dark)

static func _food(img: Image,id: int,name_text: String,color: Color) -> void:
	match id:
		1200,1203:
			var base: Color = Color("cd3e3a") if id==1200 else Color("eab63c")
			_poly(img,[Vector2(3,5),Vector2(6,4),Vector2(8,5),Vector2(11,4),Vector2(13,6),Vector2(13,10),Vector2(10,13),Vector2(8,12),Vector2(6,13),Vector2(3,11),Vector2(2,8)],base)
			_line(img,Vector2i(4,6),Vector2i(4,8),base.lightened(.45))
			_line(img,Vector2i(11,9),Vector2i(9,11),base.darkened(.25),2)
			_line(img,Vector2i(8,4),Vector2i(9,2),WOOD)
			_rect(img,Rect2i(10,2,3,2),Color("82a84b"))
		1201:
			_poly(img,[Vector2(2,8),Vector2(5,4),Vector2(10,3),Vector2(13,5),Vector2(14,8),Vector2(12,11),Vector2(6,12),Vector2(2,10)],Color("bf873c"))
			_poly(img,[Vector2(3,7),Vector2(6,5),Vector2(10,4),Vector2(12,6),Vector2(12,8),Vector2(7,10),Vector2(3,9)],Color("e3b56a"))
			for x in [5,8,11]:
				_line(img,Vector2i(x,5),Vector2i(x-1,8),Color("8f592c"))
		1202,1206,1208:
			var base: Color = Color("b96361") if id==1206 else Color("98603e")
			_poly(img,[Vector2(3,3),Vector2(7,2),Vector2(10,4),Vector2(13,4),Vector2(14,7),Vector2(12,10),Vector2(9,10),Vector2(7,13),Vector2(3,13),Vector2(1,10),Vector2(2,6)],base)
			_line(img,Vector2i(4,4),Vector2i(7,3),Color("e0ac85"),2)
			_line(img,Vector2i(3,7),Vector2i(3,10),base.lightened(.3))
			_line(img,Vector2i(5,8),Vector2i(7,5),base.darkened(.35))
			_line(img,Vector2i(8,9),Vector2i(11,6),base.darkened(.35))
			_pixel(img,6,11,Color("ead7b2"))
		1204:
			_poly(img,[Vector2(3,12),Vector2(5,6),Vector2(8,4),Vector2(11,6),Vector2(10,9)],Color("e48a25"))
			_line(img,Vector2i(5,10),Vector2i(8,6),Color("ffc55e"))
			_pixel(img,8,8,Color("a75023"))
			_line(img,Vector2i(9,5),Vector2i(9,1),Color("7cad42"),2)
			_line(img,Vector2i(10,5),Vector2i(13,2),Color("4d8535"),2)
			_line(img,Vector2i(11,6),Vector2i(14,5),Color("82b84b"))
		1205:
			_ellipse(img,Rect2i(2,4,12,9),Color("a77b43"))
			_ellipse(img,Rect2i(3,5,9,6),Color("d7b477"))
			_poly(img,[Vector2(4,7),Vector2(7,5),Vector2(11,6),Vector2(9,10),Vector2(5,10)],Color("efd493"))
			_line(img,Vector2i(5,8),Vector2i(9,7),Color("fff0bb"))
			_pixel(img,3,9,Color("79542f"))
		1207:
			_poly(img,[Vector2(2,4),Vector2(14,4),Vector2(13,9),Vector2(9,13),Vector2(5,13),Vector2(2,10)],Color("447b3b"))
			_poly(img,[Vector2(3,4),Vector2(13,4),Vector2(12,9),Vector2(9,11),Vector2(5,11),Vector2(3,9)],Color("a9c66b"))
			_poly(img,[Vector2(3,4),Vector2(12,4),Vector2(11,8),Vector2(8,10),Vector2(5,9)],Color("dd6861"))
			for point in [Vector2i(5,5),Vector2i(9,5),Vector2i(7,8)]:
				_pixel(img,point.x,point.y,Color("473b35"))
		1209:
			_line(img,Vector2i(7,3),Vector2i(10,1),Color("8c845c"),2)
			_ellipse(img,Rect2i(3,4,10,9),Color("8f679b"))
			_rect(img,Rect2i(4,5,3,3),Color("c39cbd"))
			_rect(img,Rect2i(8,8,3,3),Color("b38aa8"))
			_pixel(img,7,11,Color("69476f"))
		1210:
			_poly(img,[Vector2(2,7),Vector2(13,7),Vector2(12,12),Vector2(10,14),Vector2(5,14),Vector2(3,11)],Color("8c613b"))
			_ellipse(img,Rect2i(2,5,12,5),Color("d8bb7b"))
			_rect(img,Rect2i(4,6,3,2),Color("b95637"))
			_rect(img,Rect2i(9,6,2,2),Color("797b3f"))
			_line(img,Vector2i(4,10),Vector2i(6,12),Color("ba8c53"))
		1211:
			_line(img,Vector2i(7,3),Vector2i(10,1),Color("679149"))
			_rect(img,Rect2i(9,2,4,2),Color("7da34a"))
			for point in [Vector2i(4,5),Vector2i(8,5),Vector2i(6,9)]:
				_ellipse(img,Rect2i(point,Vector2i(5,5)),Color("a94151"))
				_pixel(img,point.x+1,point.y+1,Color("e58781"))
		_:
			if "fish" in name_text:
				_fish(img,color)
			else:
				_ellipse(img,Rect2i(3,4,10,9),color)
				_rect(img,Rect2i(4,5,3,2),color.lightened(.3))

static func _bucket(img: Image,id: int) -> void:
	_poly(img,[Vector2(2,5),Vector2(13,5),Vector2(12,13),Vector2(4,13)],Color("9caeb5"))
	_poly(img,[Vector2(3,6),Vector2(6,7),Vector2(7,12),Vector2(5,12)],Color("d1dadd"))
	_poly(img,[Vector2(11,7),Vector2(13,6),Vector2(12,12),Vector2(10,13)],Color("6c7c87"))
	_ellipse(img,Rect2i(2,3,12,5),Color("dce4df"))
	var fill: Color = Color("53616c") if id==1144 else (Color("4a91d5") if id==1145 else Color("f47b24"))
	_ellipse(img,Rect2i(3,4,10,3),fill)
	_line(img,Vector2i(4,5),Vector2i(10,5),fill.lightened(.25))

static func _dial(img: Image,clock: bool) -> void:
	var rim: Color = Color("d6b34d") if clock else Color("b5bfc5")
	_ellipse(img,Rect2i(2,2,12,12),rim)
	_ellipse(img,Rect2i(4,4,8,8),Color("486b91") if clock else Color("3c4249"))
	_line(img,Vector2i(4,3),Vector2i(9,3),rim.lightened(.3))
	if clock:
		_rect(img,Rect2i(5,5,6,3),Color("87aec5"))
		_rect(img,Rect2i(7,5,2,2),Color("f5d77b"))
		_line(img,Vector2i(7,8),Vector2i(9,10),Color("e4d6a6"))
	else:
		_poly(img,[Vector2(8,4),Vector2(10,8),Vector2(7,8)],Color("d94e4e"))
		_poly(img,[Vector2(7,8),Vector2(10,8),Vector2(6,12)],Color("dddcd3"))
		_pixel(img,8,8,Color("f5e7b8"))

static func _material(img: Image,id: int,color: Color) -> void:
	match id:
		1000:
			_line(img,Vector2i(3,13),Vector2i(12,3),WOOD,2)
			_line(img,Vector2i(3,12),Vector2i(11,3),WOOD_LIGHT)
		1003,1005,1008,1023:
			_poly(img,[Vector2(2,6),Vector2(9,3),Vector2(13,5),Vector2(14,9),Vector2(6,13),Vector2(2,10)],color)
			_poly(img,[Vector2(2,6),Vector2(9,3),Vector2(13,5),Vector2(6,9)],color.lightened(.25))
			_poly(img,[Vector2(6,9),Vector2(13,5),Vector2(14,9),Vector2(6,13)],color.darkened(.24))
			_line(img,Vector2i(3,6),Vector2i(9,4),color.lightened(.5))
		1006,1009:
			_poly(img,[Vector2(5,2),Vector2(10,2),Vector2(14,6),Vector2(8,14),Vector2(1,6)],color)
			_poly(img,[Vector2(5,3),Vector2(10,3),Vector2(11,6),Vector2(4,6)],color.lightened(.4))
			_poly(img,[Vector2(4,7),Vector2(11,7),Vector2(8,12)],color.darkened(.08))
			_poly(img,[Vector2(11,7),Vector2(13,6),Vector2(8,13)],color.darkened(.4))
			_line(img,Vector2i(3,6),Vector2i(7,11),color.lightened(.18))
		1001,1018,1030:
			_poly(img,[Vector2(4,3),Vector2(10,2),Vector2(13,5),Vector2(12,10),Vector2(8,13),Vector2(3,12),Vector2(2,7)],color)
			_poly(img,[Vector2(5,4),Vector2(9,3),Vector2(10,6),Vector2(6,8),Vector2(3,7)],color.lightened(.22))
			_line(img,Vector2i(8,11),Vector2i(11,8),color.darkened(.25))
		1002,1004,1007,1022:
			_ellipse(img,Rect2i(2,6,8,7),color.darkened(.22))
			_ellipse(img,Rect2i(6,3,8,8),color)
			_ellipse(img,Rect2i(3,4,6,7),color.lightened(.15))
			_rect(img,Rect2i(8,4,3,2),color.lightened(.35))
			_rect(img,Rect2i(5,9,2,2),Color("807269"))
		1010,1011,1025,1028:
			_poly(img,[Vector2(2,11),Vector2(5,8),Vector2(6,4),Vector2(9,5),Vector2(11,8),Vector2(14,11),Vector2(11,13),Vector2(5,13)],color)
			_rect(img,Rect2i(6,6,2,2),color.lightened(.3))
			_line(img,Vector2i(4,10),Vector2i(8,10),color.lightened(.17))
			_pixel(img,11,11,color.darkened(.3))
		1012:
			_poly(img,[Vector2(3,11),Vector2(5,3),Vector2(8,2),Vector2(10,6),Vector2(13,4),Vector2(12,12),Vector2(6,14)],Color("ddd8d2"))
			_line(img,Vector2i(6,4),Vector2i(5,11),Color("fcf8eb"),2)
			_line(img,Vector2i(9,7),Vector2i(9,12),Color("ada9b2"))
		1013:
			_ellipse(img,Rect2i(2,4,12,9),color)
			_ellipse(img,Rect2i(4,5,7,4),color.lightened(.22))
		1014:
			_poly(img,[Vector2(2,5),Vector2(11,4),Vector2(14,7),Vector2(13,11),Vector2(3,12),Vector2(1,9)],color)
			_line(img,Vector2i(3,6),Vector2i(10,5),color.lightened(.3))
			_line(img,Vector2i(4,10),Vector2i(12,9),color.darkened(.25))
		1015:
			_line(img,Vector2i(4,14),Vector2i(10,3),Color("b79a43"))
			for index in range(4):
				var p := Vector2i(6+index,10-index*2)
				_line(img,p,p+Vector2i(-2,-2),Color("dbc366"),2)
				_line(img,p+Vector2i(1,0),p+Vector2i(3,-2),Color("eed987"),2)
		1016:
			var points: Array[Vector2i] = [Vector2i(3,11),Vector2i(2,7),Vector2i(5,4),Vector2i(10,3),Vector2i(13,6),Vector2i(11,10),Vector2i(7,11),Vector2i(5,8),Vector2i(7,6),Vector2i(10,6)]
			for index in range(points.size()-1):
				_line(img,points[index],points[index+1],Color("e0dfcf"))
		1017:
			_poly(img,[Vector2(3,11),Vector2(4,6),Vector2(10,2),Vector2(14,1),Vector2(13,6),Vector2(9,10),Vector2(5,12)],Color("d7ded9"))
			_line(img,Vector2i(3,13),Vector2i(12,3),Color("929e9d"))
			_line(img,Vector2i(6,7),Vector2i(10,3),Color("f7f7ea"))
		1019:
			_line(img,Vector2i(4,13),Vector2i(12,3),Color("d59832"),3)
			_line(img,Vector2i(4,12),Vector2i(11,3),Color("f5d86e"))
			for p in [Vector2i(5,10),Vector2i(8,7),Vector2i(11,4)]:
				_line(img,p,p+Vector2i(1,1),Color("ad5c23"))
		1020,1021,1029:
			_ellipse(img,Rect2i(2,2,12,12),color.darkened(.2))
			_ellipse(img,Rect2i(3,3,10,10),color)
			_ellipse(img,Rect2i(4,4,4,3),color.lightened(.35))
			_line(img,Vector2i(10,8),Vector2i(8,11),color.darkened(.3),2)
			if id==1021:
				_ellipse(img,Rect2i(5,5,6,6),Color("d7c976"))
				_rect(img,Rect2i(7,5,2,6),Color("224c43"))
		1024:
			_poly(img,[Vector2(3,2),Vector2(6,4),Vector2(10,3),Vector2(12,2),Vector2(14,5),Vector2(11,7),Vector2(12,12),Vector2(8,14),Vector2(3,12),Vector2(4,7),Vector2(1,5)],color)
			_line(img,Vector2i(5,5),Vector2i(4,10),color.lightened(.2))
			_line(img,Vector2i(8,12),Vector2i(10,10),color.darkened(.25))
		1026:
			_poly(img,[Vector2(4,2),Vector2(13,3),Vector2(11,14),Vector2(2,12)],Color("e8e4cc"))
			_line(img,Vector2i(5,4),Vector2i(11,5),Color("fbf8e3"))
			_line(img,Vector2i(4,9),Vector2i(9,10),Color("bbbcae"))
		1027:
			_poly(img,[Vector2(3,2),Vector2(12,4),Vector2(13,13),Vector2(4,12),Vector2(2,10)],Color("8d543c"))
			_poly(img,[Vector2(4,3),Vector2(11,5),Vector2(11,10),Vector2(4,9)],Color("bd7850"))
			_line(img,Vector2i(4,10),Vector2i(11,12),Color("ded8ba"),2)
			_line(img,Vector2i(5,11),Vector2i(10,12),Color("aaa68f"))
		1142:
			_line(img,Vector2i(3,13),Vector2i(11,5),WOOD_LIGHT)
			_line(img,Vector2i(2,10),Vector2i(5,13),Color("dddcd2"),2)
			_poly(img,[Vector2(9,4),Vector2(14,1),Vector2(12,7),Vector2(11,5)],Color("c0c9c9"))
			_pixel(img,12,3,Color("f0f2e8"))
		_:
			_poly(img,[Vector2(4,3),Vector2(11,4),Vector2(13,8),Vector2(10,12),Vector2(4,13),Vector2(2,8)],color)
			_line(img,Vector2i(4,5),Vector2i(8,4),color.lightened(.35),2)

static func _potion(img: Image,color: Color) -> void:
	_rect(img,Rect2i(6,2,4,3),Color("b08a5b"))
	_rect(img,Rect2i(6,5,4,3),Color("b7d2d4"))
	_ellipse(img,Rect2i(3,7,10,8),Color("a9c4ce"))
	_ellipse(img,Rect2i(4,9,8,5),color)
	_rect(img,Rect2i(5,8,2,3),Color("eef5e2"))

static func _fish(img: Image,color: Color) -> void:
	_poly(img,[Vector2(1,5),Vector2(4,7),Vector2(7,4),Vector2(11,4),Vector2(14,7),Vector2(12,10),Vector2(7,11),Vector2(4,9),Vector2(1,11)],color)
	_line(img,Vector2i(6,5),Vector2i(10,5),color.lightened(.35))
	_pixel(img,12,6,Color("e2e3d1"))
	_pixel(img,12,7,INK)
	_line(img,Vector2i(7,9),Vector2i(10,9),color.darkened(.3))

static func _pixel(img: Image,x: int,y: int,color: Color) -> void:
	if x>=0 and y>=0 and x<16 and y<16:
		img.set_pixel(x,y,color)

static func _rect(img: Image,rect: Rect2i,color: Color) -> void:
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			_pixel(img,x,y,color)

static func _ellipse(img: Image,rect: Rect2i,color: Color) -> void:
	var center: Vector2 = Vector2(rect.position)+Vector2(rect.size)*.5
	var radius: Vector2 = Vector2(rect.size)*.5
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			var point: Vector2 = (Vector2(x+.5,y+.5)-center)/radius
			if point.length_squared()<=1.0:
				_pixel(img,x,y,color)

static func _poly(img: Image,points: Array,color: Color) -> void:
	var polygon := PackedVector2Array(points)
	for y in range(16):
		for x in range(16):
			if Geometry2D.is_point_in_polygon(Vector2(x+.5,y+.5),polygon):
				_pixel(img,x,y,color)

static func _line(img: Image,a: Vector2i,b: Vector2i,color: Color,width: int = 1) -> void:
	var distance: int = maxi(absi(b.x-a.x),absi(b.y-a.y))
	for index in range(distance+1):
		var point: Vector2i = Vector2i(Vector2(a).lerp(Vector2(b),float(index)/maxi(distance,1)).round())
		_rect(img,Rect2i(point,Vector2i(width,width)),color)

static func _outline(img: Image) -> void:
	var source: Image = img.duplicate()
	for y in range(16):
		for x in range(16):
			if source.get_pixel(x,y).a>0.0:
				continue
			for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var neighbor: Vector2i = Vector2i(x,y)+step
				if neighbor.x>=0 and neighbor.y>=0 and neighbor.x<16 and neighbor.y<16 and source.get_pixel(neighbor.x,neighbor.y).a>0.0:
					img.set_pixel(x,y,INK)
					break
