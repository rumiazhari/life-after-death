class_name ActionFlee
extends UtilityAction
## Emergency reaction to a close zombie when the survivor's combat
## confidence is too low to fight it. Runs directly away from the nearest
## zombie, biased toward the settlement when one is known.

const ENGAGE_RADIUS := 170.0
const CONFIDENCE_CEILING := 0.4 ## flee if confidence is below this

func _init() -> void:
	action_name = &"flee"
	interrupt_cost = 0.0
	is_emergency = true

func score(ai: SurvivorAI) -> float:
	if ai.nearest_zombie == null or ai.nearest_zombie_distance > ENGAGE_RADIUS:
		return 0.0
	if UtilityMath.combat_confidence(ai.data) >= CONFIDENCE_CEILING:
		return 0.0
	var closeness: float = 1.0 - UtilityMath.distance_cost(ai.nearest_zombie_distance, ENGAGE_RADIUS)
	return 0.6 + closeness * 0.6

func tick(ai: SurvivorAI, delta: float) -> bool:
	ai.data.fear = clampf(ai.data.fear + 25.0 * delta, 0.0, 100.0)
	if ai.nearest_zombie == null or not is_instance_valid(ai.nearest_zombie):
		return true
	var away: Vector2 = (ai.survivor.global_position - ai.nearest_zombie.global_position)
	if away.length() < 0.01:
		away = Vector2.RIGHT
	away = away.normalized()
	if ai.settlement:
		var to_home: Vector2 = (ai.settlement.global_position - ai.survivor.global_position).normalized()
		away = (away + to_home * 0.6).normalized()
	var flee_point: Vector2 = ai.survivor.global_position + away * 96.0
	ai.reserved_target_description = "fleeing from %s" % ai.nearest_zombie.name
	ai.survivor.move_toward_point(flee_point, delta)
	return ai.nearest_zombie_distance > ENGAGE_RADIUS * 1.6
