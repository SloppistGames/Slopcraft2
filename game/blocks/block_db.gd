class_name BlockDB
extends RefCounted
## Original, extensible voxel palette. Numeric IDs are stable save-file contracts.

static var _blocks: Dictionary = {}
static var _items: Dictionary = {}

# Append only: the index is part of the permanent stair/slab save ID contract.
# Stairs = 200 + index * 2; slabs = stairs + 1. Never reorder this list.
const SHAPE_BASE_IDS: Array[int] = [
	7,35,36,38,41,44,46,65,68,3,4,17,50,52,53,54,55,56,57,
	58,59,60,61,62,63,71,72,77,78,79,80,81,82,83,84,85,86,89,
	100,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,
	133,134,135,136,137,138,139,142,147,148,149,150,
]
const FIRST_SHAPE_ID: int = 200
const GAS_MASK_ID: int = 1400
const CHARCOAL_FILTER_ID: int = 1401

static func _ensure() -> void:
	if not _blocks.is_empty():
		return
	# id, display name, colour, pattern; optional properties are set below.
	var definitions: Array = [
		[0,"Air","000000","air"], [1,"Grass Block","729c3e","grass"],
		[2,"Dirt","89613f","dirt"], [3,"Stone","929392","stone"],
		[4,"Cobblestone","777d7a","cobble"], [5,"Oak Log","705131","log"],
		[6,"Oak Leaves","498534","leaves"], [7,"Oak Planks","b58b52","planks"],
		[8,"Sand","d9c78e","sand"], [9,"Water","3a80c5","water"],
		[10,"Bedrock","383a40","stone"], [11,"Coal Ore","292d33","coal_ore"],
		[12,"Iron Ore","c2a18a","iron_ore"], [13,"Gold Ore","e5bd43","gold_ore"],
		[14,"Diamond Ore","69d9d1","diamond_ore"], [15,"Snow","eef2ed","snow"],
		[16,"Glass","c2e1e5","glass"], [17,"Bricks","ad6a51","bricks"],
		[18,"Obsidian","292139","obsidian"], [19,"Netherrack","7d3334","netherrack"],
		[20,"Lava","ef711d","lava"], [21,"Soul Sand","695342","sand"],
		[22,"Glowstone","d8b35d","glowstone"], [23,"End Stone","c6c68c","end"],
		[24,"Purpur","a37da4","bricks"], [25,"Crafting Table","996c39","crafting"],
		[26,"Furnace","646970","furnace"], [27,"Chest","a97932","chest"],
		[28,"Torch","df9a35","torch"], [29,"Nether Portal","8838d2","portal"],
		[30,"End Portal","2caa9f","portal"], [31,"Spruce Log","51402c","log"],
		[32,"Spruce Leaves","315b43","leaves"], [33,"Birch Log","e3dec6","birch"],
		[34,"Birch Leaves","6c9d42","leaves"], [35,"Spruce Planks","725433","planks"],
		[36,"Birch Planks","d8c795","planks"], [37,"Acacia Log","7d7770","log"],
		[38,"Acacia Planks","bd7041","planks"], [39,"Acacia Leaves","6d8742","leaves"],
		[40,"Cherry Log","573943","log"], [41,"Cherry Planks","dcaaa1","planks"],
		[42,"Cherry Leaves","d7a2bb","leaves"], [43,"Dark Oak Log","443025","log"],
		[44,"Dark Oak Planks","4c3525","planks"], [45,"Jungle Log","816342","log"],
		[46,"Jungle Planks","b18463","planks"], [47,"Moss","6a873d","leaves"],
		[48,"Clay","a0a7b4","stone"], [49,"Gravel","8c8783","gravel"],
		[50,"Sandstone","d6bd7e","sandstone"], [51,"Red Sand","b9753f","sand"],
		[52,"Red Sandstone","b76d39","sandstone"], [53,"Stone Bricks","8b8c88","bricks"],
		[54,"Mossy Stone Bricks","718061","bricks"], [55,"Polished Granite","a57869","stone"],
		[56,"Diorite","c5c4bf","gravel"], [57,"Andesite","8c9292","stone"],
		[58,"Deepslate","4a4f56","cobble"], [59,"Deepslate Bricks","42474d","bricks"],
		[60,"Blackstone","363139","cobble"], [61,"Basalt","4d4d50","log"],
		[62,"Nether Bricks","4c2830","bricks"], [63,"Red Nether Bricks","7b292c","bricks"],
		[64,"Crimson Stem","803445","log"], [65,"Crimson Planks","773b50","planks"],
		[66,"Crimson Wart","9a263c","leaves"], [67,"Warped Stem","326d65","log"],
		[68,"Warped Planks","347e79","planks"], [69,"Warped Wart","268987","leaves"],
		[70,"Shroomlight","f1aa5c","glowstone"], [71,"Quartz Block","ded6c5","stone"],
		[72,"Quartz Bricks","e4dcd1","bricks"], [73,"Copper Ore","c18258","copper_ore"],
		[74,"Emerald Ore","43c57d","emerald_ore"], [75,"Redstone Ore","cd434e","redstone_ore"],
		[76,"Lapis Ore","466cce","lapis_ore"], [77,"Iron Block","d4d5d0","metal"],
		[78,"Gold Block","e8bd36","metal"], [79,"Diamond Block","56c9c5","metal"],
		[80,"Copper Block","bf7c54","metal"], [81,"Oxidized Copper","56a08c","metal"],
		[82,"Emerald Block","39ad65","metal"], [83,"Lapis Block","34549c","metal"],
		[84,"Redstone Block","ae3035","metal"], [85,"Coal Block","262b31","cobble"],
		[86,"Amethyst","9c74be","crystal"], [87,"Ice","8ac2de","glass"],
		[88,"Packed Ice","83adc9","stone"], [89,"Prismarine","5b9c8e","cobble"],
		[90,"Sea Lantern","b2e0cf","glowstone"], [91,"Bookshelf","b28a57","bookshelf"],
		[92,"Hay Bale","c8aa42","hay"], [93,"Pumpkin","c17c28","pumpkin"],
		[94,"Melon","6e9b3e","log"], [95,"Cactus","427e3d","cactus"],
		[96,"Sponge","d0c15b","gravel"], [97,"TNT","c14b39","tnt"],
		[98,"Slime Block","77c963","glass"], [99,"Honey Block","d3a140","glass"],
		[100,"Terracotta","ac7159","stone"], [101,"White Terracotta","d3b6a3","stone"],
		[102,"Orange Terracotta","ba713b","stone"], [103,"Magenta Terracotta","a0648b","stone"],
		[104,"Light Blue Terracotta","7e829f","stone"], [105,"Yellow Terracotta","c29c49","stone"],
		[106,"Lime Terracotta","768446","stone"], [107,"Pink Terracotta","be8179","stone"],
		[108,"Gray Terracotta","514644","stone"], [109,"Light Gray Terracotta","a18f86","stone"],
		[110,"Cyan Terracotta","637f7f","stone"], [111,"Purple Terracotta","795478","stone"],
		[112,"Blue Terracotta","5a5b84","stone"], [113,"Brown Terracotta","71513c","stone"],
		[114,"Green Terracotta","666b3d","stone"], [115,"Red Terracotta","a05a4a","stone"],
		[116,"Black Terracotta","392f2d","stone"],
		[117,"White Wool","ece9df","wool"], [118,"Orange Wool","e68f36","wool"],
		[119,"Magenta Wool","bd60ba","wool"], [120,"Light Blue Wool","71bdd7","wool"],
		[121,"Yellow Wool","e4c743","wool"], [122,"Lime Wool","8fbe47","wool"],
		[123,"Pink Wool","e49eae","wool"], [124,"Gray Wool","565a60","wool"],
		[125,"Light Gray Wool","b2b2aa","wool"], [126,"Cyan Wool","388e99","wool"],
		[127,"Purple Wool","8451b4","wool"], [128,"Blue Wool","4858a4","wool"],
		[129,"Brown Wool","795736","wool"], [130,"Green Wool","647b37","wool"],
		[131,"Red Wool","b84443","wool"], [132,"Black Wool","2e3037","wool"],
		[133,"White Concrete","ddddda","concrete"], [134,"Black Concrete","202128","concrete"],
		[135,"Red Concrete","a43c3b","concrete"], [136,"Blue Concrete","3d4e9b","concrete"],
		[137,"Yellow Concrete","dcc13d","concrete"], [138,"End Stone Bricks","b8b985","bricks"],
		[139,"Purpur Pillar","b090b0","log"], [140,"Dragon Egg","292135","crystal"],
		[141,"Ancient Debris","70534c","cobble"], [142,"Netherite Block","49434a","metal"],
		[143,"Red Mushroom","bf5449","mushroom"], [144,"Brown Mushroom","9d7e63","mushroom"],
		[145,"Magma Block","a64d28","magma"], [146,"Obsidian Lantern","75449a","glowstone"],
		[147,"Cobbled Deepslate","4b5057","deepslate_cobble"],
		[148,"Polished Deepslate","515963","deepslate_polished"],
		[149,"Cracked Deepslate Bricks","434951","deepslate_cracked"],
		[150,"Deepslate Tiles","3d434a","deepslate_tiles"],
		[151,"Sulfur","c3c94b","sulfur"], [152,"Sulfur Ore","adb448","sulfur_ore"],
		[153,"End Portal Frame","799889","end_frame"], [154,"Filled End Frame","7ca88b","end_frame_filled"],
		[155,"Redstone Wire","9e3038","redstone_wire"], [156,"Lever","9c886d","lever"],
		[157,"Repeater","aaa69e","repeater"], [158,"Redstone Lamp","957641","redstone_lamp"],
		[159,"Piston","a48d63","piston"], [160,"Sticky Piston","8caa5b","sticky_piston"],
		[161,"Observer","747c80","observer"], [162,"Dispenser","85898b","dispenser"],
		[163,"Dropper","85898b","dropper"], [164,"Redstone Torch","c34b3d","redstone_torch"],
		[165,"Tall Grass","71994d","tall_grass"], [166,"Wildflower","e6b6cc","wildflower"],
		[167,"Farmland","795437","farmland"], [168,"Wheat Crop","c7b54e","wheat_crop"],
		[169,"Path","aa9265","path"],
		[170,"Deepslate Coal Ore","292d33","deepslate_coal_ore"],
		[171,"Deepslate Iron Ore","c2a18a","deepslate_iron_ore"],
		[172,"Deepslate Gold Ore","e5bd43","deepslate_gold_ore"],
		[173,"Deepslate Diamond Ore","69d9d1","deepslate_diamond_ore"],
		[174,"Deepslate Redstone Ore","cd434e","deepslate_redstone_ore"],
		[175,"Deepslate Copper Ore","c18258","deepslate_copper_ore"],
		[176,"Sulfur Gas Vent","9fa449","sulfur_vent"],
		[177,"Stone Button","929392","button"], [178,"Stone Pressure Plate","929392","pressure_plate"],
		[179,"Comparator","aaa69e","comparator"], [180,"Hopper","646a70","hopper"],
		[181,"Red Bed","b44742","bed_foot"], [182,"Red Bed Head","e4e0ce","bed_head"],
		[183,"Piston Head","b58b52","piston_head"],
	]
	for entry in definitions:
		var id: int = entry[0]
		_blocks[id] = {"id":id,"name":entry[1],"color":Color(entry[2]),"solid":true,"transparent":false,"emission":0.0,"texture_kind":entry[3],"hardness":1.0,"drop":id,"category":"Building"}
	for id in [0,9,20,28,29,30]:
		_blocks[id]["solid"] = false
	for id in [0,6,9,16,20,28,29,30,32,34,39,42,87,98,99]:
		_blocks[id]["transparent"] = true
	for id in [22,28,70,90,146]:
		_blocks[id]["emission"] = 0.7
	for id in [20,29,30,145]:
		_blocks[id]["emission"] = 0.85
	_blocks[10]["hardness"] = -1.0
	_blocks[18]["hardness"] = 6.0
	_blocks[140]["hardness"] = 3.0
	for id in [6,32,34,39,42,47,66,69,117,118,119,120,121,122,123,124,125,126,127,128,129,130,131,132]:
		_blocks[id]["hardness"] = 0.35
	for id in [1,2,8,15,21,48,49,51]:
		_blocks[id]["hardness"] = 0.55
	_blocks[3]["drop"] = 4
	for pair in [[11,1001],[12,1002],[13,1004],[14,1006],[73,1007],[74,1009],[75,1010],[76,1011]]:
		_blocks[pair[0]]["drop"] = pair[1]
	_blocks[58]["texture_kind"] = "deepslate"
	_blocks[59]["texture_kind"] = "deepslate_bricks"
	_blocks[58]["drop"] = 147
	for pair in [[152,151],[155,1010],[168,1015],[170,1001],[171,1002],[172,1004],[173,1006],[174,1010],[175,1007],[176,151]]:
		_blocks[pair[0]]["drop"] = pair[1]
	for id in [155,156,157,164,165,166,168,177,178,179]:
		_blocks[id]["solid"] = false
		_blocks[id]["transparent"] = true
		_blocks[id]["hardness"] = 0.2
	for id in [58,59,147,148,149,150,170,171,172,173,174,175]:
		_blocks[id]["hardness"] = 1.6
	for id in [153,154]:
		_blocks[id]["hardness"] = -1.0
	for id in [181,182]:
		_blocks[id]["shape"] = "bed"
		_blocks[id]["transparent"] = true
		_blocks[id]["hardness"] = 0.4
		_blocks[id]["drop"] = 181
		_blocks[id]["category"] = "Furniture"
	_blocks[164]["emission"] = 0.25
	_blocks[183]["hardness"] = -1.0
	_blocks[183]["drop"] = 0
	for id in range(155,165):
		_blocks[id]["category"] = "Redstone"
	for id in [84,177,178,179,180]:
		_blocks[id]["category"] = "Redstone"
	for index in SHAPE_BASE_IDS.size():
		var base_id: int = SHAPE_BASE_IDS[index]
		for variant in 2:
			var id: int = FIRST_SHAPE_ID + index * 2 + variant
			var shaped: Dictionary = _blocks[base_id].duplicate(true)
			shaped["id"] = id
			shaped["name"] = str(shaped.name).trim_suffix(" Planks") + (" Stairs" if variant == 0 else " Slab")
			shaped["shape"] = "stair" if variant == 0 else "slab"
			shaped["base_id"] = base_id
			shaped["drop"] = id
			shaped["transparent"] = true
			shaped["category"] = "Stairs and Slabs"
			_blocks[id] = shaped
	var items: Array = [
		[1000,"Stick","a6814d","material"], [1001,"Coal","32343a","material"],
		[1002,"Raw Iron","bfa18a","material"], [1003,"Iron Ingot","d4d5d3","material"],
		[1004,"Raw Gold","d6b552","material"], [1005,"Gold Ingot","efc74b","material"],
		[1006,"Diamond","69e3db","material"], [1007,"Raw Copper","c78664","material"],
		[1008,"Copper Ingot","c58562","material"], [1009,"Emerald","50d48a","material"],
		[1010,"Redstone Dust","ca4242","material"], [1011,"Lapis Lazuli","5377d3","material"],
		[1012,"Quartz","e9e3d8","material"], [1013,"Clay Ball","abb3c2","material"],
		[1014,"Brick","c47a5c","material"], [1015,"Wheat","dfc66a","material"],
		[1016,"String","e5e3d3","material"], [1017,"Feather","e0e2db","material"],
		[1018,"Flint","7d7d86","material"], [1019,"Blaze Rod","e6b340","material"],
		[1020,"Ender Pearl","48b3a2","material"], [1021,"Eye of the End","91c576","portal_key"],
		[1022,"Netherite Scrap","806956","material"], [1023,"Netherite Ingot","6b6068","material"],
		[1024,"Leather","ab7650","material"], [1025,"Blaze Powder","edb24c","material"],
		[1026,"Paper","e4e2c8","material"], [1027,"Book","a77952","material"],
		[1028,"Gunpowder","777b7a","material"], [1029,"Slimeball","88cc6e","material"],
		[1030,"Obsidian Shard","735691","material"],
		[1100,"Wooden Pickaxe","b28b52","pickaxe"], [1101,"Stone Pickaxe","a0a39d","pickaxe"],
		[1102,"Iron Pickaxe","dadbd3","pickaxe"], [1103,"Diamond Pickaxe","61d6d4","pickaxe"],
		[1104,"Golden Pickaxe","e8c24e","pickaxe"], [1105,"Netherite Pickaxe","716474","pickaxe"],
		[1110,"Wooden Axe","b28b52","axe"], [1111,"Stone Axe","a0a39d","axe"],
		[1112,"Iron Axe","dadbd3","axe"], [1113,"Diamond Axe","61d6d4","axe"],
		[1120,"Wooden Shovel","b28b52","shovel"], [1121,"Stone Shovel","a0a39d","shovel"],
		[1122,"Iron Shovel","dadbd3","shovel"], [1123,"Diamond Shovel","61d6d4","shovel"],
		[1130,"Wooden Sword","b28b52","sword"], [1131,"Stone Sword","a0a39d","sword"],
		[1132,"Iron Sword","dadbd3","sword"], [1133,"Diamond Sword","61d6d4","sword"],
		[1134,"Netherite Sword","716474","sword"], [1140,"Iron Hoe","dadbd3","hoe"],
		[1141,"Bow","ae844c","bow"], [1142,"Arrow","c1b9a5","material"],
		[1143,"Flint and Steel","a9afb0","igniter"], [1144,"Bucket","b4c4c9","bucket"],
		[1145,"Water Bucket","548bd9","bucket"], [1146,"Lava Bucket","f89a42","bucket"],
		[1147,"Shears","c6c8c9","shears"], [1148,"Compass","b6bec5","compass"],
		[1149,"Clock","e4c564","clock"],
		[1200,"Apple","d44e45","food"], [1201,"Bread","cf9c54","food"],
		[1202,"Cooked Steak","976344","food"], [1203,"Golden Apple","e9c64d","food"],
		[1204,"Carrot","e9913e","food"], [1205,"Baked Potato","bc9563","food"],
		[1206,"Raw Beef","be6d62","food"], [1207,"Melon Slice","dc766d","food"],
		[1208,"Cooked Porkchop","b78464","food"], [1209,"Chorus Fruit","ad83b1","food"],
		[1210,"Mushroom Stew","a28159","food"], [1211,"Sweet Berries","ae4258","food"],
		[1300,"Iron Helmet","b7c0c4","armor"], [1301,"Iron Chestplate","b7c0c4","armor"],
		[1302,"Iron Leggings","b7c0c4","armor"], [1303,"Iron Boots","b7c0c4","armor"],
		[1310,"Diamond Helmet","64d5ce","armor"], [1311,"Diamond Chestplate","64d5ce","armor"],
		[1312,"Diamond Leggings","64d5ce","armor"], [1313,"Diamond Boots","64d5ce","armor"],
		[1400,"Gas Mask","53645a","armor"], [1401,"Charcoal Filter","414844","material"],
		[1402,"Oak Boat","a87b43","boat"],
	]
	for entry in items:
		var id: int = entry[0]
		_items[id] = {"id":id,"name":entry[1],"color":Color(entry[2]),"kind":entry[3],"category":"Items","stack_size":64,"damage":2.0,"speed":1.0,"food":0}
		if entry[3] in ["pickaxe","axe","shovel","sword","hoe","bow","shears","igniter","armor"]:
			_items[id]["stack_size"] = 1
	for id in [1100,1101,1102,1103,1104,1105,1110,1111,1112,1113,1120,1121,1122,1123]:
		_items[id]["speed"] = [2.0,3.5,5.0,7.0,8.0,9.0][id % 10]
	for id in [1130,1131,1132,1133,1134]:
		_items[id]["damage"] = [4.0,5.0,7.0,10.0,13.0][id % 10]
	for id in range(1200,1212):
		_items[id]["food"] = 5 if id != 1203 else 10
	for base in [1300,1310]:
		for offset in 4:
			_items[base + offset]["equipment_slot"] = ["head","chest","legs","feet"][offset]
	_items[1400]["equipment_slot"] = "head"
	_items[1400]["gas_protection"] = true
	_items[1402]["stack_size"] = 1
	_items[1010]["places_block"] = 155

