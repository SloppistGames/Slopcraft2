class_name WorldAtmosphere
extends Node3D

var dimension = "overworld"
var environment_node: WorldEnvironment
var sun: DirectionalLight3D
var clouds: MultiMeshInstance3D
var embers: MultiMeshInstance3D
var time_of_day = 0.28
var sky_material: ProceduralSkyMaterial
var elapsed = 0.0
var focus = Vector3.ZERO
var lighting_tick = 0.0
var brightness: float = 1.0
var weather_cloud: float = 0.0
var weather_fog: float = 0.0015
var weather_snow: float = 0.0
var wind_strength: float = 0.15
var shelter: float = 0.0
var lightning: float = 0.0
var local_fog_color: Color = Color.WHITE
var local_fog_density: float = 0.0
var local_fog_amount: float = 0.0
var cloud_material: StandardMaterial3D

func set_brightness(value: float) -> void:
	brightness = clampf(value / 100.0 if value > 2.0 else value, 0.5, 1.5)
	_update_lighting()

func set_weather_state(cloud: float, fog: float, snow: float, wind: float, flash: float = 0.0) -> void:
	weather_cloud = clampf(cloud, 0.0, 1.0)
	weather_fog = maxf(0.0015, fog)
	weather_snow = clampf(snow, 0.0, 1.0)
	wind_strength = maxf(wind, 0.0)
	lightning = clampf(flash, 0.0, 1.0)

func set_local_effect(color: Color, density: float, amount: float) -> void:
	local_fog_color = color
	local_fog_density = density
	local_fog_amount = clampf(amount, 0.0, 1.0)
	_update_lighting()


func setup(new_dimension: String) -> void:
	dimension = new_dimension
	environment_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("afc9e4")
	env.ambient_light_energy = 0.24
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.65
	env.fog_enabled = true
	env.fog_density = 0.0015
	env.fog_sky_affect = 0.08
	env.fog_light_color = Color("abc9e6")
	env.fog_light_energy = 0.75
	var sky = Sky.new()
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("427fd1")
	sky_material.sky_horizon_color = Color("b9d4ed")
	sky_material.ground_bottom_color = Color("586147")
	sky_material.ground_horizon_color = Color("accbe1")
	sky_material.sky_curve = 0.22
	sky_material.sky_energy_multiplier = 0.86
	sky_material.ground_energy_multiplier = 0.86
	sky_material.sun_angle_max = 8.0
	sky.sky_material = sky_material
	env.sky = sky
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-32,0)
	sun.light_color = Color("fff4d7")
	sun.light_energy = 0.44
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 115
	sun.shadow_bias = 0.035
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)
	if dimension == "nether":
		sky_material.sky_top_color = Color("271522")
		sky_material.sky_horizon_color = Color("a54530")
		sky_material.ground_bottom_color = Color("eb6b1b")
		sky_material.ground_horizon_color = Color("a54530")
		env.ambient_light_color = Color("db9081")
		env.ambient_light_energy = 0.42
		env.fog_light_color = Color("a94c35")
		env.fog_density = 0.008
		sun.light_color = Color("ffa85c")
		sun.light_energy = 0.52
		_create_embers()
	elif dimension == "end":
		var image = Image.create(1024,512,false,Image.FORMAT_RGB8)
		image.fill(Color("100e1d"))
		var rng = RandomNumberGenerator.new()
		rng.seed = 20812
		for i in range(2400):
			var x = rng.randi_range(0,1023)
			var y = rng.randi_range(0,511)
			var c = Color("6d667f").lerp(Color("e8dbef"),rng.randf())
			image.set_pixel(x,y,c)
		var panorama = PanoramaSkyMaterial.new()
		panorama.panorama = ImageTexture.create_from_image(image)
		sky.sky_material = panorama
		env.ambient_light_color = Color("b6a6c7")
		env.ambient_light_energy = 0.46
		env.fog_light_color = Color("21182f")
		env.fog_density = 0.003
		sun.light_color = Color("ddd5c4")
		sun.light_energy = 0.52
	else:
		_create_clouds()
	environment_node.environment = env
	add_child(environment_node)

func _create_clouds() -> void:
	clouds = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box = BoxMesh.new()
	box.size = Vector3(14,1.8,9)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("e1e5e5")
	cloud_material = material
	material.roughness = 1.0
	box.material = material
	mm.mesh = box
	mm.instance_count = 105
	var rng = RandomNumberGenerator.new()
	rng.seed = 4343
	for i in range(35):
		var center = Vector3(rng.randf_range(-240,240),rng.randf_range(70,78),rng.randf_range(-240,240))
		for segment in range(3):
			var pos = center+Vector3(segment*10,segment%2*0.6,rng.randf_range(-4,4))
			mm.set_instance_transform(i*3+segment,Transform3D(Basis.IDENTITY.scaled(Vector3(rng.randf_range(0.7,1.8),1,rng.randf_range(0.7,1.7))),pos))
	clouds.multimesh = mm
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(clouds)

