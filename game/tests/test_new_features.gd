extends SceneTree
class Atmosphere extends Node3D:
	var time_of_day=.72
	func _update_lighting(): pass
class Fixture extends Node3D:
	signal block_changed(p: Vector3i,id: int)
	var dimension="overworld"
	var seed_value=42
	var cells: Dictionary={}
	var states: Dictionary={}
	var atmosphere=Atmosphere.new()
	func _ready(): add_child(atmosphere)
	func get_block(p: Vector3i) -> int: return int(cells.get(p,3 if p.y<=0 else 0))
	func set_block(p: Vector3i,id: int):
		if get_block(p)==id: return
		cells[p]=id; states.erase(p); block_changed.emit(p,id)
	func get_block_state(p: Vector3i) -> Dictionary: return states.get(p,{}).duplicate(true)
	func set_block_state(p: Vector3i,state: Dictionary): states[p]=state.duplicate(true)
	func get_edits():
		var result={}
		for p in cells: result["%d,%d,%d" % [p.x,p.y,p.z]]=cells[p]
		return result
	func min_y(): return -16
	func max_y(): return 64
	func surface_height(_x,_z): return 0
	func is_solid(id): return bool(BlockDB.get_block(id).get("solid",false))
	func ensure_ready_at(_p): pass
	func spawn_position(): return Vector3(.5,1,.5)
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures+=1; push_error(label)
func _initialize(): call_deferred("run")
func settle(system,steps=80):
	for i in steps: system.step(4096,0)
