class_name SaveManager
extends RefCounted
## Versioned world files with atomic replacement, last-good backups and safe imports.
## Imports contain only JSON world data; IDs and paths are generated locally.

const FORMAT: String = "slopcraft2-world"
const SCHEMA_VERSION: int = 1
const MAX_FILE_BYTES: int = 32 * 1024 * 1024
const MAX_EDITS: int = 250000
static var worlds_directory: String = "user://worlds"
static var last_error: String = ""

static func _ensure_directory() -> Error:
	return DirAccess.make_dir_recursive_absolute(worlds_directory)

static func _safe_id(id: String) -> bool:
	if id.is_empty() or id.length() > 90:
		return false
	for character in id:
		if not (character >= "a" and character <= "z") and not (character >= "0" and character <= "9") and character != "-" and character != "_":
			return false
	return true

static func _new_id() -> String:
	return "world-%d-%08x" % [int(Time.get_unix_time_from_system()*1000.0),randi()]

static func _path(id: String) -> String:
	return worlds_directory.path_join(id + ".json")

static func create_world(world_name: String, world_seed: Variant, mode: String = "survival") -> Dictionary:
	var clean_name: String = world_name.strip_edges().left(64)
	if clean_name.is_empty():
		clean_name = "New World"
	var seed_number: int = int(world_seed) if str(world_seed).is_valid_int() else int(str(world_seed).hash())
	var now: float = Time.get_unix_time_from_system()
	var data: Dictionary = {
		"schema_version":SCHEMA_VERSION,"id":_new_id(),"name":clean_name,
		"seed":seed_number,"mode":"creative" if mode == "creative" else "survival",
		"created_at":now,"updated_at":now,"last_played":now,"dimension":"overworld",
		"player":{"position":[],"rotation":[0.0,0.0],"health":20.0,"hunger":20.0},
		"inventory":{},"dimensions":{"overworld":{"edits":{}},"nether":{"edits":{}},"end":{"edits":{}}},
		"boss_defeated":false,"play_time":0.0
	}
	var inventory = PlayerInventory.new()
	inventory.setup(mode == "creative")
	data.inventory = inventory.serialize()
	if save_world(data) != OK:
		return {}
	return data

static func list_worlds() -> Array:
	_ensure_directory()
	var result: Array = []
	var directory = DirAccess.open(worlds_directory)
	if directory == null:
		return result
	for filename in directory.get_files():
		if filename.ends_with(".json"):
			var id: String = filename.trim_suffix(".json")
			if _safe_id(id):
				var data: Dictionary = load_world(id)
				if not data.is_empty():
					result.append(data)
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a.get("updated_at",0)) > float(b.get("updated_at",0)))
	return result

static func save_world(data: Dictionary) -> Error:
	last_error = ""
	var checked: Dictionary = _validate(data)
	if not checked.get("ok",false):
		last_error = str(checked.get("error","Invalid world data."))
		return ERR_INVALID_DATA
	var world: Dictionary = checked.world
	world.schema_version = SCHEMA_VERSION
	world.updated_at = Time.get_unix_time_from_system()
	world.last_played = world.updated_at
	data.updated_at = world.updated_at
	data.last_played = world.last_played
	var directory_error: Error = _ensure_directory()
	if directory_error != OK:
		last_error = "Could not create the world save directory."
		return directory_error
	return _atomic_write(_path(str(world.id)),JSON.stringify(world),true)

static func _atomic_write(destination: String, content: String, keep_backup: bool = false) -> Error:
	if content.to_utf8_buffer().size() > MAX_FILE_BYTES:
		last_error = "This save exceeds the 32 MB world-file limit."
		return ERR_OUT_OF_MEMORY
	var temporary: String = destination + ".tmp"
	var file = FileAccess.open(temporary,FileAccess.WRITE)
	if file == null:
		last_error = "Could not write the save file."
		return FileAccess.get_open_error()
	file.store_string(content)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		last_error = "The save could not be completely written."
		return write_error
	if keep_backup and FileAccess.file_exists(destination):
		# Only replace the backup when the prior main file is valid.
		if not _read_world_file(destination).is_empty():
			var backup_temp: String = destination + ".bak.tmp"
			var backup_error: Error = DirAccess.copy_absolute(destination,backup_temp)
			if backup_error != OK:
				last_error = "Could not preserve the previous save."
				return backup_error
			backup_error = DirAccess.rename_absolute(backup_temp,destination + ".bak")
			if backup_error != OK:
				last_error = "Could not finish the save backup."
				return backup_error
	var result: Error = DirAccess.rename_absolute(temporary,destination)
	if result != OK:
		last_error = "Could not replace the world file. Your previous save is still available."
	return result

