extends SceneTree
class Observer extends Node3D:
	var camera: Camera3D
	var equipment: Dictionary = {"head":0}
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1100,700)
	var world: VoxelWorld = VoxelWorld.new()
	root.add_child(world)
	world.setup(817263,"overworld",{},2)
	world.set_process(false)
	world.atmosphere.set_process(false)
	var observer: Observer = Observer.new()
	world.add_child(observer)
	observer.position = world.spawn_position()+Vector3(4,5,8)
	observer.camera = Camera3D.new()
	observer.add_child(observer.camera)
	observer.camera.current = true
	observer.camera.far = 350
	observer.camera.fov = 78
	observer.camera.look_at(world.spawn_position()+Vector3(-12,1,-16))
	world.atmosphere.focus = observer.position
	var weather: WeatherSystem = WeatherSystem.new()
	world.add_child(weather)
	weather.setup(world,observer)
	weather.set_process(false)
	weather.automatic = false
	weather.transition_seconds = 0.5
	weather.set_time(0.25)
	var nature: NatureSystem = NatureSystem.new()
	world.add_child(nature)
	nature.setup(world,observer,PlayerInventory.new())
	nature.set_process(false)
	var effects: EnvironmentEffects = EnvironmentEffects.new()
	world.add_child(effects)
	effects.setup(world,observer)
	effects.set_process(false)
	var output: String = ProjectSettings.globalize_path("res://../../work/snapshot050/weather")
	DirAccess.make_dir_recursive_absolute(output)
	var weather_timings: Array[float] = []
	for name_value in ["clear","heavy_rain","thunderstorm","blizzard","hurricane"]:
		weather.set_weather(name_value)
		for frame in 65:
			var begin: int = Time.get_ticks_usec()
			weather._process(0.1)
			weather_timings.append(float(Time.get_ticks_usec()-begin)/1000.0)
			world.atmosphere._process(0.0)
			await process_frame
		if name_value == "thunderstorm":
			weather.trigger_lightning()
			weather._process(0.016)
			world.atmosphere._process(0.0)
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/"+name_value+".png")
	weather.set_weather("heavy_rain")
	for frame in 40: weather._process(0.1)
	for frame in 64:
		observer.position.x += 0.07
		weather._process(1.0/60.0)
		world.atmosphere._process(0.0)
		await process_frame
		if frame in [0,31,63]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"/walking_"+str(frame)+".png")
	weather.set_weather("clear")
	for frame in 40: weather._process(0.1)
	world.atmosphere._process(0.0)
	for level in [0.5,1.0,1.5]:
		weather.set_brightness(level)
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/brightness_"+str(level)+".png")
	weather.set_brightness(1.0)
	for liquid in [9,20,0]:
		var cell: Vector3i = Vector3i(observer.camera.global_position.floor())
		world.set_block(cell,liquid)
		for frame in 8:
			effects._process(0.1)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/liquid_"+str(liquid)+".png")
	weather_timings.sort()
	print("WEATHER UPDATE P95_MS ",weather_timings[int(weather_timings.size()*0.95)]," MAX_MS ",weather_timings[-1])
	print("WEATHER GALLERY ",output)
	world.queue_free()
	await process_frame
	await process_frame
	quit()