static func shape_id(base_id: int, shape: String) -> int:
	var index: int = SHAPE_BASE_IDS.find(base_id)
	if index < 0 or shape not in ["stair","slab"]:
		return 0
	return FIRST_SHAPE_ID + index * 2 + (1 if shape == "slab" else 0)

static func shape_families() -> Array[int]:
	return SHAPE_BASE_IDS.duplicate()

static func get_block(id: int) -> Dictionary:
	_ensure()
	return _blocks.get(id, _blocks[0])

static func all_blocks() -> Array:
	_ensure()
	return _blocks.values()

static func get_item(id: int) -> Dictionary:
	_ensure()
	if _blocks.has(id):
		return _blocks[id]
	return _items.get(id, {"id":0,"name":"Air","color":Color.TRANSPARENT,"kind":"none","stack_size":64})

static func item_name(id: int) -> String:
	return str(get_item(id).get("name","Unknown"))

static func item_color(id: int) -> Color:
	return get_item(id).get("color",Color.WHITE)

static func is_block(id: int) -> bool:
	_ensure()
	return id > 0 and _blocks.has(id)

static func valid_item(id: int) -> bool:
	_ensure()
	return id > 0 and (_blocks.has(id) or _items.has(id))

static func all_items() -> Array:
	_ensure()
	var result: Array = []
	for block in _blocks.values():
		if int(block.id) > 0:
			result.append(block)
	result.append_array(_items.values())
	return result
