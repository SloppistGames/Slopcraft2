class_name RedstoneSystem
extends Node3D
## Bounded 20 Hz event queue. Block states own all durable circuit state.
const SIDES=[Vector3i.FORWARD,Vector3i.RIGHT,Vector3i.BACK,Vector3i.LEFT]
const NEIGHBORS=[Vector3i.FORWARD,Vector3i.RIGHT,Vector3i.BACK,Vector3i.LEFT,Vector3i.UP,Vector3i.DOWN]
const COMPONENTS=[84,155,156,157,158,159,160,161,162,163,164,177,178,179,180]
const CONTAINERS=[27,162,163,180]
const MAX_QUEUE=16384
const SUPPORTED=[28,155,156,157,164,177,178,179]
var world
var player
var inventory
var entities
var storage_get: Callable
var storage_set: Callable
var components: Dictionary={}
var queue: Array[Vector3i]=[]
var queued: Dictionary={}
var timers: Dictionary={}
var tick=0
var elapsed=0.0
var pickups: Array[Dictionary]=[]
var _moving=false
var _focus=Vector2i(2147483647,0)
var _overflow=false
var _maintenance: Array=[]
var _maintenance_cursor=0
var _scan_all=false
var _observed_states: Dictionary={}
var _timer_scan: Array=[]
var _timer_cursor=0
# Kept configurable for deterministic overload tests; never exceeds MAX_QUEUE.
var queue_capacity=MAX_QUEUE
func setup(w,p,i,e) -> void:
	world=w; player=p; inventory=i; entities=e
	world.set_meta("redstone_system",self)
	world.block_changed.connect(_changed)
	if world.has_signal("block_state_changed"): world.block_state_changed.connect(_state_changed)
	if world.has_signal("chunk_ready"):
		world.chunk_ready.connect(_chunk_ready)
		for coord in world.chunks: _chunk_ready(coord)
	if world.has_method("get_edits"):
		var edits: Dictionary=world.get_edits()
		for key in edits:
			if int(edits[key]) in COMPONENTS or int(edits[key]) in [28,183]:
				var at=_cell(key); components[at]=true; _enqueue(at)
func _near(p: Vector3i) -> bool:
	return not is_instance_valid(player) or Vector3(p).distance_squared_to(player.global_position)<80.0*80.0
func _process(delta: float) -> void:
	elapsed+=delta
	if elapsed>=.05:
		elapsed=fmod(elapsed,.05); step()
	for drop in pickups.duplicate():
		drop.node.rotation.y+=delta
		if is_instance_valid(player) and player.active and drop.node.position.distance_to(player.position+Vector3.UP)<1.7 and inventory.add_item(int(drop.id),int(drop.count)):
			pickups.erase(drop); drop.node.queue_free()
func _enqueue(p: Vector3i) -> void:
	if not components.has(p) or queued.has(p): return
	if queue.size()>=clampi(queue_capacity,1,MAX_QUEUE):
		_overflow=true; return
	queued[p]=true; queue.append(p)
func _chunk_ready(coord: Vector2i) -> void:
	if not world.chunks.has(coord): return
	for p in world.chunks[coord].get_meta("circuit_cells",[]):
		components[p]=true; _enqueue(p)
func _wake(p: Vector3i) -> void:
	_enqueue(p)
	for d in NEIGHBORS:
		_enqueue(p+d)
		for y in [-1,1]: _enqueue(p+d+Vector3i(0,y,0))
func _changed(p: Vector3i,id: int) -> void:
	if id in COMPONENTS or id in [28,183]: components[p]=true
	else: components.erase(p); timers.erase(p); _observed_states.erase(p)
	_wake(p)
	_observe(p)
	if not _moving:
		for d in SIDES:
			var head=p+d
			if world.get_block(head)==183:
				var base=_from_array(world.get_block_state(head).get("piston_base",[]))
				if base==p and id not in [159,160]: world.set_block(head,0)
func _observe(p: Vector3i) -> void:
	for d in SIDES:
		var observer=p+d
		if world.get_block(observer)==161:
			var state: Dictionary=world.get_block_state(observer)
			if observer+_front(state)==p:
				state.pulse_pending=true; _state(observer,state); timers[observer]=true
func _state_changed(p: Vector3i,state: Dictionary) -> void:
	_wake(p)
	var visible=state.duplicate(true)
	for key in ["pulse_pending","pulse_until","pending_due","pending_power"]: visible.erase(key)
	if _observed_states.get(p,{})!=visible:
		_observed_states[p]=visible
		_observe(p)
