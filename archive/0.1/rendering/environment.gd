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

func setup(new_dimension: String) -> void:
	dimension = new_dimension
	environment_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("afc9e4")
	env.ambient_light_energy = 0.72
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.fog_enabled = true
	env.fog_density = 0.0028
	env.fog_light_color = Color("abc9e6")
	env.fog_light_energy = 0.75
	var sky = Sky.new()
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("427fd1")
	sky_material.sky_horizon_color = Color("b9d4ed")
	sky_material.ground_bottom_color = Color("586147")
	sky_material.ground_horizon_color = Color("accbe1")
	sky_material.sky_curve = 0.16
	sky_material.sun_angle_max = 8.0
	sky.sky_material = sky_material
	env.sky = sky
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-32,0)
	sun.light_color = Color("fff4d7")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)
	if dimension == "nether":
		sky_material.sky_top_color = Color("271522")
		sky_material.sky_horizon_color = Color("a54530")
		sky_material.ground_bottom_color = Color("eb6b1b")
		sky_material.ground_horizon_color = Color("a54530")
		env.ambient_light_color = Color("db9081")
		env.ambient_light_energy = 0.65
		env.fog_light_color = Color("a94c35")
		env.fog_density = 0.008
		sun.light_color = Color("ffa85c")
		sun.light_energy = 0.68
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
		env.ambient_light_energy = 0.78
		env.fog_light_color = Color("21182f")
		env.fog_density = 0.003
		sun.light_color = Color("ddd5c4")
		sun.light_energy = 0.7
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
	material.albedo_color = Color("f1f3ee")
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

func _process(delta: float) -> void:
	elapsed += delta
	if dimension == "overworld":
		time_of_day = fposmod(time_of_day + delta / 1200.0, 1.0)
		lighting_tick += delta
		if lighting_tick > 0.5:
			lighting_tick = 0.0
			var daylight = clampf(sin(time_of_day * TAU) * 1.4, 0.0, 1.0)
			sun.rotation_degrees.x = -70.0 * sin(time_of_day * TAU)
			sun.light_energy = lerpf(0.08, 1.05, daylight)
			environment_node.environment.ambient_light_energy = lerpf(0.24, 0.72, daylight)
			sky_material.sky_top_color = Color("090f25").lerp(Color("427fd1"),daylight)
			sky_material.sky_horizon_color = Color("202743").lerp(Color("b9d4ed"),daylight)
			environment_node.environment.fog_light_color = Color("202743").lerp(Color("abc9e6"),daylight)
	if clouds != null:
		clouds.position = Vector3(floorf(focus.x/160.0)*160.0 + fmod(elapsed*0.28,90),0,floorf(focus.z/160.0)*160.0)
	if embers != null:
		embers.position.x = focus.x
		embers.position.z = focus.z
		for i in range(embers.multimesh.instance_count):
			var transform = embers.multimesh.get_instance_transform(i)
			transform.origin.y = fposmod(transform.origin.y-10+delta*(0.7+float(i%4)*0.2),58)+10
			embers.multimesh.set_instance_transform(i,transform)
