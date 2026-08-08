class_name Room
extends Area2D
## One room within a building -- an Area2D whose bounds define "the player
## is in this room." `room_id`/`building_id` are stable authored
## identifiers (see docs/building_system.md for the naming convention).
## Only monitors the Player layer: room-reveal is a presentation concern
## for the player's own view, not something survivors/zombies trigger.

const LAYER_PLAYER := 2

@export var room_id: StringName = &""
@export var building_id: StringName = &""
## Doors bordering this room (assigned by the owning building script/scene).
## Two rooms are considered visually connected exactly when they share one
## of these AND it's currently open -- see BuildingVisibilityController.
var doors: Array[Door] = []

func _ready() -> void:
	add_to_group("rooms")
	collision_layer = 0
	collision_mask = LAYER_PLAYER
	monitoring = true