func _state(p: Vector3i,state: Dictionary) -> void:
	if world.get_block_state(p)==state: return
	world.set_block_state(p,state)
	if not world.has_signal("block_state_changed"): _state_changed(p,state)
func _front(state: Dictionary) -> Vector3i: return SIDES[posmod(int(state.get("rotation",0)),4)]
func step(limit=192,budget_usec=1800) -> void:
	tick+=1
	var started=Time.get_ticks_usec()
	if _timer_scan.is_empty(): _timer_scan=timers.keys(); _timer_cursor=0
	for index in mini(128,_timer_scan.size()-_timer_cursor):
		var p: Vector3i=_timer_scan[_timer_cursor]; _timer_cursor+=1
		if timers.has(p) and _near(p): _enqueue(p)
	if _timer_cursor>=_timer_scan.size(): _timer_scan.clear(); _timer_cursor=0
	if tick%8==0:
		_begin_maintenance()
	if _overflow and _maintenance.is_empty(): _begin_maintenance()
	for index in mini(64,_maintenance.size()-_maintenance_cursor):
		# Retain the cursor when saturated: restarting at the first components
		# would starve the tail of a large circuit indefinitely.
		if queue.size()>=clampi(queue_capacity,1,MAX_QUEUE): break
		var p: Vector3i=_maintenance[_maintenance_cursor]; _maintenance_cursor+=1
		if _near(p) and (_scan_all or world.get_block(p) in [178,180]): _enqueue(p)
	if _maintenance_cursor>=_maintenance.size(): _maintenance.clear(); _maintenance_cursor=0
	var count=mini(limit,queue.size())
	for index in count:
		var p: Vector3i=queue.pop_front(); queued.erase(p)
		if _near(p): _update(p)
		if budget_usec>0 and Time.get_ticks_usec()-started>=budget_usec: break
func _begin_maintenance() -> void:
	if not _maintenance.is_empty(): return
	var focus=Vector2i(floori(player.position.x/16),floori(player.position.z/16)) if is_instance_valid(player) else Vector2i.ZERO
	_scan_all=_overflow or focus!=_focus
	_focus=focus; _overflow=false
	_maintenance=components.keys(); _maintenance_cursor=0
func output_at(p: Vector3i,to: Vector3i) -> int:
	var id: int=world.get_block(p)
	if id==84: return 15
	var state: Dictionary=world.get_block_state(p)
	if id in [157,179] and to-p!=_front(state): return 0
	if id==161 and to-p!=-_front(state): return 0
	if id==164 and to==_support(p,id,state): return 0
	if id in [155,156,157,161,164,177,178,179]: return clampi(int(state.get("power",15 if id==164 else 0)),0,15)
	# Solid blocks conduct a directly attached switch/source, without recursive loops.
	if id not in COMPONENTS and world.is_solid(id):
		for d in NEIGHBORS:
			var source: int=world.get_block(p+d)
			if source==84: return 15
			if source in [156,177,178]:
				var source_state: Dictionary=world.get_block_state(p+d)
				if _support(p+d,source,source_state)==p and int(source_state.get("power",0))>0: return 15
			if source in [157,179] and _front(world.get_block_state(p+d))==-d:
				var value=clampi(int(world.get_block_state(p+d).get("power",0)),0,15)
				if value>0: return value
	return 0
func _support(p: Vector3i,id: int,state: Dictionary) -> Vector3i:
	var wall=BlockShapes.wall_normal(state) if id in [28,164] else Vector3.ZERO
	return p-Vector3i(wall) if wall!=Vector3.ZERO else p+Vector3i.DOWN
func _supported(p: Vector3i,id: int,state: Dictionary) -> bool:
	var below=_support(p,id,state)
	var support_id: int=world.get_block(below)
	if not world.is_solid(support_id): return false
	var normal=Vector3(p-below)
	var anchor=Vector3(.5,.5 if normal.y>0 else .22,.5)+normal*.499
	return BlockShapes.contains(support_id,world.get_block_state(below),anchor)
func _input_power(p: Vector3i,exclude: Vector3i=Vector3i.ZERO) -> int:
	var result=0
	for d in NEIGHBORS:
		if d!=exclude: result=maxi(result,output_at(p+d,p))
	return result
