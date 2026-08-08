class_name HitEffectManager
extends Node2D
## Presentation-only: a brief blood-impact flash where a zombie takes
## damage. A fixed-size pre-allocated pool (MAX_ACTIVE sprites, created
## once in _ready()) is reused round-robin, so rapid damage across up to
## 250 zombies never allocates a new node and never grows unbounded --
## distinct from BloodDecalManager's persistent capped decals on death.

const MAX_ACTIVE := 16
const FLASH_DURATION := 0.12
const TEXTURE := preload("res://assets/pixel/effects/blood_impact.png")

var _pool: Array[Sprite2D] = []
var _next_index: int = 0

func _ready() -> void:
	for i in range(MAX_ACTIVE):
		var sprite := Sprite2D.new()
		sprite.texture = TEXTURE
		sprite.visible = false
		add_child(sprite)
		_pool.append(sprite)
	GameEvents.zombie_damaged.connect(_on_zombie_damaged)

func _on_zombie_damaged(zombie: Node2D, _amount: float) -> void:
	if not is_instance_valid(zombie):
		return
	var sprite: Sprite2D = _pool[_next_index]
	_next_index = (_next_index + 1) % MAX_ACTIVE
	sprite.global_position = zombie.global_position
	sprite.rotation = CosmeticRng.randf() * TAU
	sprite.modulate = Color(1, 1, 1, 1)
	sprite.visible = true
	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, FLASH_DURATION)
	tween.tween_callback(_hide_sprite.bind(sprite))

func _hide_sprite(sprite: Sprite2D) -> void:
	sprite.visible = false
