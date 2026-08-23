class_name Corpse
extends RigidBody2D
## Physical 2D corpse left behind when a living actor dies. A rigid body with
## the actor's final sprite, receiving the killing blow's impulse; it can be
## shoved by later explosions. Corpses collide ONLY with the world (layer 8,
## mask 1) so zombie pathing never treats them as obstacles, disable their
## collision entirely once asleep, and free the oldest beyond a global cap.

const MAX_CORPSES := 80
const LIFETIME := 30.0
## Collision layer reserved for corpses/debris: nothing scans or navigates
## against it, but explosion queries include it so blasts move remains.
const CORPSE_LAYER := 8

static var active_count := 0

static func spawn(container: Node, source_visual: Node2D, world_position: Vector2, death_impulse: Vector2) -> Corpse:
	if container == null:
		return null
	# Bounded population: retire the oldest corpse before exceeding the cap.
	var corpses := container.get_tree().get_nodes_in_group("corpses").filter(func(node: Node) -> bool:
		return is_instance_valid(node) and not node.is_queued_for_deletion())
	while corpses.size() >= MAX_CORPSES:
		var oldest := corpses.pop_front() as Node
		if oldest != null and is_instance_valid(oldest):
			oldest.queue_free()
			active_count = maxi(active_count - 1, 0)
	var corpse := Corpse.new()
	corpse.name = "Corpse"
	corpse.gravity_scale = 0.0 # top-down world
	corpse.mass = 1.2
	corpse.linear_damp = 8.0
	corpse.angular_damp = 6.5
	corpse.can_sleep = true
	corpse.collision_layer = CORPSE_LAYER
	corpse.collision_mask = 1
	var shape := CircleShape2D.new()
	shape.radius = 7.0
	var collider := CollisionShape2D.new()
	collider.shape = shape
	corpse.add_child(collider)
	var visual := AnimatedSprite2D.new()
	_copy_visual(source_visual, visual)
	corpse.add_child(visual)
	container.add_child(corpse)
	corpse.global_position = world_position
	corpse.add_to_group("corpses")
	active_count += 1
	if death_impulse != Vector2.ZERO:
		corpse.apply_central_impulse(death_impulse)
		corpse.angular_velocity = signf(death_impulse.x if death_impulse.x != 0.0 else 1.0) * 3.0
	return corpse

static func _copy_visual(source: Node2D, target: AnimatedSprite2D) -> void:
	if source is AnimatedSprite2D:
		var animated := source as AnimatedSprite2D
		target.sprite_frames = animated.sprite_frames
		target.animation = animated.animation
		target.frame = animated.frame
	if source != null:
		target.modulate = Color(0.75, 0.7, 0.7) # drained look
		target.scale = source.scale

var _age := 0.0

func _ready() -> void:
	# Sleeping corpses freeze to zero physics cost but KEEP their collision
	# layer: blast queries (mask includes layer 8) can still find and wake
	# them, so a grenade can throw a week-old corpse across the room.
	sleeping_state_changed.connect(func() -> void:
		if sleeping:
			freeze = true)

func _physics_process(delta: float) -> void:
	# Lifetime cleanup runs regardless of sleep state: every corpse
	# eventually frees itself so the population cannot grow without bound.
	_age += delta
	if _age >= LIFETIME:
		active_count = maxi(active_count - 1, 0)
		queue_free()
		set_physics_process(false)