func wire_connections(p: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i]=[]
	for d in SIDES:
		var adjacent=p+d
		if world.get_block(adjacent) in COMPONENTS: result.append(adjacent)
		elif world.is_solid(world.get_block(adjacent)):
			if not world.is_solid(world.get_block(p+Vector3i.UP)) and world.get_block(adjacent+Vector3i.UP)==155: result.append(adjacent+Vector3i.UP)
		elif world.get_block(adjacent+Vector3i.DOWN)==155: result.append(adjacent+Vector3i.DOWN)
	return result
func _update(p: Vector3i) -> void:
	var id: int=world.get_block(p)
	var state: Dictionary=world.get_block_state(p)
	if id in SUPPORTED and not _supported(p,id,state):
		var drop=int(BlockDB.get_block(id).get("drop",id))
		if drop>0 and not _spawn_pickup(drop,1,Vector3(p)+Vector3(.5,.25,.5)):
			timers[p]=true; return
		world.set_block(p,0); return
	if id==183:
		var base=_from_array(state.get("piston_base",[]))
		if not state.has("piston_base") or world.get_block(base) not in [159,160] or base+_front(world.get_block_state(base))!=p:
			world.set_block(p,0)
		return
	if id not in COMPONENTS: return
	var before=int(state.get("power",0)); var power=0
	var front=_front(state)
	match id:
		84: power=15
		155:
			var links: Array=[]
			for neighbor in wire_connections(p):
				var value=output_at(neighbor,p)
				if world.get_block(neighbor)==155: value-=1
				power=maxi(power,value); links.append(_array(neighbor-p))
			state.connections=links
			power=maxi(power,output_at(p+Vector3i.DOWN,p))
		156: power=15 if state.get("on",false) else 0
		177,161:
			if state.get("pulse_pending",false): state.pulse_until=tick+3; state.erase("pulse_pending")
			power=15 if int(state.get("pulse_until",0))>tick else 0
			if power==0: timers.erase(p)
		178:
			if is_instance_valid(player) and AABB(Vector3(p)-Vector3(.1,0,.1),Vector3(1.2,.8,1.2)).has_point(player.position+Vector3.UP*.1): power=15
			if entities!=null:
				for actor in entities.actors:
					if actor.body.position.distance_squared_to(Vector3(p)+Vector3(.5,0,.5))<.8: power=15
		164:
			var wall=BlockShapes.wall_normal(state)
			var support=p-Vector3i(wall) if wall!=Vector3.ZERO else p+Vector3i.DOWN
			power=15 if _input_power(support,p-support)==0 else 0
			state.lit=power>0
		157:
			var side=Vector3i(front.z,0,-front.x)
			var locked=false
			for d in [side,-side]:
				if world.get_block(p+d) in [157,179] and output_at(p+d,p)>0: locked=true
			state.locked=locked
			if locked:
				state.erase("pending_due"); state.erase("pending_power"); timers.erase(p)
				_state(p,state); return
			var desired=15 if output_at(p-front,p)>0 else 0
			if desired!=before:
				if int(state.get("pending_power",-1))!=desired:
					state.pending_power=desired; state.pending_due=tick+2*clampi(int(state.get("delay",1)),1,4)
				if tick>=int(state.get("pending_due",tick)):
					power=desired; state.erase("pending_power"); state.erase("pending_due"); timers.erase(p)
				else: power=before; timers[p]=true
			else:
				power=before; state.erase("pending_power"); state.erase("pending_due"); timers.erase(p)
		179:
			var rear=p-front
			var main=output_at(rear,p)
			if world.get_block(rear) in CONTAINERS and storage_get.is_valid():
				var fill=0.0; var slots: Array=storage_get.call(rear)
				for slot in slots:
					if int(slot.get("id",0))>0: fill+=float(slot.get("count",0))/maxi(1,int(BlockDB.get_item(int(slot.id)).get("stack_size",64)))
				main=1+floori(14.0*fill/maxi(1,slots.size())) if fill>0 else 0
			var side=Vector3i(front.z,0,-front.x)
			var side_power=maxi(output_at(p+side,p),output_at(p-side,p))
			power=maxi(0,main-side_power) if state.get("subtract",false) else (main if main>=side_power else 0)
		_:
			power=_input_power(p)
			if id in [159,160]: _piston(p,id,power>0,state)
			if id in [162,163] and power>0 and before==0: _dispense(p,id,state)
			if id==180 and power==0 and tick%8==0: _hopper(p)
	state.power=clampi(power,0,15)
	state.powered=power>0
	_state(p,state)
