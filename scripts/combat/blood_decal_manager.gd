class_name BloodDecalManager
extends Node2D
## Presentation-only: drops a small persistent blood decal where a zombie
## dies. Capped and recycled (oldest decal's Sprite2D is reused, not
## re-created) instead of growing unbounded -- with up to 250 zombies
## dying in a run this would otherwise leak nodes indefinitely. A restart
## reloads the whole Main scene, which frees this node (and its pooled
## children) along with everything else, so no separate reset hook is
## needed here.

const MAX_DECALS := 40
const DECAL_PATHS := [
	"res://assets/pixel/effects/blood_decal_0.png",
	"res://assets/pixel/effects/blood_decal_1.png",
	"res://assets/pixel/effects/blood_decal_2.png",
]

var _decal_textures: Array[Texture2D] = []
var _pool: Array[Sprite2D] = []
var _next_index: int = 0

func _ready() -> void:
	z_index = -6
	for path in DECAL_PATHS:
		_decal_textures.append(load(path))
	GameEvents.zombie_died.connect(_on_zombie_died)

func _on_zombie_died(_zombie: Node, death_position: Vector2) -> void:
	var sprite: Sprite2D
	if _pool.size() < MAX_DECALS:
		sprite = Sprite2D.new()
		add_child(sprite)
		_pool.append(sprite)
	else:
		sprite = _pool[_next_index]
		_next_index = (_next_index + 1) % MAX_DECALS
	sprite.texture = _decal_textures[randi() % _decal_textures.size()]
	sprite.position = death_position
	sprite.rotation = randf() * TAU
	sprite.modulate = Color(1, 1, 1, 1)