func run():
	var world=Fixture.new(); root.add_child(world)
	var bag=PlayerInventory.new(); bag.setup(false)
	var player=VoxelPlayer.new(); world.add_child(player); player.setup(world,bag); player.set_physics_process(false)
	player.position=Vector3(4.5,1,4.5); player.active=true
	var rest=RestTransportSystem.new(); world.add_child(rest); rest.setup(world,player,bag,null); rest.set_physics_process(false)
	bag.add_item(181,3)
	check(rest.place_bed(Vector3i(0,1,0),0),"Bed places two linked halves")
	check(world.get_block(Vector3i(0,1,-1))==182 and bag.count_item(181)==2,"Bed orientation and one-item cost")
	check(rest.interact_at(Vector3i(0,1,-1)) and is_equal_approx(world.atmosphere.time_of_day,.08),"Either bed half skips night to morning")
	check(player.bed_spawn==[0,1,0] and player.bed_dimension=="overworld","Bed sets durable spawn")
	var saved_player=player.serialize(); var saved_rest=rest.serialize()
	player.restore(JSON.parse_string(JSON.stringify(saved_player))); rest.restore(JSON.parse_string(JSON.stringify(saved_rest)))
	player.health=0; player.respawn()
	check(player.position.distance_to(Vector3(0,1,0))<3 and player.health==20,"Death respawns beside saved bed")
	world.set_block(Vector3i(0,1,-1),0)
	check(world.get_block(Vector3i(0,1,0))==0 and rest.respawn_position()==world.spawn_position(),"Breaking one half clears other and invalidates spawn")
	world.set_block(Vector3i(0,2,0),3)
	var count=bag.count_item(181)
	check(not rest.place_bed(Vector3i(0,1,0),0) and bag.count_item(181)==count,"Obstructed bed consumes nothing")
	for x in range(8,20):
		for z in range(-8,9):
			for y in [1,2]: world.set_block(Vector3i(x,y,z),9)
	bag.add_item(1402,1)
	var boat=rest.launch_boat(Vector3i(12,2,0))
	check(not boat.is_empty() and bag.count_item(1402)==0,"Boat launches on water")
	player.position=rest.boats[boat].node.position+Vector3(2,0,0)
	check(rest.mount(boat) and player.mounted_vehicle==rest.boats[boat].node,"Boat mounts player")
	var at: Vector3=rest.boats[boat].node.position
	for i in 20: rest.step_boat(boat,.05,1,0)
	check(rest.boats[boat].node.position.z<at.z-.5 and absf(rest.boats[boat].node.position.y-2.83)<.1,"Boat rows and floats at surface")
	var boats_saved=JSON.parse_string(JSON.stringify(rest.serialize())); rest.restore(boats_saved)
	check(rest.boats.size()==1 and rest.mounted_id==boat,"Boat and mounted rider persist")
	check(rest.dismount() and player.mounted_vehicle==null,"Boat dismount finds safe shore or water")
	bag.add_item(1102,1); bag.select_item(1102); player._update_held_item(); player.camera_mode=1; player._update_camera(0)
	check(is_instance_valid(player._third_person_item) and player._third_person_item.is_visible_in_tree() and not player._held_root.visible,"Third-person tool is attached to visible arm")
	check(player._third_person_item.get_parent()==player.player_model.pivots.right_arm,"Held mesh moves with arm joint")
	var entities=SlopEntities.new(); world.add_child(entities); entities.setup(world,player,"overworld"); entities.set_physics_process(false)
	var trader=entities._spawn_actor("villager",player.position+Vector3(0,0,-2),{"id":"test-trader","profession":"farmer","name":"Bram"})
	bag.add_item(1015,64)
	var offers=entities._offers(trader); var wheat=bag.count_item(1015); var emerald=bag.count_item(1009)
	check(entities.trade("test-trader",0,bag) and bag.count_item(1009)==emerald+1 and bag.count_item(1015)==wheat-int(offers[0].cost[1015]),"Villager trade exchanges real items")
	var entity_save=JSON.parse_string(JSON.stringify(entities.serialize())); entities.restore(entity_save)
	var traded=false
	for actor in entities.actors:
		if str(actor.id)=="test-trader": traded=int(actor.trade_uses.get("0",0))==1
	check(traded,"Villager stock usage survives save/load")
	world.free(); await process_frame
	world=Fixture.new(); root.add_child(world)
	var circuit=RedstoneSystem.new(); world.add_child(circuit); circuit.setup(world,null,null,null); circuit.set_process(false)
	world.set_block(Vector3i(0,1,0),156)
	for x in range(1,19): world.set_block(Vector3i(x,1,0),155)
	world.set_block(Vector3i(16,1,1),158)
	circuit.interact_at(Vector3i(0,1,0)); settle(circuit)
	check(int(world.get_block_state(Vector3i(1,1,0)).get("power",0))==15 and int(world.get_block_state(Vector3i(15,1,0)).get("power",0))==1,"Dust carries attenuating power across chunk boundary")
	check(int(world.get_block_state(Vector3i(16,1,0)).get("power",0))==0,"Dust has finite fifteen-block signal range")
	world.set_block(Vector3i(15,1,1),158); settle(circuit)
	check(world.get_block_state(Vector3i(15,1,1)).get("powered",false),"Lamp receives wire power")
	circuit.interact_at(Vector3i(0,1,0)); settle(circuit)
	check(not world.get_block_state(Vector3i(15,1,1)).get("powered",true) and circuit.queue.is_empty(),"Turning source off drains network and queue settles")
	world.set_block(Vector3i(0,1,5),84); world.set_block(Vector3i(0,1,4),157); world.set_block_state(Vector3i(0,1,4),{"delay":4,"rotation":0}); world.set_block(Vector3i(0,1,3),158)
	circuit.step(4096,0)
	check(int(world.get_block_state(Vector3i(0,1,4)).get("power",0))==0,"Repeater delays signal")
	settle(circuit,15)
	check(world.get_block_state(Vector3i(0,1,3)).get("powered",false),"Repeater boosts delayed directional output")
	world.set_block(Vector3i(5,1,5),160); world.set_block(Vector3i(5,1,4),7); world.set_block(Vector3i(6,1,5),84); settle(circuit)
	check(world.get_block(Vector3i(5,1,4))==183 and world.get_block(Vector3i(5,1,3))==7,"Powered piston pushes block and extends head")
	world.set_block(Vector3i(6,1,5),0); settle(circuit)
	check(world.get_block(Vector3i(5,1,4))==7 and world.get_block(Vector3i(5,1,3))==0,"Sticky piston retracts pushed block")
	world.set_block(Vector3i(10,1,5),161); world.set_block(Vector3i(10,1,6),158); settle(circuit)
	world.set_block(Vector3i(10,1,4),7); circuit.step(4096,0); circuit.step(4096,0)
	check(world.get_block_state(Vector3i(10,1,6)).get("powered",false),"Observer pulses behind changed watched block")
	settle(circuit,10)
	check(not world.get_block_state(Vector3i(10,1,6)).get("powered",true),"Observer pulse expires")
	var storage={}
	circuit.storage_get=func(p):
		if not storage.has(p): storage[p]=[{"id":0,"count":0},{"id":0,"count":0}]
		return storage[p]
	circuit.storage_set=func(p,slots): storage[p]=slots.duplicate(true)
	world.set_block(Vector3i(0,3,10),27); world.set_block(Vector3i(0,2,10),180); world.set_block(Vector3i(0,1,10),27)
	storage[Vector3i(0,3,10)]=[{"id":7,"count":5},{"id":0,"count":0}]
	settle(circuit,56)
	check(int(storage[Vector3i(0,1,10)][0].get("count",0))==5 and storage[Vector3i(0,3,10)][0].id==0,"Hopper transports items between persisted containers")
	world.set_block(Vector3i(4,1,10),163); world.set_block(Vector3i(4,1,9),27); storage[Vector3i(4,1,10)]=[{"id":1006,"count":2},{"id":0,"count":0}]
	world.set_block(Vector3i(5,1,10),84); settle(circuit)
	check(storage[Vector3i(4,1,9)][0].count==1 and storage[Vector3i(4,1,10)][0].count==1,"Dropper transfers exactly once on rising edge")
	var serialized=JSON.parse_string(JSON.stringify(circuit.serialize()))
	check(serialized.has("tick") and serialized.queue.size()<=16384,"Circuit simulation persists bounded pending events")
	world.free(); await process_frame
	var sound=load("res://ui/soundscape.gd").new(); root.add_child(sound)
	check(sound.TRACK.get_length()>109 and sound.TRACK.get_length()<111,"Slopwoofer Lullaby imports at complete duration")
	sound.set_music_frequency(100); sound._process(6); check(sound.music.playing,"Music frequency starts real supplied track")
	sound.set_music_volume(0); check(sound.music.volume_db <= -70,"Music volume mutes track independently of effects")
	sound.set_music_frequency(0); check(not sound.music.playing,"Music frequency off stops playback")
	sound.free(); await create_timer(.12).timeout
	print("NEW FEATURES: ",checks," checks, ",failures," failures")
	quit(failures)