func interact_at(p: Vector3i) -> bool:
	var id: int=world.get_block(p); var state: Dictionary=world.get_block_state(p)
	match id:
		156: state.on=not bool(state.get("on",false))
		177: state.pulse_until=tick+20; timers[p]=true
		157:
			state.delay=posmod(int(state.get("delay",1)),4)+1
			if player!=null: player.notify.emit("Repeater delay: %d ticks" % int(state.delay))
		179:
			state.subtract=not bool(state.get("subtract",false))
			if player!=null: player.notify.emit("Comparator: "+("subtract" if state.subtract else "compare"))
		_: return false
	_state(p,state); return true
func _piston(p: Vector3i,id: int,powered: bool,state: Dictionary) -> void:
	var extended=bool(state.get("extended",false)); var front=_front(state)
	var head=p+front
	var owns_head=world.get_block(head)==183 and _from_array(world.get_block_state(head).get("piston_base",[]))==p
	if extended and not owns_head: extended=false; state.extended=false
	if powered==extended: return
	if powered:
		var push: Array[Vector3i]=[]; var cursor=p+front
		while world.get_block(cursor)!=0 and world.get_block(cursor) not in [9,20]:
			if push.size()>=12 or not _movable(cursor): return
			push.append(cursor); cursor+=front
		if not _in_bounds(cursor): return
		# Every new occupied cell matters: checking only the last destination
		# permits a piston head to appear inside a player standing in front.
		for destination in push+[cursor,head]:
			if _occupied(destination): timers[p]=true; return
		timers.erase(p)
		_moving=true
		push.reverse()
		for from in push: _move_block(from,from+front)
		world.set_block(p+front,183); world.set_block_state(p+front,{"piston_base":_array(p),"rotation":state.get("rotation",0)})
		state.extended=true; _moving=false
	else:
		_moving=true
		if owns_head: world.set_block(p+front,0)
		if id==160 and _movable(p+front*2) and not _occupied(p+front) and world.get_block(p+front)==0: _move_block(p+front*2,p+front)
		state.extended=false; _moving=false
func _in_bounds(p: Vector3i) -> bool:
	return (not world.has_method("min_y") or p.y>world.min_y()) and (not world.has_method("max_y") or p.y<world.max_y())
func _occupied(p: Vector3i) -> bool:
	if is_instance_valid(player) and AABB(Vector3(p),Vector3.ONE).intersects(AABB(player.position-Vector3(.3,0,.3),Vector3(.6,1.8,.6))): return true
	if entities!=null:
		for actor in entities.actors:
			if AABB(Vector3(p),Vector3.ONE).intersects(AABB(actor.body.position-Vector3(.35,0,.35),Vector3(.7,1.8,.7))): return true
	return false
func _movable(p: Vector3i) -> bool:
	var id: int=world.get_block(p)
	return _in_bounds(p) and id>0 and world.is_solid(id) and id not in COMPONENTS and id not in [10,18,25,26,27,29,30,153,154,181,182,183] and float(BlockDB.get_block(id).get("hardness",1))>=0
func _move_block(from: Vector3i,to: Vector3i) -> void:
	var id: int=world.get_block(from); var state: Dictionary=world.get_block_state(from)
	world.set_block(from,0); world.set_block(to,id); world.set_block_state(to,state)
func _transfer(source: Vector3i,destination: Vector3i) -> bool:
	if not storage_get.is_valid() or not storage_set.is_valid() or world.get_block(destination) not in CONTAINERS: return false
	var slots: Array=storage_get.call(source).duplicate(true)
	var other: Array=storage_get.call(destination).duplicate(true)
	for index in slots.size():
		var id=int(slots[index].get("id",0))
		if id==0 or int(slots[index].get("count",0))<=0: continue
		for j in other.size():
			if int(other[j].get("id",0)) in [0,id] and int(other[j].get("count",0))<int(BlockDB.get_item(id).get("stack_size",64)):
				other[j]={"id":id,"count":int(other[j].get("count",0))+1}
				slots[index].count-=1
				if slots[index].count==0: slots[index]={"id":0,"count":0}
				storage_set.call(source,slots); storage_set.call(destination,other); _wake(source); _wake(destination); return true
	return false
