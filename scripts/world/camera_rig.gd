class_name CameraRig
extends Camera2D
## Camera that follows an assigned target with simple lerp smoothing.
## Kept separate from Player.tscn so the player scene stays testable
## without a camera and the camera can be retargeted independently.
##
## Following itself stays smooth (the camera's LOGICAL position lerps
## every frame, `_logical_position`), but the RENDERED transform
## (`global_position`) is rounded to the nearest whole pixel each frame.
## This is what prevents 1px shimmer/vibration in the pixel-art world:
## without it, a smoothly-lerping camera's fractional position drifts
## independently of the project's snap_2d_transforms_to_pixel setting
## (which only rounds each sprite's own transform), which reads as the
## whole world "swimming" relative to the camera even though no single
## sprite is doing anything wrong. Deliberately does NOT also rely on
## snap_2d_vertices_to_pixel -- Godot's own docs advise against combining
## transform- and vertex-snapping, and transform snapping plus this
## rounded camera position is sufficient to keep the scene pixel-locked.

@export var follow_speed: float = 8.0

var target: Node2D = null
var _logical_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("main_camera")
	make_current()
	_logical_position = global_position

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_logical_position = _logical_position.lerp(target.global_position, clampf(follow_speed * delta, 0.0, 1.0))
	global_position = _snap_to_pixel(_logical_position)

func set_target(new_target: Node2D) -> void:
	target = new_target
	if new_target:
		_logical_position = new_target.global_position
		global_position = _snap_to_pixel(_logical_position)

## Rounds to the nearest world-space grid cell that corresponds to exactly
## one rendered pixel at this camera's current zoom (1 world unit at
## zoom=1, 0.5 world units at zoom=2, etc.) instead of assuming zoom=1.
func _snap_to_pixel(world_position: Vector2) -> Vector2:
	var pixel_in_world_units: Vector2 = Vector2.ONE / zoom
	return (world_position / pixel_in_world_units).round() * pixel_in_world_units
