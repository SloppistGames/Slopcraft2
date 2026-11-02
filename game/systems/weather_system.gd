class_name WeatherSystem
extends Node3D
## Climate-driven, bounded local precipitation. Never modifies player builds.
signal weather_changed(weather: String)

# cloud, rain, snow, wind, fog density, thunder probability
const PROFILES: Dictionary = {
	"clear": [0.0,0.0,0.0,0.14,0.0015,0.0],
	"cloudy": [0.35,0.0,0.0,0.24,0.0035,0.0],
	"overcast": [0.72,0.0,0.0,0.3,0.006,0.0],
	"light_rain": [0.55,0.18,0.0,0.25,0.006,0.0],
	"rain": [0.78,0.48,0.0,0.4,0.010,0.0],
	"heavy_rain": [0.94,0.85,0.0,0.65,0.018,0.0],
	"thunderstorm": [1.0,0.95,0.0,1.05,0.023,1.0],
	"light_snow": [0.48,0.0,0.22,0.24,0.008,0.0],
	"heavy_snow": [0.82,0.0,0.75,0.55,0.022,0.0],
	"blizzard": [0.97,0.0,1.0,1.7,0.052,0.0],
	"windstorm": [0.70,0.0,0.0,1.6,0.015,0.0],
	"tropical_storm": [0.96,0.9,0.0,1.75,0.032,0.45],
	"hurricane": [1.0,1.0,0.0,2.5,0.052,0.65]
}
const ALIASES: Dictionary = {"sun":"clear","clouds":"cloudy","moderate_rain":"rain","snow":"heavy_snow","snowfall":"light_snow","light_snowfall":"light_snow","heavy_snowfall":"heavy_snow","thunder":"thunderstorm","storm":"thunderstorm","wind":"windstorm","strong_windstorm":"windstorm","tropicalstorm":"tropical_storm"}
const RAIN_COUNT: int = 1350
const SNOW_COUNT: int = 810
const DEBRIS_COUNT: int = 80
var world: Node
var player: Node3D
var atmosphere: Node
var weather_name: String = "clear"
var wind_strength: float = 0.14
var wind_direction: Vector2 = Vector2(0.83,0.56)
var transition_seconds: float = 18.0
var automatic: bool = true
var remaining: float = 150.0
var climate: Dictionary = {"temperature":0.5,"humidity":0.5}
var biome: String = "Plains"
var _current: Array = [0.0,0.0,0.0,0.14,0.0015,0.0]
var _elapsed: float = 0.0
var _tick: float = 0.0
var _climate_tick: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _roof_cache: Dictionary = {}
var _roof_budget: int = 0
var _roof_y: float = 0.0
var _sheltered: float = 0.0
var _rain: MultiMeshInstance3D
var _snow: MultiMeshInstance3D
var _debris: MultiMeshInstance3D
var _rain_audio: AudioStreamPlayer
var _wind_audio: AudioStreamPlayer
var _thunder_audio: AudioStreamPlayer
var _thunder_delay: float = -1.0
var _next_flash: float = 12.0
var _flash: float = 0.0
var _bolt: MeshInstance3D
var _brightness: float = 1.0
var _camera_focus: Vector3 = Vector3.ZERO
var _weather_cells: Array[Vector3i] = []
var _cell_center: Vector3i = Vector3i(2147483647,0,0)
var _wind_offset: Vector2 = Vector2.ZERO
const CELL_SIZE: Vector3 = Vector3(16.0,24.0,16.0)

func setup(new_world: Node, new_player: Node, _inventory = null, _entities: Node = null) -> void:
	world = new_world
	player = new_player as Node3D
	atmosphere = world.get("atmosphere")
	_rng.seed = int(world.get("world_seed")) + 51803 if world.get("world_seed") != null else 51803
	_register_wind()
	_rain = _make_particles(RAIN_COUNT, Color(0.60,0.75,0.83,0.58))
	_snow = _make_particles(SNOW_COUNT, Color(0.91,0.96,1.0,0.85))
	_debris = _make_particles(DEBRIS_COUNT, Color(0.60,0.57,0.43,0.45))
	_rain_audio = _make_audio(_noise_stream(3.0, false), -60.0)
	_wind_audio = _make_audio(_noise_stream(4.0, true), -60.0)
	_thunder_audio = _make_audio(_thunder_stream(), -10.0, false)
	_bolt = MeshInstance3D.new()
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	add_child(_bolt)
	if world.has_signal("block_changed"):
		world.connect("block_changed", _block_changed)
	_update_climate()
	set_brightness(_brightness)

