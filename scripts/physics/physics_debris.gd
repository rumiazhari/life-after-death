class_name PhysicsDebris
extends RigidBody2D
## Short-lived rigid debris chunk spawned when a destructible structure (wall
## segment, barricade) breaks. A bounded number of meaningful chunks fly with
## the damage impulse, settle, stop colliding, then fade out. Global caps keep
## explosions from flooding the physics server.

const MAX_DEBRIS := 64
const LIFETIME := 14.0

static var active_count := 0

static func spawn(container: Node, world_position: Vector2, texture: Texture2D, chunk_size: Vector2, impulse: Vector2, tint: Color = Color.WHITE) -> PhysicsDebris:
	if container == null:
		return null
	var existing := container.get_tree().get_nodes_in_group("physics_debris").filter(func(node: Node) -> bool:
		return is_instance_valid(node) and not node.is_queued_for_deletion())
	while existing.size() >= MAX_DEBRIS:
		var oldest := existing.pop_front() as Node
		if oldest != null and is_instance_valid(oldest):
			oldest.queue_free()
			active_count = maxi(active_count - 1, 0)
	var debris := PhysicsDebris.new()
	debris.name = "PhysicsDebris"
	debris.gravity_scale = 0.0
	debris.mass = 0.5
	debris.linear_damp = 6.0
	debris.angular_damp = 4.0
	debris.can_sleep = true
	debris.collision_layer = Corpse.CORPSE_LAYER
	debris.collision_mask = 1
	var shape := RectangleShape2D.new()
	shape.size = chunk_size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	debris.add_child(collider)
	var sprite := Sprite2D.new()
	if texture == null:
		var flat := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		flat.fill(Color.WHITE)
		texture = ImageTexture.create_from_image(flat)
		sprite.scale = chunk_size / Vector2(4, 4)
	elif texture.get_size().x > 0.0:
		sprite.scale = chunk_size * 1.6 / texture.get_size()
	sprite.texture = texture
	sprite.modulate = tint.darkened(0.25)
	debris.add_child(sprite)
	container.add_child(debris)
	debris.global_position = world_position + Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
	debris.add_to_group("physics_debris")
	active_count += 1
	debris.apply_central_impulse(impulse + Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0)))
	debris.angular_velocity = randf_range(-9.0, 9.0)
	return debris

var _age := 0.0

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		active_count = maxi(active_count - 1, 0)
