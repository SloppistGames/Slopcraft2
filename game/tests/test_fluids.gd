extends SceneTree
class TestWorld extends Node3D:
	signal block_changed(p: Vector3i,id: int)
	var cells: Dictionary={}
	var states: Dictionary={}
	func min_y(): return -1
	func max_y(): return 32
	func get_block(p: Vector3i) -> int: return int(cells.get(p,3 if p.y<=0 else 0))
	func set_block(p: Vector3i,id: int):
		if get_block(p)==id: return
		cells[p]=id; states.erase(p); block_changed.emit(p,id)
	func get_block_state(p: Vector3i) -> Dictionary: return states.get(p,{}).duplicate(true)
	func set_block_state(p: Vector3i,value: Dictionary):
		if value.is_empty(): states.erase(p)
		else: states[p]=value.duplicate(true)
var failures=0
var checks=0
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures+=1; push_error(label)
func _initialize(): call_deferred("run")
func settle(system,steps=150):
	for i in steps: system.step(256,0)
func run():
	var world=TestWorld.new(); root.add_child(world)
	var fluid=FluidSystem.new(); world.add_child(fluid); fluid.setup(world,null,null,null); fluid.set_process(false)
	world.set_block(Vector3i(15,4,0),9); settle(fluid)
	check(world.get_block(Vector3i(15,1,0))==9,"Unsupported source falls to floor")
	check(world.get_block(Vector3i(16,1,0))==9,"Water crosses a chunk seam")
	check(world.get_block(Vector3i(22,1,0))==9 and world.get_block(Vector3i(23,1,0))==0,"Finite seven-block spread")
	check(fluid.fluid_height_at(Vector3(16,1,0))>fluid.fluid_height_at(Vector3(21,1,0)),"Flow height attenuates")
	check(fluid.flow_force_at(Vector3(17.5,1.2,.5)).x>0,"Flow pushes downstream")
	world.set_block(Vector3i(17,1,0),3); settle(fluid)
	check(world.get_block(Vector3i(17,1,0))==3,"Flow respects solid obstacle")
	var state=fluid.serialize(); var restored=FluidSystem.new(); world.add_child(restored); restored.setup(world,null,null,null); restored.restore(state); restored.set_process(false)
	check(JSON.stringify(restored.serialize())==JSON.stringify(state),"Pending simulation round trip")
	restored.free()
	world.set_block(Vector3i(15,4,0),0); settle(fluid,500)
	var flows=0
	for id in world.cells.values():
		if id==9: flows+=1
	check(flows==0,"Removing source drains all dependent flows")
	world.free()
	world=TestWorld.new(); root.add_child(world)
	for x in range(-20,21):
		for z in range(-20,21): world.cells[Vector3i(x,1,z)]=9
	for edge in range(-21,22):
		for p in [Vector3i(edge,1,-21),Vector3i(edge,1,21),Vector3i(-21,1,edge),Vector3i(21,1,edge)]: world.cells[p]=3
	fluid=FluidSystem.new(); world.add_child(fluid); fluid.setup(world,null,null,null); fluid.set_process(false)
	settle(fluid)
	check(fluid.queue.is_empty() and world.states.is_empty(),"Natural lake remains dormant")
	world.cells[Vector3i(21,1,0)]=3
	world.set_block(Vector3i(21,1,0),0); settle(fluid)
	check(world.get_block(Vector3i(21,1,0))==9,"Breaching lake wall activates flow")
	check(world.states.size()<400,"Lake disturbance stays local")
	world.set_block(Vector3i(23,2,0),20); settle(fluid)
	check(world.get_block(Vector3i(23,2,0))==18 or world.get_block(Vector3i(23,1,0)) in [4,18],"Water cools lava")
	world.free()
	await process_frame
	print("FLUIDS: ",checks," checks, ",failures," failures")
	quit(failures)
