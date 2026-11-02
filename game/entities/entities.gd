class_name SlopEntities
extends Node3D

signal boss_changed
signal boss_defeated

var world: Node3D
var player: CharacterBody3D
var dimension: String = "overworld"
var boss_health: float = 240.0
var boss_max_health: float = 240.0
var boss_alive: bool = false
var boss_was_defeated: bool = false
var actors: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var crystals: Array[Node3D] = []
var dragon: Node3D
var left_wing: Node3D
var right_wing: Node3D
var elapsed: float = 0.0
var boss_attack_timer: float = 4.0
var boss_hurt_timer: float = 0.0
var rng := RandomNumberGenerator.new()
var known_villagers: Dictionary = {}
var defeated_actor_ids: Dictionary = {}
var dormant_actors: Array[Dictionary] = []
var village_timer: float = 0.0
var dragon_material: StandardMaterial3D
var dragon_tail: Array[Node3D] = []
var dragon_head: Node3D
var dragon_legs: Array[Node3D] = []

func setup(voxel_world: Node3D, voxel_player: CharacterBody3D, dimension_name: String) -> void:
	world = voxel_world
	player = voxel_player
	dimension = dimension_name
	rng.seed = int(world.get("seed_value")) if world.get("seed_value") != null else 72942
	if dimension == "end":
		_build_boss()
	else:
		for index in range(9 if dimension == "overworld" else 5):
			var angle: float = float(index) * TAU / 9.0
			var distance: float = 9.0 + float(index % 3) * 5.0
			var x: int = int(player.position.x + cos(angle) * distance)
			var z: int = int(player.position.z + sin(angle) * distance)
			var height: int = int(world.call("surface_height", x, z))
			var species: String = "slime" if index % 4 == 3 or dimension == "nether" else ("sheep" if index % 2 == 0 else "pig")
			var floor_id: int = int(world.call("get_block", Vector3i(x, height, z)))
			if floor_id == 9 or floor_id == 20 or floor_id == 0:
				continue
			_spawn_actor(species, Vector3(x + 0.5, height + 2.0, z + 0.5), {"id":"fauna:%s:%d:%d:%s" % [dimension,x,z,species]})
		_discover_villagers()

func _material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.2
	return material

func _box(parent: Node3D, size: Vector3, offset: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.material_override = _material(color, glow)
	box.position = offset
	parent.add_child(box)
	return box

func _spawn_actor(species: String, at: Vector3, saved: Dictionary = {}) -> Dictionary:
	var body := CharacterBody3D.new()
	body.name = species.capitalize()
	body.collision_layer = 4
	body.collision_mask = 1
	body.floor_snap_length = 0.35
	add_child(body)
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.58,1.80,0.58) if species == "villager" else Vector3(0.75,0.95,0.85)
	shape.shape = box
	shape.position.y = box.size.y * 0.5
	body.add_child(shape)
	var visual := CreatureModel.new()
	body.add_child(visual)
	visual.setup(species,str(saved.get("profession","farmer")),dimension == "nether")
	var actor: Dictionary = {
		"body":body,"visual":visual,"species":species,"health":16.0 if species == "slime" else (20.0 if species == "villager" else 10.0),
		"timer":rng.randf_range(0.5,3.0),"heading":rng.randf_range(-PI,PI),"attack":0.0,"legs":visual.limbs,"hurt":0.0,
		"id":saved.get("id","actor:%s:%s" % [dimension,str(rng.randi())]),"home":at,"profession":saved.get("profession",""),
		"village_id":saved.get("village_id",""),"name":saved.get("name",species.capitalize()),"trade_uses":{},"panic":0.0
	}
	for key in ["health","timer","heading","attack","hurt","panic"]:
		if saved.has(key): actor[key] = float(saved[key])
	actor.health = clampf(float(actor.health),0.1,100.0)
	actor.home = _vector(saved.get("home",at),at)
	if saved.get("trade_uses") is Dictionary: actor.trade_uses = saved.trade_uses.duplicate(true)
	body.rotation.y = float(actor.heading)
	body.velocity = _vector(saved.get("velocity",Vector3.ZERO),Vector3.ZERO)
	actors.append(actor)
	return actor

