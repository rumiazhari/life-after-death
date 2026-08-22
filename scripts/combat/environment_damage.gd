class_name EnvironmentDamage
extends RefCounted
## Shared environmental-impact rules. Actor damage keeps using the existing
## take_damage(amount, source) interface; static environment bodies expose an
## EnvironmentDamageComponent child and are filtered by DamageClass.

enum DamageClass { SMALL_ARMS, HEAVY, EXPLOSIVE }

const WORLD_AND_ACTORS_MASK := 1 | 2 | 4 | 16

static func apply_to_body(body: Node, amount: float, damage_class: int, source: Node = null) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	var component: EnvironmentDamageComponent = body.get_node_or_null("EnvironmentDamageComponent")
	if component:
		component.apply_damage(amount, damage_class, source)
		return true
	return false

## Applies a radial hit once per physics body. The linear falloff never drops
## below 25%, so an explosive touching a reinforced wall still applies a
## meaningful structural hit at the blast edge.
static func apply_explosion(source_node: Node2D, origin: Vector2, radius: float, structural_amount: float, actor_amount: float, damage_class: int) -> int:
	if source_node == null or radius <= 0.0 or maxf(structural_amount, actor_amount) <= 0.0:
		return 0
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, origin)
	query.collision_mask = WORLD_AND_ACTORS_MASK
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
		var component: EnvironmentDamageComponent = body.get_node_or_null("EnvironmentDamageComponent")
		if component:
			component.apply_damage(structural_amount * falloff, damage_class, source_node)
		elif body.has_method("take_damage"):
			body.call("take_damage", actor_amount * falloff, source_node)
	return applied.size()
