class_name WorldDropVisualManager
extends Node2D
## Presentation-only mirror of WorldState's `drops` registry: one sprite
## per WorldDrop, added on WorldState.drop_registered (never a per-frame
## scan) and for whatever drops already existed at _ready(). Never reads
## or writes WorldDrop/Inventory data -- no looting mechanic exists yet,
## this only makes existing drops visible. A restart reloads the whole
## Main scene, which frees this node along with its sprites, so the
## registry and its visuals can never drift out of sync across a restart.

const LOOT_BAG_TEXTURE := preload("res://assets/pixel/props/loot_bag.png")

## Cosmetic-only tint per WorldDrop.reason so a death drop, a stalled-haul
## drop, and a destroyed-storage drop read as visually distinct without
## needing three separate textures.
const REASON_TINTS := {
	&"death": Color(1.0, 1.0, 1.0),
	&"haul_stalled": Color(0.75, 0.85, 1.15),
	&"storage_destroyed": Color(1.15, 0.8, 0.75),
}

func _ready() -> void:
	z_index = -3
	WorldState.drop_registered.connect(_on_drop_registered)
	for id in WorldState.drops:
		_add_visual(WorldState.drops[id])

func _on_drop_registered(drop: WorldDrop) -> void:
	_add_visual(drop)

func _add_visual(drop: WorldDrop) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = LOOT_BAG_TEXTURE
	sprite.position = drop.position
	sprite.modulate = REASON_TINTS.get(drop.reason, Color.WHITE)
	add_child(sprite)
