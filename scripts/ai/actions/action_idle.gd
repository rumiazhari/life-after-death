class_name ActionIdle
extends UtilityAction
## Do-nothing fallback. Always available with a tiny constant score so a
## survivor with no unmet need and nothing to do stands still rather than
## the decision loop having no candidate at all.

func _init() -> void:
	action_name = &"idle"
	interrupt_cost = 0.0

func score(_ai: SurvivorAI) -> float:
	return 0.05

func tick(_ai: SurvivorAI, delta: float) -> bool:
	_ai.survivor.stop_moving(delta)
	return false
