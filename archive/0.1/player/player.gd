class_name VoxelPlayer
extends CharacterBody3D
## First-person movement and grid-accurate interactions; all state is saveable.

signal stats_changed
signal inventory_changed
signal notify(message: String)
signal portal_requested(dimension: String)
signal interact_requested(block_id: int, block_position: Vector3i)
signal died

var world: Node3D
var inventory: RefCounted
var entities: Node
var can_break_block: Callable
var camera: Camera3D
var active: bool = false
var health: float = 20.0
var hunger: float = 20.0
var air: float = 10.0
var flying: bool = false
var mouse_sensitivity: float = 0.0022
var target_name: String = ""
var mining_progress: float = 0.0
var target: Dictionary = {}
var creative: bool:
	get:
		return inventory != null and bool(inventory.get("creative"))
var _pitch: float = 0.0
var _outline: MeshInstance3D
var _held_root: Node3D
var _held_model: Node3D
var _last_item: int = -1
var _bob: float = 0.0
var _swing: float = 0.0
var _attack_cooldown: float = 0.0
var _place_cooldown: float = 0.0
var _hurt_cooldown: float = 0.0
var _portal_cooldown: float = 2.0
var _food_clock: float = 0.0
var _hazard_clock: float = 0.0
var _fall_speed: float = 0.0
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _mining_cell := Vector3i(2147483647, 0, 0)
var _footstep: float = 0.0
var _audio: AudioStreamPlayer
var _sounds: Dictionary = {}

func setup(voxel_world: Node3D, player_inventory: RefCounted) -> void:
	world = voxel_world
	inventory = player_inventory
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(48.0)
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.78
	collider.shape = capsule
	collider.position.y = 0.9
	add_child(collider)
	camera = Camera3D.new()
	camera.position.y = 1.62
	camera.fov = 76.0
	camera.near = 0.05
	camera.far = 512.0
	camera.current = true
	add_child(camera)
	_held_root = Node3D.new()
	camera.add_child(_held_root)
	_held_root.position = Vector3(0.43, -0.40, -0.70)
	_held_root.rotation_degrees = Vector3(-10, -28, 0)
	_outline = MeshInstance3D.new()
	_outline.mesh = _outline_mesh()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.12, 0.10, 0.08, 0.85)
	_outline.material_override = material
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_outline)
	_outline.visible = false
	_audio = AudioStreamPlayer.new()
	_audio.volume_db = -15.0
	add_child(_audio)
	_sounds["step"] = _sound(160.0, 0.055, 0.65)
	_sounds["break"] = _sound(100.0, 0.12, 0.9)
	_sounds["place"] = _sound(240.0, 0.065, 0.6)
	_sounds["hurt"] = _sound(70.0, 0.2, 0.4)
	_sounds["shoot"] = _sound(540.0, 0.14, 0.15)
	_configure_inputs()
	if inventory.has_signal("changed"):
		inventory.connect("changed", _inventory_updated)
	_update_held_item()

func _configure_inputs() -> void:
	var mappings: Dictionary = {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "jump": KEY_SPACE, "sprint": KEY_SHIFT, "crouch": KEY_CTRL, "fly": KEY_F}
	for action: String in mappings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = int(mappings[action])
			InputMap.action_add_event(action, key)

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.55, 1.55)
		camera.rotation.x = _pitch
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9:
			inventory.set("selected", int(event.physical_keycode - KEY_1))
			_inventory_updated()
		elif event.physical_keycode == KEY_F and creative:
			flying = not flying
			velocity = Vector3.ZERO
			notify.emit("Flight enabled  ·  Space up / Ctrl down" if flying else "Flight disabled")
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			inventory.set("selected", posmod(int(inventory.get("selected")) - 1, 9))
			_inventory_updated()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			inventory.set("selected", posmod(int(inventory.get("selected")) + 1, 9))
			_inventory_updated()
		elif event.button_index == MOUSE_BUTTON_MIDDLE and creative and not target.is_empty():
			inventory.call("select_item", int(target["id"]))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_use_selected()