func _discover_villagers() -> void:
	if dimension != "overworld" or not "structure_provider" in world:
		return
	var provider: Variant = world.get("structure_provider")
	if provider == null or not provider.has_method("village_spawn_points"):
		return
	var points: Array = provider.call("village_spawn_points",player.position,96.0)
	for point: Dictionary in points:
		var id: String = str(point.get("id",""))
		if id.is_empty() or known_villagers.has(id) or defeated_actor_ids.has(id): continue
		known_villagers[id] = true
		_spawn_actor("villager",_vector(point.get("position"),player.position),point)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or not bool(player.get("active")):
		return
	elapsed += delta
	village_timer -= delta
	if village_timer <= 0.0:
		village_timer = 2.0
		_stream_actors()
		_discover_villagers()
	for actor in actors.duplicate():
		var body: CharacterBody3D = actor.body
		if not is_instance_valid(body):
			actors.erase(actor)
			continue
		var separation: Vector3 = player.global_position - body.global_position
		if separation.length_squared() > 16000.0: continue
		for timer in ["timer","attack","hurt","panic"]:
			actor[timer] = maxf(-1.0,float(actor[timer])-delta)
		var hostile: bool = actor.species == "slime"
		var walk_speed: float = 1.0
		if hostile and separation.length() < 28.0:
			actor.heading = atan2(-separation.x,-separation.z)
			walk_speed = 2.8 if dimension == "nether" else 2.3
		elif float(actor.panic) > 0.0:
			actor.heading = atan2(separation.x,separation.z)
			walk_speed = 3.6
		elif float(actor.timer) <= 0.0:
			actor.timer = rng.randf_range(2.0,5.0)
			actor.heading = rng.randf_range(-PI,PI)
			if actor.species == "villager" and body.position.distance_to(actor.home) > 12.0:
				var homeward: Vector3 = actor.home-body.position
				actor.heading = atan2(-homeward.x,-homeward.z)
		if not hostile and float(actor.timer) < 1.4 and float(actor.panic) <= 0.0: walk_speed = 0.0
		var liquid: int = int(world.call("get_block",Vector3i((body.position+Vector3.UP*0.55).floor())))
		var swimming: bool = liquid in [9,20]
		var route: Dictionary = _route(body.position,float(actor.heading),swimming)
		actor.heading = route.heading
		if not route.safe: walk_speed = 0.0
		body.rotation.y = lerp_angle(body.rotation.y,float(actor.heading),minf(delta*5.0,1.0))
		var forward: Vector3 = Vector3(-sin(float(actor.heading)),0,-cos(float(actor.heading)))
		if float(actor.hurt) <= 0.0:
			body.velocity.x = forward.x*walk_speed*(0.65 if swimming else 1.0)
			body.velocity.z = forward.z*walk_speed*(0.65 if swimming else 1.0)
		if swimming:
			body.velocity.y = move_toward(body.velocity.y,2.0,delta*9.0)
			var fluid: Variant = world.get_meta("fluid_system",null)
			if fluid != null and fluid.has_method("flow_force_at"):
				body.velocity += Vector3(fluid.call("flow_force_at",body.position))*delta*2.0
			if liquid == 20 and dimension != "nether":
				actor.health = float(actor.health)-delta*4.0
				actor.hurt = 0.2
		else:
			body.velocity.y -= 22.0*delta
			if body.is_on_floor() and bool(route.jump): body.velocity.y = 7.0
			elif hostile and body.is_on_floor() and sin(elapsed*3.0+body.position.x)>0.88: body.velocity.y = 5.8
		body.move_and_slide()
		var minimum: float = float(world.call("min_y")) if world.has_method("min_y") else -176.0
		if body.position.y < minimum-12.0 or float(actor.health) <= 0.0:
			_defeat_actor(actor,false)
			continue
		var visual: CreatureModel = actor.visual
		visual.animate(delta,Vector2(body.velocity.x,body.velocity.z).length(),body.is_on_floor(),swimming,float(actor.hurt),float(actor.attack)>1.1)
		if hostile and separation.length() < 1.5 and float(actor.attack) <= 0.0:
			actor.attack = 1.4
			player.call("take_damage",2.0,body.global_position)
			body.velocity.y = 5.0
	_update_projectiles(delta)
	if boss_alive: _update_boss(delta)

