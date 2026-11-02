class_name EnvironmentEffects
extends Node
## All immersion is derived from the rendered camera, including third person.
var world: Node
var player: Node3D
var atmosphere: Node
var active_liquid: int = 0
var immersion: float = 0.0
var sulfur_amount: float = 0.0
var liquid_profiles: Dictionary = {
	9:{"color":Color(0.06,0.28,0.32),"density":0.115,"tint":0.16,"distortion":0.0018,"muffle":1100.0},
	20:{"color":Color(0.83,0.19,0.025),"density":1.15,"tint":0.38,"distortion":0.005,"muffle":650.0}
}
var _profile: Dictionary = {}
var _layer: CanvasLayer
var _overlay: ColorRect
var _material: ShaderMaterial
var _filter: AudioEffectLowPassFilter
var _ambience: AudioStreamPlayer
var _cave_tick: float = 0.0
var _in_sulfur: bool = false
var _time: float = 0.0

func setup(new_world: Node, new_player: Node, _inventory = null, _entities: Node = null) -> void:
	world = new_world
	player = new_player as Node3D
	atmosphere = world.get("atmosphere")
	process_priority = 50
	_profile = liquid_profiles[9].duplicate()
	_layer = CanvasLayer.new()
	_layer.layer = 0
	add_child(_layer)
	_overlay = ColorRect.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader: Shader = Shader.new()
	shader.code = """shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform vec4 tint : source_color = vec4(0.06,0.28,0.32,0.0);
uniform float strength = 0.0;
uniform float distortion = 0.0;
uniform float elapsed = 0.0;
void fragment() {
 vec2 offset = vec2(sin(UV.y*33.0+elapsed*1.4)+sin(UV.y*13.0-elapsed),cos(UV.x*24.0+elapsed*1.1))*distortion*strength;
 vec3 scene = texture(screen_texture,clamp(SCREEN_UV+offset,vec2(0.001),vec2(0.999))).rgb;
 float edge = smoothstep(0.2,0.7,distance(UV,vec2(0.5)))*strength*0.08;
 COLOR = vec4(mix(scene,tint.rgb,tint.a*strength)*(1.0-edge),1.0);
}"""
	_material = ShaderMaterial.new()
	_material.shader = shader
	_overlay.material = _material
	_layer.add_child(_overlay)
	_overlay.visible = false
	_filter = AudioEffectLowPassFilter.new()
	_filter.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(0,_filter)
	AudioServer.set_bus_effect_enabled(0,_filter_index(),false)
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = _make_ambience()
	_ambience.volume_db = -70.0
	add_child(_ambience)
	if DisplayServer.get_name() != "headless": _ambience.play()

func register_liquid(block_id: int, profile: Dictionary) -> void:
	var complete: Dictionary = liquid_profiles[9].duplicate()
	complete.merge(profile,true)
	liquid_profiles[block_id] = complete

func liquid_at(position: Vector3) -> int:
	if not is_instance_valid(world): return 0
	var p: Vector3i = Vector3i(position.floor())
	var id: int = int(world.call("get_block",p))
	if not liquid_profiles.has(id): return 0
	if world.has_method("get_block_state"):
		var state: Dictionary = world.call("get_block_state",p)
		var level: int = int(state.get("fluid_level",0))
		var covered: bool = int(world.call("get_block",p+Vector3i.UP)) == id
		var height: float = 1.0
		if not covered and not bool(state.get("fluid_falling",false)):
			if id == 9: height = 0.875 if level == 0 else maxf(0.125,1.0-float(level)/8.0)
			elif id == 20: height = 1.0 if level == 0 else maxf(0.25,1.0-float(level)/4.0)
		if position.y-float(p.y) > height: return 0
	return id

func _process(delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(world): return
	var camera: Camera3D = player.get("camera") as Camera3D
	if not is_instance_valid(camera): return
	_time += delta
	active_liquid = liquid_at(camera.global_position)
	if active_liquid != 0: _profile = liquid_profiles[active_liquid]
	immersion = move_toward(immersion,1.0 if active_liquid != 0 else 0.0,delta*4.5)
	_cave_tick += delta
	if _cave_tick > 0.25:
		_cave_tick = 0.0
		_in_sulfur = world.has_method("cave_biome_at") and "sulfur" in str(world.call("cave_biome_at",camera.global_position)).to_lower()
	var equipment: Dictionary = player.get("equipment") if player.get("equipment") is Dictionary else {}
	var mask: bool = int(equipment.get("head",0)) == 1400
	var gas_target: float = (0.34 if mask else 0.7) if _in_sulfur else 0.0
	sulfur_amount = move_toward(sulfur_amount,gas_target,delta*1.2)
	var gas_color: Color = Color(0.44,0.48,0.15)
	var local_color: Color = gas_color.lerp(Color(_profile.color),immersion)
	var fog_amount: float = maxf(sulfur_amount,immersion)
	var density: float = lerpf(0.045,float(_profile.density),immersion)
	if is_instance_valid(atmosphere):
		atmosphere.call("set_local_effect",local_color,density,fog_amount)
	var tint: Color = gas_color.lerp(Color(_profile.color),immersion)
	tint.a = lerpf(0.09,float(_profile.tint),immersion)
	_material.set_shader_parameter("tint",tint)
	_material.set_shader_parameter("strength",fog_amount)
	_material.set_shader_parameter("distortion",float(_profile.distortion)*immersion)
	_material.set_shader_parameter("elapsed",_time)
	_overlay.visible = fog_amount > 0.001
	var filter_index: int = _filter_index()
	if filter_index >= 0:
		_filter.cutoff_hz = lerpf(20000.0,float(_profile.muffle),immersion)
		AudioServer.set_bus_effect_enabled(0,filter_index,immersion > 0.01)
	_ambience.volume_db = linear_to_db(maxf(0.0001,maxf(immersion*0.8,sulfur_amount*0.22)))-23.0
	_ambience.pitch_scale = 0.8 if active_liquid == 20 else (0.65 if sulfur_amount > immersion else 1.0)

func _filter_index() -> int:
	for i in range(AudioServer.get_bus_effect_count(0)):
		if AudioServer.get_bus_effect(0,i) == _filter: return i
	return -1

func _exit_tree() -> void:
	if is_instance_valid(_ambience):
		_ambience.stop()
		_ambience.stream = null
	var index: int = _filter_index()
	if index >= 0: AudioServer.remove_bus_effect(0,index)
	if is_instance_valid(atmosphere): atmosphere.call("set_local_effect",Color.WHITE,0.0,0.0)

func serialize() -> Dictionary:
	return {"version":1}

func restore(_data: Dictionary) -> void:
	# Camera location is the source of truth; never restore stale immersion.
	active_liquid = 0
	immersion = 0.0
	sulfur_amount = 0.0
	_in_sulfur = false
	if is_instance_valid(_overlay): _overlay.visible = false
	var index: int = _filter_index()
	if index >= 0: AudioServer.set_bus_effect_enabled(0,index,false)
	if is_instance_valid(atmosphere): atmosphere.call("set_local_effect",Color.WHITE,0.0,0.0)

func _make_ambience() -> AudioStreamWAV:
	var rate: int = 12000
	var count: int = rate*4
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count*2)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 901
	var low: float = 0.0
	for i in range(count):
		var t: float = float(i)/rate
		low = lerpf(low,rng.randf_range(-1,1),0.018)
		var sample_value: float = low*0.9 + sin(t*TAU*47.0)*0.04 + sin(t*TAU*62.0)*0.02
		bytes.encode_s16(i*2,int(clampf(sample_value,-1,1)*29000))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count
	return stream