func _physics_process(delta: float) -> void:
	if world == null or camera == null:
		return
	if not active:
		_outline.visible = false
		mining_progress = 0.0
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_place_cooldown = maxf(0.0, _place_cooldown - delta)
	_hurt_cooldown = maxf(0.0, _hurt_cooldown - delta)
	_portal_cooldown = maxf(0.0, _portal_cooldown - delta)
	_swing = maxf(0.0, _swing - delta * 5.0)
	var feet_id: int = int(world.call("get_block", Vector3i((global_position + Vector3(0, 0.2, 0)).floor())))
	var in_water: bool = feet_id == 9
	var crouched: bool = Input.is_action_pressed("crouch") and not flying
	var sprinting: bool = Input.is_action_pressed("sprint") and not crouched and (creative or hunger > 5.0)
	var speed: float = 7.3 if sprinting else 4.5
	if crouched:
		speed = 2.0
	if in_water and not flying:
		speed = 3.1
	if flying:
		speed = 16.0 if sprinting else 9.0
	var input_direction: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var movement: Vector3 = (global_transform.basis * Vector3(input_direction.x, 0, input_direction.y)).normalized()
	velocity.x = move_toward(velocity.x, movement.x * speed, delta * (40.0 if is_on_floor() or flying else 14.0))
	velocity.z = move_toward(velocity.z, movement.z * speed, delta * (40.0 if is_on_floor() or flying else 14.0))
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = 0.15
	else:
		_jump_buffer = maxf(0.0, _jump_buffer - delta)
	if is_on_floor():
		_coyote = 0.12
	else:
		_coyote = maxf(0.0, _coyote - delta)
	if flying:
		velocity.y = move_toward(velocity.y, (float(Input.is_action_pressed("jump")) - float(Input.is_action_pressed("crouch"))) * speed, delta * 45.0)
	elif in_water:
		velocity.y = move_toward(velocity.y, 3.8 if Input.is_action_pressed("jump") else -1.5, delta * 12.0)
		_fall_speed = 0.0
	else:
		velocity.y -= 24.0 * delta
		if _jump_buffer > 0.0 and _coyote > 0.0:
			velocity.y = 8.15
			_jump_buffer = 0.0
			_coyote = 0.0
			if not creative:
				hunger = maxf(0.0, hunger - 0.015)
	var was_on_floor: bool = is_on_floor()
	_fall_speed = minf(_fall_speed, velocity.y)
	move_and_slide()
	if is_on_floor():
		if not was_on_floor and _fall_speed < -12.5 and not flying and not in_water:
			take_damage(floorf((-_fall_speed - 12.0) * 0.55))
		_fall_speed = 0.0
	if global_position.y < -18.0:
		if creative:
			global_position = world.call("spawn_position")
			velocity = Vector3.ZERO
		else:
			take_damage(20.0)
	camera.position.y = lerpf(camera.position.y, 1.38 if crouched else 1.62, delta * 12.0)
	_update_target(delta)
	_update_survival(delta, in_water, sprinting and input_direction.length() > 0.1)
	_update_portal(feet_id)
	_update_held_item()
	var walking: bool = input_direction.length() > 0.1 and is_on_floor() and not flying
	if walking:
		_bob += delta * speed * 2.1
		_footstep += delta * speed
		if _footstep > 2.1:
			_footstep = 0.0
			_play("step")
	_held_root.position = Vector3(0.43 + sin(_bob) * 0.014, -0.40 + (absf(cos(_bob)) * 0.025 if walking else 0.0) - sin(_swing * PI) * 0.13, -0.70 + sin(_swing * PI) * 0.14)
	_held_root.rotation.z = -sin(_swing * PI) * 0.55