func _solid(at: Vector3) -> bool:
	return bool(BlockDB.get_block(int(world.call("get_block",Vector3i(at.floor())))).get("solid",false))

func _route(at: Vector3,heading: float,swimming: bool) -> Dictionary:
	# Probe alternate headings around walls; jump only a one-block obstacle with headroom.
	for turn in [0.0,0.65,-0.65,1.3,-1.3,PI]:
		var angle: float = heading+turn
		var ahead: Vector3 = at+Vector3(-sin(angle),0,-cos(angle))*0.95
		var lava: bool = int(world.call("get_block",Vector3i((ahead+Vector3.UP*0.1).floor()))) == 20
		if lava and dimension != "nether": continue
		var obstacle: bool = _solid(ahead+Vector3.UP*0.2)
		var headroom: bool = not _solid(ahead+Vector3.UP*1.2) and not _solid(ahead+Vector3.UP*2.1)
		if obstacle and not headroom: continue
		if not swimming and not obstacle and not _solid(ahead-Vector3.UP*0.5) and not _solid(ahead-Vector3.UP*1.5): continue
		return {"heading":angle,"safe":true,"jump":obstacle and headroom}
	return {"heading":heading+PI*0.5,"safe":false,"jump":false}

func _stream_actors() -> void:
	for actor in actors.duplicate():
		if actor.body.position.distance_squared_to(player.position) > 192.0*192.0:
			dormant_actors.append(_serialize_actor(actor))
			actors.erase(actor)
			actor.body.queue_free()
	for saved in dormant_actors.duplicate():
		var at: Vector3 = _vector(saved.get("position"),Vector3.ZERO)
		if at.distance_squared_to(player.position)<128.0*128.0:
			dormant_actors.erase(saved)
			if not defeated_actor_ids.has(str(saved.id)): _spawn_actor(str(saved.species),at,saved)

func _defeat_actor(actor: Dictionary,reward: bool) -> void:
	if reward and actor.species != "villager":
		player.call("collect_item",1029 if actor.species == "slime" else 1206,2)
		if actor.species == "sheep": player.call("collect_item",117,1)
	defeated_actor_ids[str(actor.id)] = true
	actors.erase(actor)
	var body: CharacterBody3D = actor.body
	body.collision_layer = 0
	body.collision_mask = 0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(body,"rotation:z",PI*0.48,0.35)
	tween.tween_property(body,"scale",Vector3.ONE*0.03,0.65).set_delay(0.3)
	tween.chain().tween_callback(body.queue_free)

