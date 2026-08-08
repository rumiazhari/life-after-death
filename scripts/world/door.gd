class_name Door
extends Node2D
## Reusable interactable door. Closed by default: blocks movement (World
## layer) and vision (Vision layer); interacting toggles both, swaps the
## sprite, and emits a noise. Collision changes are driven purely by
## `is_open`, never by the visual swap alone, so a fade/animation glitch
## can never desync physical/vision blocking from what's drawn.
##
## `door_id` is a stable authored identifier (set per-instance in the
## owning building scene) -- persistent open/closed state is looked up and
## stored in WorldState.door_states[door_id], never inferred from this
## node's own transient state, so a scene reload restores exactly how the
## player left it (see docs/interaction_system.md).

const CLOSED_TEXTURE := preload("res://assets/pixel/props/door_closed.png")
const OPEN_TEXTURE := preload("res://assets/pixel/props/door_open.png")

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ZOMBIE := 4
const LAYER_SURVIVOR := 16
const LAYER_VISION := 32
const LAYER_INTERACTABLE := 64

@export var door_id: StringName = &""
@export var is_open: bool = false
@export var noise_loudness: float = 8.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision: CollisionShape2D = $CollisionBody/CollisionShape2D
@onready var _collision_body: StaticBody2D = $CollisionBody
## Exact door-footprint Area2D -- used ONLY to detect an actor physically
## standing on the door (refuses to close on top of them). Deliberately
## NOT on the Interactable layer and NOT what PlayerInteractor sees.
@onready var _block_check_area: Area2D = $InteractArea
## Larger reach Area2D (see docs/interaction_system.md "Reach vs footprint")
## -- what PlayerInteractor actually detects, sized so a 16px-radius actor
## can stand outside the door's own solid collision and still be within
## interaction range.
@onready var _interact_reach_area: Area2D = $InteractReachArea
@onready var _interactable: InteractableComponent = $InteractReachArea/InteractableComponent

## True while a body physically overlaps the door's own footprint -- closing
## on top of an actor is refused until it clears, so nothing gets stuck
## inside solid collision.
var _blocked_by_body: bool = false

func _ready() -> void:
	add_to_group("doors")
	_collision_body.collision_layer = LAYER_WORLD | LAYER_VISION
	_collision_body.collision_mask = 0
	_block_check_area.collision_layer = 0
	_block_check_area.collision_mask = LAYER_PLAYER | LAYER_ZOMBIE | LAYER_SURVIVOR
	_interact_reach_area.collision_layer = LAYER_INTERACTABLE
	_interact_reach_area.collision_mask = 0
	_interactable.interact_label = "Open Door"
	_interactable.interacted.connect(_on_interacted)
	_block_check_area.body_entered.connect(_on_body_entered)
	_block_check_area.body_exited.connect(_on_body_exited)
	if door_id != &"":
		is_open = WorldState.get_door_open(door_id)
	_apply_state(false)

func _on_interacted(_actor: Node) -> void:
	toggle()

## Public so DistrictBuilder/tests can also flip a door programmatically
## (e.g. permanently-open service entrances) without going through the
## interaction signal path.
func toggle() -> void:
	if is_open and _blocked_by_body:
		return # refuse to close on top of an actor
	is_open = not is_open
	_apply_state(true)

func _apply_state(emit_noise: bool) -> void:
	_sprite.texture = OPEN_TEXTURE if is_open else CLOSED_TEXTURE
	_collision.disabled = is_open
	_interactable.interact_label = "Close Door" if is_open else "Open Door"
	if door_id != &"":
		WorldState.set_door_open(door_id, is_open)
		if is_open:
			UrbanNavigationService.mark_door_open(door_id)
		else:
			UrbanNavigationService.mark_door_closed(door_id)
	if emit_noise:
		NoiseManager.emit_noise(global_position, noise_loudness, &"door", self)

func _on_body_entered(_body: Node) -> void:
	_blocked_by_body = true

func _on_body_exited(_body: Node) -> void:
	_blocked_by_body = false
