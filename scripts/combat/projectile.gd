class_name Projectile
extends Area2D
## Pooled hitscan-speed projectile. Travels in a straight line, deals damage
## to whatever it hits via the take_damage(amount, source) convention, and
## returns itself to its ObjectPool instead of being freed.

var velocity: Vector2 = Vector2.ZERO
var damage: float = 0.0
var lifetime_remaining: float = 0.0
var environment_damage_class: int = EnvironmentDamage.DamageClass.SMALL_ARMS
var environment_damage: float = 0.0
var explosion_radius: float = 0.0
var explosion_noise_loudness: float = 0.0

@onready var visual: Sprite2D = $Visual

var _pool: ObjectPool = null
var _despawned: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func setup(start_position: Vector2, direction: Vector2, speed: float, projectile_damage: float, lifetime: float, pool: ObjectPool, impact_class: int = EnvironmentDamage.DamageClass.SMALL_ARMS, structural_damage: float = 0.0, blast_radius: float = 0.0, blast_noise_loudness: float = 0.0, visual_scale: float = 1.0, visual_tint: Color = Color.WHITE) -> void:
	global_position = start_position
	rotation = direction.angle()
	velocity = direction * speed
	damage = projectile_damage
	lifetime_remaining = lifetime
	environment_damage_class = impact_class
	environment_damage = structural_damage
	explosion_radius = blast_radius
	explosion_noise_loudness = blast_noise_loudness
	visual.scale = Vector2.ONE * visual_scale
	visual.modulate = visual_tint
	_pool = pool
	_despawned = false

func _physics_process(delta: float) -> void:
	lifetime_remaining -= delta
	if lifetime_remaining <= 0.0:
		_despawn()
		return
	global_position += velocity * delta

func _on_body_entered(body: Node) -> void:
	if _despawned:
		return
	if explosion_radius > 0.0:
		EnvironmentDamage.apply_explosion(self, global_position, explosion_radius, environment_damage, damage, environment_damage_class)
		GameEvents.environment_explosion.emit(global_position, explosion_radius)
		if explosion_noise_loudness > 0.0:
			NoiseManager.emit_noise(global_position, explosion_noise_loudness, &"explosion")
	else:
		var handled_environment := false
		if environment_damage > 0.0:
			handled_environment = EnvironmentDamage.apply_to_body(body, environment_damage, environment_damage_class, self)
		if not handled_environment and body.has_method("take_damage"):
			# Exact hit position drives anatomical resolution on actors.
			body.call("take_damage", damage, self, global_position)
	_despawn()

func _despawn() -> void:
	if _despawned:
		return
	_despawned = true
	if _pool:
		_pool.release(self)
	else:
		queue_free()

func on_pool_release() -> void:
	velocity = Vector2.ZERO
	environment_damage = 0.0
	explosion_radius = 0.0
	explosion_noise_loudness = 0.0
	visual.scale = Vector2.ONE
	visual.modulate = Color.WHITE
	_despawned = true

func on_pool_acquire() -> void:
	_despawned = false
