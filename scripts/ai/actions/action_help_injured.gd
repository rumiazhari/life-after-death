class_name ActionHelpInjured
extends UtilityAction
## Finds another injured settlement member and spends one carried
## medical-supplies unit healing them. Uses Survivor's lightweight
## helper-claim lock (not the settlement job board -- this is a same-
## settlement 1:1 claim, not shared multi-worker capacity) so at most one
## helper commits to a given patient.

const HEALTH_THRESHOLD_RATIO := 0.55
const SEARCH_RADIUS := 700.0

var _target: Survivor = null

func _init() -> void:
	action_name = &"help_injured"
	interrupt_cost = 0.2

func score(ai: SurvivorAI) -> float:
	if ai.survivor.carried_inventory.get_count(&"medical_supplies") <= 0:
		return 0.0
	var found := _find_target(ai)
	if found == null:
		return 0.0
	var missing_ratio: float = 1.0 - found.data.health / maxf(found.data.max_health, 1.0)
	var social: float = ai.data.personality.get("social", 0.0)
	var distance: float = ai.survivor.global_position.distance_to(found.global_position)
	var cost: float = UtilityMath.distance_cost(distance, SEARCH_RADIUS)
	return clampf(missing_ratio * (1.0 + social * 0.3) - cost * 0.3, 0.0, 1.3)

func enter(ai: SurvivorAI) -> void:
	var found := _find_target(ai)
	if found and found.try_claim_helper(ai.data.id):
		_target = found

func tick(ai: SurvivorAI, delta: float) -> bool:
	if _target == null or not is_instance_valid(_target) or _target.is_dead:
		return true
	if _target.data.health >= _target.data.max_health * HEALTH_THRESHOLD_RATIO:
		return true
	ai.reserved_target_description = "helping %s" % _target.data.survivor_name
	var arrived: bool = ai.survivor.move_toward_point(_target.global_position, delta)
	if not arrived:
		return false
	var inv: Inventory = ai.survivor.carried_inventory
	if inv.get_count(&"medical_supplies") <= 0:
		return true
	inv.remove_item(&"medical_supplies", 1)
	var item: ItemData = ItemDatabase.get_item(&"medical_supplies")
	var restore: float = item.restore_amount if item else 25.0
	_target.health_component.heal(restore)
	_target.data.infection_exposure = maxf(_target.data.infection_exposure - restore, 0.0)
	_target.data.morale = clampf(_target.data.morale + 5.0, 0.0, 100.0)
	return true

func exit(ai: SurvivorAI) -> void:
	if _target and is_instance_valid(_target) and ai.data:
		_target.release_helper(ai.data.id)
	_target = null

func _find_target(ai: SurvivorAI) -> Survivor:
	var best: Survivor = null
	var best_missing: float = 0.0
	for node in ai.survivor.get_tree().get_nodes_in_group("survivors"):
		var candidate: Survivor = node as Survivor
		if candidate == null or candidate == ai.survivor or candidate.is_dead:
			continue
		if candidate.data == null or candidate.data.health >= candidate.data.max_health * HEALTH_THRESHOLD_RATIO:
			continue
		if candidate.is_claimed_for_help() and candidate != _target:
			continue
		var distance: float = ai.survivor.global_position.distance_to(candidate.global_position)
		if distance > SEARCH_RADIUS:
			continue
		var missing: float = candidate.data.max_health - candidate.data.health
		if missing > best_missing:
			best_missing = missing
			best = candidate
	return best