static var _wind_registered: bool = false

static func ensure_wind_globals() -> void:
	if _wind_registered: return
	RenderingServer.global_shader_parameter_add("sc_wind_strength", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.14)
	RenderingServer.global_shader_parameter_add("sc_wind_direction", RenderingServer.GLOBAL_VAR_TYPE_VEC2, Vector2(0.83,0.56))
	_wind_registered = true

func _register_wind() -> void:
	ensure_wind_globals()

func set_weather(value: String) -> bool:
	var key: String = value.to_lower().strip_edges().replace(" ","_").replace("-","_")
	key = str(ALIASES.get(key,key))
	if not PROFILES.has(key):
		return false
	weather_name = key
	remaining = _rng.randf_range(180.0,420.0)
	weather_changed.emit(weather_name)
	return true

func set_time(normalized: float) -> void:
	if is_instance_valid(atmosphere):
		atmosphere.set("time_of_day", fposmod(normalized,1.0))
		atmosphere.call("_update_lighting")

func set_brightness(value: float) -> void:
	_brightness = clampf(value / 100.0 if value > 2.0 else value, 0.5, 1.5)
	if is_instance_valid(atmosphere):
		atmosphere.call("set_brightness", _brightness)

func available_weather() -> Array:
	return PROFILES.keys()

func eligible_weather(temperature: float, humidity: float, region: String, altitude: float = 0.0) -> Array:
	var names: Array = ["clear","cloudy","overcast","windstorm"]
	var cold: bool = temperature < 0.27 or altitude > 125.0 or "snow" in region.to_lower() or "frozen" in region.to_lower() or "tundra" in region.to_lower() or "permafrost" in region.to_lower()
	if cold:
		names.append_array(["light_snow","heavy_snow","blizzard"])
	elif humidity > 0.28:
		names.append_array(["light_rain","rain","heavy_rain","thunderstorm"])
		var coastal: bool = "coast" in region.to_lower() or "beach" in region.to_lower() or "swamp" in region.to_lower()
		if coastal and temperature > 0.7 and humidity > 0.65:
			names.append_array(["tropical_storm","hurricane"])
	return names

func _choose_weather() -> void:
	var names: Array = eligible_weather(float(climate.temperature),float(climate.humidity),biome,player.global_position.y)
	# The same regional climate drives all choices; severe events have low weights.
	var weights: Dictionary = {"clear":34.0,"cloudy":20.0,"overcast":13.0,"windstorm":3.0,"light_rain":15.0,"rain":10.0,"heavy_rain":4.0,"thunderstorm":2.0,"light_snow":17.0,"heavy_snow":7.0,"blizzard":2.0,"tropical_storm":0.8,"hurricane":0.2}
	var total: float = 0.0
	for key in names:
		total += float(weights[key])
	var pick: float = _rng.randf() * total
	for key in names:
		pick -= float(weights[key])
		if pick <= 0.0:
			set_weather(str(key))
			return

func _update_climate() -> void:
	if not is_instance_valid(player) or not is_instance_valid(world): return
	if world.has_method("climate_at"):
		climate = world.call("climate_at",player.global_position)
	if world.has_method("biome_at"):
		biome = str(world.call("biome_at",player.global_position))

