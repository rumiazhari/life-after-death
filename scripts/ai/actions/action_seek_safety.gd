class_name ActionSeekSafety
extends UtilityAction
## Retreats toward the settlement interior when settlement danger or the
## survivor's own fear is elevated but no single zombie is close enough yet
## to trigger the harder Flee reaction. Scores itself to 0 once inside the
## settlement's safe radius, so it naturally hands off to Guard/Idle/Sleep.

const DANGER_THRESHOLD := 30.0
const FEAR_THRESHOLD := 45.0

func _init() -> void:
	action_name = &"seek_safety"
	interrupt_cost = 0.1

func score(ai: SurvivorAI) -> float:
	if ai.settlement == null:
		return 0.0
	if ai.settlement.is_position_safe(ai.survivor.global_position):
		return 0.0
	var danger_score: float = UtilityMath.urgency(ai.settlement.danger_level(), DANGER_THRESHOLD)
	var fear_score: float = UtilityMath.urgency(ai.data.fear, FEAR_THRESHOLD)
	return maxf(danger_score, fear_score) * 0.9

func can_start(ai: SurvivorAI) -> bool:
	return ai.settlement != null

func tick(ai: SurvivorAI, delta: float) -> bool:
	ai.reserved_target_description = "settlement safe zone"
	return ai.survivor.move_toward_point(ai.settlement.global_position, delta)
