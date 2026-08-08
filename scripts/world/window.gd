class_name BuildingWindow
extends Node2D
## Always blocks movement. Vision blocking depends on authored state:
## intact glass lets the BuildingVisibilityController's room reveal see
## through it (also usable later as a reduced-detection sightline for
## zombie perception); boarded fully blocks vision like a wall. State is
## authored per-instance (no breaking/interaction gameplay yet -- see
## docs/interaction_system.md "Known limitations").

const INTACT_TEXTURE := preload("res://assets/pixel/props/window_intact.png")
const BOARDED_TEXTURE := preload("res://assets/pixel/props/window_boarded.png")

const LAYER_WORLD := 1
const LAYER_VISION := 32

@export var window_id: StringName = &""
@export var is_boarded: bool = false

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision_body: StaticBody2D = $CollisionBody

func _ready() -> void:
	add_to_group("windows")
	_sprite.texture = BOARDED_TEXTURE if is_boarded else INTACT_TEXTURE
	_collision_body.collision_layer = LAYER_WORLD | (LAYER_VISION if is_boarded else 0)
	_collision_body.collision_mask = 0

## Whether a raycast may pass through this window for room-reveal / vision
## purposes. Boarded windows never do; intact ones do.
func blocks_vision() -> bool:
	return is_boarded
