extends SceneTree
## Event-order and overload regressions; no world-save directory is touched.
class Fixture extends Node3D:
	signal block_changed(p: Vector3i,id: int)
	signal block_state_changed(p: Vector3i,state: Dictionary)
	var cells: Dictionary={}
	var states: Dictionary={}
	func get_block(p: Vector3i) -> int: return int(cells.get(p,3 if p.y<=0 else 0))
	func set_block(p: Vector3i,id: int) -> void:
		if get_block(p)==id: return
		cells[p]=id; states.erase(p); block_changed.emit(p,id)
	func get_block_state(p: Vector3i) -> Dictionary: return states.get(p,{}).duplicate(true)
	func set_block_state(p: Vector3i,state: Dictionary) -> void:
		if get_block_state(p)==state: return
		states[p]=state.duplicate(true); block_state_changed.emit(p,state.duplicate(true))
	func get_edits() -> Dictionary:
		var result={}
		for p in cells: result["%d,%d,%d" % [p.x,p.y,p.z]]=cells[p]
		return result
	func min_y(): return -16
	func max_y(): return 64
	func is_solid(id): return bool(BlockDB.get_block(id).get("solid",false))
var checks=0
var failures=0
var world: Fixture
var circuit: RedstoneSystem
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func _initialize(): call_deferred("run")
func reset() -> void:
	if is_instance_valid(world): world.free()
	world=Fixture.new(); root.add_child(world)
	circuit=RedstoneSystem.new(); world.add_child(circuit)
	circuit.setup(world,null,null,null); circuit.set_process(false)
func put(p: Vector3i,id: int,state: Dictionary={}) -> void:
	world.set_block(p,id)
	if not state.is_empty(): world.set_block_state(p,state)
func settle(steps=100) -> void:
	for index in steps: circuit.step(4096,0)
