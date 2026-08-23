class_name PhysicsReactionComponent
extends Node
## Shared reactive-physics architecture for hybrid 2D physics.
##
## Lifecycle: an object starts as a plain StaticBody2D prop. The FIRST impact
## above its mass-class threshold converts it ONCE into a top-down RigidBody2D
## (visuals, interaction area, damage component and collision shape move into
## it; the old StaticBody2D is removed). From then on the rigid body is the
## permanent physical form: dynamic -> sleeping -> frozen -> DYNAMIC AGAIN.
## Freezing never destroys the body, so a moved/refrozen chair can be kicked
## across the room years later. Weak contacts accumulate through
## apply_contact_impulse until they collectively exceed the threshold -- a
## single zombie cannot shove a wardrobe, a crowd can.

enum MassClass { LIGHT, HEAVY }

const LIGHT_THRESHOLD := 55.0
const HEAVY_THRESHOLD := 175.0
const LIGHT_MASS := 0.8
const HEAVY_MASS := 4.5
const LINEAR_DAMP := 7.0
const ANGULAR_DAMP := 6.0
## How long a converted body must sleep before it freezes again. Freezing is
## cheap and fully reversible -- unlike the old model, nothing is lost.
const REFREEZE_DELAY := 6.0

@export var mass_class: int = MassClass.LIGHT

var impulse_threshold: float = LIGHT_THRESHOLD
var _body: RigidBody2D = null
var _converted := false
var _sleep_timer := 0.0
## Accumulated magnitude of weak contacts that individually failed the
## threshold; crossing it converts/reactivates the body.
var _contact_accum := 0.0

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

func is_dynamic() -> bool:
	return _converted

func is_frozen() -> bool:
	return _converted and _body != null and _body.freeze

## Applies one strong impulse. Static props convert first if the impulse is
## strong enough; frozen bodies thaw; live bodies just react.
func apply_impulse(impulse: Vector2, torque: float = 0.0) -> bool:
	if impulse == Vector2.ZERO:
		return false
	if not _converted:
		if impulse.length() < impulse_threshold:
			return false
		_convert_to_dynamic()
	_apply_impulse_to_body(impulse, torque)
	return true

## Bounded contact pressure (walking actors bumping into furniture). Each
## individual shove may be far below the threshold; they accumulate until the
## combined pressure justifies moving the piece.
func apply_contact_impulse(impulse: Vector2) -> void:
	if not _converted:
		_contact_accum += impulse.length()
		if _contact_accum >= impulse_threshold:
			_contact_accum = 0.0
			_convert_to_dynamic()
			_apply_impulse_to_body(impulse.limit_length(90.0), signf(impulse.x + 0.001))
		return
	if _body != null and _body.freeze:
		if impulse.length() < impulse_threshold * 0.5:
			return
		_body.freeze = false
	_apply_impulse_to_body(impulse.limit_length(60.0), 0.0)

func _apply_impulse_to_body(impulse: Vector2, torque: float) -> void:
	if _body == null:
		return
	if _body.freeze:
		# A refrozen body thaws whenever meaningful force returns: the
		# moved/refrozen -> dynamic cycle repeats indefinitely.
		_body.freeze = false
	if _body.sleeping:
		_body.sleeping = false
	_body.apply_central_impulse(impulse)
	if torque != 0.0:
		_body.apply_torque_impulse(torque)
	set_process(true)

## Cheap bounded actor-contact shoving. Called by characters right after
## move_and_slide(); iterates only THIS actor's actual slide collisions --
## no scene-wide queries anywhere.
static func contact_push(actor: CharacterBody2D, strength_factor: float) -> void:
	var speed := actor.velocity.length()
	if speed < 20.0:
		return
	for i in range(actor.get_slide_collision_count()):
		var collision := actor.get_slide_collision(i)
		var collider := collision.get_collider()
		if collider == null or not (collider is CollisionObject2D):
			continue
		var holder: Node = null
		if (collider as Node).get_node_or_null("PhysicsReactionComponent") != null:
			holder = collider
		elif (collider as Node).get_parent() != null and (collider as Node).get_parent().get_node_or_null("PhysicsReactionComponent") != null:
			holder = collider.get_parent()
		if holder == null:
			continue
		var reaction := (holder as Node).get_node("PhysicsReactionComponent") as PhysicsReactionComponent
		if reaction != null:
			reaction.apply_contact_impulse(-collision.get_normal() * speed * strength_factor)

