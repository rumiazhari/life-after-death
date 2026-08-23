class_name GoreSystem
extends RefCounted
## Bounded blood/gore presentation: directional splats, persistent decals and
## one-shot sprays. Everything is pooled/capped -- decals live far longer than
## physics chunks but never accumulate without limit. All lookups happen at
## spawn time only; nothing scans per frame.

const MAX_DECALS := 140
const DECAL_LIFETIME := 40.0
const MAX_SPRAYS := 24

static var _blood_texture: ImageTexture = null

static func _blood_tex() -> ImageTexture:
	if _blood_texture != null:
		return _blood_texture
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Irregular multi-blob splat.
	for blob in [Vector2(12, 12), Vector2(7, 14), Vector2(16, 8), Vector2(15, 16), Vector2(9, 9)]:
		var radius := 3.0 + fposmod(int(blob.x * 7 + blob.y * 3), 4)
		for y in range(24):
			for x in range(24):
				if Vector2(x + 0.5, y + 0.5).distance_to(blob) <= radius * 0.55:
					img.set_pixel(x, y, Color8(140, 20, 20, 210))
	_blood_texture = ImageTexture.create_from_image(img)
	return _blood_texture

## Directional splat: main pool offset along the hit direction plus droplets.
static func blood_splat(container: Node, world_position: Vector2, direction: Vector2, strength: float) -> void:
	if container == null or not container.is_inside_tree():
		return
	var existing := container.get_tree().get_nodes_in_group("blood_decals").filter(func(n: Node) -> bool:
		return is_instance_valid(n) and not n.is_queued_for_deletion())
	while existing.size() >= MAX_DECALS:
		var oldest := existing.pop_front() as Node
		if oldest != null:
			oldest.queue_free()
	var count := 1 + clampi(int(strength / 30.0), 0, 2)
	for i in range(count):
		var decal := Sprite2D.new()
		decal.name = "BloodDecal"
		decal.texture = _blood_tex()
		var spread := direction.rotated((float(i) - float(count - 1) * 0.5) * 0.6)
		decal.global_position = world_position + spread * (10.0 + float(i) * 12.0)
		decal.rotation = spread.angle()
		decal.scale = Vector2.ONE * clampf(0.5 + strength / 90.0, 0.5, 1.4)
		decal.z_index = -5
		decal.modulate = Color(1, 1, 1, 0.85)
		container.add_child(decal)
		decal.add_to_group("blood_decals")
		var lifetime := Timer.new()
		lifetime.wait_time = DECAL_LIFETIME
		lifetime.one_shot = true
		lifetime.autostart = true
		lifetime.timeout.connect(decal.queue_free)
		decal.add_child(lifetime)

## One-shot short-lived spray burst at a wound point.
static func blood_spray(container: Node, world_position: Vector2, direction: Vector2, strength: float) -> void:
	if container == null or not container.is_inside_tree():
		return
	var sprays := container.get_tree().get_nodes_in_group("blood_sprays")
	if sprays.size() >= MAX_SPRAYS:
		return
	var particles := CPUParticles2D.new()
	particles.name = "BloodSpray"
	particles.one_shot = true
	particles.emitting = true
	particles.amount = clampi(6 + int(strength / 12.0), 6, 18)
	particles.lifetime = 0.45
	particles.explosiveness = 1.0
	particles.direction = direction
	particles.spread = 32.0
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 60.0 + strength
	particles.gravity = Vector2.ZERO
	particles.damping_min = 120.0
	particles.damping_max = 180.0
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.4
	particles.color = Color8(150, 22, 22)
	particles.global_position = world_position
	container.add_child(particles)
	particles.add_to_group("blood_sprays")
	var cleaner := Timer.new()
	cleaner.wait_time = 1.2
	cleaner.one_shot = true
	cleaner.autostart = true
	cleaner.timeout.connect(particles.queue_free)
	particles.add_child(cleaner)

## A small physical gore chunk: bounded like debris, tinted wet red.
static func gore_chunk(container: Node, world_position: Vector2, impulse: Vector2) -> void:
	PhysicsDebris.spawn(container, world_position, null, Vector2(6, 5), impulse, Color8(130, 18, 18))