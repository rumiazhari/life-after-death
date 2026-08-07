class_name ActionDrink
extends UtilityAction
## Mirror of ActionEat for thirst/water_bottle -- see that file for why
## fetching is deliberately a separate action.

const ITEM_ID := &"water_bottle"
const THIRST_THRESHOLD := 15.0

func _init() -> void:
	action_name = &"drink"
	interrupt_cost = 0.15

func score(ai: SurvivorAI) -> float:
	if ai.survivor.carried_inventory.get_count(ITEM_ID) <= 0:
		return 0.0
	return UtilityMath.urgency(ai.data.thirst, THIRST_THRESHOLD) * 1.35

func tick(ai: SurvivorAI, delta: float) -> bool:
	ai.survivor.stop_moving(delta)
	var inv: Inventory = ai.survivor.carried_inventory
	if inv.get_count(ITEM_ID) > 0 and inv.remove_item(ITEM_ID, 1):
		var item: ItemData = ItemDatabase.get_item(ITEM_ID)
		var restore: float = item.restore_amount if item else 30.0
		ai.data.thirst = maxf(ai.data.thirst - restore, 0.0)
		ai.data.morale = clampf(ai.data.morale + 2.0, 0.0, 100.0)
	return true
