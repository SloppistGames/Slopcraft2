class_name TorchLights
extends Node3D
## A bounded pool follows nearby placed/generated torches. Chunk metadata and
## block events supply candidates; no full-world scan or node per torch exists.
const MAX_LIGHTS = 12
const LIGHT_DISTANCE = 24.0
var world
var player
var pool: Array[OmniLight3D] = []
var flame_frames: Array[ImageTexture] = []
var extra_torches: Dictionary = {}
var selected: Array[Vector3i] = []
var refresh_clock = 0.0
var animation_clock = 0.0

func setup(new_world: Node,new_player: Node,_inventory = null,_entities: Node = null) -> void:
	world = new_world
	player = new_player
	if not world.block_changed.is_connected(_on_block_changed): world.block_changed.connect(_on_block_changed)
	_make_flames()
	for i in MAX_LIGHTS:
		var light = OmniLight3D.new()
		light.name = "TorchLight_%d" % i
		light.light_color = Color("ffbe78")
		light.light_energy = 2.2
		light.omni_range = 11.0
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		light.visible = false
		var flame = Sprite3D.new()
		flame.name = "Flame"
		flame.texture = flame_frames[0]
		flame.pixel_size = 0.021
		flame.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		flame.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		flame.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		flame.set_draw_flag(SpriteBase3D.FLAG_SHADED,false)
		flame.set_draw_flag(SpriteBase3D.FLAG_DOUBLE_SIDED,true)
		flame.position.y = 0.06
		light.add_child(flame)
		add_child(light)
		pool.append(light)
	_refresh()

func _process(delta: float) -> void:
	if not is_instance_valid(world): return
	refresh_clock += delta
	animation_clock += delta
	if refresh_clock>=0.2:
		refresh_clock = 0
		_refresh()
	for i in selected.size():
		var light = pool[i]
		var phase = animation_clock*9.0+i*1.7
		light.light_energy = 2.1 if int(world.get_block(selected[i]))==158 else (0.85 if int(world.get_block(selected[i]))==164 else 2.2)*(0.96+sin(phase)*0.035+sin(phase*1.83)*0.025)
		light.get_child(0).texture = flame_frames[posmod(int(animation_clock*10)+i,flame_frames.size())]

func _on_block_changed(cell: Vector3i,id: int) -> void:
	if id in [28,158,164]: extra_torches[cell] = id
	else: extra_torches.erase(cell)
	refresh_clock = 0.2

func _refresh() -> void:
	var origin: Vector3 = player.global_position if is_instance_valid(player) else world.focus_position
	var center = Vector2i(floori(origin.x/16.0),floori(origin.z/16.0))
	var candidates: Dictionary = {}
	for z in range(center.y-2,center.y+3):
		for x in range(center.x-2,center.x+3):
			var coord = Vector2i(x,z)
			if not world.chunks.has(coord): continue
			for cell in world.chunks[coord].get_meta("torch_cells",[]): candidates[cell] = true
	for cell in extra_torches.keys():
		if Vector3(cell).distance_squared_to(origin)>LIGHT_DISTANCE*LIGHT_DISTANCE*4:
			extra_torches.erase(cell)
		else: candidates[cell] = true
	var nearby: Array[Vector3i] = []
	for cell in candidates:
		if Vector3(cell).distance_squared_to(origin)>LIGHT_DISTANCE*LIGHT_DISTANCE: continue
		var id: int = world.get_block(cell)
		if id not in [28,158,164]: continue
		var state: Dictionary = world.get_block_state(cell)
		if id==158 and not bool(state.get("powered",false)): continue
		if not bool(state.get("lit",true)) or bool(state.get("disabled",false)): continue
		nearby.append(cell)
	nearby.sort_custom(func(a: Vector3i,b: Vector3i): return Vector3(a).distance_squared_to(origin)<Vector3(b).distance_squared_to(origin))
	selected.clear()
	for i in MAX_LIGHTS:
		var light = pool[i]
		light.visible = i<nearby.size()
		if not light.visible: continue
		var cell = nearby[i]
		selected.append(cell)
		var id: int = world.get_block(cell)
		light.position = Vector3(cell)+(Vector3.ONE*.5 if id==158 else BlockShapes.torch_tip(world.get_block_state(cell)))
		light.get_child(0).visible = id!=158
		light.light_color = Color("f47e63") if id==164 else Color("ffbe78")
		light.omni_range = 7.0 if id==164 else 11.0
		light.get_child(0).modulate = Color("ff9281") if id==164 else Color.WHITE

func _make_flames() -> void:
	if not flame_frames.is_empty(): return
	for phase in 4:
		var image = Image.create(8,12,false,Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		for y in range(1,12):
			var width = 1 if y<4 else (2 if y<8 else 3)
			var center = 3+(1 if (y+phase)%5<2 else 0)
			for x in range(8):
				var d = absi(x-center)
				if d>=width: continue
				var color = Color("e97c24")
				if d<width-1 and y>4: color = Color("ffcd54")
				if d==0 and y>8: color = Color("fff3bf")
				image.set_pixel(x,y,color)
		flame_frames.append(ImageTexture.create_from_image(image))

func serialize() -> Dictionary:
	return {}

func restore(_data: Dictionary) -> void:
	refresh_clock = 0.2
