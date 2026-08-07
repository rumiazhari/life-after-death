class_name ActionSleep
extends UtilityAction
## Claims a free sleep spot in the home settlement and rests there,
## recovering fatigue (and a little morale) until rested or interrupted.
## Only scores once the settlement is reasonably safe -- a survivor won't
## choose to lie down while danger is high, though an emergency (nearby
## zombie, critical health) can still interrupt an already-started nap.

const FATIGUE_THRESHOLD := 35.0
const RECOVERY_RATE := 9.0 ## fatigue points per second while resting
const DANGER_CEILING := 40.0

var _spot: SleepSpot = null

func _init() -> void:
	action_name = &"sleep"
	interrupt_cost = 0.2

func score(ai: SurvivorAI) -> float:
	if ai.settlement == null:
		return 0.0
	if ai.settlement.danger_level() > DANGER_CEILING:
		return 0.0
	if ai.settlement.get_free_sleep_spot(ai.data.id) == null:
		return 0.0
	return UtilityMath.urgency(ai.data.fatigue, FATIGUE_THRESHOLD) * 1.2

func can_start(ai: SurvivorAI) -> bool:
	return ai.settlement != null

func enter(ai: SurvivorAI) -> void:
	_spot = ai.settlement.get_free_sleep_spot(ai.data.id)
	if _spot and not _spot.try_occupy(ai.data.id):
		_spot = null ## lost a same-frame race to another survivor

func tick(ai: SurvivorAI, delta: float) -> bool:
	if _spot == null or not is_instance_valid(_spot):
		return true
	if ai.settlement.danger_level() > DANGER_CEILING + 20.0:
		return true
	var arrived: bool = ai.survivor.move_toward_point(_spot.global_position, delta)
	ai.reserved_target_description = "sleep spot %s" % _spot.name
	if not arrived:
		return false
	ai.data.fatigue = maxf(ai.data.fatigue - RECOVERY_RATE * delta, 0.0)
	ai.data.morale = clampf(ai.data.morale + 1.5 * delta, 0.0, 100.0)
	return ai.data.fatigue <= 5.0

func exit(ai: SurvivorAI) -> void:
	if _spot:
		_spot.vacate(ai.data.id)
	_spot = null