func _process(delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(atmosphere): return
	_elapsed += delta
	var active: bool = str(world.get("dimension")) == "overworld"
	var target: Array = PROFILES[weather_name] if active else PROFILES.clear
	var blend: float = 1.0 - exp(-delta * 4.0 / maxf(0.1,transition_seconds))
	for i in range(6):
		_current[i] = lerpf(float(_current[i]),float(target[i]),blend)
	var camera: Camera3D = player.get("camera") as Camera3D
	var focus: Vector3 = camera.global_position if is_instance_valid(camera) else player.global_position
	_camera_focus = focus
	_update_cells(focus)
	wind_strength = float(_current[3]) * (1.0 + maxf(0.0, focus.y-70.0) / 300.0)
	var angle: float = sin(_elapsed * 0.007) * 0.35 + 0.6
	wind_direction = Vector2(cos(angle),sin(angle))
	_wind_offset += wind_direction * wind_strength * delta
	RenderingServer.global_shader_parameter_set("sc_wind_strength", wind_strength)
	RenderingServer.global_shader_parameter_set("sc_wind_direction", wind_direction)
	_climate_tick += delta
	if _climate_tick > 3.0:
		_climate_tick = 0.0
		_update_climate()
	remaining -= delta
	if automatic and active and remaining <= 0.0:
		_choose_weather()
	_tick += delta
	_roof_budget = 0
	_roof_y = focus.y
	if _tick >= 1.0/30.0:
		_roof_budget = 14
		_tick = 0.0
	# World-space transforms update every rendered frame, independent of roof-query cadence.
	_update_particles(_rain, float(_current[1]), false, false)
	_update_particles(_snow, float(_current[2]), true, false)
	_update_particles(_debris, maxf(0.0,wind_strength-0.65)*0.45 if active else 0.0, false, true)
	_roof_budget = 1
	var roof: float = precipitation_roof(floori(focus.x),floori(focus.z))
	var sheltered_target: float = 1.0 if roof > focus.y + 0.15 else 0.0
	_sheltered = lerpf(_sheltered,sheltered_target,1.0-exp(-delta*2.5))
	atmosphere.set("shelter",_sheltered)
	_update_lightning(delta, active)
	atmosphere.call("set_weather_state",float(_current[0]),float(_current[4]),float(_current[2]),wind_strength,_flash)
	var rain_level: float = float(_current[1]) * lerpf(1.0,0.28,_sheltered)
	_rain_audio.volume_db = linear_to_db(maxf(0.001,rain_level)) - 19.0
	_wind_audio.volume_db = linear_to_db(maxf(0.001,wind_strength / 2.5)) - 23.0 - _sheltered*10.0

func _make_particles(count: int, color: Color) -> MultiMeshInstance3D:
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3.ONE
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	mesh.material = material
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	node.multimesh = mm
	node.custom_aabb = AABB(Vector3(-18,-13,-18),Vector3(36,40,36))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func _update_cells(focus: Vector3) -> void:
	var center: Vector3i = Vector3i((focus/CELL_SIZE).floor())
	if center == _cell_center: return
	_cell_center = center
	var needed: Array[Vector3i] = []
	for y in range(-1,2):
		for z in range(-1,2):
			for x in range(-1,2): needed.append(center+Vector3i(x,y,z))
	if _weather_cells.is_empty():
		_weather_cells = needed
	else:
		# Keep overlapping slots exactly where they are; recycle only cells outside view.
		var missing: Array[Vector3i] = []
		for cell in needed:
			if not _weather_cells.has(cell): missing.append(cell)
		for i in range(_weather_cells.size()):
			if not needed.has(_weather_cells[i]): _weather_cells[i] = missing.pop_back()
	var bounds: AABB = AABB(Vector3(center-Vector3i.ONE)*CELL_SIZE, CELL_SIZE*3.0)
	for node in [_rain,_snow,_debris]:
		if is_instance_valid(node): node.custom_aabb = bounds

func _cell_seed(cell: Vector3i, index: int) -> Vector3:
	# Hash fixed cell coordinates, never the player or transient emitter index.
	var n: int = (cell.x*73856093) ^ (cell.y*19349663) ^ (cell.z*83492791) ^ (index*2654435761)
	return Vector3(float(posmod(n,16001))/1000.0,float(posmod(n*31+991,24001))/1000.0,float(posmod(n*17+719,16001))/1000.0)

func _update_particles(node: MultiMeshInstance3D, density: float, snow: bool, debris: bool) -> void:
	var per_cell: int = node.multimesh.instance_count/27
	var active_per_cell: int = clampi(int(ceil(per_cell*density)),0,per_cell) if density > 0.001 else 0
	node.multimesh.visible_instance_count = active_per_cell*27
	if active_per_cell == 0: return
	var speed: float = 2.7 if snow else (1.2 if debris else 22.0)
	var drift_rate: float = 6.0 if snow or debris else 4.5
	var fall: Vector3 = Vector3(wind_direction.x*wind_strength*drift_rate,-speed,wind_direction.y*wind_strength*drift_rate)
	var up: Vector3 = -fall.normalized()
	var right: Vector3 = up.cross(Vector3.FORWARD).normalized()
	var rain_basis: Basis = Basis(right,up,right.cross(up))
	var index: int = 0
	for cell in _weather_cells:
		for i in range(active_per_cell):
			var seed_value: Vector3 = _cell_seed(cell,i)
			var pos: Vector3 = Vector3(cell)*CELL_SIZE+Vector3(fposmod(seed_value.x+_wind_offset.x*drift_rate,16.0),fposmod(seed_value.y-_elapsed*speed,24.0),fposmod(seed_value.z+_wind_offset.y*drift_rate,16.0))
			if snow or debris:
				pos.x += sin(_elapsed*1.2+seed_value.y)*0.4
				pos.z += cos(_elapsed*0.8+seed_value.y)*0.4
			var roof: float = precipitation_roof(floori(pos.x),floori(pos.z))
			var scale_value: Vector3 = Vector3(0.025,0.78,0.025)
			var basis: Basis = rain_basis
			if snow:
				scale_value = Vector3(0.08,0.055,0.08)*(0.75+float(i%4)*0.15)
				basis = Basis(Vector3.UP,_elapsed*0.7+seed_value.x)
			elif debris:
				scale_value = Vector3(0.12,0.025,0.07)
				basis = Basis(Vector3(1,0.5,0).normalized(),_elapsed*2.0+seed_value.x)
			if pos.y <= roof+0.15: scale_value = Vector3.ZERO
			node.multimesh.set_instance_transform(index,Transform3D(basis.scaled(scale_value),pos))
			index += 1

func precipitation_roof(x: int, z: int) -> float:
	var key: Vector2i = Vector2i(x,z)
	if _roof_cache.has(key):
		var cached: Vector2 = _roof_cache[key]
		if _elapsed-cached.y < 8.0: return cached.x
	if _roof_budget <= 0: return INF
	_roof_budget -= 1
	var surface: int = int(world.call("surface_height",x,z)) if world.has_method("surface_height") else floori(_roof_y)-15
	var roof: float = float(surface+1)
	# Terrain provides roofs for deep caves without scanning hundreds of cells.
	if surface < _roof_y+24.0:
		for y in range(floori(_roof_y)+24,maxi(surface,floori(_roof_y)-13),-1):
			var id: int = int(world.call("get_block",Vector3i(x,y,z)))
			if id != 0 and id not in [22,29,30,164,165,166,168]:
				roof = float(y+1)
				break
	if _roof_cache.size() > 4096: _roof_cache.clear()
	_roof_cache[key] = Vector2(roof,_elapsed)
	return roof

func _block_changed(pos: Vector3i, _id: int) -> void:
	_roof_cache.erase(Vector2i(pos.x,pos.z))

func _update_lightning(delta: float, active: bool) -> void:
	_flash = move_toward(_flash,0.0,delta*4.5)
	_bolt.visible = _flash > 0.05
	_next_flash -= delta
	if active and float(_current[5]) > 0.15 and _next_flash <= 0.0:
		trigger_lightning()
		_next_flash = _rng.randf_range(11.0,29.0)/maxf(0.2,float(_current[5]))
	if _thunder_delay >= 0.0:
		_thunder_delay -= delta
		if _thunder_delay < 0.0 and DisplayServer.get_name() != "headless": _thunder_audio.play()

func trigger_lightning() -> void:
	_flash = 1.0
	var radius: float = _rng.randf_range(35.0,95.0)
	var angle: float = _rng.randf_range(0.0,TAU)
	var end: Vector3 = _camera_focus + Vector3(cos(angle)*radius,0,sin(angle)*radius)
	end.y = float(world.call("surface_height",floori(end.x),floori(end.z))) + 1.0 if world.has_method("surface_height") else _camera_focus.y-3.0
	var mesh: ImmediateMesh = ImmediateMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.82,0.9,1.0)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,mat)
	var last: Vector3 = end-global_position
	for i in range(8):
		var next: Vector3 = last + Vector3(_rng.randf_range(-4,4),8.0,_rng.randf_range(-4,4))
		mesh.surface_add_vertex(last)
		mesh.surface_add_vertex(next)
		last = next
	mesh.surface_end()
	_bolt.mesh = mesh
	_bolt.visible = true
	_thunder_delay = radius/80.0

