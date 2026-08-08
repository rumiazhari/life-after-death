class_name SalvageableComponent
extends Node
## Turns a prop into exactly `material_yield` units of `materials`, with
## exact conservation across partial pickups: a salvage attempt transfers
## only what currently fits in the actor's carried_inventory and keeps the
## unclaimed remainder on the prop rather than destroying it. Persisted via
## WorldState.prop_states[prop_id]["remaining_yield"] (never local-only
## state), so partial progress survives a scene reload exactly like the
## old one-shot "salvaged" flag did. Disables the sibling
## InteractableComponent once remaining_yield reaches zero instead of
## tracking a separate "used" flag, so a fully-depleted prop simply stops
## appearing as an interaction candidate at all -- a partially-salvaged one
## stays interactable so the rest can be collected later (e.g. once the
## actor has free capacity).

signal salvaged(actor: Node, amount: int)

@export var prop_id: StringName = &""
@export var material_yield: int = 3

var _interactable: InteractableComponent

func _ready() -> void:
	_interactable = get_parent().get_node_or_null("InteractableComponent")
	if _interactable == null:
		return
	_interactable.interacted.connect(_on_interacted)
	_interactable.interact_label = "Salvage"
	if remaining_yield() <= 0:
		_interactable.enabled = false

## Units of `materials` this prop still has to give -- WorldState-persisted,
## defaulting to the full material_yield the first time this prop_id is
## ever queried.
func remaining_yield() -> int:
	return WorldState.get_prop_state_flag(prop_id, &"remaining_yield", material_yield)

func _on_interacted(actor: Node) -> void:
	if not ("carried_inventory" in actor):
		return
	var remaining: int = remaining_yield()
	if remaining <= 0:
		return
	var take: int = mini(remaining, actor.carried_inventory.max_fit(&"materials"))
	if take <= 0:
		return # no free capacity right now -- change neither side
	var added: int = actor.carried_inventory.add_item(&"materials", take)
	if added <= 0:
		return
	var new_remaining: int = remaining - added
	WorldState.set_prop_state_flag(prop_id, &"remaining_yield", new_remaining)
	if new_remaining <= 0:
		_interactable.enabled = false
	salvaged.emit(actor, added)
	NoiseManager.emit_actor_noise(actor, actor.global_position, 5.0, &"salvage")
