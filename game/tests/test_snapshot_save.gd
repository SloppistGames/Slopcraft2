extends SceneTree
var failures = 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	SaveManager.worlds_directory = "user://snapshot-save-test-%d" % Time.get_ticks_usec()
	var d = SaveManager.create_world("Snapshot persistence",817,"survival")
	check(not d.is_empty(),"World creation")
	check(d.get("generator_version",0) == 2,"New worlds use generation2")
	var legacy = d.duplicate(true)
	legacy.erase("generator_version")
	legacy.schema_version = 1
	var migrated = SaveManager._validate(legacy)
	check(migrated.ok and migrated.world.generator_version == 1,"Legacy terrain preserved")
	d.player.equipment = {"head":1400}
	d.player.camera_mode = 2
	d.player.player_name = "CloudBuilder"
	d.player.skin_path = "user://skins/custom.png"
	d.player.position = [2,-140,4]
	d.dimensions.overworld.edits = {"2,-140,4":200}
	d.dimensions.overworld.block_states = {"2,-140,4":{"rotation":3,"top":true,"power":12}}
	d.dimensions.overworld.systems = {
		"weather":{"weather":"heavy_snow","time":0.7},
		"fluids":{"queue":[[15,-100,16]],"sources":{"15,-100,15":10}},
		"redstone":{"ticks":123,"pending":[[2,10,2]]},
		"portals":{"anchors":{"nether":[2,30,4]}},
		"nature":{"pending":[[4,30,8]]}}
	check(SaveManager.save_world(d) == OK,"Snapshot save writes")
	var loaded = SaveManager.load_world(d.id)
	check(equivalent(loaded.player,d.player),"Player appearance/equipment round trip")
	check(equivalent(loaded.dimensions,d.dimensions),"Block and system state round trip")
	var path = SaveManager.worlds_directory.path_join("snapshot.slopworld")
	check(SaveManager.export_world(d.id,path) == OK,"Export snapshot")
	var imported = SaveManager.import_world(path)
	check(imported.ok and imported.world.id != d.id,"Independent import")
	check(imported.ok and equivalent(imported.world.dimensions,d.dimensions),"Import system state intact")
	var damaged = d.duplicate(true)
	damaged.dimensions.overworld.block_states["bad"] = {"power":4}
	check(SaveManager.save_world(damaged) != OK,"Reject malformed block state")
	damaged = d.duplicate(true)
	damaged.dimensions.overworld.systems.weather.time = NAN
	check(SaveManager.save_world(damaged) != OK,"Reject nonfinite simulation state")
	damaged = d.duplicate(true)
	damaged.generator_version = 99
	check(SaveManager.save_world(damaged) != OK,"Reject unsupported future terrain version")
	check(equivalent(SaveManager.load_world(d.id).dimensions,d.dimensions),"Rejected writes preserve good world")
	var dir = DirAccess.open(SaveManager.worlds_directory)
	for filename in dir.get_files(): DirAccess.remove_absolute(SaveManager.worlds_directory.path_join(filename))
	DirAccess.remove_absolute(SaveManager.worlds_directory)
	print("SNAPSHOT SAVE: ","PASS" if failures == 0 else str(failures)+" FAILURES")
	quit(failures)

func equivalent(a: Variant,b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))
