extends SceneTree
## Run: Godot --headless --path . --script res://tests/test_gameplay.gd

class TestWorld extends Node3D:
	var dimension: String = "overworld"
	var seed_value: int = 42
	var blocks: Dictionary = {}
	func get_block(p: Vector3i) -> int:
		return int(blocks.get(p, 3 if p.y == 0 else 0))
	func set_block(p: Vector3i, id: int) -> void:
		blocks[p] = id
	func surface_height(_x: int, _z: int) -> int:
		return 0
	func spawn_position() -> Vector3:
		return Vector3(0.5, 2.0, 0.5)
	func end_pillars() -> Array[Vector3]:
		return [Vector3(0, 3, -8), Vector3(12, 3, -8)]

var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)
	else:
		print("PASS: " + label)

func mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _run() -> void:
	var world := TestWorld.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(200, 1, 200)
	collider.shape = floor_shape
	floor_body.position.y = 0.5
	floor_body.add_child(collider)
	world.add_child(floor_body)
	var inventory := PlayerInventory.new()
	inventory.setup(false)
	var player := VoxelPlayer.new()
	world.add_child(player)
	player.setup(world, inventory)
	player.position = Vector3(0.5, 4, 0.5)
	player.active = true
	for tick in range(90):
		await physics_frame
	check(absf(player.position.y - 1.0) < 0.08, "Capsule lands on a voxel floor without falling through")
	check(player.is_on_floor(), "Ground contact is recognized")
	var before_walk: float = player.position.z
	Input.action_press("move_forward")
	for tick in range(30):
		await physics_frame
	Input.action_release("move_forward")
	check(player.position.z < before_walk - 1.0, "WASD moves player at walking speed")
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	for tick in range(10):
		await physics_frame
	check(player.position.y > 1.5, "Jump clears a one-block step")
	player.set_physics_process(false)
	player.position = Vector3(0.5, 1.0, 0.5)
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	world.blocks[Vector3i(0,2,-3)] = 3
	var hit: Dictionary = player._raycast_voxels(6)
	check(hit.get("position") == Vector3i(0,2,-3), "DDA raycast selects the correct voxel")
	check(hit.get("normal") == Vector3i(0,0,1), "DDA supplies correct placement normal")
	check(player._raycast_voxels(2).is_empty(), "Blocks beyond reach cannot be targeted")
	var before_cobble: int = inventory.count_item(4)
	mouse(MOUSE_BUTTON_LEFT, true)
	player._update_target(2.0)
	mouse(MOUSE_BUTTON_LEFT, false)
	check(world.get_block(Vector3i(0,2,-3)) == 0, "Holding mine removes a stone voxel")
	check(inventory.count_item(4) == before_cobble + 1, "Mining stone awards its cobblestone drop")
	inventory.select_item(7)
	world.blocks[Vector3i(0,2,-3)] = 3
	player.target = player._raycast_voxels(6)
	var before_planks: int = inventory.count_item(7)
	player._place_cooldown = 0.0
	player._use_selected()
	check(world.get_block(Vector3i(0,2,-2)) == 7, "Right-click places block against selected face")
	check(inventory.count_item(7) == before_planks - 1, "Placement consumes exactly one block")
	player.target = {"id":3,"position":Vector3i(0,1,-1),"normal":Vector3i(0,0,1),"distance":0.5}
	player._place_cooldown = 0.0
	before_planks = inventory.count_item(7)
	player._use_selected()
	check(inventory.count_item(7) == before_planks-1, "Underfoot placement consumes exactly one block")
	check(world.get_block(Vector3i(0,1,0)) == 7 and player.position.y >= 2.0, "Underfoot placement lifts the player clear of the new block")
	world.blocks.erase(Vector3i(0,1,0))
	player.position = Vector3(0.5,1.0,0.5)
	world.blocks[Vector3i(0,3,0)] = 3
	player._place_cooldown = 0.0
	before_planks = inventory.count_item(7)
	player._use_selected()
	check(inventory.count_item(7)==before_planks and world.get_block(Vector3i(0,1,0))==0, "Blocked headroom rejects underfoot placement without consuming a block")
	world.blocks.erase(Vector3i(0,3,0))
	var inventory_backup: Dictionary = inventory.serialize()
	for slot_index in range(inventory.slots.size()):
		inventory.slots[slot_index] = {"id":1,"count":64}
	inventory.slots[0] = {"id":1100,"count":1}
	inventory.selected = 0
	world.blocks.erase(Vector3i(0,2,-2))
	player._attack_cooldown = 0.0
	mouse(MOUSE_BUTTON_LEFT, true)
	player._update_target(2.0)
	mouse(MOUSE_BUTTON_LEFT, false)
	check(world.get_block(Vector3i(0,2,-3)) == 3, "Full inventory leaves mined block intact instead of losing its drop")
	inventory.restore(inventory_backup)
	world.blocks[Vector3i(0,2,-3)] = 27
	player.can_break_block = func(_cell: Vector3i, id: int) -> bool: return id != 27
	player._attack_cooldown = 0.0
	mouse(MOUSE_BUTTON_LEFT, true)
	player._update_target(2.0)
	mouse(MOUSE_BUTTON_LEFT, false)
	check(world.get_block(Vector3i(0,2,-3)) == 27, "Nonempty chest hook rejects mining before destroying storage")
	player.can_break_block = Callable()
	var saved: Dictionary = player.serialize()
	player.position = Vector3(200, 200, 200)
	player.restore(saved)
	check(player.position.distance_to(Vector3(0.5,1,0.5)) < 0.01, "Player position round-trips through save data")
	player.health = 10.0
	player.hunger = 5.0
	inventory.select_item(1201)
	player.target = {}
	player._place_cooldown = 0.0
	player._use_selected()
	check(player.hunger == 10.0, "Eating food restores hunger")
	check(inventory.count_item(1201) == 7, "Eating consumes exactly one food item")
	var manager := SlopEntities.new()
	world.add_child(manager)
	manager.setup(world, player, "overworld")
	manager.set_physics_process(false)
	player.entities = manager
	var actor: Dictionary = manager.actors[0]
	var actor_body: CharacterBody3D = actor["body"]
	var actor_center: Vector3 = actor_body.position + Vector3(0,0.6,0)
	var actor_count: int = manager.actors.size()
	check(manager.attack(actor_center + Vector3(0,0,3), Vector3.FORWARD, 20.0, 4.0), "Melee ray hits a passive animal")
	check(manager.actors.size() == actor_count - 1, "Lethal melee removes the defeated animal")
	check(inventory.count_item(1206) == 2, "Defeated animals award food")
	manager.queue_free()
	var boss := SlopEntities.new()
	world.add_child(boss)
	world.dimension = "end"
	boss.setup(world, player, "end")
	boss.set_physics_process(false)
	player.entities = boss
	check(boss.boss_alive and boss.crystals.size() == 2, "Enderslop and healing crystals spawn in the End")
	var crystal: Node3D = boss.crystals[0]
	var crystal_origin: Vector3 = crystal.position + Vector3(0,0,5)
	check(boss.attack(crystal_origin, Vector3.FORWARD, 14.0, 8.0), "Ranged attack destroys an End crystal")
	check(boss.crystals.size() == 1, "Destroyed crystal is removed from healing sources")
	inventory.add_item(1141, 1)
	inventory.add_item(1142, 4)
	inventory.select_item(1141)
	player.position = boss.dragon.position + Vector3(0,-1.62,15)
	player.camera.rotation = Vector3.ZERO
	player._attack_cooldown = 0
	player._shoot_bow()
	check(boss.boss_health == 226.0, "Bow shot damages Enderslop at range")
	check(inventory.count_item(1142) == 3, "Bow shot consumes one arrow")
	var boss_state: Dictionary = boss.serialize()
	check(boss_state["alive_crystals"] == [1], "Boss save identifies the exact surviving crystal")
	boss.attack(boss.dragon.position + Vector3(0,0,15), Vector3.FORWARD, 240.0, 20)
	check(not boss.boss_alive and boss.boss_was_defeated, "Final boss can be defeated")
	var dead_boss_state: Dictionary = boss.serialize()
	var restored_boss := SlopEntities.new()
	world.add_child(restored_boss)
	restored_boss.setup(world, player, "end")
	restored_boss.set_physics_process(false)
	restored_boss.restore(dead_boss_state)
	check(not restored_boss.boss_alive and restored_boss.crystals.size() == 1, "Boss defeat and crystals persist after reopening")
	player.health = 2.0
	player._hurt_cooldown = 0
	var death_flag: Array[bool] = [false]
	player.died.connect(func() -> void: death_flag[0] = true)
	player.take_damage(4.0)
	check(death_flag[0] and not player.active and player.health == 0.0, "Fatal damage raises death state and stops controls")
	player.respawn()
	check(player.active and player.health == 20.0 and player.hunger == 20.0, "Respawn restores control and survival stats")
	player.active = false
	world.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("GAMEPLAY_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
