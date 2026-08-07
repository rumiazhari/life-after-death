class_name ActionFight
extends UtilityAction
## Emergency reaction to a close zombie when the survivor is confident
## enough to engage: closes to weapon range and fires. A capable survivor
## picks this over Flee via the CONFIDENCE_CEILING split in ActionFlee.

const ENGAGE_RADIUS := 220.0
const FIRE_RANGE := 260.0
const CONFIDENCE_FLOOR := 0.4 ## fight if confidence is at or above this

func _init() -> void:
	action_name = &"fight"
	interrupt_cost = 0.1
	is_emergency = true

func score(ai: SurvivorAI) -> float:
	if ai.nearest_zombie == null or ai.nearest_zombie_distance > ENGAGE_RADIUS:
		return 0.0
	if UtilityMath.combat_confidence(ai.data) < CONFIDENCE_FLOOR:
		return 0.0
	var closeness: float = 1.0 - UtilityMath.distance_cost(ai.nearest_zombie_distance, ENGAGE_RADIUS)
	return 0.55 + closeness * 0.5

func tick(ai: SurvivorAI, delta: float) -> bool:
	if ai.nearest_zombie == null or not is_instance_valid(ai.nearest_zombie):
		return true
	var target_pos: Vector2 = (ai.nearest_zombie as Node2D).global_position
	var distance: float = ai.survivor.global_position.distance_to(target_pos)
	ai.reserved_target_description = "fighting %s" % ai.nearest_zombie.name
	if distance > FIRE_RANGE:
		ai.survivor.move_toward_point(target_pos, delta)
	else:
		ai.survivor.stop_moving(delta)
		ai.survivor.face_and_fire(target_pos)
	if ai.data.health <= ai.data.max_health * 0.2:
		return true
	return ai.nearest_zombie_distance > ENGAGE_RADIUS * 1.4