func _hopper(p: Vector3i) -> void:
	_transfer(p,p+Vector3i.DOWN)
	if world.get_block(p+Vector3i.UP) in CONTAINERS: _transfer(p+Vector3i.UP,p)
	for drop in pickups.duplicate():
		if drop.node.position.distance_to(Vector3(p)+Vector3(.5,1,.5))<1.1 and _store_one(p,int(drop.id)):
			drop.count-=1
			if drop.count<=0: pickups.erase(drop); drop.node.queue_free()
func _store_one(p: Vector3i,id: int) -> bool:
	if not storage_get.is_valid() or not storage_set.is_valid(): return false
	var slots: Array=storage_get.call(p).duplicate(true)
	for i in slots.size():
		if int(slots[i].get("id",0)) in [0,id] and int(slots[i].get("count",0))<int(BlockDB.get_item(id).get("stack_size",64)):
			slots[i]={"id":id,"count":int(slots[i].get("count",0))+1}; storage_set.call(p,slots); return true
	return false
func _dispense(p: Vector3i,id: int,state: Dictionary) -> void:
	if not storage_get.is_valid() or not storage_set.is_valid(): return
	var front=_front(state); var destination=p+front
	if id==163 and _transfer(p,destination): return
	var slots: Array=storage_get.call(p).duplicate(true)
	for i in slots.size():
		var item=int(slots[i].get("id",0))
		if item==0 or int(slots[i].get("count",0))<=0: continue
		var consumed=false
		if id==162 and item in [1145,1146] and world.get_block(destination)==0:
			world.set_block(destination,9 if item==1145 else 20); slots[i]={"id":1144,"count":1}; storage_set.call(p,slots); return
		elif id==162 and item==1142 and entities!=null:
			entities.attack(Vector3(p)+Vector3.ONE*.5+Vector3(front)*.7,Vector3(front),5.0,18.0); consumed=true
		elif id==162 and BlockDB.is_block(item) and world.get_block(destination)==0 and not _occupied(destination):
			world.set_block(destination,item); consumed=true
		if not consumed:
			if world.is_solid(world.get_block(destination)) or not _spawn_pickup(item,1,Vector3(destination)+Vector3(.5,.4,.5)): return
		slots[i].count-=1
		if slots[i].count<=0: slots[i]={"id":0,"count":0}
		storage_set.call(p,slots); return
func _spawn_pickup(id: int,count: int,at: Vector3) -> bool:
	for drop in pickups:
		if int(drop.id)==id and int(drop.count)+count<=int(BlockDB.get_item(id).get("stack_size",64)) and drop.node.position.distance_squared_to(at)<4.0:
			drop.count+=count; return true
	if pickups.size()>=128: return false
	var sprite=Sprite3D.new(); sprite.texture=BlockAtlas.icon_texture(id) if BlockDB.is_block(id) else ItemGlyphs.texture_for(id)
	sprite.pixel_size=.35/float(sprite.texture.get_width()); sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST; sprite.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD
	add_child(sprite); sprite.position=at; pickups.append({"id":id,"count":count,"node":sprite})
	return true
func serialize() -> Dictionary:
	var waiting: Array=[]; var drops: Array=[]
	for p in queue: waiting.append(_array(p))
	for drop in pickups: drops.append({"id":drop.id,"count":drop.count,"position":_array(drop.node.position)})
	return {"tick":tick,"queue":waiting,"pickups":drops}
func restore(data: Dictionary) -> void:
	tick=maxi(0,int(data.get("tick",0)))
	for p in data.get("queue",[]):
		if p is Array and p.size()==3: _enqueue(_from_array(p))
	for p in components:
		var state: Dictionary=world.get_block_state(p)
		if state.has("pending_due") or state.has("pulse_until"): timers[p]=true
	for drop in data.get("pickups",[]):
		if drop is Dictionary and BlockDB.valid_item(int(drop.get("id",0))) and drop.get("position",[]).size()==3:
			var v=drop.position; _spawn_pickup(int(drop.id),clampi(int(drop.get("count",1)),1,64),Vector3(float(v[0]),float(v[1]),float(v[2])))
static func _array(p) -> Array: return [p.x,p.y,p.z]
static func _from_array(a: Array) -> Vector3i: return Vector3i(int(a[0]),int(a[1]),int(a[2])) if a.size()==3 else Vector3i.ZERO
static func _cell(key: String) -> Vector3i:
	var a=key.split(","); return Vector3i(int(a[0]),int(a[1]),int(a[2]))
