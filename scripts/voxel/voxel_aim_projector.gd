class_name VoxelAimProjector
extends RefCounted


static func ground_direction(camera: Camera3D, actor_position: Vector3, screen_direction: Vector2, fallback: Vector3) -> Vector3:
	if camera == null or screen_direction.length_squared() < 0.0001:
		return fallback
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var screen_point := viewport_size * 0.5 + screen_direction.normalized() * viewport_size.length() * 0.5
	var ray_origin := camera.project_ray_origin(screen_point)
	var ray_direction := camera.project_ray_normal(screen_point)
	var ground := Plane(Vector3.UP, actor_position.y)
	var intersection = ground.intersects_ray(ray_origin, ray_direction)
	if intersection == null:
		return fallback
	var direction: Vector3 = intersection - actor_position
	direction.y = 0.0
	return fallback if direction.length_squared() < 0.0001 else direction.normalized()

