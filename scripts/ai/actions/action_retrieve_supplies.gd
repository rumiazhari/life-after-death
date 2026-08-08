class_name ActionRetrieveSupplies
extends UtilityAction
## Proactively fetches food, water, or medical supplies from the matching
## settlement storage into the survivor's own carried inventory whenever
## that need is building and nothing of that kind is already carried. Eat/
## Drink/TreatSelf then consume what gets fetched here on a later tick.
##
## Reserves the stack at the source container the moment it commits
## (enter()), so two survivors picking this action in the same
## reconsideration window can't both walk off with the same last ration.

const HUNGER_THRESHOLD := 20.0
const THIRST_THRESHOLD := 20.0

var _target_container: StorageContainer = null
var _item_id: StringName = &""
var _reservation_id: int = 0

func _init() -> void:
	action_name = &"retrieve_supplies"
	interrupt_cost = 0.1

func can_start(ai: SurvivorAI) -> bool:
	return ai.settlement != null

func score(ai: SurvivorAI) -> float:
	var best: Dictionary = _select(ai)
	if best.is_empty():
		return 0.0
	return float(best["urgency"]) * 0.95

func enter(ai: SurvivorAI) -> void:
	var best: Dictionary = _select(ai)
	if best.is_empty():
		return
	_target_container = ai.settlement.storage_containers.get(best["role"])
	if _target_container == null or not is_instance_valid(_target_container):
		_target_container = null
		return
	var inv: Inventory = _target_container.get_inventory()
	var amount: int = mini(int(best["amount"]), inv.get_available(best["item_id"]))
	if amount <= 0:
		_target_container = null
		return
	_item_id = best["item_id"]
	_reservation_id = inv.reserve(_item_id, amount)
	if _reservation_id == 0:
		_target_container = null

func tick(ai: SurvivorAI, delta: float) -> bool:
	if _target_container == null or not is_instance_valid(_target_container) or _reservation_id == 0:
		return true
	ai.reserved_target_description = "retrieve %s from %s storage" % [_item_id, _target_container.storage_role]
	var arrived: bool = ai.survivor.move_toward_point(_target_container.global_position, delta)
	if not arrived:
		return false
	var inv: Inventory = _target_container.get_inventory()
	if not inv.confirm_reserved_transfer(_reservation_id, ai.survivor.carried_inventory):
		# Either the source depleted out from under the reservation (which
		# confirm_reserved_transfer already released on our behalf) or the
		# survivor's own carried inventory is temporarily too full to accept
		# it (reservation deliberately left intact by confirm_reserved_transfer
		# in that case). Only stop -- and only then clear our local id -- once
		# the reservation is actually gone; otherwise keep it and retry next
		# tick so a full destination can never orphan it.
		if not inv.has_reservation(_reservation_id):
			_reservation_id = 0
			_target_container = null
			return true
		return false
	_reservation_id = 0
	_target_container = null
	return true

func exit(_ai: SurvivorAI) -> void:
	if _reservation_id != 0 and _target_container and is_instance_valid(_target_container):
		_target_container.get_inventory().release_reservation(_reservation_id)
	_reservation_id = 0
	_target_container = null

func _select(ai: SurvivorAI) -> Dictionary:
	if ai.settlement == null:
		return {}
	var carried: Inventory = ai.survivor.carried_inventory
	var candidates: Array[Dictionary] = []
	if carried.get_count(&"food_ration") == 0:
		var u: float = UtilityMath.urgency(ai.data.hunger, HUNGER_THRESHOLD)
		if u > 0.0:
			candidates.append({"item_id": &"food_ration", "role": "food", "urgency": u, "amount": 3})
	if carried.get_count(&"water_bottle") == 0:
		var u: float = UtilityMath.urgency(ai.data.thirst, THIRST_THRESHOLD)
		if u > 0.0:
			candidates.append({"item_id": &"water_bottle", "role": "water", "urgency": u, "amount": 3})
	if carried.get_count(&"medical_supplies") == 0:
		var missing_ratio: float = 1.0 - ai.data.health / maxf(ai.data.max_health, 1.0)
		if missing_ratio > 0.15 or ai.data.infection_exposure > 15.0:
			candidates.append({"item_id": &"medical_supplies", "role": "medical", "urgency": clampf(missing_ratio * 1.2, 0.0, 1.0), "amount": 1})
	var best: Dictionary = {}
	for candidate in candidates:
		var inv: Inventory = ai.settlement.get_inventory(candidate["role"])
		if inv == null or inv.get_available(candidate["item_id"]) <= 0:
			continue
		if best.is_empty() or candidate["urgency"] > best["urgency"]:
			best = candidate
	return best