func _build_boss() -> void:
	boss_alive = true
	dragon = Node3D.new()
	dragon.name = "Enderslop"
	add_child(dragon)
	dragon_material = CreatureModel.textured_material("dragon")
	CreatureModel.part(dragon,Vector3(2.4,1.7,5.3),Vector3.ZERO,dragon_material,0)
	dragon_head = CreatureModel.joint(dragon,Vector3(0,0.4,-2.4))
	CreatureModel.part(dragon_head,Vector3(1.35,1.0,1.7),Vector3(0,0,-0.6),dragon_material,4)
	CreatureModel.part(dragon_head,Vector3(1.6,1.0,1.9),Vector3(0,0.1,-2.2),dragon_material,0)
	CreatureModel.part(dragon_head,Vector3(1.3,0.45,1.6),Vector3(0,-0.37,-2.5),dragon_material,3)
	for side in [-1.0,1.0]:
		var eye := CreatureModel.part(dragon_head,Vector3(0.06,0.20,0.62),Vector3(side*0.82,0.28,-2.35),dragon_material,1)
		eye.material_override = dragon_material.duplicate()
		eye.material_override.emission_enabled = true
		eye.material_override.emission = Color("a545ca")
		eye.material_override.emission_energy_multiplier = 0.8
		CreatureModel.part(dragon_head,Vector3(0.26,0.9,0.30),Vector3(side*0.54,0.85,-1.95),dragon_material,6)
		for z in [-1.35,1.6]:
			var leg := CreatureModel.joint(dragon,Vector3(side*0.95,-0.7,z))
			dragon_legs.append(leg)
			CreatureModel.part(leg,Vector3(0.47,0.95,0.5),Vector3(0,-0.4,0.1),dragon_material,4)
			CreatureModel.part(leg,Vector3(0.52,0.27,0.8),Vector3(0,-0.85,-0.1),dragon_material,2)
	var parent: Node3D = dragon
	for index in range(6):
		var segment := CreatureModel.joint(parent,Vector3(0,-0.05,2.6 if index == 0 else 1.05))
		dragon_tail.append(segment)
		CreatureModel.part(segment,Vector3(0.95-index*0.12,0.85-index*0.1,1.3),Vector3(0,0,0.5),dragon_material,0)
		CreatureModel.part(segment,Vector3(0.18,0.45-index*0.04,0.28),Vector3(0,0.55-index*0.06,0.4),dragon_material,6)
		parent = segment
	for index in range(5):
		CreatureModel.part(dragon,Vector3(0.2,0.6,0.3),Vector3(0,1.02,float(index)-2),dragon_material,6)
	left_wing = _make_wing(-1.0)
	right_wing = _make_wing(1.0)
	dragon.position = Vector3(8, 62, 8)
	if world.has_method("end_pillars"):
		var positions: Array = world.call("end_pillars")
		for crystal_position: Vector3 in positions:
			var crystal := Node3D.new()
			add_child(crystal)
			crystal.position = crystal_position + Vector3(0, 1.2, 0)
			_box(crystal, Vector3(0.85, 0.85, 0.85), Vector3.ZERO, Color("d19aff"), true).rotation_degrees = Vector3(45, 45, 0)
			_box(crystal, Vector3(1.2, 0.18, 1.2), Vector3(0, -1.0, 0), Color("26232c"))
			crystal.set_meta("pillar_index", crystals.size())
			crystals.append(crystal)
	boss_changed.emit()

