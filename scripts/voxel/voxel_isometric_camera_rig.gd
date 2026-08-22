class_name VoxelIsometricCameraRig
extends Node3D

@export var follow_smoothing := 8.0
@export var zoom_step := 2.0
@export var minimum_size := 18.0
@export var maximum_size := 42.0

var target: Node3D
@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	InputRouter.camera_zoom_requested.connect(_on_camera_zoom_requested)


func configure(actor: Node3D) -> void:
	target = actor
	global_position = actor.global_position


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var weight := 1.0 - exp(-follow_smoothing * delta)
	global_position = global_position.lerp(target.global_position, weight)


func zoom(direction: float) -> void:
	camera.size = clampf(camera.size + direction * zoom_step, minimum_size, maximum_size)


func _on_camera_zoom_requested(direction: float) -> void:
	zoom(direction)
