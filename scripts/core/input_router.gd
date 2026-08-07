extends Node
## Centralized input source (autoload "InputRouter").
##
## Player, Weapon-adjacent gameplay code, and UI panels (PauseMenu) read
## from this instead of polling Input/InputMap directly or reaching into
## the touch controls. Desktop input keeps flowing through the project's
## InputMap actions (computed here, not removed); MobileControls -- the
## on-screen joysticks and buttons -- reports into this router through the
## setter methods below instead of touching Player/Weapon/PauseMenu
## directly. This is what keeps touch UI and gameplay decoupled in both
## directions.

signal reload_requested()
signal interact_requested()
signal pause_requested()

var movement_vector: Vector2 = Vector2.ZERO
var aim_vector: Vector2 = Vector2.ZERO
var fire_pressed: bool = false
var reload_pressed: bool = false
var interact_pressed: bool = false
var pause_pressed: bool = false

var _touch_movement_active: bool = false
var _touch_movement: Vector2 = Vector2.ZERO
var _touch_aim_active: bool = false
var _touch_aim: Vector2 = Vector2.ZERO
var _touch_firing: bool = false

var _pending_reload: bool = false
var _pending_interact: bool = false
var _pending_pause: bool = false

func _ready() -> void:
	# Must keep reading input while SceneTree.paused is true, otherwise the
	# pause action could never be polled again to unpause.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _physics_process(_delta: float) -> void:
	movement_vector = _touch_movement if _touch_movement_active else _keyboard_movement_vector()

	if _touch_aim_active:
		aim_vector = _touch_aim
		fire_pressed = _touch_firing
	else:
		aim_vector = _mouse_aim_vector()
		fire_pressed = Input.is_action_pressed("fire")

	reload_pressed = Input.is_action_just_pressed("reload") or _pending_reload
	interact_pressed = Input.is_action_just_pressed("interact") or _pending_interact
	pause_pressed = Input.is_action_just_pressed("pause") or _pending_pause
	_pending_reload = false
	_pending_interact = false
	_pending_pause = false

	if reload_pressed:
		reload_requested.emit()
	if interact_pressed:
		interact_requested.emit()
	if pause_pressed:
		pause_requested.emit()

func _keyboard_movement_vector() -> Vector2:
	var raw := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	return raw if raw.length() <= 1.0 else raw.normalized()

func _mouse_aim_vector() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2.ZERO
	var center: Vector2 = viewport.get_visible_rect().size * 0.5
	var to_mouse: Vector2 = viewport.get_mouse_position() - center
	return Vector2.ZERO if to_mouse.length() < 1.0 else to_mouse.normalized()

## --- Mobile touch reporting -----------------------------------------
## Called only by MobileControls / VirtualJoystick. Gameplay code never
## calls these and touch UI never calls anything else on this router.

func set_touch_movement(vector: Vector2) -> void:
	_touch_movement_active = true
	_touch_movement = vector

func clear_touch_movement() -> void:
	_touch_movement_active = false
	_touch_movement = Vector2.ZERO

func set_touch_aim(vector: Vector2, firing: bool) -> void:
	_touch_aim_active = true
	_touch_aim = vector
	_touch_firing = firing

func clear_touch_aim() -> void:
	_touch_aim_active = false
	_touch_aim = Vector2.ZERO
	_touch_firing = false

func request_reload() -> void:
	_pending_reload = true

func request_interact() -> void:
	_pending_interact = true

func request_pause() -> void:
	_pending_pause = true
