extends SceneTree
## Run: godot --headless --path . --script tests/test_data.gd
var failures: int = 0
var test_directory: String

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _initialize() -> void:
	test_directory = "user://test-data-%d-%08x" % [Time.get_ticks_usec(),randi()]
	SaveManager.worlds_directory = test_directory
	_test_inventory()
	_test_saves()
	var directory = DirAccess.open(test_directory)
	if directory != null:
		for file in directory.get_files():
			DirAccess.remove_absolute(test_directory.path_join(file))
		DirAccess.remove_absolute(test_directory)
	print("DATA TESTS: %s" % ("PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)

func _test_inventory() -> void:
	var inventory = PlayerInventory.new()
	expect(BlockDB.all_blocks().size() >= 140,"Substantial block registry")
	expect(BlockDB.all_items().size() > 200,"Substantial item registry")
	expect(inventory.add_item(7,70),"Stacks split across slots")
	expect(inventory.slots[0].count == 64 and inventory.slots[1].count == 6,"Stack limit enforced")
	expect(not inventory.consume(7,71),"Insufficient consumption rejected")
	expect(inventory.count_item(7) == 70,"Rejected consumption is atomic")
	expect(inventory.consume(7,65),"Consume across stacks")
	expect(inventory.count_item(7) == 5,"Correct remaining count")
	var recipe: Dictionary = {"ingredients":{7:4},"result":25,"count":1}
	expect(inventory.craft(recipe),"Recipe creates crafting table")
	expect(inventory.count_item(7) == 1 and inventory.count_item(25) == 1,"Craft consumes exact materials")
	var restored = PlayerInventory.new()
	restored.restore(inventory.serialize())
	expect(restored.serialize() == inventory.serialize(),"Inventory serialization round trip")
	var full = PlayerInventory.new()
	for i in PlayerInventory.SLOT_COUNT:
		full.slots[i] = {"id":7,"count":64}
	var before: Dictionary = full.serialize()
	expect(not full.add_item(3,1),"Full inventory rejects new item")
	expect(full.serialize() == before,"Failed add does not alter inventory")
	expect(not full.craft({"ingredients":{7:1},"result":3,"count":64}),"Craft fails if result cannot fit")
	expect(full.serialize() == before,"Failed crafting restores consumed materials")
	full.setup(true)
	expect(full.consume(7,999),"Creative resources remain infinite")
	expect(full.select_item(1133) and full.selected_id() == 1133,"Creative palette assignment")

func _test_saves() -> void:
	var data: Dictionary = SaveManager.create_world("Automated test world",12345,"survival")
	expect(not data.is_empty(),"Create and persist world")
	if data.is_empty():
		return
	var id: String = data.id
	data.dimensions.overworld.edits["1,10,-3"] = 7
	data.dimensions.nether.edits["0,20,0"] = 67
	data.dimensions.end.edits["9,12,9"] = 0
	data.player.position = [1.5,22.0,-3.5]
	data.player.health = 13
	data.boss_defeated = true
	expect(SaveManager.save_world(data) == OK,"Save mutated world")
	var restored: Dictionary = SaveManager.load_world(id)
	expect(restored.dimensions == data.dimensions,"All dimension edits persist")
	expect(restored.player.position == data.player.position and restored.player.health == 13,"Player state persists")
	expect(restored.inventory == data.inventory,"Inventory persists")
	expect(restored.boss_defeated,"Boss progress persists")
	expect(SaveManager.list_worlds().size() == 1,"World discoverable after reload")
	var export_path: String = test_directory.path_join("backup.slopworld")
	expect(SaveManager.export_world(id,export_path) == OK,"World exports")
	var imported: Dictionary = SaveManager.import_world(export_path)
	expect(imported.ok,"World imports")
	if imported.ok:
		expect(imported.world.id != id,"Import gets independent ID")
		expect(imported.world.dimensions == data.dimensions,"Import preserves edits")
		expect(SaveManager.list_worlds().size() == 2,"Import does not overwrite original")
	var malformed_path: String = test_directory.path_join("malformed.slopworld")
	var malformed = FileAccess.open(malformed_path,FileAccess.WRITE)
	malformed.store_string('{"format":"slopcraft2-world","version":1,"world":{"id":"../../escape"}}')
	malformed.close()
	expect(not SaveManager.import_world(malformed_path).ok,"Path traversal import is rejected")
	var invalid: Dictionary = data.duplicate(true)
	invalid.dimensions.overworld.edits["bad-coordinate"] = 3
	expect(SaveManager.save_world(invalid) != OK,"Malformed edits cannot corrupt a save")
	expect(not SaveManager.load_world(id).is_empty(),"Rejected save leaves original intact")
	# Another save ensures the last-good backup contains our modifications.
	expect(SaveManager.save_world(data) == OK,"Second save updates backup")
	var corrupt = FileAccess.open(test_directory.path_join(id + ".json"),FileAccess.WRITE)
	corrupt.store_string("corrupt data")
	corrupt.close()
	var recovered: Dictionary = SaveManager.load_world(id)
	expect(not recovered.is_empty(),"Corrupt primary recovers backup")
	if not recovered.is_empty():
		expect(recovered.dimensions == data.dimensions,"Recovered backup preserves latest prior edits")
	expect(SaveManager.load_world("../../escape").is_empty(),"Unsafe load identifier rejected")