func _create_embers() -> void:
	embers = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box = BoxMesh.new()
	box.size = Vector3(0.10,0.10,0.10)
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("ffca5b")
	box.material = material
	mm.mesh = box
	mm.instance_count = 110
	for i in range(mm.instance_count):
		var pos = Vector3(fposmod(i*23.71,100)-50,fposmod(i*13.18,58)+10,fposmod(i*31.98,100)-50)
		mm.set_instance_transform(i,Transform3D(Basis.IDENTITY,pos))
	embers.multimesh = mm
	add_child(embers)

func _update_lighting() -> void:
	if not is_instance_valid(environment_node) or environment_node.environment == null:
		return
	var env: Environment = environment_node.environment
	env.tonemap_exposure = 0.65 * brightness
	var fog_color: Color = Color("a7bfd2")
	var fog_density: float = weather_fog
	if dimension == "overworld":
		var daylight: float = smoothstep(-0.10, 0.36, sin(time_of_day * TAU))
		var dusk: float = pow(1.0 - absf(sin(time_of_day * TAU)), 8.0) * (1.0 - weather_cloud)
		var top: Color = Color("081023").lerp(Color("3675bb"), daylight)
		var horizon: Color = Color("182038").lerp(Color("92bde0"), daylight)
		top = top.lerp(Color("4e5d6d") * lerpf(0.25, 1.0, daylight), weather_cloud * 0.88)
		horizon = horizon.lerp(Color("77838c") * lerpf(0.25, 1.0, daylight), weather_cloud * 0.84)
		horizon = horizon.lerp(Color("c78970"), dusk * 0.4)
		sun.rotation_degrees.x = -70.0 * sin(time_of_day * TAU)
		sun.light_energy = lerpf(0.045, 0.44, daylight) * lerpf(1.0, 0.24, weather_cloud) + lightning * 1.8
		sun.light_color = Color("a2b4d8").lerp(Color("fff2d6"), daylight).lerp(Color.WHITE, lightning)
		env.ambient_light_color = Color("8095b0").lerp(Color("b8cad8"), daylight)
		env.ambient_light_energy = lerpf(0.105, 0.24, daylight) * lerpf(1.0, 0.78, weather_cloud) * lerpf(1.0, 0.22, shelter) + lightning * 0.28
		sky_material.sky_top_color = top.lerp(Color("dbe6fa"), lightning * 0.7)
		sky_material.sky_horizon_color = horizon.lerp(Color("eef3ff"), lightning * 0.8)
		sky_material.ground_horizon_color = horizon
		sky_material.ground_bottom_color = horizon.darkened(0.18)
		sky_material.ground_curve = 0.3
		fog_color = horizon.lerp(Color("b5c4cc"), weather_snow * 0.35)
		if cloud_material != null:
			cloud_material.albedo_color = Color("e1e5e5").lerp(Color("5d6873"), weather_cloud).lerp(Color("3b4660"), (1.0-daylight) * 0.75)
		if clouds != null:
			clouds.scale = Vector3(lerpf(1.0, 1.9, weather_cloud), lerpf(1.0, 2.3, weather_cloud), lerpf(1.0, 1.9, weather_cloud))
	elif dimension == "nether":
		fog_color = Color("a94c35")
		fog_density = 0.008
	else:
		fog_color = Color("21182f")
		fog_density = 0.003
	env.fog_light_color = fog_color.lerp(local_fog_color, local_fog_amount)
	env.fog_density = lerpf(fog_density, local_fog_density, local_fog_amount)
	env.fog_sky_affect = lerpf(lerpf(0.08,0.92,weather_cloud),1.0,local_fog_amount) if dimension == "overworld" else 0.75
	env.fog_light_energy = lerpf(0.64, 0.4, shelter)

func _process(delta: float) -> void:
	elapsed += delta
	if dimension == "overworld":
		time_of_day = fposmod(time_of_day + delta / 1200.0, 1.0)
	_update_lighting()
	if clouds != null:
		clouds.position = Vector3(floorf(focus.x/160.0)*160.0 + fmod(elapsed*(0.28+wind_strength*0.35),90),150,floorf(focus.z/160.0)*160.0)
	if embers != null:
		embers.position = Vector3(focus.x, focus.y - 20.0, focus.z)
		for i in range(embers.multimesh.instance_count):
			var transform: Transform3D = embers.multimesh.get_instance_transform(i)
			transform.origin.y = fposmod(transform.origin.y-10+delta*(0.7+float(i%4)*0.2),58)+10
			embers.multimesh.set_instance_transform(i,transform)
