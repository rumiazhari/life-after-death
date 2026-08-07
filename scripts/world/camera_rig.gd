class_name CameraRig
extends Camera2D
## Camera that follows an assigned target with simple lerp smoothing.
## Kept separate from Player.tscn so the player scene stays testable
## without a camera and the camera can be retargeted independently.

@export var follow_speed: float = 8.0

var target: Node2D = null

func _ready() -> void:
	add_to_group("main_camera")
	make_current()

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	global_position = global_position.lerp(target.global_position, clampf(follow_speed * delta, 0.0, 1.0))

func set_target(new_target: Node2D) -> void:
	target = new_target
	if new_target:
		global_position = new_target.global_position
