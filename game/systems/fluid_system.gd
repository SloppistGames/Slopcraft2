class_name FluidSystem
extends Node
## Event-driven finite-distance fluids. Natural sources sleep until disturbed.
const SIDES=[Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]
const NEIGHBORS=[Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK,Vector3i.UP,Vector3i.DOWN]
const MAX_PENDING=16384
const TICK_SECONDS=0.12
var world
var player
var queue: Array[Vector3i]=[]
var scheduled: Dictionary={}
var tick=0
var elapsed=0.0
var _changing=false
var updates_last_tick=0
func setup(new_world,new_player,_inventory=null,_entities=null) -> void:
	world=new_world; player=new_player
	world.set_meta("fluid_system",self)
	if world.has_signal("block_changed"): world.block_changed.connect(_block_changed)
func _process(delta: float) -> void:
	elapsed+=delta
	if elapsed>=TICK_SECONDS:
		elapsed=fmod(elapsed,TICK_SECONDS)
		step(96,1800)
func _block_changed(p: Vector3i,id: int) -> void:
	if _changing: return
	if id in [9,20]:
		world.set_block_state(p,{"fluid_source":true,"fluid_level":0,"fluid_falling":false})
	_enqueue(p)
	for offset in NEIGHBORS: _enqueue(p+offset)
func _enqueue(p: Vector3i,delay: int=1) -> void:
	if p.y<=_min_y() or p.y>=_max_y() or scheduled.has(p) or queue.size()>=MAX_PENDING: return
	scheduled[p]=tick+delay; queue.append(p)
func step(limit: int=96,budget_usec: int=1800) -> void:
	tick+=1; updates_last_tick=0
	var started=Time.get_ticks_usec(); var attempts=mini(queue.size(),limit*3)
	for i in attempts:
		if queue.is_empty() or updates_last_tick>=limit: break
		var p=queue.pop_front()
		if int(scheduled.get(p,tick))>tick or not _near_player(p): queue.append(p); continue
		scheduled.erase(p)
		_update_cell(p); updates_last_tick+=1
		if budget_usec>0 and Time.get_ticks_usec()-started>=budget_usec: break
func _near_player(p: Vector3i) -> bool:
	return not is_instance_valid(player) or Vector3(p).distance_squared_to(player.global_position)<80.0*80.0
func _min_y() -> int:
	return int(world.min_y()) if world.has_method("min_y") else 0
func _max_y() -> int:
	return int(world.max_y()) if world.has_method("max_y") else 192
func _state(p: Vector3i) -> Dictionary:
	return world.get_block_state(p)
func _source(p: Vector3i) -> bool:
	return bool(_state(p).get("fluid_source",not _state(p).has("fluid_level")))
func _level(p: Vector3i) -> int:
	return int(_state(p).get("fluid_level",0))
func _replaceable(id: int) -> bool:
	return id==0 or id in [28,155,164,165,166,168]
func _supported(p: Vector3i,id: int) -> bool:
	var below=int(world.get_block(p+Vector3i.DOWN))
	return (below==id and _source(p+Vector3i.DOWN)) or (below not in [0,9,20] and not _replaceable(below))
func _update_cell(p: Vector3i) -> void:
	var current=int(world.get_block(p))
	if current not in [0,9,20] and not _replaceable(current): return
	if current in [9,20]:
		for offset in NEIGHBORS:
			var neighbor=int(world.get_block(p+offset))
			if (current==20 and neighbor==9) or (current==9 and neighbor==20):
				var lava=p if current==20 else p+offset
				_write(lava,18 if _source(lava) else 4,{})
				return
		if _source(p):
			_spread_from(p,current)
			return
	var desired=0; var level=99; var falling=false
	var above=p+Vector3i.UP; var above_id=int(world.get_block(above))
	if above_id in [9,20]:
		desired=above_id; level=0; falling=true
	else:
		for offset in SIDES:
			var neighbor=p+offset; var id=int(world.get_block(neighbor))
			if id not in [9,20] or not _supported(neighbor,id): continue
			var candidate=_level(neighbor)+1
			var maximum=7 if id==9 else 3
			if candidate<=maximum and candidate<level:
				desired=id; level=candidate
	if desired==0:
		if current in [9,20]: _write(p,0,{})
		return
	var state={"fluid_source":false,"fluid_level":level,"fluid_falling":falling}
	if current!=desired or _state(p)!=state:
		_write(p,desired,state)
		_spread_from(p,desired)
func _spread_from(p: Vector3i,id: int) -> void:
	var delay=1 if id==9 else 4
	var below=p+Vector3i.DOWN
	var below_id=int(world.get_block(below))
	if _replaceable(below_id) or (below_id==id and not _source(below)):
		_enqueue(below,delay)
	if _supported(p,id):
		for offset in SIDES:
			var candidate=p+offset; var neighbor=int(world.get_block(candidate))
			if _replaceable(neighbor) or (neighbor in [9,20] and not _source(candidate)): _enqueue(candidate,delay)
func _write(p: Vector3i,id: int,state: Dictionary) -> void:
	_changing=true
	world.set_block(p,id)
	world.set_block_state(p,state)
	_changing=false
	for offset in NEIGHBORS: _enqueue(p+offset,1 if id!=20 else 4)
func fluid_height_at(position: Vector3) -> float:
	var p=Vector3i(position.floor()); var id=int(world.get_block(p))
	if id not in [9,20]: return 0.0
	var state=_state(p)
	if bool(state.get("fluid_falling",false)): return 1.0
	var level=int(state.get("fluid_level",0))
	if level==0: return .88 if id==9 else 1.0
	return maxf(.125,1.0-float(level)/(8.0 if id==9 else 4.0))
func flow_force_at(position: Vector3) -> Vector3:
	var p=Vector3i(position.floor()); var id=int(world.get_block(p))
	if id not in [9,20] or position.y-float(p.y)>fluid_height_at(position): return Vector3.ZERO
	var force=Vector3.ZERO; var height=fluid_height_at(position)
	for offset in SIDES:
		var other=int(world.get_block(p+offset))
		if other==id: force+=Vector3(offset)*(height-fluid_height_at(Vector3(p+offset)))
		elif _replaceable(other): force+=Vector3(offset)*height
	if bool(_state(p).get("fluid_falling",false)): force.y=-.35
	return force.limit_length(1.0)*(2.2 if id==9 else .7)
func serialize() -> Dictionary:
	var pending: Array=[]
	for p in queue: pending.append([p.x,p.y,p.z,maxi(1,int(scheduled.get(p,tick))-tick)])
	return {"tick":tick,"pending":pending}
func restore(data: Dictionary) -> void:
	queue.clear(); scheduled.clear(); tick=int(data.get("tick",0)); elapsed=0
	for entry in data.get("pending",[]):
		if not entry is Array or entry.size()!=4: continue
		_enqueue(Vector3i(int(entry[0]),int(entry[1]),int(entry[2])),clampi(int(entry[3]),1,20))
