class_name SeveredLimb
extends RigidBody2D
## A physically detached zombie limb: elongated flesh chunk that flies along
## the killing blow, tumbles, reacts to later blasts (corpse layer), sleeps,
## and frees under a global cap. Not a ragdoll -- a rigid limb is enough.

const MAX_LIMBS := 24
const LIFETIME := 15.0

static var active_count := 0

static func spawn(container: Node, world_position: Vector2, impulse: Vector2) -> SeveredLimb:
	if container == null or not container.is_inside_tree():
		return null
	var existing := container.get_tree().get_nodes_in_group("severed_limbs").filter(func(node: Node) -> bool:
		return is_instance_valid(node) and not node.is_queued_for_deletion())
	while existing.size() >= MAX_LIMBS:
		var oldest := existing.pop_front() as Node
		if oldest != null:
			oldest.queue_free()
			active_count = maxi(active_count - 1, 0)
	var limb := SeveredLimb.new()
	limb.name = "SeveredLimb"
	limb.gravity_scale = 0.0
	limb.mass = 0.7
	limb.linear_damp = 6.5
	limb.angular_damp = 4.0
	limb.can_sleep = true
	limb.collision_layer = Corpse.CORPSE_LAYER
	limb.collision_mask = 1
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, 6)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	limb.add_child(collider)
	limb.add_child(_make_limb_sprite())
	container.add_child(limb)
	limb.global_position = world_position
	limb.rotation = impulse.angle()
	limb.add_to_group("severed_limbs")
	active_count += 1
	if impulse != Vector2.ZERO:
		limb.apply_central_impulse(impulse)
		limb.angular_velocity = signf(impulse.x + 0.001) * randf_range(6.0, 12.0)
	return limb

## Two-tone zombie-flesh limb: bone highlight at the severed end.
static func _make_limb_sprite() -> Sprite2D:
	var img := Image.create(18, 8, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 1, 14, 6), Color8(96, 118, 88))
	img.fill_rect(Rect2i(0, 1, 14, 2), Color8(74, 94, 68))
	img.fill_rect(Rect2i(13, 2, 5, 4), Color8(140, 30, 30)) # wet severed end
	img.fill_rect(Rect2i(15, 3, 3, 2), Color8(196, 180, 160)) # bone
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	return sprite

var _age := 0.0

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		active_count = maxi(active_count - 1, 0)
		queue_free()
		set_physics_process(false)
