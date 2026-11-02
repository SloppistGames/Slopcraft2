extends SceneTree
class VillageProvider extends RefCounted:
	func village_spawn_points(_at: Vector3,_radius: float) -> Array:
		var result: Array = []
		var jobs: Array = ["farmer","smith","librarian","mason"]
		for i in jobs.size(): result.append({"id":"village:42:"+jobs[i],"position":Vector3(i*2,1,-3),"profession":jobs[i],"village_id":"village:42","name":["Alder","Hazel","Rowan","Wren"][i]})
		return result
class Fixture extends Node3D:
	var seed_value: int = 42
	var dimension: String = "overworld"
	var structure_provider = VillageProvider.new()
	var cells: Dictionary = {}
	var ground: int = 0
	func get_block(p: Vector3i) -> int: return int(cells.get(p,3 if p.y<=ground else 0))
	func surface_height(_x: int,_z: int) -> int: return ground
	func min_y() -> int: return -176
	func max_y() -> int: return 192
	func spawn_position() -> Vector3: return Vector3(0,1,0)
	func end_pillars() -> Array: return [Vector3(0,8,-10),Vector3(12,8,-10)]
class Flow extends RefCounted:
	func flow_force_at(_at: Vector3) -> Vector3: return Vector3(4,0,0)
var failures: int = 0
var checks: int = 0
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: run.call_deferred()
func find_actor(manager: SlopEntities,id: String) -> Dictionary:
	for actor in manager.actors:
		if str(actor.id)==id: return actor
	return {}
