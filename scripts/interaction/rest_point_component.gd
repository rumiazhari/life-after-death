class_name RestPointComponent
extends Node
## Foundation for a future rest/sleep mechanic -- registers a use, does not
## simulate sleep time yet (explicitly out of scope for this phase).

signal rested(actor: Node)

@export var prop_id: StringName = &""

var last_used_tick: int = -1

func _ready() -> void:
	var interactable: InteractableComponent = get_parent().get_node_or_null("InteractableComponent")
	if interactable:
		interactable.interacted.connect(_on_interacted)
		interactable.interact_label = "Rest"

func _on_interacted(actor: Node) -> void:
	last_used_tick = SimulationClock.tick_count
	rested.emit(actor)
