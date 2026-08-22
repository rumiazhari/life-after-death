class_name VoxelSettlementRuntime
extends RefCounted

var world_data
var _claims: Dictionary = {} # service stable id -> survivor id
var _storage_reservations: Dictionary = {} # survivor id -> {reservation_id, role}


func configure(data) -> void:
	world_data = data


func service_ids(kind: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	if world_data == null:
		return result
	for stable_id in world_data.stable_objects:
		if world_data.stable_objects[stable_id].get("kind", &"") == kind:
			result.append(StringName(stable_id))
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return result


func first_service(kind: StringName) -> Dictionary:
	var ids := service_ids(kind)
	return world_data.get_stable_object(ids[0]) if not ids.is_empty() else {}


func first_service_id(kind: StringName) -> StringName:
	var ids := service_ids(kind)
	return ids[0] if not ids.is_empty() else &""


func claim_service(stable_id: StringName, survivor_id: int) -> bool:
	if stable_id == &"" or survivor_id <= 0:
		return false
	if _claims.has(stable_id) and int(_claims[stable_id]) != survivor_id:
		return false
	_claims[stable_id] = survivor_id
	return true


func release_survivor(survivor_id: int) -> void:
	for stable_id in _claims.keys():
		if int(_claims[stable_id]) == survivor_id:
			_claims.erase(stable_id)
	if _storage_reservations.has(survivor_id):
		var entry: Dictionary = _storage_reservations[survivor_id]
		var inventory := storage_inventory(StringName(entry["role"]))
		if inventory != null:
			inventory.release_reservation(int(entry["reservation_id"]))
		_storage_reservations.erase(survivor_id)


func claimed_by(stable_id: StringName) -> int:
	return int(_claims.get(stable_id, 0))


func storage_inventory(role: StringName = &"general") -> Inventory:
	var stable_id := storage_id(role)
	if stable_id == &"":
		return null
	var state: Dictionary = world_data.get_stable_object(stable_id).get("state", {})
	return WorldState.get_or_create_prop_container(stable_id, float(state.get("capacity", 1000.0)), {})


func storage_id(role: StringName) -> StringName:
	for stable_id in service_ids(&"settlement_storage"):
		if StringName(world_data.get_stable_object(stable_id).get("state", {}).get("role", &"general")) == role:
			return stable_id
	return &""


func storage_record(role: StringName) -> Dictionary:
	var stable_id := storage_id(role)
	return world_data.get_stable_object(stable_id) if stable_id != &"" else {}


func inventory_for_item(item_id: StringName) -> Inventory:
	return storage_inventory(_role_for_item(item_id))


func record_for_item(item_id: StringName) -> Dictionary:
	return storage_record(_role_for_item(item_id))


func deposit_all(from: Inventory) -> Dictionary:
	var destination := storage_inventory()
	return from.move_all_to(destination) if from != null and destination != null else {}


func deposit_item(from: Inventory, item_id: StringName, amount_requested: int = -1) -> int:
	var destination := storage_inventory(_role_for_item(item_id))
	if from == null or destination == null:
		return 0
	var available := from.get_available(item_id)
	var amount := mini(available, amount_requested) if amount_requested >= 0 else available
	var moving := mini(amount, destination.max_fit(item_id))
	return moving if moving > 0 and Inventory.transfer_item(from, destination, item_id, moving) else 0


func reserve_item(survivor_id: int, item_id: StringName, amount: int = 1) -> bool:
	if _storage_reservations.has(survivor_id):
		return false
	var role := _role_for_item(item_id)
	var inventory := storage_inventory(role)
	if inventory == null:
		return false
	var reservation_id := inventory.reserve(item_id, amount)
	if reservation_id == 0:
		return false
	_storage_reservations[survivor_id] = {"reservation_id": reservation_id, "role": role}
	return true


func confirm_reserved_item(survivor_id: int, destination: Inventory) -> bool:
	if not _storage_reservations.has(survivor_id):
		return false
	var entry: Dictionary = _storage_reservations[survivor_id]
	var inventory := storage_inventory(StringName(entry["role"]))
	var reservation_id := int(entry["reservation_id"])
	if inventory == null or not inventory.confirm_reserved_transfer(reservation_id, destination):
		return false
	_storage_reservations.erase(survivor_id)
	return true


func _role_for_item(item_id: StringName) -> StringName:
	var item: ItemData = ItemDatabase.get_item(item_id)
	if item == null:
		return &"general"
	match item.category:
		ItemData.Category.FOOD: return &"food"
		ItemData.Category.WATER: return &"water"
		ItemData.Category.MEDICAL: return &"medical"
		_: return &"general"