func _update_target(delta: float) -> void:
	target = _raycast_voxels(6.0)
	target_name = BlockDB.item_name(int(target["id"])) if not target.is_empty() else ""
	_outline.visible = not target.is_empty()
	if not target.is_empty():
		_outline.position = Vector3(target["position"]) + Vector3.ONE * 0.5
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var item_id: int = int(inventory.call("selected_id"))
		var item: Dictionary = BlockDB.get_item(item_id)
		var kind: String = str(item.get("kind", "block"))
		if _attack_cooldown <= 0.0 and is_instance_valid(entities):
			if kind == "bow":
				_shoot_bow()
				return
			var reach: float = minf(4.5, float(target.get("distance", 4.5)))
			if bool(entities.call("attack", camera.global_position, -camera.global_transform.basis.z, float(item.get("damage", 2.0)), reach)):
				_attack_cooldown = 0.35
				_swing = 1.0
				mining_progress = 0.0
				_play("break")
				return
		if target.is_empty() or _attack_cooldown > 0.0:
			mining_progress = 0.0
			return
		var cell: Vector3i = target["position"]
		if cell != _mining_cell:
			_mining_cell = cell
			mining_progress = 0.0
		var block: Dictionary = BlockDB.get_block(int(target["id"]))
		var hardness: float = float(block.get("hardness", 1.0))
		if hardness < 0.0 and not creative:
			return
		var tool_speed: float = float(item.get("speed", 1.0))
		if kind not in ["pickaxe", "axe", "shovel"]:
			tool_speed = 1.0
		mining_progress += delta * (12.0 if creative else tool_speed / maxf(hardness * 1.35, 0.12))
		_swing = fmod(mining_progress * 3.0, 1.0)
		if mining_progress >= 1.0:
			if can_break_block.is_valid() and not bool(can_break_block.call(cell, int(target["id"]))):
				mining_progress = 0.0
				_attack_cooldown = 0.5
				notify.emit("Empty this chest before mining it.")
				return
			if not creative and not collect_item(int(block.get("drop", int(target["id"]))), 1):
				mining_progress = 0.0
				_attack_cooldown = 0.5
				return
			world.call("set_block", cell, 0)
			if not creative:
				_hunger_cost(0.015)
			mining_progress = 0.0
			_attack_cooldown = 0.12 if creative else 0.08
			_play("break")
	else:
		mining_progress = 0.0
		_mining_cell = Vector3i(2147483647, 0, 0)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and _place_cooldown <= 0.0:
		var selected: int = int(inventory.call("selected_id"))
		if BlockDB.is_block(selected):
			_use_selected()

func _use_selected() -> void:
	if not active or _place_cooldown > 0.0:
		return
	_place_cooldown = 0.18
	var item_id: int = int(inventory.call("selected_id"))
	var item: Dictionary = BlockDB.get_item(item_id)
	var kind: String = str(item.get("kind", "block"))
	if not target.is_empty() and not Input.is_action_pressed("crouch"):
		var target_id: int = int(target["id"])
		if target_id == 29 or target_id == 30:
			_request_portal(target_id)
			return
		if target_id in [25,26,27]:
			interact_requested.emit(target_id, target["position"])
			return
	if kind == "food":
		if hunger < 20.0 and bool(inventory.call("consume", item_id, 1)):
			hunger = minf(20.0, hunger + float(item.get("food", 5)))
			if item_id == 1203:
				health = minf(20.0, health + 8.0)
			stats_changed.emit()
			_swing = 1.0
			_place_cooldown = 0.5
			_play("place")
		return
	if kind == "bow":
		_shoot_bow()
		return
	if target.is_empty():
		return
	var place_id: int = item_id
	if item_id == 1145:
		place_id = 9
	elif item_id == 1146:
		place_id = 20
	elif item_id == 1143 and int(target["id"]) == 97:
		_explode(target["position"])
		return
	elif item_id == 1143 and int(target["id"]) == 18:
		place_id = 29
	elif item_id == 1021:
		place_id = 30
	if not BlockDB.is_block(place_id) or place_id == 0:
		return
	var destination: Vector3i = target["position"] + target["normal"]
	if destination.y < 1 or destination.y > 78:
		return
	if bool(BlockDB.get_block(place_id).get("solid", true)):
		var block_box := AABB(Vector3(destination), Vector3.ONE)
		var player_box := AABB(global_position + Vector3(-0.31, 0.02, -0.31), Vector3(0.62, 1.77, 0.62))
		if block_box.intersects(player_box):
			return
	if bool(inventory.call("consume", item_id, 1)):
		world.call("set_block", destination, place_id)
		_swing = 1.0
		_play("place")
		if place_id in [29,30]:
			notify.emit("Gateway placed. Walk into it or right-click to travel.")

