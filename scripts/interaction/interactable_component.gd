class_name InteractableComponent
extends Node
## Declares that its parent (an Area2D on the Interactable collision layer)
## is something PlayerInteractor can act on. One component = one
## interaction verb; a prop with multiple verbs (e.g. a searchable AND
## salvageable crate) composes multiple sibling *Component nodes under the
## same Area2D rather than branching inside one big script -- see
## docs/interaction_system.md.

signal interacted(actor: Node)

@export var interact_label: String = "Interact"
@export var enabled: bool = true

func can_interact(_actor: Node) -> bool:
	return enabled

## PlayerInteractor calls this exactly once per interact request; it never
## calls it directly on can_interact() == false.
func interact(actor: Node) -> void:
	interacted.emit(actor)