func meshes(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D: found.append(node)
	for child in node.get_children(): found.append_array(meshes(child))
	return found
func run() -> void:
	var world := Fixture.new(); root.add_child(world)
	var bag := PlayerInventory.new(); bag.setup(false)
	var player := VoxelPlayer.new(); world.add_child(player); player.setup(world,bag)
	player.set_physics_process(false); player.active = true; player.position = Vector3(0,1,0)
	var manager := SlopEntities.new(); world.add_child(manager); manager.setup(world,player,"overworld"); manager.set_physics_process(false)
	var ids: Dictionary = {}; var villagers: int = 0
	for actor in manager.actors:
		ids[str(actor.id)] = true
		if actor.species == "villager": villagers += 1
	check(villagers==4 and ids.size()==manager.actors.size(),"Four distinct persistent village professions spawn")
	var original_count: int = manager.actors.size()
	manager._discover_villagers(); manager._discover_villagers()
	check(manager.actors.size()==original_count,"Repeated village discovery does not duplicate residents")
	var farmer: Dictionary = find_actor(manager,"village:42:farmer")
	var offers: Array = manager._offers(farmer)
	check(offers[0].result==1009 and offers[0].cost.has(1015),"Farmer buys obtainable wheat for emeralds")
	check(manager._offers(find_actor(manager,"village:42:smith"))[2].result==1102,"Smith has profession-specific tool trade")
	check(manager._offers(find_actor(manager,"village:42:librarian"))[0].cost.has(1026),"Librarian buys paper")
	check(manager._offers(find_actor(manager,"village:42:mason"))[0].cost.has(4),"Mason buys cobblestone")
	var hit: Dictionary = manager.interact(player.position+Vector3.UP,Vector3.FORWARD,5)
	check(hit.get("id")==farmer.id and hit.offers.size()==3,"Reachable villager ray returns real offers")
	world.cells[Vector3i(0,2,-2)] = 3
	check(manager.interact(player.position+Vector3.UP,Vector3.FORWARD,5).is_empty(),"Villager interaction cannot pass through wall")
	world.cells.clear()
	bag.restore({"slots":[]})
	var before: Dictionary = bag.serialize()
	check(not manager.trade(farmer.id,0,bag) and bag.serialize()==before and farmer.trade_uses.is_empty(),"Missing payment changes neither inventory nor trade stock")
	for slot in bag.slots: slot.id=7; slot.count=64
	bag.slots[0] = {"id":1015,"count":64}
	before = bag.serialize()
	check(not manager.trade(farmer.id,0,bag) and bag.serialize()==before and farmer.trade_uses.is_empty(),"Full bag cannot consume payment or stock")
	bag.slots[1] = {"id":0,"count":0}
	var changes: Array = []
	var observe_change: Callable = func(): changes.append(bag.serialize())
	bag.changed.connect(observe_change)
	check(manager.trade(farmer.id,0,bag),"A valid exchange commits")
	check(bag.count_item(1015)==64-int(offers[0].cost[1015]) and bag.count_item(1009)==1,"Successful trade transfers exact amounts")
	check(changes.size()==1 and changes[0].slots==bag.serialize().slots,"Inventory observers see only the final atomic trade")
	bag.changed.disconnect(observe_change)
	check(not manager.trade(farmer.id,-1,bag) and not manager.trade(farmer.id,99,bag),"Invalid offer indices are rejected")
	farmer.trade_uses["0"] = offers[0].stock
	before = bag.serialize()
	check(not manager.trade(farmer.id,0,bag) and bag.serialize()==before,"Sold-out trade cannot alter the bag")
	farmer.trade_uses["0"] = 1
	player.position.x=20
	check(not manager.trade(farmer.id,0,bag),"Trade validates player proximity")
	player.position.x=0
	farmer.health=13; farmer.heading=1.3; farmer.timer=1.7; farmer.body.velocity=Vector3(1,2,3)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(manager.serialize()))
	manager.restore(saved)
	var restored: Dictionary = find_actor(manager,farmer.id)
	check(restored.health==13 and restored.body.velocity==Vector3(1,2,3) and is_equal_approx(float(restored.heading),1.3),"Actor health, motion and behavior persist through JSON")
	check(manager._offers(restored)==manager._offers(farmer) and restored.village_id=="village:42","Seeded trade list, stock and village association survive save")
	check(manager.actors.size()==original_count,"Restoring replaces initial actors instead of duplicating")
	manager.restore({"boss_health":240,"boss_defeated":false})
	check(manager.actors.size()==original_count,"Legacy boss-only saves preserve fauna")
	player.position = Vector3(400,1,0); manager._stream_actors()
	check(manager.actors.is_empty() and manager.dormant_actors.size()==original_count,"Distant actors unload into saved dormant records")
	var dormant_save: Dictionary = JSON.parse_string(JSON.stringify(manager.serialize())); manager.restore(dormant_save)
	check(manager.actors.is_empty() and manager.dormant_actors.size()==original_count,"Dormant actors survive reload without becoming active")
	player.position=Vector3(0,1,0); manager._stream_actors(); manager._discover_villagers()
	check(manager.actors.size()==original_count and manager.dormant_actors.is_empty(),"Returning reactivates residents without duplicates")
	restored=find_actor(manager,"village:42:farmer"); manager._defeat_actor(restored,false)
	manager._discover_villagers()
	check(find_actor(manager,"village:42:farmer").is_empty(),"Defeated villagers do not immediately respawn")
	manager.restore(JSON.parse_string(JSON.stringify(manager.serialize()))); manager._discover_villagers()
	check(find_actor(manager,"village:42:farmer").is_empty(),"Defeated actor IDs survive save and discovery")
	var malformed: Dictionary = manager.serialize(); malformed.actors.append({"id":"bad","species":"unknown","position":[0,0,0]}); malformed.actors.append(malformed.actors[0])
	manager.restore(malformed)
	check(manager.actors.size()==original_count-1,"Invalid and duplicate actor records are ignored")
	# Navigation checks meaningful terrain differences, including real negative coordinates.
	world.cells[Vector3i(0,1,-1)]=3
	check(manager._route(Vector3(.5,1,.5),0,false).jump,"One-block obstacles with headroom request a jump")
	world.cells[Vector3i(0,2,-1)]=3
	var route: Dictionary = manager._route(Vector3(.5,1,.5),0,false)
	check(route.heading!=0 or not route.safe,"Two-block wall steers to another path")
	world.cells[Vector3i(0,1,-1)]=20; world.cells.erase(Vector3i(0,2,-1))
	check(manager._route(Vector3(.5,1,.5),0,false).heading!=0,"Surface animals steer away from lava")
	world.cells.clear(); world.ground=-101; player.position=Vector3(0,-100,0)
	var deep: Dictionary = manager._spawn_actor("pig",Vector3(0,-100,1),{"id":"deep-pig"})
	manager._physics_process(.016)
	check(deep.body.position.y<-99 and manager.actors.has(deep),"Creatures remain valid below the former zero-height floor")
	world.ground=0; player.position=Vector3(40,1,40)
	world.cells[Vector3i(40,1,40)]=9; world.set_meta("fluid_system",Flow.new())
	var swimmer: Dictionary = manager._spawn_actor("pig",Vector3(40.5,1,40.5),{"id":"swimmer","heading":0,"timer":3})
	manager._physics_process(.1)
	check(swimmer.body.velocity.x>0.1 and swimmer.body.velocity.y>0,"Liquid provides buoyancy and directional flow force")
	var model: CreatureModel = swimmer.visual
	model.animate(.2,2,true,false,0); var walking: float = model.limbs[0].rotation.x
	model.animate(.2,2,false,true,.1)
	check(not is_equal_approx(model.limbs[0].rotation.x,walking) and model.coat.albedo_color.g<1,"Swimming changes limb pose and hurt tints the skin")
	for kind in ["pig","sheep","slime","villager"]:
		var creature := CreatureModel.new(); root.add_child(creature); creature.setup(kind)
		for part in meshes(creature):
			check(part.mesh is ArrayMesh and part.material_override.albedo_texture!=null,"Every creature part uses actual UV pixel art")
			var arrays: Array=part.mesh.surface_get_arrays(0)
			check(arrays[Mesh.ARRAY_TEX_UV].size()==24,"Every cuboid has all six mapped faces")
		creature.free()
	# Third-person grip maps an actual handle pixel to the palm and clears correctly.
	bag.setup(true); bag.select_item(1102); player._update_held_item()
	var held: Node3D = player._third_person_item.get_child(0)
	check((held.transform*Vector3(-.21875,-.21875,0)).length()<0.001,"Pickaxe handle pixel is anchored at the palm")
	player.player_model.animate(.1,0,0)
	check(player.player_model.pivots.right_arm.rotation.x>.2,"Held arm has a supported forward grip pose")
	bag.slots[bag.selected]={"id":0,"count":0}; player._update_held_item()
	check(player._third_person_item==null and not player.player_model.holding_item,"Empty hand clears the third-person item and grip")
	var boss := SlopEntities.new(); world.add_child(boss); boss.setup(world,player,"end"); boss.set_physics_process(false)
	check(boss.dragon_tail.size()==6 and boss.dragon_legs.size()==4,"Dragon has articulated tail and legs")
	for wing in [boss.left_wing,boss.right_wing]:
		check((wing.get_child(1) as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].size()==6,"Dragon membranes have UV-mapped pixel artwork")
	boss.elapsed=1; boss._update_boss(.1)
	check(boss.left_wing.rotation.z==-boss.right_wing.rotation.z and boss.dragon_tail[0].rotation.y!=0,"Dragon wings and tail animate together")
	boss.boss_health=180; boss.boss_attack_timer=1.2
	var boss_saved: Dictionary=JSON.parse_string(JSON.stringify(boss.serialize()))
	boss.dragon.position=Vector3.ZERO; boss.restore(boss_saved)
	check(boss.boss_health==180 and is_equal_approx(boss.boss_attack_timer,1.2) and boss.dragon.position!=Vector3.ZERO,"Boss pose, health and attack timer persist")
	world.free(); await process_frame
	await create_timer(.1).timeout
	print("ENTITIES SNAPSHOT: %d checks, %d failures" % [checks,failures])
	quit(failures)
