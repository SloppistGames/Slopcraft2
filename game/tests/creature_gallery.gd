extends SceneTree
## Bounded native-renderer gallery; deterministic display poses and no saved world writes.
class Fixture extends Node3D:
	var dimension: String = "end"
	var seed_value: int = 42
	func get_block(_p: Vector3i) -> int: return 0
	func surface_height(_x: int,_z: int) -> int: return 0
	func spawn_position() -> Vector3: return Vector3.ZERO
	func end_pillars() -> Array: return []
func _initialize() -> void: run.call_deferred()
func label_at(scene: Node3D,text: String,position: Vector3) -> void:
	var label := Label3D.new(); label.text = text; label.position = position
	label.font_size=48; label.pixel_size=.0045; label.modulate=Color("d4ddd0")
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; label.no_depth_test=true; scene.add_child(label)
func run() -> void:
	root.size=Vector2i(1600,1000); root.position=Vector2i(100,100)
	var scene := Fixture.new(); root.add_child(scene)
	var environment := WorldEnvironment.new(); var settings := Environment.new()
	settings.background_mode=Environment.BG_COLOR; settings.background_color=Color("1d2931")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; settings.ambient_light_color=Color("c0ced2"); settings.ambient_light_energy=.4
	environment.environment=settings; scene.add_child(environment)
	var light := DirectionalLight3D.new(); light.rotation_degrees=Vector3(-45,-28,0); light.light_energy=.8; light.shadow_enabled=true; scene.add_child(light)
	var floor_mesh := MeshInstance3D.new(); var floor_shape := PlaneMesh.new(); floor_shape.size=Vector2(35,26); floor_mesh.mesh=floor_shape
	var material := StandardMaterial3D.new(); material.albedo_color=Color("354549"); material.roughness=1; floor_mesh.material_override=material; floor_mesh.position.y=-.02; scene.add_child(floor_mesh)
	var roster: Array = [["pig","farmer"],["sheep","farmer"],["slime","farmer"],["villager","farmer"],["villager","smith"],["villager","librarian"],["villager","mason"]]
	for i in roster.size():
		var model := CreatureModel.new(); scene.add_child(model); model.setup(roster[i][0],roster[i][1]); model.position=Vector3(-6.6+i*2.2,0,0)
		model.rotation.y=-.3; model.animate(.12,0,true,false,0)
		label_at(scene,roster[i][1].capitalize() if roster[i][0]=="villager" else roster[i][0].capitalize(),model.position+Vector3(0,-.25,-.8))
	var bag := PlayerInventory.new(); bag.setup(true)
	var player := VoxelPlayer.new(); scene.add_child(player); player.setup(scene,bag); player.set_physics_process(false); player.position=Vector3(-4.5,0,-5)
	bag.select_item(1102); player._update_held_item(); player.camera_mode=2; player._update_camera(0); player.player_model.animate(.1,0,0)
	player.rotation.y=-.30; player.camera.current=false
	label_at(scene,"Player / iron pickaxe",player.position+Vector3(0,-.25,-.7))
	var second := VoxelPlayer.new(); scene.add_child(second); var tools := PlayerInventory.new(); tools.setup(true); second.setup(scene,tools); second.set_physics_process(false); second.position=Vector3(-1.5,0,-5)
	tools.select_item(1133); second._update_held_item(); second.camera_mode=2; second._update_camera(0); second.player_model.animate(.1,0,0); second.rotation.y=.25; second.camera.current=false
	label_at(scene,"Player / diamond sword",second.position+Vector3(0,-.25,-.7))
	var boss := SlopEntities.new(); scene.add_child(boss); boss.setup(scene,player,"end"); boss.set_physics_process(false)
	boss.elapsed=1.3; boss.boss_attack_timer=2; boss._update_boss(0)
	boss.dragon.position=Vector3(3.6,1.4,-5); boss.dragon.scale=Vector3.ONE*.30; boss.dragon.rotation=Vector3(0,-.35,0)
	label_at(scene,"Enderslop / articulated pixel skin",Vector3(3.6,-.25,-6.4))
	var camera := Camera3D.new(); scene.add_child(camera); camera.position=Vector3(0,8,-19); camera.look_at(Vector3(0,.8,-2.4)); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=10; camera.current=true
	for frame in 16: await process_frame
	await RenderingServer.frame_post_draw
	var path: String=ProjectSettings.globalize_path("res://../../work/snapshot050/creature-gallery.png")
	var result: Error=root.get_texture().get_image().save_png(path)
	print("CREATURE GALLERY: ",path," status ",result)
	# Close portrait verifies the grip anchor and default face at readable pixel scale.
	for child in scene.get_children():
		if child is CreatureModel or child is Label3D: child.hide()
	boss.hide(); player.position=Vector3(-.75,0,-5); second.position=Vector3(.75,0,-5)
	player.rotation.y=-.12; second.rotation.y=.12
	camera.position=Vector3(.4,2.0,-9); camera.look_at(Vector3(0,.95,-5)); camera.size=2.6
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var close_path: String=ProjectSettings.globalize_path("res://../../work/snapshot050/held-grip-gallery.png")
	result=root.get_texture().get_image().save_png(close_path)
	print("HELD GRIP GALLERY: ",close_path," status ",result)
	scene.free(); await process_frame; await create_timer(.2).timeout
	quit(result)