func power(p: Vector3i) -> int: return int(world.get_block_state(p).get("power",0))
func run() -> void:
	reset()
	# Removed support is a real block event, including wall torches and top slabs.
	var ids=[155,156,157,164,177,178,179,28]
	for i in ids.size(): put(Vector3i(i*3,1,0),ids[i])
	settle()
	for i in ids.size():
		check(world.get_block(Vector3i(i*3,1,0))==ids[i],"Supported component remains "+str(ids[i]))
		world.set_block(Vector3i(i*3,0,0),0)
	settle()
	for i in ids.size(): check(world.get_block(Vector3i(i*3,1,0))==0,"Removed support drops component "+str(ids[i]))
	var drop_count=0
	for drop in circuit.pickups: drop_count+=int(drop.count)
	check(drop_count==ids.size(),"Support removal preserves exactly one recoverable item each")
	put(Vector3i(0,1,5),3); put(Vector3i(1,1,5),28,{"wall":[1,0,0]}); settle()
	world.set_block(Vector3i(0,1,5),0); settle()
	check(world.get_block(Vector3i(1,1,5))==0,"Wall torch follows its wall support")
	put(Vector3i(0,1,8),BlockDB.shape_id(4,"slab"),{"top":true}); put(Vector3i(0,2,8),155); settle()
	check(world.get_block(Vector3i(0,2,8))==155,"Top slab supports floor components")
	world.set_block_state(Vector3i(0,1,8),{"top":false}); settle()
	check(world.get_block(Vector3i(0,2,8))==0,"Changing slab state removes unsupported floating wire")

	reset()
	var repeater=Vector3i(0,1,0)
	put(repeater,157,{"rotation":0,"delay":2}); put(repeater+Vector3i.BACK,84)
	circuit.step(4096,0)
	var due=int(world.get_block_state(repeater).get("pending_due",-1))
	check(due==circuit.tick+4 and power(repeater)==0,"Repeater schedules four simulation ticks before output")
	while circuit.tick<due-1: circuit.step(4096,0)
	check(power(repeater)==0,"Repeater never changes early")
	circuit.step(4096,0)
	check(power(repeater)==15,"Repeater changes on its scheduled tick")
	check(circuit.output_at(repeater,repeater+Vector3i.FORWARD)==15 and circuit.output_at(repeater,repeater+Vector3i.RIGHT)==0 and circuit.output_at(repeater,repeater+Vector3i.BACK)==0,"Repeater emits only toward its front")
	# A powered perpendicular repeater locks the present output, then unlocks.
	put(repeater+Vector3i.RIGHT,157,{"rotation":3}); put(repeater+Vector3i.RIGHT*2,84); settle()
	world.set_block(repeater+Vector3i.BACK,0); settle()
	check(power(repeater)==15 and world.get_block_state(repeater).get("locked",false),"Side repeater locks stored output")
	world.set_block(repeater+Vector3i.RIGHT*2,0); settle()
	check(power(repeater)==0 and not world.get_block_state(repeater).get("locked",true),"Unlocked repeater follows its rear input again")

	reset()
	var comparator=Vector3i(0,1,0)
	put(comparator,179); put(comparator+Vector3i.BACK,27)
	var slots=[{"id":7,"count":32},{"id":0,"count":0}]
	circuit.storage_get=func(_p): return slots
	settle()
	check(power(comparator)==4,"Comparator reads actual fractional container fullness")
	put(comparator+Vector3i.RIGHT,84); settle()
	check(power(comparator)==0,"Comparator compare mode rejects stronger side input")
	world.set_block(comparator+Vector3i.RIGHT,0)
	world.set_block_state(comparator,{"subtract":true}); settle()
	check(power(comparator)==4,"Comparator subtract mode keeps rear signal without side power")
	put(comparator+Vector3i.RIGHT,84); settle()
	check(power(comparator)==0,"Comparator subtract mode clamps at zero")

	reset()
	var torch=Vector3i(0,2,0)
	put(torch+Vector3i.DOWN,3); put(torch,164); settle()
	check(power(torch)==15 and circuit.output_at(torch,torch+Vector3i.DOWN)==0,"Torch does not power its own support or self-latch")
	put(Vector3i(1,1,0),84); settle()
	check(power(torch)==0 and not world.get_block_state(torch).get("lit",true),"Powered support extinguishes torch")
	world.set_block(Vector3i(1,1,0),0); settle()
	check(power(torch)==15 and circuit.queue.is_empty(),"Torch returns on and settles after input removal")

	reset()
	var observer=Vector3i(0,1,0); var watched=observer+Vector3i.FORWARD
	put(observer,161); put(watched,156); put(observer+Vector3i.BACK,158); settle()
	circuit.interact_at(watched)
	circuit.step(4096,0); circuit.step(4096,0)
	check(power(observer)==15 and world.get_block_state(observer+Vector3i.BACK).get("powered",false),"Observer sees real lever state events and pulses behind itself")
	check(circuit.output_at(observer,watched)==0,"Observer cannot power its watched face")
	settle(20)
	check(power(observer)==0 and circuit.queue.is_empty(),"Observer pulse expires without re-triggering from timer bookkeeping")
	world.set_block_state(watched,{"on":true,"power":15,"powered":true,"pending_due":999})
	settle(10)
	check(power(observer)==0,"Invisible timer-only metadata does not trigger observers")

	reset()
	var piston=Vector3i(0,1,0)
	put(piston,160); put(piston+Vector3i.FORWARD,7)
	var actor=Node3D.new(); world.add_child(actor); actor.position=Vector3(.5,1,-.5); circuit.player=actor
	put(piston+Vector3i.RIGHT,84); settle()
	check(world.get_block(piston+Vector3i.FORWARD)==7 and world.get_block(piston+Vector3i.FORWARD*2)==0,"Piston cannot create a head through an actor even when final destination is empty")
	actor.position=Vector3(5,1,5); settle()
	check(world.get_block(piston+Vector3i.FORWARD)==183 and world.get_block(piston+Vector3i.FORWARD*2)==7,"Blocked piston retries after actor leaves")
	world.set_block(piston,0); settle()
	check(world.get_block(piston+Vector3i.FORWARD)==0,"Breaking piston removes only its associated head")
	put(Vector3i(10,1,0),183,{"piston_base":[11,1,0]}); settle()
	check(world.get_block(Vector3i(10,1,0))==0,"Orphan head from interrupted or old save is cleaned up")

	reset()
	circuit.queue_capacity=3
	put(Vector3i(0,1,0),156)
	for x in range(1,20): put(Vector3i(x,1,0),155)
	circuit.interact_at(Vector3i(0,1,0)); settle(500)
	check(power(Vector3i(15,1,0))==1 and power(Vector3i(16,1,0))==0,"Overflow rescan eventually propagates the complete finite signal")
	check(circuit.queue.size()<=3,"Overload never exceeds the configured queue bound")
	circuit.interact_at(Vector3i(0,1,0)); settle(1000)
	var off=true
	for x in range(1,20): off=off and power(Vector3i(x,1,0))==0
	check(off and circuit.queue.is_empty(),"Dropped events recover and unpowered wire loop settles after overload")
	reset()
	put(Vector3i(0,1,0),177); put(Vector3i(1,1,0),158)
	circuit.interact_at(Vector3i(0,1,0)); circuit.step(4096,0)
	var saved=JSON.parse_string(JSON.stringify(circuit.serialize()))
	var saved_cells=world.cells.duplicate(true); var saved_states=world.states.duplicate(true)
	reset(); world.cells=saved_cells; world.states=saved_states
	circuit.free(); circuit=RedstoneSystem.new(); world.add_child(circuit); circuit.setup(world,null,null,null); circuit.set_process(false); circuit.restore(saved)
	settle(3)
	check(power(Vector3i(0,1,0))==15,"Button pulse survives serialized reload at its remaining tick")
	settle(25)
	check(power(Vector3i(0,1,0))==0 and not world.get_block_state(Vector3i(1,1,0)).get("powered",true),"Restored button expires and updates its lamp")
	reset()
	for z in 32:
		put(Vector3i(0,1,z*2),156)
		for x in range(1,17): put(Vector3i(x,1,z*2),155)
		circuit.interact_at(Vector3i(0,1,z*2))
	var samples: Array[int]=[]
	for index in 180:
		var started=Time.get_ticks_usec(); circuit.step(); samples.append(Time.get_ticks_usec()-started)
	samples.sort()
	print("REDSTONE_BUDGET components=",circuit.components.size()," p95_usec=",samples[171]," max_usec=",samples[-1])
	check(samples[171]<8000 and samples[-1]<50000,"Dense 544-component circuit stays within a bounded per-frame CPU slice")
	check(power(Vector3i(15,1,62))==1,"Budgeted scheduling eventually updates the distant end of dense circuits")

	reset()
	# Native state event + incremental mesher, rather than a mirrored test mock.
	var real=VoxelWorld.new(); root.add_child(real); real.setup(42,"overworld",{},1,false); real.set_process(false)
	real.pending.clear(); real.far_pending.clear()
	var lamp=Vector3i(8,60,8); real.set_block(lamp,158)
	var events: Array=[]
	real.block_state_changed.connect(func(p,s): events.append([p,s]))
	real.active_coord=Vector2i.ZERO; real.active_started=Time.get_ticks_msec()
	real._process(0)
	var original=real.active_mesh
	check(original!=null,"Incremental real-world mesh job starts")
	for i in 10:
		real.set_block_state(lamp,{"powered":i%2==0})
		check(real.active_mesh==original,"State clock preserves current mesh job "+str(i))
	real.set_block_state(lamp,{"powered":false})
	check(events.size()==10,"State setter emits changes once and ignores exact repeats")
	var attempts=0
	while not real.chunks.has(Vector2i.ZERO) and attempts<1000: real._process(0); attempts+=1
	check(real.chunks.has(Vector2i.ZERO) and real.dirty_chunks.has(Vector2i.ZERO),"Changed-in-flight mesh installs and schedules a fresh revision")
	while (real.dirty_chunks.has(Vector2i.ZERO) or real.active_coord!=VoxelWorld.NO_CHUNK) and attempts<2000: real._process(0); attempts+=1
	check(not real.dirty_chunks.has(Vector2i.ZERO),"Follow-up mesh converges to final state")
	var revision=int(real.state_revisions.get(Vector2i.ZERO,0))
	real.set_block_state(lamp,{"powered":false,"pending_due":123})
	check(int(real.state_revisions.get(Vector2i.ZERO,0))==revision,"Timer metadata does not rebuild geometry")
	real.free()
	world.free(); await process_frame
	print("REDSTONE: ",checks," checks, ",failures," failures")
	quit(failures)
