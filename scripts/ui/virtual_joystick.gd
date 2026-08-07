class_name TouchJoystick
extends Control
## Fixed-position on-screen joystick driven by raw touch events
## (InputEventScreenTouch / InputEventScreenDrag) that MobileControls
## forwards to it, not by Godot's touch-to-mouse emulation -- that's what
## lets two of these track two independent fingers at once. This node
## only ever reports its own value; it has no reference to InputRouter,
## Player, or Weapon, so MobileControls is the sole place that couples
## touch state to gameplay.

signal value_changed(vector: Vector2, active: bool)

## Radius (px, in this Control's local space) a touch-down must land
## within to claim this joystick. Deliberately larger than the visual
## base for an easy-to-grab touch target on phones.
@export var catch_radius: float = 100.0
## Radius the knob can travel from center before the value saturates.
@export var max_radius: float = 70.0
@export_range(0.0, 0.9) var dead_zone: float = 0.15
@export_range(0.1, 5.0) var sensitivity: float = 1.0

@onready var base: Control = $Base
@onready var knob: Control = $Base/Knob

var _touch_index: int = -1
var _value: Vector2 = Vector2.ZERO

func _ready() -> void:
	# This control (and Base/Knob) only exist to be drawn; all input comes
	# from MobileControls forwarding raw touch events, not the GUI pipeline.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Computed fresh (not cached) so it stays correct across window resize,
## orientation change, and the parent SafeArea's inset being applied
## after this node's own _ready() runs (children ready before parents).
func _get_center() -> Vector2:
	return global_position + size * 0.5

func is_active() -> bool:
	return _touch_index != -1

## Called by MobileControls for every raw touch/drag event. Only reacts
## to touches that already belong to this joystick, or a fresh touch-down
## landing in its catch area while it's unclaimed -- so a finger already
## owned by the other joystick is never even considered here.
func handle_touch_event(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_index == -1 and _within_catch_area(event.position):
				_touch_index = event.index
				_update_value(event.position)
				return true
		elif event.index == _touch_index:
			_release()
			return true
	elif event is InputEventScreenDrag:
		if event.index == _touch_index:
			_update_value(event.position)
			return true
	return false

func _within_catch_area(global_pos: Vector2) -> bool:
	return global_pos.distance_to(_get_center()) <= catch_radius

func _update_value(global_pos: Vector2) -> void:
	var offset: Vector2 = global_pos - _get_center()
	var dist: float = offset.length()
	var clamped_dist: float = minf(dist, max_radius)
	knob.position = base.size * 0.5 - knob.size * 0.5
	if dist > 0.0:
		knob.position += (offset / dist) * clamped_dist
	var normalized: float = clamped_dist / max_radius
	if normalized < dead_zone or dist <= 0.0:
		_value = Vector2.ZERO
	else:
		var eased: float = (normalized - dead_zone) / (1.0 - dead_zone)
		_value = (offset / dist) * clampf(eased * sensitivity, 0.0, 1.0)
	value_changed.emit(_value, true)

func _release() -> void:
	_touch_index = -1
	_value = Vector2.ZERO
	knob.position = base.size * 0.5 - knob.size * 0.5
	value_changed.emit(Vector2.ZERO, false)
