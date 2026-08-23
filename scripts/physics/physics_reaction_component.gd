class_name PhysicsReactionComponent
extends Node
## Shared reactive-physics architecture for hybrid 2D physics. One component
## per destructible/movable object converts a STATIC prop into a temporary
## dynamic RigidBody2D only when an impact exceeds its mass-class threshold,
## lets it settle, then refreezes it. Living actors stay CharacterBody2D and
## use apply_knockback instead; corpses/debris are always-dynamic rigid
## bodies managed by their own scripts. Nothing here scans groups per frame.

enum MassClass { LIGHT, HEAVY }

const LIGHT_THRESHOLD := 55.0
const HEAVY_THRESHOLD := 175.0
const LIGHT_MASS := 0.8
const HEAVY_MASS := 4.5
const LINEAR_DAMP := 7.0
const ANGULAR_DAMP := 6.0
## How long a converted body must sleep before it is frozen again so long
## tail simulation never accumulates.
const REFREEZE_DELAY := 6.0

@export var mass_class: int = MassClass.LIGHT

var impulse_threshold: float = LIGHT_THRESHOLD
var _dynamic_body: RigidBody2D = null
var _sleep_timer := 0.0

static func attach(root: Node2D, target_mass_class: int) -> PhysicsReactionComponent:
	if root == null or root.get_node_or_null("PhysicsReactionComponent") != null:
		return null
	var component := PhysicsReactionComponent.new()
	component.name = "PhysicsReactionComponent"
	component.mass_class = target_mass_class
	component.impulse_threshold = HEAVY_THRESHOLD if target_mass_class == MassClass.HEAVY else LIGHT_THRESHOLD
	root.add_child(component)
	return component

func _ready() -> void:
	set_process(false)

## Applies one physical impact. Weak shoves against heavy/static furniture
## are absorbed (returns false); sufficient force converts the host into a
## real dynamic body first. Returns true when the body actually moved.
func apply_impulse(impulse: Vector2, torque: float = 0.0) -> bool:
	if impulse == Vector2.ZERO:
		return false
	if _dynamic_body == null:
		if impulse.length() < impulse_threshold:
			return false
		_convert_to_dynamic()
		if _dynamic_body == null:
			return false
	_dynamic_body.apply_central_impulse(impulse)
	if torque != 0.0:
		_dynamic_body.apply_torque_impulse(torque)
	return true

func is_dynamic() -> bool:
	return _dynamic_body != null

## Converts this static prop into a live top-down rigid body: every visual,
## the interaction area, the collision shape and the damage component ride
## into a new RigidBody2D; navigation frees the footprint; the old
## StaticBody2D disappears. Works identically for plain sprites and for
## composed street-object visuals.
func _convert_to_dynamic() -> void:
	var root := get_parent() as Node2D
	if root == null:
		return
	var static_body := _find_static_body(root)
	if static_body == null:
		return
	var body := RigidBody2D.new()
	body.name = "DynamicBody"
	body.gravity_scale = 0.0 # top-down world: no gravity, damping settles motion
	body.mass = HEAVY_MASS if mass_class == MassClass.HEAVY else LIGHT_MASS
	body.linear_damp = LINEAR_DAMP
	body.angular_damp = ANGULAR_DAMP
	body.can_sleep = true
	body.collision_layer = 1
	body.collision_mask = 1
	root.add_child(body)
	for child in static_body.get_children():
		if child is CollisionShape2D or child is EnvironmentDamageComponent:
			child.reparent(body)
	# Everything else visual/interactive follows the physics body.
	for child in root.get_children():
		if child == self or child == body or not (child is Node2D):
			continue
		child.reparent(body)
	body.global_transform = static_body.global_transform
	var damage := body.get_node_or_null("EnvironmentDamageComponent") as EnvironmentDamageComponent
	if damage != null:
		damage.destroy_target = root
		UrbanNavigationService.mark_area_free(Rect2(root.global_position - damage.affected_size * 0.5, damage.affected_size), body.get_rid())
	static_body.queue_free()
	_dynamic_body = body
	set_process(true)

func _find_static_body(root: Node2D) -> StaticBody2D:
	for child in root.get_children():
		if child is StaticBody2D:
			return child
	return null

## Mass classes by semantic kind: light loose items convert under modest
## shoves; substantial furniture needs real force (explosions, heavy hits).
const LIGHT_KINDS := [
	&"chair", &"crate", &"pallet", &"nightstand", &"trash", &"cone",
	&"bollard", &"planter", &"sign_post", &"rubble", &"medical_cache",
]

static func mass_class_for_kind(kind: StringName) -> int:
	return MassClass.LIGHT if kind in LIGHT_KINDS else MassClass.HEAVY

func _process(delta: float) -> void:
	if _dynamic_body == null:
		set_process(false)
		return
	if not _dynamic_body.sleeping:
		_sleep_timer = 0.0
		return
	_sleep_timer += delta
	if _sleep_timer >= REFREEZE_DELAY:
		# Settled long enough: freeze to a zero-cost static transform.
		_dynamic_body.freeze = true
		_dynamic_body = null
		set_process(false)
