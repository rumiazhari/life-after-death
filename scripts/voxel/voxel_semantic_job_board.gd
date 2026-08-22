class_name VoxelSemanticJobBoard
extends RefCounted

var world_data
var _claims: Dictionary = {} # stable object id -> survivor id


func configure(data) -> void:
	world_data = data


func available_scavenge_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	if world_data == null:
		return result
	for stable_id in world_data.stable_objects:
		var record: Dictionary = world_data.stable_objects[stable_id]
		if record.get("kind", &"") != &"scavenge_point" or _claims.has(stable_id):
			continue
		if int((record.get("state", {}) as Dictionary).get("stock", 0)) > 0:
			result.append(StringName(stable_id))
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return result


func claim(stable_id: StringName, survivor_id: int) -> bool:
	if survivor_id <= 0 or _claims.has(stable_id) or stable_id not in available_scavenge_ids():
		return false
	_claims[stable_id] = survivor_id
	return true


func release_survivor(survivor_id: int) -> void:
	for stable_id in _claims.keys():
		if int(_claims[stable_id]) == survivor_id:
			_claims.erase(stable_id)


func claimed_by(stable_id: StringName) -> int:
	return int(_claims.get(stable_id, 0))


func metrics() -> Dictionary:
	return {
		"available": available_scavenge_ids().size(),
		"reserved": _claims.size(),
	}


func harvest(stable_id: StringName, survivor_id: int, destination: Inventory) -> Dictionary:
	if destination == null or claimed_by(stable_id) != survivor_id:
		return {}
	var record: Dictionary = world_data.get_stable_object(stable_id)
	var state: Dictionary = record.get("state", {})
	var stock := int(state.get("stock", 0))
	var requested := mini(stock, int(state.get("yield", 0)))
	var item_id := StringName(state.get("item_id", &""))
	var added := destination.add_item(item_id, requested)
	if added <= 0:
		return {}
	state["stock"] = stock - added
	WorldState.set_prop_state_flag(stable_id, &"remaining_stock", stock - added)
	world_data.set_stable_object_state(stable_id, state)
	_claims.erase(stable_id)
	return {item_id: added}
