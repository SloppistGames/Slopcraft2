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
		for pair in [[1100,1],[1130,1],[7,24],[4,16],[28,12],[1201,8],[25,1],[29,1],[30,1]]:
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
		{"name":"Nether Portal","ingredients":{18:6,1018:1,1003:1},"result":29,"count":1},
		{"name":"End Portal","ingredients":{23:4,1021:1},"result":30,"count":1},
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
	return result

func can_craft(recipe: Dictionary) -> bool:
	if creative:
		return true
	for id in recipe.get("ingredients",{}):
		if count_item(int(id)) < int(recipe.ingredients[id]):
			return false
	return true

func craft(recipe: Dictionary) -> bool:
	if not can_craft(recipe):
		return false
	var snapshot: Array = slots.duplicate(true)
	for id in recipe.get("ingredients",{}):
		consume(int(id),int(recipe.ingredients[id]))
	if not add_item(int(recipe.get("result",0)),int(recipe.get("count",1))):
		slots = snapshot
		changed.emit()
		return false
	changed.emit()
	return true
