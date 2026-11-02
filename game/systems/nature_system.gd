class_name NatureSystem
extends Node3D
## Event-driven leaf support checks. No forest-wide scan or permanent seasonal loss.
const LEAVES: Array[int] = [6,32,34,39,42]
const LOGS: Array[int] = [5,31,33,37,40,43,45]
const DIRS: Array[Vector3i] = [Vector3i.RIGHT,Vector3i.LEFT,Vector3i.UP,Vector3i.DOWN,Vector3i.FORWARD,Vector3i.BACK]
const MAX_QUEUE: int = 2048
const QUERY_BUDGET: int = 384
const MAX_DROPS: int = 48
var world: Node
var player: Node3D
var inventory
var _time: float = 0.0
var _tick: float = 0.0
var _queue: Array[Vector3i] = []
var _queued: Dictionary = {}
var _job: Dictionary = {}
var _decay: Dictionary = {}
var _drops: Array[Dictionary] = []
var _drop_meshes: Array[MeshInstance3D] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _drift: MultiMeshInstance3D
var _biome: String = ""
var _biome_tick: float = 0.0
var queries_last_tick: int = 0
var decayed_count: int = 0
var _mutating: bool = false

func setup(new_world: Node, new_player: Node, new_inventory, _entities: Node = null) -> void:
	world = new_world
	player = new_player as Node3D
	inventory = new_inventory
	_rng.seed = int(world.get("world_seed"))+7162 if world.get("world_seed") != null else 7162
	WeatherSystem.ensure_wind_globals()
	_install_foliage_materials()
	_build_drift()
	if world.has_signal("block_changed"): world.connect("block_changed",_block_changed)

func _block_changed(pos: Vector3i, id: int) -> void:
	# Player-placed leaf blocks are decorative and remain intact.
	if id in LEAVES and not _mutating and world.has_method("set_block_state"):
		var state: Dictionary = world.call("get_block_state",pos)
		state["leaf_persistent"] = true
		world.call("set_block_state",pos,state)
	if id == 0 or id in LOGS or id in LEAVES:
		for direction in DIRS: _enqueue(pos+direction)
		# Reconnecting a branch cancels pending decay until support is checked again.
		if id in LOGS:
			for leaf in _decay.keys():
				if Vector3(leaf-pos).length_squared() <= 49.0:
					_decay.erase(leaf)
					_enqueue(leaf)

func _enqueue(pos: Vector3i) -> void:
	if _queued.has(pos) or _queue.size() >= MAX_QUEUE: return
	if int(world.call("get_block",pos)) not in LEAVES: return
	_queued[pos] = true
	_queue.append(pos)

func _persistent(pos: Vector3i) -> bool:
	return world.has_method("get_block_state") and bool(world.call("get_block_state",pos).get("leaf_persistent",false))

func _start_job(pos: Vector3i, confirm: bool = false) -> void:
	if int(world.call("get_block",pos)) not in LEAVES or _persistent(pos):
		_decay.erase(pos)
		return
	_job = {"origin":pos,"frontier":[pos],"depths":[0],"cursor":0,"visited":{pos:true},"supported":false,"confirm":confirm}

func _advance_job() -> void:
	while not _job.is_empty() and queries_last_tick + 6 <= QUERY_BUDGET:
		var cursor: int = int(_job.cursor)
		var frontier: Array = _job.frontier
		if cursor >= frontier.size():
			_finish_job(false)
			return
		var pos: Vector3i = frontier[cursor]
		var depth: int = int(_job.depths[cursor])
		_job.cursor = cursor+1
		for direction in DIRS:
			var neighbor: Vector3i = pos+direction
			queries_last_tick += 1
			var id: int = int(world.call("get_block",neighbor))
			if id in LOGS:
				_finish_job(true)
				return
			if id in LEAVES and depth < 5 and not _job.visited.has(neighbor):
				_job.visited[neighbor] = true
				_job.frontier.append(neighbor)
				_job.depths.append(depth+1)