static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null:
		return null
	if file.get_length() > MAX_FILE_BYTES:
		file.close()
		return null
	var text: String = file.get_as_text()
	file.close()
	var parser = JSON.new()
	if parser.parse(text) != OK:
		return null
	return parser.data

static func _read_world_file(path: String) -> Dictionary:
	var raw: Variant = _read_json(path)
	if not raw is Dictionary:
		return {}
	var checked: Dictionary = _validate(raw)
	if not checked.get("ok",false):
		return {}
	return checked.world

static func load_world(id: String) -> Dictionary:
	last_error = ""
	if not _safe_id(id):
		last_error = "Invalid world identifier."
		return {}
	var data: Dictionary = _read_world_file(_path(id))
	if data.is_empty():
		data = _read_world_file(_path(id) + ".bak")
		if not data.is_empty():
			last_error = "Recovered the previous world save from its backup."
		else:
			last_error = "This world is missing or damaged."
	if not data.is_empty() and str(data.id) != id:
		last_error = "World identifier does not match its save file."
		return {}
	return data

static func export_world(id: String, destination: String) -> Error:
	var data: Dictionary = load_world(id)
	if data.is_empty():
		return ERR_FILE_NOT_FOUND
	if destination.strip_edges().is_empty():
		last_error = "Choose a location for the world export."
		return ERR_INVALID_PARAMETER
	var envelope: Dictionary = {"format":FORMAT,"version":SCHEMA_VERSION,"world":data}
	return _atomic_write(destination,JSON.stringify(envelope,"\t"))

static func import_world(source: String) -> Dictionary:
	last_error = ""
	var envelope: Variant = _read_json(source)
	if not envelope is Dictionary or envelope.get("format","") != FORMAT:
		return _failure("This is not a Slopcraft 2 world export.")
	if not _is_integer(envelope.get("version",0)) or int(envelope.get("version",0)) > SCHEMA_VERSION or int(envelope.get("version",0)) < 1:
		return _failure("This world export uses an unsupported version.")
	var raw: Variant = envelope.get("world",null)
	if not raw is Dictionary:
		return _failure("The export is missing its world data.")
	var checked: Dictionary = _validate(raw)
	if not checked.get("ok",false):
		return checked
	var data: Dictionary = checked.world
	data.id = _new_id()
	data.name = (str(data.name) + " (imported)").left(64)
	data.updated_at = Time.get_unix_time_from_system()
	var result: Error = save_world(data)
	if result != OK:
		return _failure(last_error)
	return {"ok":true,"error":"","world":data}

static func _failure(message: String) -> Dictionary:
	last_error = message
	return {"ok":false,"error":message,"world":{}}

static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _is_integer(value: Variant) -> bool:
	return _is_number(value) and float(value) == floor(float(value))

static func _valid_vector(value: Variant, expected: int, allow_empty: bool = false) -> bool:
	if not value is Array:
		return false
	if allow_empty and value.is_empty():
		return true
	if value.size() != expected:
		return false
	for component in value:
		if not _is_number(component) or absf(float(component)) > 30000000.0:
			return false
	return true

