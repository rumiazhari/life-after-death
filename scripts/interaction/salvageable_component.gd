class_name SalvageableComponent
extends Node
## Turns a prop into a fixed amount of `materials` exactly once. Persisted
## via WorldState.prop_states[prop_id]["salvaged"] (never local-only state),
## so it can't be salvaged twice even across a scene reload. Disables the
## sibling InteractableComponent once spent instead of tracking its own
## separate "used" flag, so a depleted salvage prop simply stops appearing
## as an interaction candidate at all.

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
	if WorldState.get_prop_state_flag(prop_id, &"salvaged", false):
		_interactable.enabled = false

func _on_interacted(actor: Node) -> void:
	if not ("carried_inventory" in actor):
		return
	var added: int = actor.carried_inventory.add_item(&"materials", material_yield)
	WorldState.set_prop_state_flag(prop_id, &"salvaged", true)
	_interactable.enabled = false
	salvaged.emit(actor, added)
	NoiseManager.emit_noise(actor.global_position, 5.0, &"salvage", actor)
