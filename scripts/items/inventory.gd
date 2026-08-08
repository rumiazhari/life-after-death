class_name Inventory
extends RefCounted
## Stackable, weight-limited, reservation-aware item container. Used both
## for a survivor's carried items and for settlement storage containers --
## the same class, so hauling between them is symmetric.
##
## Reservations let a survivor "claim" an item or a stack before actually
## walking over to fetch it, so two survivors never both commit to the same
## single food item (see SettlementJobBoard). A reservation only blocks
## *other* claims; the items stay put until confirm_reserved_transfer()
## (or the direct remove_item path for self-consumption) actually moves
## them, and that move + the matching reservation cleanup happen in one
## call so items can never be duplicated or lost mid-transfer.

signal inventory_changed(item_id: StringName)

## 0 or less = unlimited capacity.
var capacity_weight: float = 0.0

var _counts: Dictionary = {} ## StringName -> int
var _reserved: Dictionary = {} ## StringName -> int (sum of live reservations)
var _reservations: Dictionary = {} ## int reservation_id -> {item_id, amount}
var _next_reservation_id: int = 1

func _init(weight_capacity: float = 0.0) -> void:
	capacity_weight = weight_capacity

func get_count(item_id: StringName) -> int:
	return _counts.get(item_id, 0)

func get_reserved(item_id: StringName) -> int:
	return _reserved.get(item_id, 0)

## Count not already claimed by a reservation -- what a new claim can see.
func get_available(item_id: StringName) -> int:
	return get_count(item_id) - get_reserved(item_id)

func has_available(item_id: StringName, amount: int = 1) -> bool:
	return get_available(item_id) >= amount

func total_weight() -> float:
	var total: float = 0.0
	for item_id in _counts:
		var item: ItemData = ItemDatabase.get_item(item_id)
		total += _counts[item_id] * (item.weight_per_unit if item else 1.0)
	return total

func can_fit(item_id: StringName, amount: int) -> bool:
	if amount <= 0:
		return true
	if capacity_weight <= 0.0:
		return true
	var item: ItemData = ItemDatabase.get_item(item_id)
	var unit_weight: float = item.weight_per_unit if item else 1.0
	return total_weight() + amount * unit_weight <= capacity_weight + 0.0001

## How many whole units of item_id would currently fit given free weight
## capacity, without mutating anything. Lets a caller (e.g. a capacity-aware
## harvest) decide how much to remove from a source *before* removing it,
## instead of removing a fixed amount and discovering afterward that some
## of it didn't fit anywhere.
const UNLIMITED_FIT := 1_000_000_000

func max_fit(item_id: StringName) -> int:
	if capacity_weight <= 0.0:
		return UNLIMITED_FIT
	var item: ItemData = ItemDatabase.get_item(item_id)
	var unit_weight: float = item.weight_per_unit if item else 1.0
	if unit_weight <= 0.0:
		return UNLIMITED_FIT
	var free_weight: float = maxf(capacity_weight - total_weight(), 0.0)
	return int(floor((free_weight + 0.0001) / unit_weight))

## Adds as much as fits; returns the amount actually added.
func add_item(item_id: StringName, amount: int) -> int:
	if amount <= 0:
		return 0
	var added: int = amount
	if capacity_weight > 0.0:
		var item: ItemData = ItemDatabase.get_item(item_id)
		var unit_weight: float = item.weight_per_unit if item else 1.0
		if unit_weight > 0.0:
			var free_weight: float = maxf(capacity_weight - total_weight(), 0.0)
			added = mini(amount, int(floor(free_weight / unit_weight)))
	if added <= 0:
		return 0
	_add_raw(item_id, added)
	inventory_changed.emit(item_id)
	return added

## Direct removal of unreserved units (e.g. self-consumption). Fails if not
## enough *available* (unreserved) stock exists.
func remove_item(item_id: StringName, amount: int) -> bool:
	if amount <= 0 or not has_available(item_id, amount):
		return false
	_remove_raw(item_id, amount)
	inventory_changed.emit(item_id)
	return true

## Claims `amount` of `item_id` without moving it yet. Returns a
## reservation id (>0) on success, 0 if not enough unreserved stock exists.
func reserve(item_id: StringName, amount: int) -> int:
	if amount <= 0 or not has_available(item_id, amount):
		return 0
	var reservation_id: int = _next_reservation_id
	_next_reservation_id += 1
	_reserved[item_id] = get_reserved(item_id) + amount
	_reservations[reservation_id] = {"item_id": item_id, "amount": amount}
	return reservation_id

func has_reservation(reservation_id: int) -> bool:
	return _reservations.has(reservation_id)

func reservation_count() -> int:
	return _reservations.size()

## Drops a claim without moving anything. Safe to call on an id that no
## longer exists (already confirmed/released) -- used when a survivor dies,
## is interrupted, or its job is cancelled.
func release_reservation(reservation_id: int) -> void:
	if not _reservations.has(reservation_id):
		return
	var entry: Dictionary = _reservations[reservation_id]
	var item_id: StringName = entry["item_id"]
	_reserved[item_id] = maxi(get_reserved(item_id) - int(entry["amount"]), 0)
	if _reserved[item_id] <= 0:
		_reserved.erase(item_id)
	_reservations.erase(reservation_id)

## Moves a previously reserved stack from this inventory into `to`, in one
## atomic step: either the whole amount moves and the reservation clears, or
## nothing changes. Returns false (reservation left releasable by the
## caller) if the destination can no longer fit it.
func confirm_reserved_transfer(reservation_id: int, to: Inventory) -> bool:
	if not _reservations.has(reservation_id):
		return false
	var entry: Dictionary = _reservations[reservation_id]
	var item_id: StringName = entry["item_id"]
	var amount: int = int(entry["amount"])
	if get_count(item_id) < amount:
		release_reservation(reservation_id)
		return false
	if not to.can_fit(item_id, amount):
		return false
	_remove_raw(item_id, amount)
	_reserved[item_id] = maxi(get_reserved(item_id) - amount, 0)
	if _reserved[item_id] <= 0:
		_reserved.erase(item_id)
	_reservations.erase(reservation_id)
	to._add_raw(item_id, amount)
	inventory_changed.emit(item_id)
	to.inventory_changed.emit(item_id)
	return true

## Unconditional atomic move not tied to a prior reservation (e.g. the
## player manually depositing items). Fails clean -- either both sides
## update or neither does.
static func transfer_item(from: Inventory, to: Inventory, item_id: StringName, amount: int) -> bool:
	if amount <= 0 or not from.has_available(item_id, amount) or not to.can_fit(item_id, amount):
		return false
	from._remove_raw(item_id, amount)
	to._add_raw(item_id, amount)
	from.inventory_changed.emit(item_id)
	to.inventory_changed.emit(item_id)
	return true

func to_dict() -> Dictionary:
	return {
		"capacity_weight": capacity_weight,
		"counts": _counts.duplicate(),
	}

func _add_raw(item_id: StringName, amount: int) -> void:
	_counts[item_id] = get_count(item_id) + amount

func _remove_raw(item_id: StringName, amount: int) -> void:
	var remaining: int = get_count(item_id) - amount
	if remaining > 0:
		_counts[item_id] = remaining
	else:
		_counts.erase(item_id)
