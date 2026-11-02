class_name PlayerInventory
extends RefCounted
## 9 hotbar slots + 27 backpack slots; all inventory transactions are atomic.

signal changed
const SLOT_COUNT: int = 36
var slots: Array = []
var selected: int = 0
var creative: bool = false

func _init() -> void:
	_clear()

func _clear() -> void:
	slots.clear()
	for i in SLOT_COUNT:
		slots.append({"id":0,"count":0})

func setup(is_creative: bool) -> void:
	creative = is_creative
	selected = 0
	_clear()
	if creative:
		for pair in [[1,64],[3,64],[7,64],[16,64],[28,64],[18,64],[29,64],[30,64],[1133,1]]:
			add_item(pair[0],pair[1])
	else:
		for pair in [[1100,1],[1130,1],[7,24],[4,16],[28,12],[1201,8],[25,1],[1001,4],[5,4]]:
			add_item(pair[0],pair[1])
	changed.emit()

func add_item(id: int, amount: int = 1) -> bool:
	if amount <= 0 or not BlockDB.valid_item(id):
		return false
	var limit: int = int(BlockDB.get_item(id).get("stack_size",64))
	var capacity: int = 0
	for slot in slots:
		if slot.id == id:
			capacity += limit - int(slot.count)
		elif slot.id == 0:
			capacity += limit
	if capacity < amount:
		return false
	var remaining: int = amount
	for slot in slots:
		if slot.id == id and int(slot.count) < limit:
			var transfer: int = mini(remaining,limit-int(slot.count))
			slot.count = int(slot.count) + transfer
			remaining -= transfer
			if remaining == 0:
				changed.emit()
				return true
	for slot in slots:
		if slot.id == 0:
			var transfer: int = mini(remaining,limit)
			slot.id = id
			slot.count = transfer
			remaining -= transfer
			if remaining == 0:
				changed.emit()
				return true
	return false

func consume(id: int, amount: int = 1) -> bool:
	if amount <= 0:
		return false
	if creative:
		return true
	if count_item(id) < amount:
		return false
	var remaining: int = amount
	for slot in slots:
		if slot.id == id:
			var transfer: int = mini(remaining,int(slot.count))
			slot.count = int(slot.count) - transfer
			remaining -= transfer
			if int(slot.count) == 0:
				slot.id = 0
			if remaining == 0:
				changed.emit()
				return true
	return false

func count_item(id: int) -> int:
	var total: int = 0
	for slot in slots:
		if int(slot.id) == id:
			total += int(slot.count)
	return total

func selected_id() -> int:
	return int(slots[clampi(selected,0,8)].id)

func select_item(id: int) -> bool:
	if not BlockDB.valid_item(id):
		return false
	if creative:
		slots[clampi(selected,0,8)] = {"id":id,"count":int(BlockDB.get_item(id).get("stack_size",64))}
		changed.emit()
		return true
	for i in slots.size():
		if int(slots[i].id) == id:
			if i < 9:
				selected = i
			else:
				var swap: Dictionary = slots[selected]
				slots[selected] = slots[i]
				slots[i] = swap
			changed.emit()
			return true
	return false

func swap_slots(a: int,b: int) -> void:
	if a < 0 or b < 0 or a >= slots.size() or b >= slots.size():
		return
	var previous: Dictionary = slots[a]
	slots[a] = slots[b]
	slots[b] = previous
	changed.emit()

func serialize() -> Dictionary:
	return {"slots":slots.duplicate(true),"selected":selected,"creative":creative}

func restore(data: Dictionary) -> void:
	_clear()
	creative = bool(data.get("creative",false))
	selected = clampi(int(data.get("selected",0)),0,8)
	var stored: Variant = data.get("slots",[])
	if stored is Array:
		for i in mini(stored.size(),SLOT_COUNT):
			if not stored[i] is Dictionary:
				continue
			var id: int = int(stored[i].get("id",0))
			var count: int = int(stored[i].get("count",0))
			if BlockDB.valid_item(id) and count > 0:
				slots[i] = {"id":id,"count":clampi(count,1,int(BlockDB.get_item(id).get("stack_size",64)))}
	changed.emit()