func _make_wing(side: float) -> Node3D:
	var pivot := CreatureModel.joint(dragon,Vector3(side,0.4,-0.5))
	CreatureModel.part(pivot,Vector3(6.5,0.24,0.32),Vector3(side*3.1,0,0),dragon_material,6)
	var instance := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO,Vector3(side*7.3,0,0.5),Vector3(side*4.2,0,4.0),Vector3.ZERO,Vector3(side*4.2,0,4.0),Vector3(0,0,2.0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(.876,.01),Vector2(.999,.01),Vector2(.956,.99),Vector2(.876,.01),Vector2(.956,.99),Vector2(.876,.5)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	instance.mesh = mesh
	var membrane: StandardMaterial3D = dragon_material.duplicate()
	membrane.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = membrane
	pivot.add_child(instance)
	for rib in range(2):
		var bar := CreatureModel.part(pivot,Vector3(0.16,0.18,4.2),Vector3(side*(2.5+rib*2.0),0.04,1.8),dragon_material,6)
		bar.rotation.y = side*-0.4
	return pivot

func _update_boss(delta: float) -> void:
	boss_hurt_timer = maxf(0.0, boss_hurt_timer - delta)
	var phase: float = 1.0 if boss_health > boss_max_health * 0.5 else 1.45
	var angle: float = elapsed * 0.23 * phase
	var desired := Vector3(8.0 + cos(angle) * 26.0, 61.0 + sin(elapsed * 0.6) * 5.0, 8.0 + sin(angle) * 26.0)
	if fmod(elapsed, 14.0) > 10.0:
		desired = player.global_position + Vector3(cos(angle) * 7.0, 6.0, sin(angle) * 7.0)
	var movement: Vector3 = desired - dragon.position
	dragon.position += movement * minf(delta * 1.4, 1.0)
	if movement.length() > 0.1:
		dragon.rotation.y = lerp_angle(dragon.rotation.y, atan2(-movement.x, -movement.z), delta * 3.0)
	left_wing.rotation.z = sin(elapsed * 4.0 * phase) * 0.43
	right_wing.rotation.z = -left_wing.rotation.z
	dragon_material.albedo_color = Color(1.0,0.5,0.5) if boss_hurt_timer>0 else Color.WHITE
	dragon.rotation.x = lerpf(dragon.rotation.x,clampf(-movement.y*0.025,-0.25,0.25),minf(delta*3,1))
	left_wing.rotation.x = cos(elapsed*4.0*phase)*0.08
	right_wing.rotation.x = left_wing.rotation.x
	for index in dragon_tail.size():
		dragon_tail[index].rotation.y = sin(elapsed*2.2-index*0.65)*0.13
		dragon_tail[index].rotation.x = sin(elapsed*1.6-index*0.4)*0.06
	for index in dragon_legs.size(): dragon_legs[index].rotation.x = 0.2+sin(elapsed*4.0+index)*0.12
	dragon_head.rotation.x = sin(elapsed*1.7)*0.07 + (-0.12 if boss_attack_timer<0.5 else 0.0)
	boss_attack_timer -= delta
	if boss_attack_timer <= 0.0:
		boss_attack_timer = 3.2 / phase
		var start: Vector3 = dragon.global_position - dragon.global_transform.basis.z * 4.0
		var direction: Vector3 = (player.global_position + Vector3(0, 1.0, 0) - start).normalized()
		var projectile := Node3D.new()
		add_child(projectile)
		projectile.position = start
		_box(projectile, Vector3(0.7, 0.7, 0.7), Vector3.ZERO, Color("c66bff"), true)
		projectiles.append({"node": projectile, "velocity": direction * 12.0, "life": 8.0})
	for crystal in crystals:
		if is_instance_valid(crystal):
			crystal.rotation.y += delta
			crystal.get_child(0).position.y = sin(elapsed * 2.0) * 0.25
	if crystals.size() > 0 and boss_health < boss_max_health:
		boss_health = minf(boss_max_health, boss_health + delta * 0.2 * crystals.size())
		boss_changed.emit()

func _update_projectiles(delta: float) -> void:
	for shot in projectiles.duplicate():
		var node: Node3D = shot["node"]
		node.position += (shot["velocity"] as Vector3) * delta
		node.rotation += Vector3(2, 3, 1) * delta
		shot["life"] = float(shot["life"]) - delta
		var hit: bool = node.global_position.distance_to(player.global_position + Vector3(0, 0.8, 0)) < 1.3
		var block: int = int(world.call("get_block", Vector3i(node.position.floor())))
		if hit:
			player.call("take_damage", 4.0, node.global_position)
		if hit or block != 0 or float(shot["life"]) <= 0.0:
			_sparks(node.global_position, Color("b576e8"), 6)
			node.queue_free()
			projectiles.erase(shot)

func attack(origin: Vector3, direction: Vector3, damage: float, reach: float) -> bool:
	var closest_distance: float = reach
	var target_actor: Dictionary = {}
	var target_crystal: Node3D = null
	var target_boss: bool = false
	for actor in actors:
		var body: CharacterBody3D = actor["body"]
		var distance: float = _ray_sphere(origin, direction.normalized(), body.global_position + Vector3(0, 0.9 if actor.species == "villager" else 0.6, 0), 0.78)
		if distance >= 0.0 and distance < closest_distance:
			closest_distance = distance
			target_actor = actor
	for crystal in crystals:
		var distance: float = _ray_sphere(origin, direction, crystal.global_position, 1.3)
		if distance >= 0.0 and distance < closest_distance:
			closest_distance = distance
			target_actor = {}
			target_crystal = crystal
	if boss_alive:
		var distance: float = _ray_sphere(origin, direction, dragon.global_position, 4.1)
		if distance >= 0.0 and distance < closest_distance:
			closest_distance = distance
			target_actor = {}
			target_crystal = null
			target_boss = true
	if not target_actor.is_empty():
		var body: CharacterBody3D = target_actor["body"]
		target_actor["health"] = float(target_actor["health"]) - damage
		target_actor["hurt"] = 0.25
		target_actor["panic"] = 4.0
		body.velocity = direction * 4.0 + Vector3.UP * 4.0
		_sparks(body.global_position + Vector3(0, 0.6, 0), Color("ede4b7"), 6)
		if float(target_actor["health"]) <= 0.0:
			_defeat_actor(target_actor,true)
		return true
	if target_crystal != null:
		_sparks(target_crystal.global_position, Color("e9aeff"), 16)
		crystals.erase(target_crystal)
		target_crystal.queue_free()
		player.emit_signal("notify", "End crystal shattered! %d remaining" % crystals.size())
		return true
	if target_boss:
		boss_health = maxf(0.0, boss_health - damage)
		boss_hurt_timer = 0.15
		_sparks(origin + direction * closest_distance, Color("db86ff"), 8)
		boss_changed.emit()
		if boss_health <= 0.0:
			boss_alive = false
			boss_was_defeated = true
			_sparks(dragon.global_position, Color("eed1ff"), 40)
			var dying := create_tween().set_parallel(true)
			dying.tween_property(dragon,"rotation:z",PI*0.7,1.4)
			dying.tween_property(dragon,"position:y",dragon.position.y-8.0,1.4)
			dying.tween_property(dragon,"scale",Vector3.ZERO,0.5).set_delay(0.9)
			dying.chain().tween_callback(dragon.queue_free)
			boss_defeated.emit()
		return true
	return false

func _ray_sphere(origin: Vector3, direction: Vector3, center: Vector3, radius: float) -> float:
	var offset: Vector3 = origin - center
	var b: float = offset.dot(direction)
	var c: float = offset.length_squared() - radius * radius
	var discriminant: float = b * b - c
	if discriminant < 0.0:
		return -1.0
	return maxf(0.0, -b - sqrt(discriminant)) if -b + sqrt(discriminant) >= 0.0 else -1.0

func _sparks(at: Vector3, color: Color, count: int) -> void:
	for index in range(count):
		var particle := _box(self, Vector3.ONE * rng.randf_range(0.08, 0.22), at, color, true)
		var destination: Vector3 = at + Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(0.0, 2.2), rng.randf_range(-2.0, 2.0))
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(particle, "position", destination, 0.55)
		tween.tween_property(particle, "scale", Vector3.ZERO, 0.55)
		tween.chain().tween_callback(particle.queue_free)