func _make_audio(stream: AudioStreamWAV, level: float, looping: bool = true) -> AudioStreamPlayer:
	var audio: AudioStreamPlayer = AudioStreamPlayer.new()
	audio.stream = stream
	audio.volume_db = level
	add_child(audio)
	if looping and DisplayServer.get_name() != "headless": audio.play()
	return audio

func _noise_stream(duration: float, wind: bool) -> AudioStreamWAV:
	var rate: int = 16000
	var count: int = int(rate*duration)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count*2)
	var low: float = 0.0
	var audio_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	audio_rng.seed = 148 if wind else 349
	for i in range(count):
		var noise: float = audio_rng.randf_range(-1,1)
		low = lerpf(low,noise,0.025 if wind else 0.25)
		var pulse: float = 0.7+0.18*sin(float(i)/rate*TAU/duration)
		var value: float = low*2.5*pulse if wind else (noise*0.27+low*0.6)
		bytes.encode_s16(i*2,int(clampf(value,-1,1)*26000))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count
	return stream

func _thunder_stream() -> AudioStreamWAV:
	var stream: AudioStreamWAV = _noise_stream(3.5,true)
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	var bytes: PackedByteArray = stream.data
	var low: float = 0.0
	for i in range(bytes.size()/2):
		var t: float = float(i)/stream.mix_rate
		var value: float = float(bytes.decode_s16(i*2))/32768.0
		low = lerpf(low,value,0.07)
		var envelope: float = minf(t*25.0,1.0)*exp(-t*1.05)
		bytes.encode_s16(i*2,int(clampf((low*4.0+sin(t*TAU*43.0)*0.16)*envelope,-1,1)*30000))
	stream.data = bytes
	return stream

