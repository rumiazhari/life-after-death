class_name VoxelPrototypeProjectile
extends Area3D

signal released(projectile: Area3D)

var direction := Vector3.FORWARD
var speed := 18.0
var damage := 10.0
var lifetime_remaining := 1.5
var environment_damage_class := 0
var environment_damage := 0.0
var explosion_radius := 0.0
var damage_service: Node
var active := false


func setup(origin: Vector3, fire_direction: Vector3, projectile_speed: float, actor_damage: float, lifetime: float, impact_class: int, structural_damage: float, blast_radius: float, visual_scale: float, visual_tint: Color) -> void:
	global_position = origin
	direction = fire_direction.normalized()
	speed = projectile_speed
	damage = actor_damage
	lifetime_remaining = lifetime
	environment_damage_class = impact_class
	environment_damage = structural_damage
	explosion_radius = blast_radius
	$Visual.scale = Vector3.ONE * visual_scale
	$Visual.material_override.albedo_color = visual_tint
	visible = true
	monitorable = true
	active = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not active:
		return
	var travel := direction * speed * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + travel, collision_mask)
	query.collide_with_areas = true
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_resolve_hit(hit)
		_release()
		return
	global_position += travel
	lifetime_remaining -= delta
	if lifetime_remaining <= 0.0:
		_release()


func _resolve_hit(hit: Dictionary) -> void:
	var hit_position: Vector3 = hit.get("position", global_position)
	var collider: Object = hit.get("collider")
	if explosion_radius > 0.0:
		_apply_actor_explosion(hit_position)
		if damage_service != null:
			damage_service.apply_explosion(hit_position, explosion_radius, environment_damage, environment_damage_class)
		GameEvents.voxel_environment_explosion.emit(hit_position, explosion_radius)
		return
	if collider != null and collider.has_method(&"take_damage"):
		collider.take_damage(damage, self)
	elif damage_service != null:
		damage_service.apply_hit(hit_position, hit.get("normal", Vector3.ZERO), environment_damage, environment_damage_class)


func _apply_actor_explosion(origin: Vector3) -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = explosion_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.collision_mask = 2 | 4
	query.collide_with_bodies = true
	var applied: Dictionary = {}
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 128):
		var body: Object = hit.get("collider")
		if body == null or not body.has_method(&"take_damage") or applied.has(body.get_instance_id()):
			continue
		applied[body.get_instance_id()] = true
		var body_position: Vector3 = body.global_position if body is Node3D else origin
		var falloff := clampf(1.0 - origin.distance_to(body_position) / explosion_radius, 0.25, 1.0)
		body.take_damage(damage * falloff, self)


func _release() -> void:
	if not active:
		return
	active = false
	visible = false
	monitorable = false
	set_physics_process(false)
	released.emit(self)

