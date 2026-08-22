class_name SpawnRegion
extends Node2D
## A semantic zombie spawn area (map-edge street, alley, functional room, or
## concealed exterior spot). Pure data -- SpawnManager reads `radius`/
## `category` and picks a random point within it via its OWN gameplay RNG,
## never this node's.

@export var region_id: StringName = &""
@export var radius: float = 150.0
@export var category: StringName = &"map_edge"
## Legacy authored multiplier retained for the five regression buildings and
## baked district. Procedural regions provide distinct phase weights below.
@export_range(0.01, 20.0, 0.01) var selection_weight: float = 1.0
@export_range(0.0, 20.0, 0.01) var initial_weight: float = 1.0
@export_range(0.0, 20.0, 0.01) var replenishment_weight: float = 1.0
@export var allow_initial: bool = true
@export var allow_replenishment: bool = true
@export var is_indoor: bool = false
@export var is_reachable: bool = true
@export var environment_tags: Array[StringName] = []

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

func allows_phase(phase: StringName) -> bool:
	if not is_reachable:
		return false
	return allow_initial if phase == &"initial" else allow_replenishment

func weight_for_phase(phase: StringName) -> float:
	if not allows_phase(phase):
		return 0.0
	var phase_weight := initial_weight if phase == &"initial" else replenishment_weight
	return maxf(phase_weight * selection_weight, 0.0)
