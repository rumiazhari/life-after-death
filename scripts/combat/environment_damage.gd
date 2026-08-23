class_name EnvironmentDamage
extends RefCounted
## Shared environmental-impact rules. Actor damage keeps using the existing
## take_damage(amount, source) interface; static environment bodies expose an
## EnvironmentDamageComponent child and are filtered by DamageClass.
## Every hit ALSO dispatches one physical reaction through the shared hybrid
## physics layer (PhysicsReactionComponent on props, apply_knockback on live
## actors, direct impulses on rigid corpses/debris), so a shotgun blast,
## melee swing or explosion moves the whole world consistently instead of
## each system implementing its own knockback.

enum DamageClass { SMALL_ARMS, HEAVY, EXPLOSIVE }

const WORLD_AND_ACTORS_MASK := 1 | 2 | 4 | 16
## Corpses and loose debris ride their own layer so navigation never treats
## them as obstacles -- but explosions must still shove them.
const BLAST_MASK := WORLD_AND_ACTORS_MASK | Corpse.CORPSE_LAYER

## Approximate impulse strength per unit of damage for each damage class.
const CLASS_IMPULSE := {DamageClass.SMALL_ARMS: 55.0, DamageClass.HEAVY: 130.0, DamageClass.EXPLOSIVE: 240.0}

static func impulse_for(amount: float, damage_class: int) -> float:
	return maxf(amount, 4.0) * float(CLASS_IMPULSE.get(damage_class, CLASS_IMPULSE[DamageClass.SMALL_ARMS])) * 0.08

static func apply_to_body(body: Node, amount: float, damage_class: int, source: Node = null) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	var component: EnvironmentDamageComponent = body.get_node_or_null("EnvironmentDamageComponent")
	var applied := false
	if component:
		applied = component.apply_damage(amount, damage_class, source)
	# Physical reaction regardless of whether structural damage applied.
	dispatch_reaction(body, impact_origin(source), impact_direction(body, source), impulse_for(amount, damage_class))
	return applied

static func impact_origin(source: Node) -> Vector2:
	if source is Node2D:
		return (source as Node2D).global_position
	return Vector2.ZERO

static func impact_direction(body: Node, source: Node) -> Vector2:
	if body is Node2D and source is Node2D:
		var direction: Vector2 = (body as Node2D).global_position - (source as Node2D).global_position
		if direction.length_squared() > 0.01:
			return direction.normalized()
	return Vector2.ZERO

## One physical reaction dispatched through whichever interface the target
## implements: reactive prop component (on the prop root OR its collision
## body -- queries return the StaticBody2D itself), live-actor knockback, or
## raw rigid body impulse (corpses, debris).
static func dispatch_reaction(body: Node, origin: Vector2, direction: Vector2, strength: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	var reaction := body.get_node_or_null("PhysicsReactionComponent") as PhysicsReactionComponent
	if reaction == null and body.get_parent() != null:
		reaction = body.get_parent().get_node_or_null("PhysicsReactionComponent") as PhysicsReactionComponent
	if reaction != null:
		# Off-center spin derived deterministically from the hit direction so
		# props visibly tumble instead of sliding like pucks.
		var spin := signf(direction.x * 0.7 + 0.35)
		reaction.apply_impulse(direction * strength, spin * strength * 0.05)
		return
	if body.has_method("apply_knockback"):
		body.call("apply_knockback", direction * strength * 0.9)
		return
	if body is RigidBody2D:
		(body as RigidBody2D).apply_central_impulse(direction * strength * 0.8)

## Applies a radial hit once per physics body. The linear falloff never drops
## below 25%, so an explosive touching a reinforced wall still applies a
## meaningful structural hit at the blast edge. Every covered body also gets
## an outward physical push with the same falloff.
static func apply_explosion(source_node: Node2D, origin: Vector2, radius: float, structural_amount: float, actor_amount: float, damage_class: int) -> int:
	if source_node == null or radius <= 0.0 or maxf(structural_amount, actor_amount) <= 0.0:
		return 0
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, origin)
	query.collision_mask = BLAST_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hits := source_node.get_world_2d().direct_space_state.intersect_shape(query, 256)
	var applied: Dictionary = {}
	for hit in hits:
		var body: Node = hit.get("collider")
		if body == null:
			continue
		var instance_id := body.get_instance_id()
		if applied.has(instance_id):
			continue
		applied[instance_id] = true
		var body_position: Vector2 = body.global_position if body is Node2D else origin
		var falloff := clampf(1.0 - origin.distance_to(body_position) / radius, 0.25, 1.0)
		var direction := (body_position - origin).normalized() if body_position.distance_to(origin) > 1.0 else Vector2.RIGHT
		var component: EnvironmentDamageComponent = body.get_node_or_null("EnvironmentDamageComponent")
		if component:
			component.apply_damage(structural_amount * falloff, damage_class, source_node)
		elif body.has_method("take_damage"):
			body.call("take_damage", actor_amount * falloff, source_node)
		# Radial push: reactive props convert/budge, actors get knocked back,
		# corpses and debris fly -- all with identical distance falloff.
		dispatch_reaction(body, origin, direction, impulse_for(maxf(structural_amount, actor_amount), damage_class) * falloff * 1.6)
	return applied.size()