func _serialize_actor(actor: Dictionary) -> Dictionary:
	var state: Dictionary = {}
	for key in ["id","species","health","timer","heading","attack","hurt","panic","profession","village_id","name","trade_uses"]:
		state[key] = actor[key]
	state.position = _array(actor.body.position)
	state.velocity = _array(actor.body.velocity)
	state.home = _array(actor.home)
	return state.duplicate(true)

static func _array(at: Vector3) -> Array:
	return [at.x,at.y,at.z]

static func _vector(value: Variant,fallback: Vector3) -> Vector3:
	var result: Vector3 = fallback
	if value is Vector3: result = value
	elif value is Array and value.size() == 3:
		if (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int) and (value[2] is float or value[2] is int):
			result = Vector3(float(value[0]),float(value[1]),float(value[2]))
	return result if result.is_finite() else fallback

func serialize() -> Dictionary:
	var alive_crystals: Array[int] = []
	for crystal in crystals: alive_crystals.append(int(crystal.get_meta("pillar_index",0)))
	var stored_actors: Array = dormant_actors.duplicate(true)
	for actor in actors: stored_actors.append(_serialize_actor(actor))
	var shots: Array = []
	for shot in projectiles:
		shots.append({"position":_array(shot.node.position),"velocity":_array(shot.velocity),"life":shot.life})
	var state: Dictionary = {
		"boss_health":boss_health,"boss_defeated":boss_was_defeated,"crystals_remaining":crystals.size(),"alive_crystals":alive_crystals,
		"actors":stored_actors,"known_villagers":known_villagers.duplicate(),"defeated_actor_ids":defeated_actor_ids.duplicate(),
		"elapsed":elapsed,"boss_attack_timer":boss_attack_timer,"boss_hurt_timer":boss_hurt_timer,"projectiles":shots,"rng_state":str(rng.state)
	}
	if boss_alive and is_instance_valid(dragon):
		state.boss_position = _array(dragon.position)
		state.boss_rotation = _array(dragon.rotation)
	return state

