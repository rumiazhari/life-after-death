class_name ActionEat
extends UtilityAction
## Consumes one carried food ration to reduce hunger. Deliberately does not
## fetch food itself (that's ActionRetrieveSupplies) -- if nothing is
## carried this scores 0 and the fetch action takes over, then the next
## reconsideration hands back to Eat once supplies are on hand.

const ITEM_ID := &"food_ration"
const HUNGER_THRESHOLD := 15.0

func _init() -> void:
	action_name = &"eat"
	interrupt_cost = 0.15

func score(ai: SurvivorAI) -> float:
	if ai.survivor.carried_inventory.get_count(ITEM_ID) <= 0:
		return 0.0
	return UtilityMath.urgency(ai.data.hunger, HUNGER_THRESHOLD) * 1.3

func tick(ai: SurvivorAI, delta: float) -> bool:
	ai.survivor.stop_moving(delta)
	var inv: Inventory = ai.survivor.carried_inventory
	if inv.get_count(ITEM_ID) > 0 and inv.remove_item(ITEM_ID, 1):
		var item: ItemData = ItemDatabase.get_item(ITEM_ID)
		var restore: float = item.restore_amount if item else 30.0
		ai.data.hunger = maxf(ai.data.hunger - restore, 0.0)
		ai.data.morale = clampf(ai.data.morale + 2.0, 0.0, 100.0)
	return true
