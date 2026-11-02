extends SceneTree

class TestWorld extends Node3D:
	signal block_changed(pos: Vector3i, id: int)
	var world_seed: int = 12
	var dimension: String = "overworld"
	var atmosphere: WorldAtmosphere
	var blocks: Dictionary = {}
	var states: Dictionary = {}
	var sulfur: bool = false
	func get_block(p: Vector3i) -> int: return int(blocks.get(p,1 if p.y <= 0 else 0))
	func get_block_state(p: Vector3i) -> Dictionary: return states.get(p,{})
	func surface_height(_x: int,_z: int) -> int: return 0
	func biome_at(_pos: Vector3) -> String: return "Plains"
	func climate_at(_pos: Vector3) -> Dictionary: return {"temperature":0.5,"humidity":0.5}
	func cave_biome_at(_pos: Vector3) -> String: return "Sulfuric Caves" if sulfur else "Normal Caves"

class TestPlayer extends Node3D:
	var camera: Camera3D
	var equipment: Dictionary = {"head":0}

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func _run() -> void:
	var world: TestWorld = TestWorld.new()
	root.add_child(world)
	world.atmosphere = WorldAtmosphere.new()
	world.add_child(world.atmosphere)
	world.atmosphere.setup("overworld")
	world.atmosphere.set_process(false)
	var player: TestPlayer = TestPlayer.new()
	world.add_child(player)
	player.position = Vector3(0,2,0)
	player.camera = Camera3D.new()
	player.add_child(player.camera)
	player.camera.position = Vector3(0,1.6,0)
	var weather: WeatherSystem = WeatherSystem.new()
	world.add_child(weather)
	weather.setup(world,player,RefCounted.new(),null)
	weather.set_process(false)
	weather.automatic = false
	weather.transition_seconds = 0.2
	check(weather.available_weather().size() == 13,"13 weather profiles available")
	for name_value in weather.available_weather():
		check(weather.set_weather(name_value),"weather accepted: "+name_value)
		for step in range(12): weather._process(0.1)
		var profile: Array = WeatherSystem.PROFILES[name_value]
		check(absf(float(weather._current[0])-float(profile[0])) < 0.01,"cloud transition reached "+name_value)
		check(weather._rain.multimesh.visible_instance_count <= WeatherSystem.RAIN_COUNT,"rain bounded "+name_value)
		check(weather._snow.multimesh.visible_instance_count <= WeatherSystem.SNOW_COUNT,"snow bounded "+name_value)
		if float(profile[1]) > 0.0: check(weather._rain.multimesh.visible_instance_count > 0,"rain rendered "+name_value)
		if float(profile[2]) > 0.0: check(weather._snow.multimesh.visible_instance_count > 0,"snow rendered "+name_value)
	check(not weather.set_weather("invalid"),"invalid weather rejected")
	check(weather.set_weather("moderate rain") and weather.weather_name == "rain","weather aliases")
	check("blizzard" in weather.eligible_weather(0.1,0.8,"Permafrost"),"cold climates allow blizzard")
	check("rain" not in weather.eligible_weather(0.1,0.8,"Permafrost"),"cold climate excludes rain")
	check("hurricane" in weather.eligible_weather(0.8,0.8,"Beaches"),"warm humid coast allows hurricane")
	check("hurricane" not in weather.eligible_weather(0.8,0.8,"Oak Forest"),"inland excludes hurricane")
	check("rain" not in weather.eligible_weather(0.8,0.1,"Desert"),"arid excludes rain")
	weather._update_cells(Vector3(2,8,2))
	weather._elapsed = 6.0
	weather._roof_budget = 1000
	weather._update_particles(weather._rain,1.0,false,false)
	var fixed: Transform3D = weather._rain.multimesh.get_instance_transform(0)
	var previous_cells: Array = weather._weather_cells.duplicate()
	weather._update_cells(Vector3(7,8,2))
	weather._roof_budget = 1000
	weather._update_particles(weather._rain,1.0,false,false)
	check(weather._rain.multimesh.get_instance_transform(0).origin == fixed.origin,"camera walking does not drag particles")
	weather._update_cells(Vector3(18,8,2))
	var retained: int = 0
	for i in range(27):
		if weather._weather_cells[i] == previous_cells[i]: retained += 1
	check(retained == 18,"crossing a cell boundary retains 18 of 27 emitter cells")
	check(weather.global_position == Vector3.ZERO,"weather root stays fixed in world space")
	weather.set_weather("heavy_rain")
	weather.transition_seconds = 18.0
	var before: float = float(weather._current[1])
	weather._process(0.016)
	check(float(weather._current[1])-before < 0.03,"weather transition is gradual")
	weather.set_time(0.65)
	var saved: Dictionary = weather.serialize()
	weather.set_weather("clear")
	weather.set_time(0.2)
	weather.restore(saved)
	check(weather.weather_name == "heavy_rain","weather restores")
	check(is_equal_approx(world.atmosphere.time_of_day,0.65),"time restores")
	check(weather._current == saved.current,"transition restores")
	weather._roof_cache.clear()
	weather._roof_budget = 2
	weather._roof_y = 3.6
	world.blocks[Vector3i(0,6,0)] = 1
	check(weather.precipitation_roof(0,0) == 7.0,"roof prevents precipitation below ceiling")
	check(weather.precipitation_roof(1,0) == 1.0,"precipitation remains visible outside shelter")
	world.blocks.erase(Vector3i(0,6,0))
	world.block_changed.emit(Vector3i(0,6,0),0)
	weather._roof_budget = 1
	check(weather.precipitation_roof(0,0) == 1.0,"roof break invalidates cache")
	weather.set_brightness(50)
	var dark: float = world.atmosphere.environment_node.environment.tonemap_exposure
	weather.set_brightness(150)
	check(world.atmosphere.environment_node.environment.tonemap_exposure > dark*2.9,"brightness changes exposure")
	weather.trigger_lightning()
	check(weather._flash == 1.0 and weather._bolt.visible,"visible lightning strike")
	check(weather._thunder_delay > 0.0,"thunder is delayed")
	check(weather._thunder_audio.stream.data.size() > 1000,"thunder has synthesized samples")
	var bus_count: int = AudioServer.get_bus_effect_count(0)
	var effects: EnvironmentEffects = EnvironmentEffects.new()
	world.add_child(effects)
	effects.setup(world,player,RefCounted.new(),null)
	effects.set_process(false)
	world.blocks[Vector3i(0,3,0)] = 9
	effects._process(0.3)
	check(effects.active_liquid == 9 and effects.immersion == 1.0,"camera in water activates immersion")
	check(world.atmosphere.local_fog_amount == 1.0,"water adds fog")
	check(AudioServer.is_bus_effect_enabled(0,effects._filter_index()),"water muffles sound")
	player.camera.position = Vector3(0,5,3)
	effects._process(0.3)
	check(effects.active_liquid == 0 and effects.immersion == 0.0,"third person camera out of water clears immersion")
	check(not effects._overlay.visible and world.atmosphere.local_fog_amount == 0.0,"overlay and fog clear")
	check(not AudioServer.is_bus_effect_enabled(0,effects._filter_index()),"muffled sound restores")
	player.camera.position = Vector3(0,1.6,0)
	world.blocks[Vector3i(0,3,0)] = 20
	effects._process(0.3)
	check(effects.active_liquid == 20 and float(effects._profile.density) > 1.0,"lava immersion profile")
	effects.restore({})
	check(effects.immersion == 0.0,"restore never resurrects stale immersion")
	world.blocks[Vector3i(0,3,0)] = 9
	world.states[Vector3i(0,3,0)] = {"fluid_level":7}
	check(effects.liquid_at(Vector3(0.5,3.7,0.5)) == 0,"flowing liquid surface respected")
	check(effects.liquid_at(Vector3(0.5,3.05,0.5)) == 9,"shallow liquid submerged detection")
	player.camera.position = Vector3(0,5,3)
	world.sulfur = true
	effects._process(1.0)
	var exposed: float = effects.sulfur_amount
	player.equipment.head = 1400
	effects._process(1.0)
	check(effects.sulfur_amount < exposed,"mask reduces sulfur irritation overlay")
	world.sulfur = false
	effects._process(1.0)
	check(effects.sulfur_amount == 0.0,"sulfur atmosphere clears on exit")
	effects.free()
	check(AudioServer.get_bus_effect_count(0) == bus_count,"audio effect cleaned up on world exit")
	world.queue_free()
	await process_frame
	await create_timer(0.08).timeout
	print("WEATHER / IMMERSION: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