func recipes() -> Array:
	var result: Array = [
		{"name":"Oak Planks x4","ingredients":{5:1},"result":7,"count":4},
		{"name":"Spruce Planks x4","ingredients":{31:1},"result":35,"count":4},
		{"name":"Birch Planks x4","ingredients":{33:1},"result":36,"count":4},
		{"name":"Cherry Planks x4","ingredients":{40:1},"result":41,"count":4},
		{"name":"Sticks x4","ingredients":{7:2},"result":1000,"count":4},
		{"name":"Crafting Table","ingredients":{7:4},"result":25,"count":1},
		{"name":"Furnace","ingredients":{4:8},"result":26,"count":1},
		{"name":"Chest","ingredients":{7:8},"result":27,"count":1},
		{"name":"Torches x4","ingredients":{1000:1,1001:1},"result":28,"count":4},
		{"name":"Wooden Pickaxe","ingredients":{7:3,1000:2},"result":1100,"count":1},
		{"name":"Stone Pickaxe","ingredients":{4:3,1000:2},"result":1101,"count":1},
		{"name":"Iron Pickaxe","ingredients":{1003:3,1000:2},"result":1102,"count":1},
		{"name":"Diamond Pickaxe","ingredients":{1006:3,1000:2},"result":1103,"count":1},
		{"name":"Netherite Pickaxe","ingredients":{1103:1,1023:1},"result":1105,"count":1},
		{"name":"Stone Axe","ingredients":{4:3,1000:2},"result":1111,"count":1},
		{"name":"Iron Axe","ingredients":{1003:3,1000:2},"result":1112,"count":1},
		{"name":"Iron Shovel","ingredients":{1003:1,1000:2},"result":1122,"count":1},
		{"name":"Wooden Sword","ingredients":{7:2,1000:1},"result":1130,"count":1},
		{"name":"Stone Sword","ingredients":{4:2,1000:1},"result":1131,"count":1},
		{"name":"Iron Sword","ingredients":{1003:2,1000:1},"result":1132,"count":1},
		{"name":"Diamond Sword","ingredients":{1006:2,1000:1},"result":1133,"count":1},
		{"name":"Netherite Sword","ingredients":{1133:1,1023:1},"result":1134,"count":1},
		{"name":"Bow","ingredients":{1000:3,1016:3},"result":1141,"count":1},
		{"name":"Arrows x4","ingredients":{1000:1,1017:1,1018:1},"result":1142,"count":4},
		{"name":"Flint and Steel","ingredients":{1003:1,1018:1},"result":1143,"count":1},
		{"name":"Bucket","ingredients":{1003:3},"result":1144,"count":1},
		{"name":"Bread","ingredients":{1015:3},"result":1201,"count":1},
		{"name":"Golden Apple","ingredients":{1200:1,1005:8},"result":1203,"count":1},
		{"name":"Stone Bricks x4","ingredients":{3:4},"result":53,"count":4},
		{"name":"Bricks","ingredients":{1014:4},"result":17,"count":1},
		{"name":"Iron Block","ingredients":{1003:9},"result":77,"count":1},
		{"name":"Gold Block","ingredients":{1005:9},"result":78,"count":1},
		{"name":"Diamond Block","ingredients":{1006:9},"result":79,"count":1},
		{"name":"Blaze Powder x2","ingredients":{1019:1},"result":1025,"count":2},
		{"name":"Eye of the End","ingredients":{1020:1,1025:1},"result":1021,"count":1},
		{"name":"Nether Portal","ingredients":{18:6,1018:1,1003:1},"result":29,"count":1,"creative_only":true},
		{"name":"End Portal","ingredients":{23:4,1021:1},"result":30,"count":1,"creative_only":true},
		{"name":"Netherite Ingot","ingredients":{1022:4,1005:4},"result":1023,"count":1},
		{"name":"Iron Ingot • smelt","ingredients":{1002:1,1001:1},"result":1003,"count":1,"station":26},
		{"name":"Gold Ingot • smelt","ingredients":{1004:1,1001:1},"result":1005,"count":1,"station":26},
		{"name":"Copper Ingot • smelt","ingredients":{1007:1,1001:1},"result":1008,"count":1,"station":26},
		{"name":"Glass x4 • smelt","ingredients":{8:4,1001:1},"result":16,"count":4,"station":26},
		{"name":"Stone x4 • smelt","ingredients":{4:4,1001:1},"result":3,"count":4,"station":26},
		{"name":"Brick x4 • smelt","ingredients":{48:1,1001:1},"result":1014,"count":4,"station":26},
		{"name":"Cooked Steak • smelt","ingredients":{1206:1,1001:1},"result":1202,"count":1,"station":26},
		{"name":"Netherite Scrap • smelt","ingredients":{141:1,1001:1},"result":1022,"count":1,"station":26},
	]
	# The first 46 entries retain the previous recipe book and its stable ordering.
	# Activated portals remain available in creative; survival builds/ignites frames.
	result.append_array([
		{"name":"Red Bed","ingredients":{7:3,117:3},"result":181,"count":1},
		{"name":"Oak Boat","ingredients":{7:5},"result":1402,"count":1},
		{"name":"Charcoal Filter","ingredients":{1001:2,1026:2,1003:1},"result":1401,"count":1},
		{"name":"Gas Mask","ingredients":{1003:3,16:2,1401:1},"result":1400,"count":1},
		{"name":"Paper x3 • grass pulp","ingredients":{165:3},"result":1026,"count":3},
		{"name":"String x2 • grass fibre","ingredients":{165:3},"result":1016,"count":2},
		{"name":"Flint • sift gravel","ingredients":{49:3},"result":1018,"count":1},
		{"name":"Quartz x4 • cut quartz block","ingredients":{71:1},"result":1012,"count":4},
		{"name":"White Wool","ingredients":{1016:4},"result":117,"count":1},
		{"name":"Clay Balls x4","ingredients":{48:1},"result":1013,"count":4},
		{"name":"Charcoal • smelt logs","ingredients":{5:2},"result":1001,"count":1,"station":26},
		{"name":"Redstone Wire x4","ingredients":{1010:4},"result":155,"count":4},
		{"name":"Lever","ingredients":{1000:1,4:1},"result":156,"count":1},
		{"name":"Redstone Torch","ingredients":{1000:1,1010:1},"result":164,"count":1},
		{"name":"Repeater","ingredients":{164:2,1010:1,3:3},"result":157,"count":1},
		{"name":"Redstone Lamp","ingredients":{22:1,1010:4},"result":158,"count":1},
		{"name":"Piston","ingredients":{7:3,4:4,1003:1,1010:1},"result":159,"count":1},
		{"name":"Sticky Piston","ingredients":{159:1,1029:1},"result":160,"count":1},
		{"name":"Observer","ingredients":{4:6,1010:2,1012:1},"result":161,"count":1},
		{"name":"Dispenser","ingredients":{4:7,1141:1,1010:1},"result":162,"count":1},
		{"name":"Dropper","ingredients":{4:7,1010:1},"result":163,"count":1},
		{"name":"Stone Button","ingredients":{3:1},"result":177,"count":1},
		{"name":"Stone Pressure Plate","ingredients":{3:2},"result":178,"count":1},
		{"name":"Comparator","ingredients":{164:3,3:3,1012:1},"result":179,"count":1},
		{"name":"Hopper","ingredients":{1003:5,27:1},"result":180,"count":1},
		{"name":"Deepslate x4 • smelt","ingredients":{147:4,1001:1},"result":58,"count":4,"station":26},
		{"name":"Polished Deepslate x4","ingredients":{147:4},"result":148,"count":4},
		{"name":"Deepslate Bricks x4","ingredients":{148:4},"result":59,"count":4},
		{"name":"Cracked Deepslate Bricks x4 • smelt","ingredients":{59:4,1001:1},"result":149,"count":4,"station":26},
		{"name":"Deepslate Tiles x4","ingredients":{59:4},"result":150,"count":4},
		{"name":"Sandstone","ingredients":{8:4},"result":50,"count":1},
		{"name":"Red Sandstone","ingredients":{51:4},"result":52,"count":1},
		{"name":"Mossy Stone Bricks","ingredients":{53:1,47:1},"result":54,"count":1},
		{"name":"Diorite x2","ingredients":{4:2,1012:2},"result":56,"count":2},
		{"name":"Andesite x2","ingredients":{56:1,3:1},"result":57,"count":2},
		{"name":"Polished Granite x2","ingredients":{56:2,1007:1},"result":55,"count":2},
		{"name":"Nether Bricks x4 • smelt","ingredients":{19:4,1001:1},"result":62,"count":4,"station":26},
		{"name":"Red Nether Bricks x4","ingredients":{62:4,66:1},"result":63,"count":4},
		{"name":"Quartz Block","ingredients":{1012:4},"result":71,"count":1},
		{"name":"Quartz Bricks x4","ingredients":{71:4},"result":72,"count":4},
		{"name":"Oxidized Copper","ingredients":{80:1,151:1},"result":81,"count":1},
		{"name":"Amethyst • grow crystal","ingredients":{1012:4,1011:1},"result":86,"count":1},
		{"name":"Prismarine x4","ingredients":{4:4,1008:1,1011:1},"result":89,"count":4},
		{"name":"Blackstone x4","ingredients":{4:4,1001:1},"result":60,"count":4},
		{"name":"Basalt x4 • fuse stone","ingredients":{3:4,1001:1},"result":61,"count":4,"station":26},
		{"name":"Terracotta x4 • smelt","ingredients":{48:4,1001:1},"result":100,"count":4,"station":26},
		{"name":"White Concrete x8","ingredients":{8:4,49:4,1013:1},"result":133,"count":8},
		{"name":"Black Concrete x8","ingredients":{133:8,1001:1},"result":134,"count":8},
		{"name":"Red Concrete x8","ingredients":{133:8,166:1},"result":135,"count":8},
		{"name":"Blue Concrete x8","ingredients":{133:8,1011:1},"result":136,"count":8},
		{"name":"Yellow Concrete x8","ingredients":{133:8,151:1},"result":137,"count":8},
		{"name":"End Stone Bricks x4","ingredients":{23:4},"result":138,"count":4},
		{"name":"Purpur Pillar x2","ingredients":{24:2},"result":139,"count":2},
		{"name":"Farmland","ingredients":{2:1,1000:1},"result":167,"count":1},
		{"name":"Wheat Crop","ingredients":{1015:1},"result":168,"count":1},
		{"name":"Path","ingredients":{2:1,49:1},"result":169,"count":2},
	])
	for pair in [[37,38],[43,44],[45,46],[64,65],[67,68]]:
		result.append({"name":BlockDB.item_name(pair[1])+" x4","ingredients":{pair[0]:1},"result":pair[1],"count":4})
	for base in [35,36,38,41,44,46,65,68]:
		result.append({"name":"Sticks x4 • "+BlockDB.item_name(base),"ingredients":{base:2},"result":1000,"count":4})
	for pair in [[1008,80],[1009,82],[1011,83],[1010,84],[1001,85],[1023,142]]:
		result.append({"name":BlockDB.item_name(pair[1]),"ingredients":{pair[0]:9},"result":pair[1],"count":1})
	# Pigments use obtainable minerals and plants without introducing unused dye items.
	var pigments: Array[int] = [1013,1007,166,1011,151,6,166,1001,1013,1007,1011,1011,2,6,166,1001]
	for index in pigments.size():
		var id: int = 101 + index
		result.append({"name":BlockDB.item_name(id)+" x8","ingredients":{100:8,pigments[index]:1},"result":id,"count":8})
	for base_id in BlockDB.shape_families():
		var stair: int = BlockDB.shape_id(base_id,"stair")
		var slab: int = BlockDB.shape_id(base_id,"slab")
		result.append({"name":BlockDB.item_name(stair)+" x4","ingredients":{base_id:6},"result":stair,"count":4})
		result.append({"name":BlockDB.item_name(slab)+" x6","ingredients":{base_id:3},"result":slab,"count":6})
	return result

func can_craft(recipe: Dictionary) -> bool:
	if not BlockDB.valid_item(int(recipe.get("result",0))) or int(recipe.get("count",1)) <= 0:
		return false
	if not recipe.get("ingredients",{}) is Dictionary:
		return false
	if not creative and bool(recipe.get("creative_only",false)):
		return false
	for id in recipe.get("ingredients",{}):
		if not BlockDB.valid_item(int(id)) or int(recipe.ingredients[id]) <= 0:
			return false
	if creative:
		return true
	for id in recipe.get("ingredients",{}):
		if count_item(int(id)) < int(recipe.ingredients[id]):
			return false
	return true

func craft(recipe: Dictionary) -> bool:
	if not can_craft(recipe):
		return false
	# Simulate on a private inventory, so listeners never observe half a craft.
	var transaction = PlayerInventory.new()
	transaction.slots = slots.duplicate(true)
	transaction.creative = creative
	for id in recipe.get("ingredients",{}):
		if not transaction.consume(int(id),int(recipe.ingredients[id])):
			return false
	if not transaction.add_item(int(recipe.get("result",0)),int(recipe.get("count",1))):
		return false
	slots = transaction.slots
	changed.emit()
	return true