func _shoot_bow() -> void:
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = 0.5
	_swing = 1.0
	if not creative and not bool(inventory.call("consume", 1142, 1)):
		notify.emit("You need arrows. Craft them in your inventory.")
		return
	var result: Dictionary = _raycast_voxels(80.0)
	var distance: float = float(result.get("distance", 80.0))
	var direction: Vector3 = -camera.global_transform.basis.z
	if is_instance_valid(entities):
		entities.call("attack", camera.global_position, direction, 14.0, distance)
	var arrow := MeshInstance3D.new()
	var arrow_mesh := BoxMesh.new()
	arrow_mesh.size = Vector3(0.025, 0.025, 0.65)
	arrow.mesh = arrow_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("e9dcbb")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow.material_override = material
	world.add_child(arrow)
	arrow.global_position = camera.global_position + direction * 0.8 + Vector3(0.1, -0.1, 0)
	arrow.look_at(arrow.global_position + direction, Vector3.UP)
	var tween := create_tween()
	tween.tween_property(arrow, "global_position", camera.global_position + direction * distance, minf(distance / 65.0, 0.8))
	tween.tween_callback(arrow.queue_free)
	_play("shoot")

func _explode(center: Vector3i) -> void:
	for x in range(-3,4):
		for y in range(-3,4):
			for z in range(-3,4):
				var delta := Vector3i(x,y,z)
				if Vector3(delta).length() < 3.2:
					var cell: Vector3i = center + delta
					var block_id: int = int(world.call("get_block", cell))
					if block_id != 10 and (not can_break_block.is_valid() or bool(can_break_block.call(cell, block_id))):
						world.call("set_block", cell, 0)
	_play("break")
	var distance: float = global_position.distance_to(Vector3(center))
	if distance < 6.0:
		take_damage((6.0 - distance) * 2.0, Vector3(center))
	notify.emit("Boom!")

func _update_survival(delta: float, in_water: bool, sprinting: bool) -> void:
	if creative:
		return
	_food_clock += delta
	_hazard_clock += delta
	_hunger_cost(delta * (0.025 if sprinting else 0.004))
	var head_id: int = int(world.call("get_block", Vector3i(camera.global_position.floor())))
	if head_id == 9:
		air = maxf(0.0, air - delta)
	else:
		air = minf(10.0, air + delta * 3.0)
	if _hazard_clock >= 1.0:
		_hazard_clock = 0.0
		var feet: int = int(world.call("get_block", Vector3i((position + Vector3(0, 0.2, 0)).floor())))
		var below: int = int(world.call("get_block", Vector3i((position - Vector3(0, 0.1, 0)).floor())))
		if feet == 20 or head_id == 20 or below == 145:
			take_damage(4.0)
		elif air <= 0.0 and in_water:
			take_damage(2.0)
		stats_changed.emit()
	if _food_clock >= 4.0:
		_food_clock = 0.0
		if hunger >= 17.0 and health < 20.0:
			health = minf(20.0, health + 1.0)
			hunger = maxf(0.0, hunger - 0.35)
		elif hunger <= 0.0 and health > 1.0:
			take_damage(1.0)
		stats_changed.emit()

func _hunger_cost(cost: float) -> void:
	if not creative:
		hunger = maxf(0.0, hunger - cost)

func _update_portal(feet_id: int) -> void:
	if feet_id in [29,30] and _portal_cooldown <= 0.0:
		_request_portal(feet_id)

func _request_portal(id: int) -> void:
	if _portal_cooldown > 0.0:
		return
	_portal_cooldown = 3.0
	var current: String = str(world.get("dimension"))
	var destination: String = "nether" if id == 29 else "end"
	if current == destination:
		destination = "overworld"
	portal_requested.emit(destination)