func _finish_job(supported: bool) -> void:
	var pos: Vector3i = _job.origin
	var confirm: bool = bool(_job.confirm)
	_job.clear()
	if supported:
		_decay.erase(pos)
		return
	if confirm:
		_decay.erase(pos)
		var id: int = int(world.call("get_block",pos))
		if id in LEAVES and not _persistent(pos):
			_mutating = true
			world.call("set_block",pos,0)
			_mutating = false
			decayed_count += 1
			var chance: float = _rng.randf()
			if chance < 0.12: _spawn_drop(Vector3(pos)+Vector3(0.5,0.25,0.5),1200 if id == 6 and chance < 0.025 else 1000)
	elif not _decay.has(pos):
		_decay[pos] = _time+_rng.randf_range(2.0,7.0)

func _process(delta: float) -> void:
	if not is_instance_valid(world) or not is_instance_valid(player): return
	_time += delta
	_tick += delta
	if _tick >= 0.1:
		_tick = 0.0
		queries_last_tick = 0
		# One check at a time; large connected crowns continue across ticks.
		if _job.is_empty():
			for pos in _decay.keys():
				if float(_decay[pos]) <= _time:
					_start_job(pos,true)
					break
		if _job.is_empty() and not _queue.is_empty():
			var pos: Vector3i = _queue.pop_front()
			_queued.erase(pos)
			_start_job(pos)
		_advance_job()
	_update_drops(delta)
	_update_drift(delta)

func _spawn_drop(pos: Vector3, id: int) -> void:
	if _drops.size() >= MAX_DROPS: return
	_drops.append({"position":pos,"id":id,"age":0.0})
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = HeldItemMesh.for_item(id)
	node.scale = Vector3.ONE*0.22
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = pos
	_drop_meshes.append(node)

func _update_drops(delta: float) -> void:
	for i in range(_drops.size()-1,-1,-1):
		var drop: Dictionary = _drops[i]
		drop.age = float(drop.age)+delta
		var pos: Vector3 = drop.position
		var below: Vector3i = Vector3i((pos-Vector3(0,0.2,0)).floor())
		if int(world.call("get_block",below)) == 0: pos.y -= delta*2.3
		drop.position = pos
		_drop_meshes[i].global_position = pos+Vector3(0,sin(_time*2.0+float(i))*0.035,0)
		_drop_meshes[i].rotation.y += delta*1.3
		var picked: bool = false
		if player.global_position.distance_to(pos) < 2.2 and inventory != null and inventory.has_method("add_item"):
			picked = bool(inventory.call("add_item",int(drop.id),1))
		if picked or float(drop.age) > 180.0:
			_drop_meshes[i].queue_free()
			_drop_meshes.remove_at(i)
			_drops.remove_at(i)

func _build_drift() -> void:
	_drift = MultiMeshInstance3D.new()
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.09,0.055)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color("9ca65f")
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	mm.mesh = quad
	mm.instance_count = 24
	mm.visible_instance_count = 0
	_drift.multimesh = mm
	_drift.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_drift)

func _update_drift(delta: float) -> void:
	_biome_tick += delta
	if _biome_tick > 3.0:
		_biome_tick = 0.0
		_biome = str(world.call("biome_at",player.global_position)).to_lower() if world.has_method("biome_at") else ""
	var forest: bool = "forest" in _biome or "taiga" in _biome
	var outdoors: bool = not world.has_method("surface_height") or player.global_position.y > float(world.call("surface_height",floori(player.global_position.x),floori(player.global_position.z)))-2.0
	_drift.multimesh.visible_instance_count = 24 if forest and outdoors else 0
	if not forest or not outdoors: return
	_drift.global_position = player.global_position
	for i in range(24):
		var pos: Vector3 = Vector3(fposmod(float(i)*7.31+_time*0.35,20.0)-10.0,fposmod(float(i)*2.17-_time*0.22,10.0),fposmod(float(i)*11.83+_time*0.22,20.0)-10.0)
		var basis: Basis = Basis(Vector3(1,0.4,0.2).normalized(),_time*0.8+float(i))
		_drift.multimesh.set_instance_transform(i,Transform3D(basis,pos))

