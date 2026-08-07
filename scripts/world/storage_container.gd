class_name StorageContainer
extends Node2D
## A settlement storage point (general / food / water / medical). Owns an
## Inventory registered with WorldState under a stable container id --
## Survivor and Player both read/write through that same Inventory instance,
## so NPC and player storage access share one set of rules.

## "general" / "food" / "water" / "medical" -- matched by
## SettlementJobBoard._refresh_haul_jobs() and by AI actions looking for a
## place to deposit/withdraw a given item category.
@export var storage_role: String = "general"
@export var capacity_weight: float = 500.0
## item_id (string) -> starting count, authored per-instance in the scene.
@export var starting_items: Dictionary = {}

var container_id: int = 0
var _inventory: Inventory

func _ready() -> void:
	add_to_group("storage_container")
	_inventory = Inventory.new(capacity_weight)
	for item_id in starting_items:
		_inventory.add_item(StringName(item_id), int(starting_items[item_id]))
	container_id = WorldState.register_container(_inventory)

func get_inventory() -> Inventory:
	return _inventory