func take_damage(amount: float, source: Vector3 = Vector3.INF) -> void:
	if creative or health <= 0.0 or _hurt_cooldown > 0.0:
		return
	_hurt_cooldown = 0.65
	health = maxf(0.0, health - amount)
	if source != Vector3.INF:
		var push: Vector3 = (global_position - source).normalized()
		velocity += push * 5.0 + Vector3.UP * 3.0
	_play("hurt")
	stats_changed.emit()
	if health <= 0.0:
		active = false
		died.emit()

func collect_item(id: int, amount: int = 1) -> bool:
	if not bool(inventory.call("add_item", id, amount)):
		notify.emit("Inventory full. Make room to collect %s." % BlockDB.item_name(id))
		return false
	return true

func respawn() -> void:
	health = 20.0
	hunger = 20.0
	air = 10.0
	velocity = Vector3.ZERO
	_fall_speed = 0.0
	global_position = world.call("spawn_position")
	active = true
	stats_changed.emit()

func _raycast_voxels(max_distance: float) -> Dictionary:
	var origin: Vector3 = camera.global_position
	var direction: Vector3 = -camera.global_transform.basis.z.normalized()
	var cell := Vector3i(origin.floor())
	var step := Vector3i(int(sign(direction.x)), int(sign(direction.y)), int(sign(direction.z)))
	var delta := Vector3(1e20,1e20,1e20)
	var next := Vector3(1e20,1e20,1e20)
	for axis in range(3):
		if absf(direction[axis]) > 0.000001:
			delta[axis] = absf(1.0 / direction[axis])
			next[axis] = (float(cell[axis] + (1 if step[axis] > 0 else 0)) - origin[axis]) / direction[axis]
	var normal := Vector3i.ZERO
	var distance: float = 0.0
	for iteration in range(512):
		var id: int = int(world.call("get_block", cell))
		if id != 0 and id != 9 and id != 20:
			return {"position": cell, "normal": normal, "id": id, "distance": distance}
		var axis: int = 0
		if next.y < next.x:
			axis = 1
		if next.z < next[axis]:
			axis = 2
		distance = next[axis]
		if distance > max_distance:
			break
		cell[axis] += step[axis]
		next[axis] += delta[axis]
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
	return {}

func _inventory_updated() -> void:
	_update_held_item()
	inventory_changed.emit()

func _update_held_item() -> void:
	if _held_root == null or inventory == null:
		return
	var id: int = int(inventory.call("selected_id"))
	if id == _last_item:
		return
	_last_item = id
	if is_instance_valid(_held_model):
		_held_model.queue_free()
	_held_model = Node3D.new()
	_held_root.add_child(_held_model)
	var kind: String = str(BlockDB.get_item(id).get("kind", "block"))
	if BlockDB.is_block(id) and id != 0:
		_held_voxel(id)
		_held_model.rotation_degrees = Vector3(12, 28, 0)
	elif id == 0:
		_held_hand()
	else:
		_held_sprite(id, kind)

func _held_sprite(id: int, kind: String) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = HeldItemMesh.for_item(id)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_held_model.add_child(instance)
	if kind in ["pickaxe", "axe", "shovel", "sword", "hoe"]:
		# Sprite handles run from bottom-left to top-right in the inventory.
		# Turn the silhouette so the handle enters from the lower-right hand.
		_held_model.scale = Vector3.ONE * 0.66
		_held_model.position = Vector3(-0.015, 0.10, 0.0)
		_held_model.rotation_degrees = Vector3(0, 12, 90)
	elif kind == "bow":
		_held_model.scale = Vector3.ONE * 0.62
		_held_model.position.y = 0.08
		_held_model.rotation_degrees = Vector3(0, 8, 8)
	else:
		_held_model.scale = Vector3.ONE * 0.43
		_held_model.position.y = 0.015
		_held_model.rotation_degrees = Vector3(0, 10, -10)

