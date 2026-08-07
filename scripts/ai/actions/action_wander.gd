class_name ActionWander
extends UtilityAction
## Low-priority filler: walk to a random nearby point and stop. Scores just
## above Idle so a survivor with no real need looks alive instead of
## statue-still, but any genuine need trivially outscores it.

@export var wander_radius: float = 180.0

var _target: Vector2 = Vector2.ZERO
var _has_target: bool = false

func _init() -> void:
	action_name = &"wander"
	interrupt_cost = 0.0

func score(_ai: SurvivorAI) -> float:
	return 0.1

func enter(ai: SurvivorAI) -> void:
	_pick_point(ai)

func tick(ai: SurvivorAI, delta: float) -> bool:
	if not _has_target:
		_pick_point(ai)
	var arrived: bool = ai.survivor.move_toward_point(_target, delta)
	ai.reserved_target_description = "wander -> %s" % _target
	return arrived

func exit(_ai: SurvivorAI) -> void:
	_has_target = false

func _pick_point(ai: SurvivorAI) -> void:
	var origin: Vector2 = ai.survivor.global_position
	var angle: float = randf() * TAU
	var radius: float = randf() * wander_radius
	_target = origin + Vector2.RIGHT.rotated(angle) * radius
	_has_target = true
