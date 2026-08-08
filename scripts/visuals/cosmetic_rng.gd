extends Node
## Autoload "CosmeticRng". The one shared random stream for purely
## cosmetic/visual choices (zombie visual-variant selection, blood-decal
## texture/rotation pick, and any future decorative variety) --
## deliberately never touched by gameplay code (spawn positions, AI
## timing, combat, simulation). Kept as a single dedicated
## RandomNumberGenerator, never Godot's implicit global randf()/randi(),
## so toggling or reordering visual effects can never perturb a
## gameplay RNG sequence, and vice versa. See Zombie._gameplay_rng /
## SpawnManager._gameplay_rng for the gameplay-side counterparts.

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)

func randf() -> float:
	return _rng.randf()

func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)