func restore(data: Dictionary) -> void:
	boss_was_defeated = bool(data.get("boss_defeated",false))
	boss_health = clampf(float(data.get("boss_health",boss_max_health)),0,boss_max_health)
	elapsed = maxf(0,float(data.get("elapsed",0)))
	boss_attack_timer = clampf(float(data.get("boss_attack_timer",4)),0,20)
	boss_hurt_timer = clampf(float(data.get("boss_hurt_timer",0)),0,1)
	if data.has("rng_state"): rng.state = int(data.rng_state)
	if data.get("known_villagers") is Dictionary: known_villagers = data.known_villagers.duplicate()
	if data.get("defeated_actor_ids") is Dictionary: defeated_actor_ids = data.defeated_actor_ids.duplicate()
	# Boss-only legacy saves retain their original initial animals.
	if data.get("actors") is Array:
		for actor in actors: actor.body.queue_free()
		actors.clear(); dormant_actors.clear()
		var loaded: Dictionary = {}
		for stored in data.actors:
			if not stored is Dictionary: continue
			var id: String = str(stored.get("id",""))
			var species: String = str(stored.get("species",""))
			if id.is_empty() or loaded.has(id) or defeated_actor_ids.has(id) or species not in ["pig","sheep","slime","villager"]: continue
			if float(stored.get("health",1)) <= 0: continue
			loaded[id] = true
			var at: Vector3 = _vector(stored.get("position"),player.position)
			if species == "villager": known_villagers[id] = true
			if at.distance_squared_to(player.position)>192.0*192.0:
				dormant_actors.append(stored.duplicate(true))
			else: _spawn_actor(species,at,stored)
	for shot in projectiles: shot.node.queue_free()
	projectiles.clear()
	for stored in data.get("projectiles",[]):
		if not stored is Dictionary or float(stored.get("life",0)) <= 0: continue
		var projectile := Node3D.new(); add_child(projectile)
		projectile.position = _vector(stored.get("position"),player.position)
		_box(projectile,Vector3.ONE*0.7,Vector3.ZERO,Color("c66bff"),true)
		projectiles.append({"node":projectile,"velocity":_vector(stored.get("velocity"),Vector3.ZERO),"life":minf(float(stored.life),8)})
	if dimension == "end":
		if boss_was_defeated:
			boss_alive = false
			if is_instance_valid(dragon): dragon.queue_free()
		elif is_instance_valid(dragon):
			dragon.position = _vector(data.get("boss_position"),dragon.position)
			dragon.rotation = _vector(data.get("boss_rotation"),dragon.rotation)
		if data.has("alive_crystals"):
			var alive_crystals: Array = data.alive_crystals
			for crystal in crystals.duplicate():
				if int(crystal.get_meta("pillar_index",0)) not in alive_crystals:
					crystals.erase(crystal); crystal.queue_free()
		else:
			var remaining: int = maxi(0,int(data.get("crystals_remaining",crystals.size())))
			while crystals.size()>remaining:
				var crystal: Node3D = crystals.pop_back(); crystal.queue_free()
		boss_changed.emit()

