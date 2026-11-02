extends SceneTree
class TestWorld extends Node3D:
	var dimension: String = "overworld"
	var blocks: Dictionary = {}
	var states: Dictionary = {}
	var cave: String = "Normal Caves"
	func get_block(p: Vector3i) -> int: return int(blocks.get(p,0))
	func set_block(p: Vector3i,id: int) -> void: blocks[p] = id; states.erase(p)
	func get_block_state(p: Vector3i) -> Dictionary: return states.get(p,{})
	func set_block_state(p: Vector3i,state: Dictionary) -> void: states[p] = state.duplicate(true)
	func cave_biome_at(_pos: Vector3) -> String: return cave
	func min_y() -> int: return -176
	func max_y() -> int: return 192
	func spawn_position() -> Vector3: return Vector3(0.5,24,0.5)

var checks: int = 0
var failures: int = 0
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var world = TestWorld.new()
	root.add_child(world)
	var inventory = PlayerInventory.new()
	var player = VoxelPlayer.new()
	world.add_child(player)
	player.setup(world,inventory)
	player.set_physics_process(false)
	player.position = Vector3(0.5,1,0.5)
	player.active = true
	await physics_frame
	# All three camera modes preserve the eye-origin interaction ray.
	world.blocks[Vector3i(0,2,-3)] = 3
	var origin: Vector3 = player.interaction_origin()
	for mode in [1,2,0]:
		var event = InputEventKey.new()
		event.physical_keycode = KEY_F5; event.pressed = true
		player._unhandled_input(event)
		check(player.camera_mode == mode,"F5 cycles first/behind/front cameras")
		check(player.player_model.visible == (mode != 0),"Third person shows the skinned player")
		check(player._held_root.visible == (mode == 0),"Held mesh is first-person only")
		check(player.interaction_origin().is_equal_approx(origin),"Camera does not displace interaction origin")
		check(player._raycast_voxels(6).get("position") == Vector3i(0,2,-3),"All camera modes target the same reachable voxel")
	# Sweep the camera volume into a real physics wall.
	var wall = StaticBody3D.new()
	var collider = CollisionShape3D.new()
	var shape = BoxShape3D.new(); shape.size = Vector3(5,5,0.4)
	collider.shape = shape; wall.add_child(collider)
	wall.position = Vector3(0.5,2,2.0); world.add_child(wall)
	await physics_frame
	player.camera_mode = 1; player._update_camera(0)
	check(player.camera.global_position.z < 1.7,"Third-person camera sphere stays in front of wall")
	player.camera_mode = 0; player._update_camera(0)
	# Equipment consumes and returns real inventory items atomically.
	inventory.add_item(1400,1); inventory.add_item(1300,1)
	check(player.equip_head(1400),"Gas mask equips from inventory")
	check(inventory.count_item(1400) == 0 and player.equipment.head == 1400,"Equipped mask is removed from backpack")
	check(player._mask_overlay.visible and player.player_model._mask.visible,"Mask overlay and physical model activate")
	check(player.equip_head(1300) and inventory.count_item(1400) == 1,"Replacing head gear returns previous item")
	check(not player._mask_overlay.visible,"Mask overlay disappears when replaced")
	check(player.equip_head(1400),"Mask can be equipped again")
	for slot in inventory.slots: slot.id = 7; slot.count = 64
	var before: Dictionary = inventory.serialize()
	check(not player.unequip_head() and inventory.serialize() == before and player.equipment.head == 1400,"Full backpack cannot lose equipped mask")
	inventory.slots[0] = {"id":0,"count":0}
	check(player.unequip_head(),"Mask removal succeeds with one empty slot")
	# Poison activates immediately, ticks only while exposed and respects equipment.
	world.cave = "Sulfuric Caves"
	player.health = 20; player._hurt_cooldown = 0
	player._update_survival(0.1,false,false)
	check(player.poisoned,"Unprotected sulfur exposure marks poison status")
	player._update_survival(2.0,false,false)
	check(player.health == 19,"Sulfur poison deals periodic damage")
	check(player.equip_head(1400) and not player.poisoned,"Equipping mask clears poison immediately")
	player._hurt_cooldown = 0; player._update_survival(2.0,false,false)
	check(player.health >= 19 and not player.poisoned,"Mask prevents sulfur damage")
	player.equipment.head = 0; world.cave = "Normal Caves"
	player._update_survival(0.1,false,false)
	check(not player.poisoned,"Leaving sulfur cave clears status")
	# A real PNG is embedded into the player save and restored after source removal.
	var image: Image = PlayerModel.default_skin_image()
	image.set_pixel(44,24,Color.MAGENTA)
	var path: String = "user://skin-test-%d.png" % Time.get_ticks_usec()
	image.save_png(path)
	check(player.load_skin(path),"Loads a valid 64x64 PNG skin")
	player.player_name = "Miner Test"
	player.camera_mode = 2; player.equipment.head = 1400
	var saved: Dictionary = player.serialize()
	DirAccess.remove_absolute(path)
	var restored = VoxelPlayer.new(); world.add_child(restored)
	restored.setup(world,PlayerInventory.new()); restored.set_physics_process(false)
	restored.restore(saved)
	check(restored.player_name == "Miner Test" and restored.camera_mode == 2 and restored.equipment.head == 1400,"Name, camera and equipment survive save restore")
	check(restored.player_model.skin_image.get_pixel(44,24) == Color.MAGENTA,"Embedded skin survives missing original file")
	check(not restored.player_model.set_skin_image(Image.create(32,32,false,Image.FORMAT_RGBA8)),"Invalid skin dimensions rejected")
	restored.inventory.select_item(0)
	check(restored._held_model.get_child(0).material_override == restored.player_model.material,"First-person arm shares the actual skin material")
	for part in PlayerModel.PARTS:
		var arrays: Array = PlayerModel.part_mesh(part).surface_get_arrays(0)
		for face in 6:
			var base: int = face * 4
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var winding: Vector3 = (vertices[base+1]-vertices[base]).cross(vertices[base+2]-vertices[base])
			check(winding.dot(PlayerModel.NORMALS[face]) < 0,"Skin faces wind clockwise so exterior artwork is visible")
		for layer in [false,true]:
			for rect in PlayerModel.face_rects(part,layer):
				check(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= 64 and rect.end.y <= 64,"Skin UV face remains in the 64x64 net")
	# Negative height is valid; the new bedrock limit determines void death.
	player.position = Vector3(0.5,-100,0.5)
	player.velocity = Vector3.ZERO; player.health = 20
	player._physics_process(0.016)
	check(player.health == 20 and player.position.y < -99,"Deep-world physics does not use the old -18 void boundary")
	player.set_physics_process(false)
	inventory.setup(true); inventory.select_item(7)
	player.target = {"id":3,"position":Vector3i(0,-100,-3),"normal":Vector3i.UP,"point":Vector3(0.5,-99,-2.5)}
	player._place_cooldown = 0; player._use_selected()
	check(world.get_block(Vector3i(0,-99,-3)) == 7,"Blocks can be placed below zero")
	var slab: int = BlockDB.shape_id(7,"slab")
	inventory.select_item(slab)
	world.set_block(Vector3i(0,-100,-3),slab)
	world.set_block_state(Vector3i(0,-100,-3),{"top":false})
	player.target = {"id":slab,"position":Vector3i(0,-100,-3),"normal":Vector3i.UP,"point":Vector3(0.5,-99.5,-2.5)}
	player._place_cooldown = 0; player._use_selected()
	check(world.get_block(Vector3i(0,-100,-3)) == 7,"Matching slabs combine into the full material block")
	var state: Dictionary = player.placement_state(slab,{"position":Vector3i.ZERO,"normal":Vector3i.RIGHT,"point":Vector3(1,0.8,0.5)})
	check(state.top,"Side placement above half height makes a top slab")
	player.rotation.y = -PI * 0.5
	check(player.placement_state(BlockDB.shape_id(7,"stair"),{}).rotation == 1,"Stair placement saves cardinal orientation")
	# Upper slab gaps are not treated as full-cube ray targets.
	player.rotation = Vector3.ZERO; player.position = Vector3(0.5,0.13,0.5)
	world.blocks.clear(); world.states.clear()
	world.set_block(Vector3i(0,1,-2),slab); world.set_block(Vector3i(0,1,-3),3)
	check(player._raycast_voxels(6).get("position") == Vector3i(0,1,-3),"Selection ray passes through a lower slab's empty half")
	world.set_block_state(Vector3i(0,1,-2),{"top":true})
	check(player._raycast_voxels(6).get("position") == Vector3i(0,1,-2),"Selection ray hits the occupied half of a top slab")
	world.queue_free(); await process_frame
	# Let queued audio playback releases drain before the headless process exits.
	await create_timer(0.25).timeout
	print("PLAYER SNAPSHOT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
