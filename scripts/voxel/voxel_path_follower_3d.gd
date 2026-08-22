class_name VoxelPathFollower3D
extends RefCounted

var actor: CharacterBody3D
var navigation_service
var target_position := Vector3.INF
var waypoint_tolerance := 0.18
var repath_interval := 0.25
var _path := PackedVector3Array()
var _repath_remaining := 0.0


func configure(body: CharacterBody3D, service) -> void:
	actor = body
	navigation_service = service


func set_target(position: Vector3) -> void:
	if target_position == position:
		return
	target_position = position
	_repath_remaining = 0.0


func clear() -> void:
	target_position = Vector3.INF
	_path.clear()
	if actor != null:
		actor.velocity = Vector3.ZERO


func physics_step(delta: float, speed: float) -> bool:
	if actor == null or navigation_service == null or target_position == Vector3.INF:
		return false
	_repath_remaining -= delta
	if _repath_remaining <= 0.0 or _path.is_empty():
		_path = navigation_service.find_path(actor.global_position, target_position)
		_repath_remaining = repath_interval
	while not _path.is_empty():
		var flat_offset: Vector3 = _path[0] - actor.global_position
		flat_offset.y = 0.0
		if flat_offset.length() > waypoint_tolerance:
			break
		_path.remove_at(0)
	if _path.is_empty():
		actor.velocity = Vector3.ZERO
		return actor.global_position.distance_to(target_position) <= 1.0
	var direction: Vector3 = _path[0] - actor.global_position
	direction.y = 0.0
	direction = direction.normalized()
	actor.velocity = Vector3(direction.x * speed, -2.0, direction.z * speed)
	actor.rotation.y = atan2(direction.x, direction.z)
	actor.move_and_slide()
	return false
