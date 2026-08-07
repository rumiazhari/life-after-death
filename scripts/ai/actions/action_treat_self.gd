class_name ActionTreatSelf
extends UtilityAction
## Consumes one carried medical-supplies unit to heal a minor injury and
## reduce infection exposure. Like Eat/Drink, fetching medical supplies is
## ActionRetrieveSupplies's job, not this one's.

const ITEM_ID := &"medical_supplies"
const HEALTH_THRESHOLD_RATIO := 0.75 ## worth treating once below 75% health

func _init() -> void:
	action_name = &"treat_self"
	interrupt_cost = 0.2

func score(ai: SurvivorAI) -> float:
	if ai.survivor.carried_inventory.get_count(ITEM_ID) <= 0:
		return 0.0
	var missing_ratio: float = 1.0 - (ai.data.health / maxf(ai.data.max_health, 1.0))
	if ai.data.health >= ai.data.max_health * HEALTH_THRESHOLD_RATIO and ai.data.infection_exposure < 20.0:
		return 0.0
	return clampf(missing_ratio * 1.5 + ai.data.infection_exposure / 100.0, 0.0, 1.4)

func tick(ai: SurvivorAI, delta: float) -> bool:
	ai.survivor.stop_moving(delta)
	var inv: Inventory = ai.survivor.carried_inventory
	if inv.get_count(ITEM_ID) > 0 and inv.remove_item(ITEM_ID, 1):
		var item: ItemData = ItemDatabase.get_item(ITEM_ID)
		var restore: float = item.restore_amount if item else 25.0
		ai.survivor.health_component.heal(restore)
		ai.data.infection_exposure = maxf(ai.data.infection_exposure - restore, 0.0)
	return true
