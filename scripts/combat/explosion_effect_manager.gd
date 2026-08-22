class_name ExplosionEffectManager
extends Node2D
## Pooled presentation-only blast flashes. Gameplay damage and noise are
## resolved by Projectile/EnvironmentDamage before this signal is emitted.

const POOL_SIZE := 8
const SEGMENTS := 24
const FLASH_DURATION := 0.28

var _bursts: Array[Polygon2D] = []
var _next_index := 0
var _active_tweens: Dictionary = {}

func _ready() -> void:
	z_index = 8
	for i in range(POOL_SIZE):
		var burst := Polygon2D.new()
		burst.visible = false
		add_child(burst)
		_bursts.append(burst)
	GameEvents.environment_explosion.connect(_on_environment_explosion)

func _on_environment_explosion(origin: Vector2, radius: float) -> void:
	var burst := _bursts[_next_index]
	_next_index = (_next_index + 1) % _bursts.size()
	var old_tween: Tween = _active_tweens.get(burst)
	if old_tween and old_tween.is_valid():
		old_tween.kill()
	burst.polygon = _circle_polygon(radius)
	burst.global_position = origin
	burst.scale = Vector2.ONE * 0.18
	burst.color = Color(1.0, 0.48, 0.08, 0.58)
	burst.modulate = Color.WHITE
	burst.visible = true
	var tween := create_tween()
	_active_tweens[burst] = tween
	tween.set_parallel(true)
	tween.tween_property(burst, "scale", Vector2.ONE, FLASH_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(burst, "modulate:a", 0.0, FLASH_DURATION)
	tween.chain().tween_callback(_hide_burst.bind(burst))

func _circle_polygon(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(SEGMENTS):
		points.append(Vector2.RIGHT.rotated(TAU * i / SEGMENTS) * radius)
	return points

func _hide_burst(burst: Polygon2D) -> void:
	burst.visible = false
	_active_tweens.erase(burst)
