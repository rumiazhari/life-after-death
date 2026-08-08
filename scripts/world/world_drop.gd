class_name WorldDrop
extends RefCounted
## A persistent item drop left at a world position -- created when a
## survivor dies while carrying items, or when a haul delivery can't be
## completed anywhere else, so that cargo stays recoverable instead of
## being destroyed along with whatever created it. Pure data, like
## SurvivorData/SettlementData: WorldState is the source of truth. Nothing
## currently reads this back into gameplay (no looting mechanic exists in
## this slice) -- it exists so carried inventory is never simply discarded.

var id: int = 0
var inventory: Inventory
var position: Vector2 = Vector2.ZERO
## What produced this drop, for debugging/a future looting mechanic: the
## survivor whose death or stalled delivery created it (0 if unattributed).
var source_survivor_id: int = 0
## The StorageContainer id (and its storage_role, e.g. "food") that was
## permanently destroyed to produce this drop (0 / "" if not
## container-attributed -- a survivor-death or haul-stall drop instead).
var source_container_id: int = 0
var storage_role: String = ""
## Short cause tag ("death", "haul_stalled", "storage_destroyed", ...).
var reason: StringName = &""
var created_tick: int = 0

func to_dict() -> Dictionary:
	return {
		"id": id,
		"position": {"x": position.x, "y": position.y},
		"source_survivor_id": source_survivor_id,
		"source_container_id": source_container_id,
		"storage_role": storage_role,
		"reason": String(reason),
		"created_tick": created_tick,
		"inventory": inventory.to_dict() if inventory else {},
	}
