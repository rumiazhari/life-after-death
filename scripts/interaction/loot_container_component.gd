class_name LootContainerComponent
extends Node
## Real Inventory-backed loot container (shelves, fridges, medical
## cabinets, cars, dumpsters, ...). Contents live in
## WorldState.prop_containers keyed by the stable `prop_id`, never in a
## per-instance Inventory this node owns itself -- that's what makes
## depletion (and non-duplication) survive a scene reload: the second time
## anything asks for this prop_id's Inventory, it gets back the SAME
## (already-depleted) instance instead of a fresh one reseeded from
## `starting_items`. Expects a sibling InteractableComponent under the same
## Area2D; forwards `interacted` into `_search`.

signal looted(actor: Node, items: Dictionary)

@export var prop_id: StringName = &""
@export var capacity_weight: float = 200.0
@export var starting_items: Dictionary = {} ## item_id (String) -> count

func _ready() -> void:
	var interactable: InteractableComponent = get_parent().get_node_or_null("InteractableComponent")
	if interactable:
		interactable.interacted.connect(_search)
		interactable.interact_label = "Search"

func get_inventory() -> Inventory:
	return WorldState.get_or_create_prop_container(prop_id, capacity_weight, starting_items)

func is_depleted() -> bool:
	return get_inventory().is_empty()

func _search(actor: Node) -> void:
	if not ("carried_inventory" in actor):
		return
	var inv: Inventory = get_inventory()
	if inv.is_empty():
		return
	var moved: Dictionary = inv.move_all_to(actor.carried_inventory)
	if not moved.is_empty():
		looted.emit(actor, moved)
		NoiseManager.emit_noise(actor.global_position, 4.0, &"search", actor)
