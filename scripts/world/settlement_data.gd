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

## --- generic survivor-base occupancy state (decoupled from geometry) ---
## Stable id of the generated ProceduralCityGenerator building this group
## has claimed as its base. Empty when no ordinary building is occupied.
@export var building_id: StringName = &""
## Archetype of the claimed building (apartment/store/restaurant/...).
## The building itself stays a completely normal generated building; this is
## purely descriptive occupancy state.
@export var base_type: StringName = &""
@export var security_level: int = 0
@export var barricade_level: int = 0
@export var stored_resources: Dictionary = {}
@export var power_state: bool = false
@export var water_state: bool = false

func to_dict() -> Dictionary:
	return {
		"id": id,
		"settlement_name": settlement_name,
		"danger_level": danger_level,
		"member_ids": member_ids.duplicate(),
		"storage_container_ids": storage_container_ids.duplicate(),
		"building_id": building_id,
		"base_type": base_type,
		"security_level": security_level,
		"barricade_level": barricade_level,
		"stored_resources": stored_resources.duplicate(),
		"power_state": power_state,
		"water_state": water_state,
	}
