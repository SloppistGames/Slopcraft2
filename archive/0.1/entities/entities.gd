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
			var x: int = int(8.0 + cos(angle) * distance)
			var z: int = int(8.0 + sin(angle) * distance)
			var height: int = int(world.call("surface_height", x, z))
			var species: String = "slime" if index % 4 == 3 or dimension == "nether" else ("sheep" if index % 2 == 0 else "pig")
			var floor_id: int = int(world.call("get_block", Vector3i(x, height, z)))
			if floor_id == 9 or floor_id == 20 or floor_id == 0:
				continue
			_spawn_actor(species, Vector3(x + 0.5, height + 2.0, z + 0.5))

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

func _spawn_actor(species: String, at: Vector3) -> void:
	var body := CharacterBody3D.new()
	body.name = species.capitalize()
	body.collision_layer = 4
	body.collision_mask = 1
	add_child(body)
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.75, 0.85, 0.75)
	shape.shape = box
	shape.position.y = 0.45
	body.add_child(shape)
	var visual := Node3D.new()
	body.add_child(visual)
	var legs: Array[MeshInstance3D] = []
	if species == "slime":
		var color := Color("7fb83b") if dimension != "nether" else Color("e54b23")
		_box(visual, Vector3(0.95, 0.85, 0.95), Vector3(0, 0.48, 0), color)
		_box(visual, Vector3(0.19, 0.16, 0.02), Vector3(-0.23, 0.65, -0.49), Color("173d20"))
		_box(visual, Vector3(0.19, 0.16, 0.02), Vector3(0.23, 0.65, -0.49), Color("173d20"))
		_box(visual, Vector3(0.21, 0.08, 0.02), Vector3(0, 0.35, -0.49), Color("173d20"))
	else:
		var color := Color("e4dfcb") if species == "sheep" else Color("dd8c8f")
		_box(visual, Vector3(0.87, 0.65, 1.13), Vector3(0, 0.72, 0), color)
		_box(visual, Vector3(0.55, 0.55, 0.48), Vector3(0, 0.86, -0.65), color.darkened(0.12))
		if species == "pig":
			_box(visual, Vector3(0.31, 0.19, 0.11), Vector3(0, 0.77, -0.94), Color("bb6570"))
		for side in [-1.0, 1.0]:
			_box(visual, Vector3(0.08, 0.09, 0.03), Vector3(side * 0.17, 0.95, -0.91), Color("22202b"))
			for front in [-1.0, 1.0]:
				legs.append(_box(visual, Vector3(0.19, 0.4, 0.21), Vector3(side * 0.28, 0.23, front * 0.34), color.darkened(0.3)))
	actors.append({"body": body, "visual": visual, "species": species, "health": 16.0 if species == "slime" else 10.0, "timer": rng.randf_range(0.5, 3.0), "heading": rng.randf_range(-PI, PI), "attack": 0.0, "legs": legs, "hurt": 0.0})

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or not bool(player.get("active")):
		return
	elapsed += delta
	for actor in actors.duplicate():
		var body: CharacterBody3D = actor["body"]
		if not is_instance_valid(body):
			actors.erase(actor)
			continue
		var separation: Vector3 = player.global_position - body.global_position
		if separation.length_squared() > 16000.0:
			continue
		actor["timer"] = float(actor["timer"]) - delta
		actor["attack"] = maxf(0.0, float(actor["attack"]) - delta)
		actor["hurt"] = maxf(0.0, float(actor["hurt"]) - delta)
		var hostile: bool = actor["species"] == "slime"
		var walk_speed: float = 1.0
		if hostile and separation.length() < 28.0:
			actor["heading"] = atan2(-separation.x, -separation.z)
			walk_speed = 2.8 if dimension == "nether" else 2.3
		elif float(actor["timer"]) <= 0.0:
			actor["timer"] = rng.randf_range(2.0, 5.0)
			actor["heading"] = rng.randf_range(-PI, PI)
		if not hostile and float(actor["timer"]) < 1.4:
			walk_speed = 0.0
		body.rotation.y = lerp_angle(body.rotation.y, float(actor["heading"]), delta * 4.0)
		var forward: Vector3 = -body.global_transform.basis.z
		body.velocity.x = forward.x * walk_speed
		body.velocity.z = forward.z * walk_speed
		body.velocity.y -= 22.0 * delta
		if body.is_on_floor() and body.is_on_wall():
			body.velocity.y = 6.0
		elif hostile and body.is_on_floor() and sin(elapsed * 3.0 + body.position.x) > 0.88:
			body.velocity.y = 5.8
		body.move_and_slide()
		if body.position.y < -10.0:
			body.position.y = float(world.call("surface_height", int(body.position.x), int(body.position.z))) + 3.0
		var visual: Node3D = actor["visual"]
		visual.scale = Vector3.ONE * (1.08 if float(actor["hurt"]) > 0.0 else 1.0)
		var legs: Array = actor["legs"]
		for leg_index in range(legs.size()):
			var leg: MeshInstance3D = legs[leg_index]
			leg.rotation.x = sin(elapsed * 7.0 + float(leg_index % 2) * PI) * 0.32 * walk_speed
		if hostile and separation.length() < 1.5 and float(actor["attack"]) <= 0.0:
			actor["attack"] = 1.4
			player.call("take_damage", 2.0, body.global_position)
			body.velocity.y = 5.0
	_update_projectiles(delta)
	if boss_alive:
		_update_boss(delta)

