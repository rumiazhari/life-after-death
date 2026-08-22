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
signal weapon_slot_requested(slot_index: int)
signal weapon_cycle_requested(direction: int)
signal camera_zoom_requested(direction: float)

var movement_vector: Vector2 = Vector2.ZERO
var aim_vector: Vector2 = Vector2.ZERO
var fire_pressed: bool = false
var reload_pressed: bool = false
var interact_pressed: bool = false
var pause_pressed: bool = false
var weapon_slot_pressed: int = -1
var weapon_cycle_pressed: int = 0

var _touch_movement_active: bool = false
var _touch_movement: Vector2 = Vector2.ZERO
var _touch_aim_active: bool = false
var _touch_aim: Vector2 = Vector2.ZERO
var _touch_firing: bool = false

var _pending_reload: bool = false
var _pending_interact: bool = false
var _pending_pause: bool = false
var _pending_weapon_cycle: int = 0

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
	weapon_slot_pressed = _desktop_weapon_slot()
	weapon_cycle_pressed = (1 if Input.is_action_just_pressed("weapon_cycle") else 0) + _pending_weapon_cycle
	_pending_reload = false
	_pending_interact = false
	_pending_pause = false
	_pending_weapon_cycle = 0

	if reload_pressed:
		reload_requested.emit()
	if interact_pressed:
		interact_requested.emit()
	if pause_pressed:
		pause_requested.emit()
	if weapon_slot_pressed >= 0:
		weapon_slot_requested.emit(weapon_slot_pressed)
	elif weapon_cycle_pressed != 0:
		weapon_cycle_requested.emit(weapon_cycle_pressed)

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

func _desktop_weapon_slot() -> int:
	if Input.is_action_just_pressed("weapon_slot_1"):
		return 0
	if Input.is_action_just_pressed("weapon_slot_2"):
		return 1
	return -1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_zoom_requested.emit(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_zoom_requested.emit(1.0)


func request_camera_zoom(direction: float) -> void:
	camera_zoom_requested.emit(clampf(direction, -1.0, 1.0))

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

func request_weapon_cycle(direction: int = 1) -> void:
	_pending_weapon_cycle = 1 if direction >= 0 else -1