func _held_hand() -> void:
	_held_model.rotation_degrees = Vector3(-14, 8, -12)
	_held_box(Vector3(0.19, 0.26, 0.20), Vector3(0, -0.21, 0), Color("246b75"))
	_held_box(Vector3(0.194, 0.045, 0.204), Vector3(0, -0.065, 0), Color("398994"))
	_held_box(Vector3(0.175, 0.22, 0.18), Vector3(0, 0.065, 0), Color("c58e69"))
	_held_box(Vector3(0.116, 0.024, 0.182), Vector3(-0.018, 0.145, 0.001), Color("dfa77c"))
	_held_box(Vector3(0.045, 0.083, 0.145), Vector3(-0.099, 0.036, 0.014), Color("b9815f"))
	_held_box(Vector3(0.052, 0.13, 0.203), Vector3(-0.06, -0.20, 0.001), Color("327f88"))

func _held_voxel(id: int) -> void:
	BlockAtlas.prepare()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for face in range(6):
		var rect: Rect2 = BlockAtlas.tile_rect(id, face)
		var face_uv: Array[Vector2] = [Vector2(rect.position.x, rect.end.y), rect.position, Vector2(rect.end.x, rect.position.y), rect.end]
		var shade: float = VoxelChunkMesh.SHADES[face]
		for corner in range(4):
			vertices.append((VoxelChunkMesh.CORNERS[face][corner] - Vector3.ONE * 0.5) * 0.32)
			normals.append(VoxelChunkMesh.NORMALS[face])
			uv.append(face_uv[corner])
			colors.append(Color(shade, shade, shade))
		for index in [0,2,1,0,3,2]:
			indices.append(face * 4 + index)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = BlockAtlas.materials[0]
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_held_model.add_child(instance)

func _held_box(size: Vector3, offset: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = offset
	_held_model.add_child(instance)
	return instance

func _outline_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var corners: Array[Vector3] = []
	for x in [-0.503,0.503]:
		for y in [-0.503,0.503]:
			for z in [-0.503,0.503]:
				corners.append(Vector3(x,y,z))
	for i in range(8):
		for j in range(i + 1,8):
			var same: int = int(is_equal_approx(corners[i].x,corners[j].x)) + int(is_equal_approx(corners[i].y,corners[j].y)) + int(is_equal_approx(corners[i].z,corners[j].z))
			if same == 2:
				vertices.append(corners[i])
				vertices.append(corners[j])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh

func _sound(frequency: float, duration: float, noise: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var frames: int = int(duration * 22050)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var random := RandomNumberGenerator.new()
	random.seed = int(frequency * 37.0)
	for index in range(frames):
		var t: float = float(index) / 22050.0
		var envelope: float = pow(1.0 - float(index) / frames, 2.0)
		var signal_value: float = (sin(TAU * frequency * t) * (1.0 - noise) + random.randf_range(-1.0,1.0) * noise) * envelope * 14000.0
		bytes.encode_s16(index * 2, int(signal_value))
	stream.data = bytes
	return stream

func _play(sound_name: String) -> void:
	if _audio != null:
		_audio.stop()
		_audio.stream = _sounds[sound_name]
		_audio.play()

func serialize() -> Dictionary:
	return {"position":[position.x,position.y,position.z], "yaw":rotation.y,"pitch":_pitch,"health":health,"hunger":hunger,"air":air,"flying":flying}

func restore(data: Dictionary) -> void:
	var saved_position: Array = data.get("position", [])
	if saved_position.size() == 3:
		position = Vector3(float(saved_position[0]),float(saved_position[1]),float(saved_position[2]))
	rotation.y = float(data.get("yaw", 0.0))
	_pitch = clampf(float(data.get("pitch", 0.0)), -1.55, 1.55)
	if camera != null:
		camera.rotation.x = _pitch
	health = clampf(float(data.get("health", 20.0)), 1.0, 20.0)
	hunger = clampf(float(data.get("hunger", 20.0)), 0.0, 20.0)
	air = clampf(float(data.get("air", 10.0)), 0.0, 10.0)
	flying = creative and bool(data.get("flying", false))
	velocity = Vector3.ZERO
	stats_changed.emit()

func _exit_tree() -> void:
	if is_instance_valid(_audio):
		_audio.stop()
		_audio.stream = null
	_sounds.clear()
