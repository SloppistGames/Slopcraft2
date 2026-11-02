extends SceneTree
## Stable content IDs, real acquisition chains, and atomic inventory transactions.
var failures: int = 0
var checks: int = 0
var notifications: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	_test_compatibility()
	_test_shapes()
	_test_progression()
	_test_transactions()
	print("CONTENT REGISTRY: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _test_compatibility() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/pre_snapshot_content.json"))
	for entry in fixture.entries:
		check(BlockDB.item_name(int(entry.id)) == str(entry.name),"Original item ID/name changed: %d" % int(entry.id))
	var inventory = PlayerInventory.new()
	var book: Array = inventory.recipes()
	check(fixture.recipes.size() == 46,"Baseline contains all 46 recipes")
	for index in fixture.recipes.size():
		var old: Dictionary = fixture.recipes[index]
		var current: Dictionary = book[index]
		check(current.name == old.name and int(current.result) == int(old.result) and int(current.count) == int(old.count),"Original recipe identity changed: %d" % index)
		check(current.ingredients.size() == old.ingredients.size(),"Original recipe ingredient count changed: %d" % index)
		for id in old.ingredients:
			check(int(current.ingredients.get(int(id),0)) == int(old.ingredients[id]),"Original recipe cost changed: %d" % index)
	for id in range(147,181):
		check(BlockDB.is_block(id),"New block is missing: %d" % id)
	check(BlockDB.get_item(1400).equipment_slot == "head" and BlockDB.get_item(1400).gas_protection,"Gas mask is head equipment with gas protection")
	check(BlockDB.get_item(1400).stack_size == 1,"Gas mask equipment cannot stack")
	check(BlockDB.get_item(1010).places_block == 155 and BlockDB.get_block(155).drop == 1010,"Dust placement and mining use matching IDs")
	for pair in [[170,1001],[171,1002],[172,1004],[173,1006],[174,1010],[175,1007]]:
		check(BlockDB.get_block(pair[0]).drop == pair[1],"Deep ores provide usable resources")

func _test_shapes() -> void:
	var expected: Array[int] = [7,35,36,38,41,44,46,65,68,3,4,17,50,52,53,54,55,56,57,58,59,60,61,62,63,71,72,77,78,79,80,81,82,83,84,85,86,89,100,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,133,134,135,136,137,138,139,142,147,148,149,150]
	check(BlockDB.shape_families() == expected,"Shape family order remains the published ID contract")
	for index in expected.size():
		for offset in 2:
			var id: int = 200 + index * 2 + offset
			var shape: String = "stair" if offset == 0 else "slab"
			var block: Dictionary = BlockDB.get_block(id)
			check(BlockDB.shape_id(expected[index],shape) == id,"Shape ID mapping is stable")
			check(block.get("shape","") == shape and int(block.get("base_id",0)) == expected[index],"Shape has geometry and material metadata")
			check(int(block.drop) == id and block.solid,"Shape drops itself and has collision")
			var inventory = PlayerInventory.new()
			inventory.add_item(expected[index],6)
			var recipe: Dictionary = recipe_for(inventory,id)
			check(not recipe.is_empty() and inventory.craft(recipe),"Shape has working survival recipe: %d" % id)
			var restored = PlayerInventory.new()
			restored.restore(inventory.serialize())
			check(restored.count_item(id) == (4 if offset == 0 else 6),"Shape ID and stack persist")
	check(BlockDB.shape_id(2,"stair") == 0,"Ordinary dirt is not an architectural family")

func recipe_for(inventory: PlayerInventory, id: int) -> Dictionary:
	for recipe in inventory.recipes():
		if int(recipe.result) == id:
			return recipe
	return {}

func _test_progression() -> void:
	var starter = PlayerInventory.new()
	starter.setup(false)
	check(starter.count_item(29) == 0 and starter.count_item(30) == 0,"Survival starter has no activated portals")
	for portal in [29,30]:
		var recipe: Dictionary = recipe_for(starter,portal)
		for id in recipe.ingredients:
			starter.add_item(id,recipe.ingredients[id])
		check(not starter.can_craft(recipe) and not starter.craft(recipe),"Survival cannot bypass portal progression")
		starter.creative = true
		check(starter.craft(recipe),"Legacy portal recipe remains available in creative")
		starter.creative = false
	var inventory = PlayerInventory.new()
	for pair in [[1001,8],[1002,4],[8,4],[165,3]]:
		inventory.add_item(pair[0],pair[1])
	for id in [1003,1003,1003,1003,16,1026,1401,1400]:
		check(inventory.craft(recipe_for(inventory,id)),"Craft gas mask from coal, raw iron, sand and grass: %d" % id)
	check(inventory.count_item(1400) == 1 and inventory.count_item(1401) == 0,"Gas mask consumes its filter")
	# Reachability over real mined/gathered inputs checks dependencies, not free grants.
	var reachable: Dictionary = {}
	for source in [4,5,31,33,37,40,43,45,64,67,8,51,47,48,49,147,19,22,66,71,23,24,141,1001,1002,1004,1006,1007,1009,1010,1011,1029,151,165,166,6,2]:
		reachable[source] = true
	var recipes: Array = inventory.recipes()
	for pass_index in 16:
		for recipe in recipes:
			if recipe.get("creative_only",false):
				continue
			var available: bool = true
			for ingredient in recipe.ingredients:
				available = available and reachable.has(int(ingredient))
			if available:
				reachable[int(recipe.result)] = true
	for id in range(155,165):
		check(reachable.has(id),"Circuit component has a survival acquisition chain: %d" % id)
	for id in [177,178,179,180,1400,1401]:
		check(reachable.has(id),"New component has a survival acquisition chain: %d" % id)
	for id in range(200,334):
		check(reachable.has(id),"Architectural shape has a material acquisition chain: %d" % id)
	check(not reachable.has(29) and not reachable.has(30),"Acquisition graph cannot craft activated portals")

func _test_transactions() -> void:
	var inventory = PlayerInventory.new()
	for slot in PlayerInventory.SLOT_COUNT:
		inventory.slots[slot] = {"id":7,"count":64}
	var before: Dictionary = inventory.serialize()
	inventory.changed.connect(func(): notifications += 1)
	check(not inventory.craft({"ingredients":{7:1},"result":1400,"count":1}),"Full inventory rejects craft")
	check(inventory.serialize() == before and notifications == 0,"Rejected craft cannot publish partial ingredients")
	check(inventory.craft({"ingredients":{7:64},"result":1400,"count":1}),"Craft can use a newly emptied slot")
	check(notifications == 1 and inventory.count_item(1400) == 1,"Successful craft publishes one committed update")
	check(not inventory.craft({"ingredients":{7:-1},"result":3,"count":1}),"Negative ingredient costs rejected")
