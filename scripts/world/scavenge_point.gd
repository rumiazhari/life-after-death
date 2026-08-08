class_name ScavengePoint
extends Node2D
## A nearby scavenging location. Depletes as survivors scavenge it and frees
## itself when empty -- SettlementJobBoard jobs targeting it then fail
## target validation and get cancelled automatically instead of needing a
## separate "is this point still good" check.

@export var item_id: StringName = &"materials"
@export var yield_per_scavenge: int = 3
@export var remaining_stock: int = 9
@export var scavenge_duration: float = 2.5 ## seconds of standing here to work the job
## Rough danger rating (0..100) folded into utility risk scoring -- higher
## for points further from the settlement or historically zombie-heavy.
@export var danger: float = 20.0

func _ready() -> void:
	add_to_group("scavenge_point")

func is_depleted() -> bool:
	return remaining_stock <= 0

## Removes up to one yield's worth of stock, capped at `max_amount` (the
## caller's carrying capacity, computed *before* calling this), and returns
## how much was actually removed. Capacity-aware by construction: excess
## stock the caller can't accept is left at the point rather than being
## removed and silently discarded, and max_amount == 0 removes nothing.
## Frees the node once emptied.
func harvest(max_amount: int) -> int:
	var amount: int = mini(mini(yield_per_scavenge, remaining_stock), max_amount)
	if amount <= 0:
		return 0
	remaining_stock -= amount
	if remaining_stock <= 0:
		call_deferred("queue_free")
	return amount

## Atomically harvests directly into `destination`: either the whole
## capacity-limited amount moves, or nothing does. Replaces the old
## harvest(max_fit)-then-add_item() two-step, where a rounding mismatch
## between max_fit()'s and add_item()'s capacity formulas could round-trip
## lose a unit (removed here, silently not accepted there) for certain
## fractional item weights. `destination.max_fit()` and `destination.add_item()`
## now share one formula (see Inventory._fit_count()) and nothing else
## touches `destination`'s weight state between the two calls here, so
## add_item() is guaranteed to accept exactly what was harvested.
func harvest_into(destination: Inventory) -> int:
	var potential: int = mini(yield_per_scavenge, remaining_stock)
	if potential <= 0:
		return 0
	var take: int = mini(potential, destination.max_fit(item_id))
	if take <= 0:
		return 0
	var harvested: int = harvest(take)
	return destination.add_item(item_id, harvested)