func _install_foliage_materials() -> void:
	BlockAtlas.prepare()
	var replacements: Dictionary = {}
	for group in [0,3]:
		if group >= BlockAtlas.materials.size(): continue
		var original: Material = BlockAtlas.materials[group]
		if original.has_meta("nature_wind"): continue
		var shader: Shader = Shader.new()
		shader.code = """shader_type spatial;
render_mode cull_BACK;
global uniform float sc_wind_strength;
global uniform vec2 sc_wind_direction;
uniform sampler2D atlas : source_color, filter_nearest;
void vertex(){
 int tile = int(floor(UV.x*32.0))+int(floor(UV.y*38.0))*32;
 int id = tile/6;
 bool leaf = id==6 || id==32 || id==34 || id==39 || id==42;
 bool plant = id==165 || id==166 || id==168;
 if(leaf || plant){
  vec3 p = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
  float wave = sin(p.x*0.48+p.z*0.37+TIME*(1.15+sc_wind_strength*0.3)) + 0.35*sin(p.z*0.91-TIME*1.7);
  float anchor = plant ? 1.0-fract(UV.y*38.0) : 1.0;
  float amplitude = (plant ? 0.075 : 0.018) * min(2.6,0.5+sc_wind_strength) * anchor;
  VERTEX.xz += sc_wind_direction*wave*amplitude;
 }
}
void fragment(){
 vec4 texel = texture(atlas,UV);
 ALBEDO = texel.rgb*COLOR.rgb;
 ALPHA = texel.a;
 ALPHA_SCISSOR_THRESHOLD = 0.35;
 ROUGHNESS = 0.92;
 SPECULAR = 0.15;
}""".replace("cull_BACK","cull_disabled" if group == 3 else "cull_back")
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("atlas",BlockAtlas.texture)
		material.set_meta("nature_wind",true)
		BlockAtlas.materials[group] = material
		replacements[original] = material
	if not replacements.is_empty(): _replace_surface_materials(world,replacements)

func _replace_surface_materials(node: Node, replacements: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh is ArrayMesh:
		for surface in range(node.mesh.get_surface_count()):
			var old: Material = node.mesh.surface_get_material(surface)
			if replacements.has(old): node.mesh.surface_set_material(surface,replacements[old])
	for child in node.get_children(): _replace_surface_materials(child,replacements)

func serialize() -> Dictionary:
	var pending: Array = []
	for pos in _queue: pending.append([pos.x,pos.y,pos.z])
	if not _job.is_empty():
		var pos: Vector3i = _job.origin
		pending.append([pos.x,pos.y,pos.z])
	var decay: Array = []
	for pos in _decay: decay.append([pos.x,pos.y,pos.z,maxf(0.0,float(_decay[pos])-_time)])
	var drops: Array = []
	for drop in _drops:
		var pos: Vector3 = drop.position
		drops.append({"position":[pos.x,pos.y,pos.z],"id":int(drop.id),"age":float(drop.age)})
	return {"pending":pending,"decay":decay,"drops":drops,"rng":str(_rng.state)}

func restore(data: Dictionary) -> void:
	_queue.clear(); _queued.clear(); _job.clear(); _decay.clear()
	for raw in data.get("pending",[]):
		if raw is Array and raw.size() >= 3: _enqueue(Vector3i(int(raw[0]),int(raw[1]),int(raw[2])))
	for raw in data.get("decay",[]):
		if raw is Array and raw.size() >= 4 and _decay.size() < MAX_QUEUE: _decay[Vector3i(int(raw[0]),int(raw[1]),int(raw[2]))] = _time+clampf(float(raw[3]),0.0,8.0)
	for mesh in _drop_meshes: mesh.queue_free()
	_drop_meshes.clear(); _drops.clear()
	for raw in data.get("drops",[]):
		if raw is Dictionary and raw.get("position",[]) is Array and raw.position.size() == 3 and int(raw.get("id",0)) in [1000,1200]:
			_spawn_drop(Vector3(float(raw.position[0]),float(raw.position[1]),float(raw.position[2])),int(raw.id))
			if not _drops.is_empty(): _drops[-1].age = clampf(float(raw.get("age",0.0)),0.0,180.0)
	if data.has("rng"): _rng.state = int(str(data.rng))
