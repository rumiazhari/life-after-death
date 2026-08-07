class_name SettlementData
extends Resource
## Persistent, serializable model for one settlement. Owned by WorldState;
## the `Settlement` scene node (scripts/world/settlement.gd) is the runtime
## presentation of this data, not the other way around.

@export var id: int = 0
@export var settlement_name: String = "Safehouse"
@export var danger_level: float = 0.0 ## 0 = safe, 100 = under siege
## Survivor IDs currently belonging to this settlement.
@export var member_ids: Array[int] = []
## Container IDs (see Inventory/WorldState) keyed by role, e.g.
## "general" / "food" / "water" / "medical".
@export var storage_container_ids: Dictionary = {}

func to_dict() -> Dictionary:
	return {
		"id": id,
		"settlement_name": settlement_name,
		"danger_level": danger_level,
		"member_ids": member_ids.duplicate(),
		"storage_container_ids": storage_container_ids.duplicate(),
	}