func serialize() -> Dictionary:
	return {"weather":weather_name,"current":_current.duplicate(),"remaining":remaining,"automatic":automatic,"elapsed":_elapsed,"wind_offset":[_wind_offset.x,_wind_offset.y],"rng_state":str(_rng.state),"time":float(atmosphere.get("time_of_day")) if is_instance_valid(atmosphere) else 0.28}

func restore(data: Dictionary) -> void:
	var name_value: String = str(data.get("weather","clear"))
	if not set_weather(name_value): set_weather("clear")
	remaining = clampf(float(data.get("remaining",180.0)),0.0,900.0)
	automatic = bool(data.get("automatic",true))
	_elapsed = maxf(0.0,float(data.get("elapsed",0.0)))
	var offset: Array = data.get("wind_offset",[0.0,0.0])
	if offset.size() == 2: _wind_offset = Vector2(float(offset[0]),float(offset[1]))
	var saved: Array = data.get("current",PROFILES[weather_name])
	if saved.size() == 6:
		for i in range(6): _current[i] = clampf(float(saved[i]),0.0,3.0)
	if data.has("rng_state"): _rng.state = int(str(data.rng_state))
	set_time(float(data.get("time",0.28)))
	_roof_cache.clear()

func _exit_tree() -> void:
	for audio in [_rain_audio,_wind_audio,_thunder_audio]:
		if is_instance_valid(audio):
			audio.stop()
			audio.stream = null
	if _wind_registered:
		RenderingServer.global_shader_parameter_set("sc_wind_strength",0.14)
