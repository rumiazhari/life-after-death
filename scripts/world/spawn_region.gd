class_name SpawnRegion
extends Node2D
## A fixed, authored zombie spawn area (map-edge street, alley, or
## concealed exterior spot). Pure data -- SpawnManager reads `radius`/
## `category` and picks a random point within it via its OWN gameplay RNG,
## never this node's.

@export var region_id: StringName = &""
@export var radius: float = 150.0
@export var category: StringName = &"map_edge"

func _ready() -> void:
	add_to_group("spawn_regions")

## A uniformly-distributed point inside this region's circle, using the
## CALLER's own RandomNumberGenerator (never a local/global one) so spawn
## selection stays on SpawnManager's private gameplay RNG stream -- see
## docs/perception_system.md "RNG isolation carries over".
func random_point(rng: RandomNumberGenerator) -> Vector2:
	var angle: float = rng.randf() * TAU
	var dist: float = sqrt(rng.randf()) * radius
	return global_position + Vector2.RIGHT.rotated(angle) * dist