static func _validate(raw: Dictionary) -> Dictionary:
	# Schema 0 used the same fields but omitted schema_version/timestamps.
	var version: Variant = raw.get("schema_version",0)
	if not _is_integer(version) or int(version) < 0 or int(version) > SCHEMA_VERSION:
		return _failure("Unsupported world schema version.")
	if not raw.get("id",null) is String or not _safe_id(raw.id):
		return _failure("World identifier is invalid.")
	if not raw.get("name",null) is String or str(raw.name).length() > 128:
		return _failure("World name is invalid.")
	if not _is_integer(raw.get("seed",null)) or absf(float(raw.seed)) > 9007199254740991.0:
		return _failure("World seed is invalid.")
	if not raw.get("mode","") in ["creative","survival"]:
		return _failure("World game mode is invalid.")
	if not raw.get("dimension","") in ["overworld","nether","end"]:
		return _failure("World dimension is invalid.")
	var player: Variant = raw.get("player",{})
	if not player is Dictionary:
		return _failure("Player data is invalid.")
	if not _valid_vector(player.get("position",[]),3,true):
		return _failure("Player position is invalid.")
	var rotation: Variant = player.get("rotation",[0.0,0.0])
	if not _valid_vector(rotation,2) and not _valid_vector(rotation,3):
		return _failure("Player rotation is invalid.")
	for stat in ["health","hunger"]:
		if not _is_number(player.get(stat,20.0)):
			return _failure("Player status is invalid.")
	var dimensions: Variant = raw.get("dimensions",{})
	if not dimensions is Dictionary:
		return _failure("Dimension data is invalid.")
	var edits_count: int = 0
	for dimension in dimensions:
		if not dimension in ["overworld","nether","end"] or not dimensions[dimension] is Dictionary:
			return _failure("Unknown or damaged dimension data.")
		var edits: Variant = dimensions[dimension].get("edits",{})
		if not edits is Dictionary:
			return _failure("World block edits are invalid.")
		edits_count += edits.size()
		if edits_count > MAX_EDITS:
			return _failure("This world exceeds the supported edit limit.")
		for coordinate in edits:
			if not coordinate is String:
				return _failure("A block position is invalid.")
			var components: PackedStringArray = coordinate.split(",")
			if components.size() != 3:
				return _failure("A block position is invalid.")
			for component in components:
				if not component.strip_edges().is_valid_int() or absi(int(component)) > 30000000:
					return _failure("A block position is outside the supported range.")
			var block_id: Variant = edits[coordinate]
			if not _is_integer(block_id) or (int(block_id) != 0 and not BlockDB.is_block(int(block_id))):
				return _failure("The world contains an unknown block.")
	var inventory: Variant = raw.get("inventory",{})
	if not inventory is Dictionary:
		return _failure("Inventory data is invalid.")
	var inventory_slots: Variant = inventory.get("slots",[])
	if not inventory_slots is Array or inventory_slots.size() > PlayerInventory.SLOT_COUNT:
		return _failure("Inventory slots are invalid.")
	for slot in inventory_slots:
		if not slot is Dictionary or not _is_integer(slot.get("id",null)) or not _is_integer(slot.get("count",null)):
			return _failure("An inventory slot is invalid.")
		if int(slot.id) < 0 or (int(slot.id) != 0 and not BlockDB.valid_item(int(slot.id))) or int(slot.count) < 0 or int(slot.count) > 64:
			return _failure("An inventory item is invalid.")
	if not _is_integer(inventory.get("selected",0)) or int(inventory.get("selected",0)) < 0 or int(inventory.get("selected",0)) > 8:
		return _failure("The selected inventory slot is invalid.")
	var world: Dictionary = raw.duplicate(true)
	world.schema_version = SCHEMA_VERSION
	world.seed = int(world.seed)
	world.inventory = inventory.duplicate(true)
	world.inventory.selected = int(inventory.get("selected",0))
	world.inventory.creative = world.mode == "creative"
	world.inventory.slots = []
	for slot in inventory_slots:
		world.inventory.slots.append({"id":int(slot.id),"count":int(slot.count)})
	world.name = str(world.name).strip_edges().left(64)
	if world.name.is_empty():
		world.name = "New World"
	world.player = player.duplicate(true)
	world.player.rotation = rotation
	world.player.health = clampf(float(player.get("health",20.0)),0.0,20.0)
	world.player.hunger = clampf(float(player.get("hunger",20.0)),0.0,20.0)
	world.dimensions = dimensions.duplicate(true)
	for dimension in ["overworld","nether","end"]:
		if not world.dimensions.has(dimension):
			world.dimensions[dimension] = {"edits":{}}
		elif not world.dimensions[dimension].has("edits"):
			world.dimensions[dimension].edits = {}
		for coordinate in world.dimensions[dimension].edits:
			world.dimensions[dimension].edits[coordinate] = int(world.dimensions[dimension].edits[coordinate])
	for timestamp in ["created_at","updated_at","last_played"]:
		var value: Variant = world.get(timestamp,Time.get_unix_time_from_system())
		world[timestamp] = float(value) if _is_number(value) else Time.get_unix_time_from_system()
	return {"ok":true,"error":"","world":world}

static func load_settings() -> Dictionary:
	var data: Variant = _read_json("user://settings.json")
	return data if data is Dictionary else {}

static func save_settings(settings: Dictionary) -> Error:
	return _atomic_write("user://settings.json",JSON.stringify(settings))