func _offers(actor: Dictionary) -> Array:
	var variation: int = posmod(str(actor.id).hash(),3)
	var offers: Array = []
	match str(actor.profession):
		"farmer":
			offers = [_offer("Sell wheat",{1015:18+variation},1009,1,16),_offer("Buy bread",{1009:1},1201,4,12),_offer("Buy carrots",{1009:1},1204,5,12)]
		"smith":
			offers = [_offer("Sell coal",{1001:16+variation},1009,1,12),_offer("Sell iron",{1003:4},1009,1,12),_offer("Buy iron pickaxe",{1009:5+variation},1102,1,4)]
		"librarian":
			offers = [_offer("Sell paper",{1026:20+variation},1009,1,16),_offer("Buy book",{1009:2},1027,1,12),_offer("Buy bookshelf",{1009:7},91,1,8)]
		"mason":
			offers = [_offer("Sell cobblestone",{4:24+variation},1009,1,16),_offer("Buy bricks",{1009:1},1014,12,12),_offer("Buy polished stone",{1009:2},17,12,12)]
	for index in offers.size():
		offers[index].used = clampi(int(actor.trade_uses.get(str(index),0)),0,int(offers[index].stock))
	return offers

func _offer(label: String,cost: Dictionary,result: int,count: int,stock: int) -> Dictionary:
	return {"label":label,"cost":cost,"result":result,"count":count,"stock":stock,"used":0}

func interact(origin: Vector3,direction: Vector3,reach: float) -> Dictionary:
	var closest: float = minf(reach,6.0)
	var target: Dictionary = {}
	if direction.length_squared()<0.01: return target
	for actor in actors:
		if actor.species != "villager": continue
		var distance: float = _ray_sphere(origin,direction.normalized(),actor.body.global_position+Vector3.UP*1.0,0.7)
		if distance<0.0 or distance>closest: continue
		if not _line_clear(origin,origin+direction.normalized()*distance): continue
		closest = distance; target = actor
	if target.is_empty(): return {}
	return {"id":target.id,"name":target.name,"profession":target.profession,"village_id":target.village_id,"offers":_offers(target)}

func _line_clear(start: Vector3,finish: Vector3) -> bool:
	var distance: float = start.distance_to(finish)
	var steps: int = maxi(1,ceili(distance*5))
	for step in range(1,steps):
		if _solid(start.lerp(finish,float(step)/steps)): return false
	return true

func trade(villager_id: String,offer_index: int,inventory: PlayerInventory) -> bool:
	if inventory == null or offer_index<0: return false
	for actor in actors:
		if str(actor.id) != villager_id or actor.species != "villager": continue
		if actor.body.position.distance_to(player.position)>6.0 or not _line_clear(player.position+Vector3.UP,actor.body.position+Vector3.UP): return false
		var offers: Array = _offers(actor)
		if offer_index>=offers.size(): return false
		var offer: Dictionary = offers[offer_index]
		if int(offer.used)>=int(offer.stock): return false
		# Work on an isolated inventory so insufficient room never eats the payment.
		var transaction := PlayerInventory.new()
		transaction.restore(inventory.serialize())
		for id in offer.cost:
			if not transaction.consume(int(id),int(offer.cost[id])): return false
		if not transaction.add_item(int(offer.result),int(offer.count)): return false
		actor.trade_uses[str(offer_index)] = int(offer.used)+1
		actor.timer = 2.0
		inventory.restore(transaction.serialize())
		return true
	return false