func _build_boss() -> void:
	boss_alive = true
	dragon = Node3D.new()
	dragon.name = "Enderslop"
	add_child(dragon)
	var dark := Color("201c2b")
	var edge := Color("514563")
	_box(dragon, Vector3(2.4, 1.7, 5.3), Vector3.ZERO, dark)
	_box(dragon, Vector3(1.45, 1.1, 2.0), Vector3(0, 0.6, -3.2), dark)
	_box(dragon, Vector3(1.6, 1.0, 2.0), Vector3(0, 0.5, -4.8), dark)
	_box(dragon, Vector3(1.3, 0.5, 1.5), Vector3(0, 0.03, -5.1), edge)
	for side in [-1.0, 1.0]:
		_box(dragon, Vector3(0.16, 0.25, 0.65), Vector3(side * 0.82, 0.73, -5.0), Color("d478ff"), true)
		_box(dragon, Vector3(0.3, 0.9, 0.3), Vector3(side * 0.54, 1.35, -4.5), edge)
		_box(dragon, Vector3(0.5, 1.3, 0.5), Vector3(side * 0.95, -0.95, 1.5), dark)
	for index in range(5):
		_box(dragon, Vector3(0.9 - index * 0.12, 0.9 - index * 0.12, 1.3), Vector3(0, -index * 0.1, 3.0 + index * 1.05), dark)
		_box(dragon, Vector3(0.2, 0.6, 0.3), Vector3(0, 1.02, float(index) - 2.0), edge)
	left_wing = _make_wing(-1.0, dark, edge)
	right_wing = _make_wing(1.0, dark, edge)
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

func _make_wing(side: float, dark: Color, edge: Color) -> Node3D:
	var pivot := Node3D.new()
	dragon.add_child(pivot)
	pivot.position = Vector3(side * 1.0, 0.4, -0.5)
	_box(pivot, Vector3(6.5, 0.22, 0.32), Vector3(side * 3.1, 0, 0), edge)
	var mesh_instance := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(side * 7.3, 0, 0.5), Vector3(side * 4.2, 0, 4.0), Vector3(0, 0, 0), Vector3(side * 4.2, 0, 4.0), Vector3(0, 0, 2.0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = mesh
	var material := _material(dark.lightened(0.08))
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	pivot.add_child(mesh_instance)
	for rib in range(2):
		var bar := _box(pivot, Vector3(0.16, 0.18, 4.2), Vector3(side * (2.5 + rib * 2.0), 0.04, 1.8), edge)
		bar.rotation.y = side * -0.4
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
	dragon.scale = Vector3.ONE * (1.06 if boss_hurt_timer > 0.0 else 1.0)
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
		var distance: float = _ray_sphere(origin, direction, body.global_position + Vector3(0, 0.6, 0), 0.78)
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
		target_actor["hurt"] = 0.13
		body.velocity = direction * 4.0 + Vector3.UP * 4.0
		_sparks(body.global_position + Vector3(0, 0.6, 0), Color("ede4b7"), 6)
		if float(target_actor["health"]) <= 0.0:
			player.call("collect_item", 1029 if target_actor["species"] == "slime" else 1206, 2)
			if target_actor["species"] == "sheep":
				player.call("collect_item", 117, 1)
			actors.erase(target_actor)
			body.queue_free()
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
			dragon.queue_free()
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

func serialize() -> Dictionary:
	var alive_crystals: Array[int] = []
	for crystal in crystals:
		alive_crystals.append(int(crystal.get_meta("pillar_index", 0)))
	return {"boss_health": boss_health, "boss_defeated": boss_was_defeated, "crystals_remaining": crystals.size(), "alive_crystals": alive_crystals}

func restore(data: Dictionary) -> void:
	boss_was_defeated = bool(data.get("boss_defeated", false))
	boss_health = float(data.get("boss_health", boss_max_health))
	if dimension == "end":
		if boss_was_defeated:
			boss_alive = false
			if is_instance_valid(dragon):
				dragon.queue_free()
		if data.has("alive_crystals"):
			var alive_crystals: Array = data["alive_crystals"]
			for crystal in crystals.duplicate():
				if int(crystal.get_meta("pillar_index", 0)) not in alive_crystals:
					crystals.erase(crystal)
					crystal.queue_free()
		else:
			var remaining: int = maxi(0, int(data.get("crystals_remaining", crystals.size())))
			while crystals.size() > remaining:
				var crystal: Node3D = crystals.pop_back()
				crystal.queue_free()
		boss_changed.emit()
