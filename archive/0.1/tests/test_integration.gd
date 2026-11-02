extends SceneTree
var game: Node
var errors: Array[String]=[]
var checks=0
var created_ids: Array[String]=[]
var capture=false
var output_dir=""

func _initialize() -> void:
	call_deferred("run")

func verify(condition: bool, description: String) -> void:
	checks+=1
	if not condition:
		errors.append(description)
		push_error(description)

func shot(name: String) -> void:
	if not capture: return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join(name+".png"))

func run() -> void:
	SaveManager.worlds_directory="user://integration-tests-"+str(Time.get_ticks_usec())
	output_dir=ProjectSettings.globalize_path("res://../../work/screens")
	capture="--captures" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(output_dir)
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(2.0).timeout
	verify(game.page=="title" and is_instance_valid(game.menu),"title screen opens")
	await shot("title")
	game._show_worlds()
	verify(game.page=="worlds","world browser opens")
	await shot("worlds-empty")
	game._show_create()
	await shot("create")
	game._show_options("title")
	await shot("options")
	game._show_guide()
	await shot("guide")
	var data=SaveManager.create_world("Integration world",842019,"survival")
	created_ids.append(data.id)
	await game._start_world(data)
	verify(game.page=="game" and game.player.active,"survival world runs")
	await create_timer(1.0).timeout
	verify(game.player.position.y>10,"player remains above ground")
	game.player.health=13.0
	game.player.hunger=11.0
	var edit=Vector3i(11,45,11)
	game.world.set_block(edit,53)
	var chest=Vector3i(13,31,11)
	game.world.set_block(chest,27)
	var key=game._chest_key(chest)
	game.current_data.chests={key:[{"id":1006,"count":3}]}
	verify(not game._can_break(chest,27),"nonempty chest is protected")
	game._show_chest(chest)
	await shot("chest")
	game._resume()
	game._show_inventory()
	await shot("inventory")
	game.inventory_tab="Crafting"
	game._show_inventory()
	await shot("crafting")
	game._show_pause()
	await shot("pause")
	verify(not game.player.active,"pause blocks player simulation")
	verify(game._checkpoint(),"checkpoint writes valid player and entities")
	var id=str(game.current_data.id)
	var saved=SaveManager.load_world(id)
	verify(saved.dimensions.overworld.edits.get("11,45,11")==53,"edited blocks saved")
	verify(saved.get("chests",{}).has(key),"chest contents saved")
	verify(saved.player.health==13.0,"health saved")
	await game._travel("nether")
	verify(game.current_data.dimension=="nether","travel to Nether")
	verify(is_equal_approx(game.player.health,13.0),"health persists across first visit")
	game.world.set_block(Vector3i(11,45,11),22)
	game._show_pause()
	await shot("nether")
	await game._travel("end")
	verify(game.entities.boss_alive,"Enderslop spawns in End")
	game.world.set_block(Vector3i(11,45,11),24)
	game._show_pause()
	await shot("end")
	await game._travel("overworld")
	verify(game.world.get_block(edit)==53,"Overworld edits survive round trip")
	verify(game._checkpoint(),"all realms checkpoint")
	var export_path=SaveManager.worlds_directory.path_join("test.slopworld")
	verify(SaveManager.export_world(id,export_path)==OK,"export world")
	var imported=SaveManager.import_world(export_path)
	verify(imported.get("ok",false),"import world")
	if imported.get("ok",false):
		created_ids.append(imported.world.id)
		verify(imported.world.id!=id,"import creates independent copy")
		verify(imported.world.dimensions.nether.edits.get("11,45,11")==22,"Nether changes in export")
		verify(imported.world.dimensions.end.edits.get("11,45,11")==24,"End changes in export")
		verify(imported.world.chests[key][0].count==3,"chest items in export")
	await game._quit_to_title()
	verify(game.page=="title" and not is_instance_valid(game.player),"save and quit releases player")
	await game._start_world(SaveManager.load_world(id))
	verify(game.world.get_block(edit)==53,"world reopens with edits")
	verify(game.inventory.slots.size()==36,"inventory reload complete")
	game._show_inventory()
	game._resume()
	game._show_pause()
	await game._quit_to_title()
	var creative=SaveManager.create_world("Creative Integration",12345,"creative")
	created_ids.append(creative.id)
	await game._start_world(creative)
	game.inventory_tab="All items"
	game._show_inventory()
	await shot("creative")
	game._show_travel()
	await shot("travel")
	verify(game.inventory.creative,"creative mode retained")
	game._checkpoint()
	game.queue_free()
	await process_frame
	await process_frame
	for file in DirAccess.get_files_at(SaveManager.worlds_directory):
		DirAccess.remove_absolute(SaveManager.worlds_directory.path_join(file))
	DirAccess.remove_absolute(SaveManager.worlds_directory)
	if errors.is_empty(): print("INTEGRATION PASS: %d checks"%checks)
	else: print("INTEGRATION FAIL: ",errors)
	quit(0 if errors.is_empty() else 1)