func _convert_to_dynamic() -> void:
	var root := get_parent() as Node2D
	if root == null:
		return
	var static_body := _find_static_body(root)
	if static_body == null:
		return
	var body := RigidBody2D.new()
	body.name = "DynamicBody"
	body.gravity_scale = 0.0 # top-down world: damping settles motion
	body.mass = HEAVY_MASS if mass_class == MassClass.HEAVY else LIGHT_MASS
	body.linear_damp = LINEAR_DAMP
	body.angular_damp = ANGULAR_DAMP
	body.can_sleep = true
	body.collision_layer = 1
	body.collision_mask = 1
	root.add_child(body)
	# Duck-typed on purpose: a hard type reference here closes a parse cycle
	# with EnvironmentDamageComponent and breaks the class-cache scan.
	for child in static_body.get_children():
		if (child is CollisionShape2D) or String(child.name) == "EnvironmentDamageComponent":
			child.reparent(body)
	# Everything else visual/interactive follows the physics body.
	for child in root.get_children():
		if child == self or child == body or not (child is Node2D):
			continue
		child.reparent(body)
	body.global_transform = static_body.global_transform
	var damage: Node = body.get_node_or_null("EnvironmentDamageComponent")
	if damage != null:
		damage.destroy_target = root
		UrbanNavigationService.mark_area_free(Rect2(root.global_position - damage.affected_size * 0.5, damage.affected_size), body.get_rid())
	static_body.queue_free()
	_body = body
	_converted = true
	set_process(true)

func _find_static_body(root: Node2D) -> StaticBody2D:
	for child in root.get_children():
		if child is StaticBody2D:
			return child
	return null

func _process(delta: float) -> void:
	if not _converted or _body == null:
		set_process(false)
		return
	if _body.freeze:
		set_process(false)
		return
	if not _body.sleeping:
		_sleep_timer = 0.0
		return
	_sleep_timer += delta
	if _sleep_timer >= REFREEZE_DELAY:
		persist_moved_transform()
		# Freeze WITHOUT losing the body: the next impact thaws it again.
		_body.freeze = true
		set_process(false)

## Persist where physics left this piece so a reload restores the MOVED pose,
## never the original procedural placement.
func persist_moved_transform() -> void:
	if _body == null:
		return
	var root := get_parent() as Node2D
	var damage: Node = _body.get_node_or_null("EnvironmentDamageComponent")
	if root == null or damage == null or damage.object_id == &"":
		return
	WorldState.set_prop_state_flag(damage.object_id, &"moved_offset", root.position)
	WorldState.set_prop_state_flag(damage.object_id, &"moved_rotation", root.rotation)

## Deterministically runs the settle->persist->freeze transition (used by
## tests and debug tooling; normal gameplay reaches it through _process).
func debug_force_refreeze() -> void:
	if not _converted or _body == null:
		return
	persist_moved_transform()
	_body.freeze = true
	set_process(false)

## Re-applies a previously persisted moved pose right after construction.
## The stored values are the object's LOCAL pose when persistence ran.
static func restore_moved_transform(root: Node2D, object_id: StringName) -> void:
	if root == null or object_id == &"":
		return
	var offset_variant: Variant = WorldState.get_prop_state_flag(object_id, &"moved_offset", null)
	var rotation_variant: Variant = WorldState.get_prop_state_flag(object_id, &"moved_rotation", null)
	if offset_variant is Vector2:
		root.position = offset_variant
	if rotation_variant is float:
		root.rotation = rotation_variant

## Mass classes by semantic kind: light loose items convert under modest
## shoves; substantial furniture needs real force (explosions, heavy hits).
const LIGHT_KINDS := [
	&"chair", &"crate", &"pallet", &"nightstand", &"trash", &"cone",
	&"bollard", &"planter", &"sign_post", &"rubble", &"medical_cache",
	&"office_chair", &"basket", &"barrel_small", &"mattress",
]

static func mass_class_for_kind(kind: StringName) -> int:
	return MassClass.LIGHT if kind in LIGHT_KINDS else MassClass.HEAVY