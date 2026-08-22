class_name VoxelSpawnSampler
extends RefCounted

const COORDINATES := preload("res://scripts/voxel/voxel_coordinates.gd")

var navigation_service


func configure(service) -> void:
	navigation_service = service


func sample_region(region: Dictionary, chunk_coordinate: Vector2i, seed_value: int, attempts: int = 24) -> Vector3:
	if navigation_service == null:
		return Vector3.INF
	var center: Vector2 = region.get("position", Vector2.ZERO)
	var radius := float(region.get("radius", 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ String(region.get("id", &"")).hash()
	for _attempt in range(attempts):
		var angle := rng.randf_range(0.0, TAU)
		var distance := sqrt(rng.randf()) * radius
		var semantic := center + Vector2(cos(angle), sin(angle)) * distance
		var world_cell := COORDINATES.semantic_local_to_world_cell(semantic, chunk_coordinate)
		if navigation_service.is_walkable(world_cell):
			return COORDINATES.world_cell_to_world_position(world_cell) + Vector3(0.5, 1.0, 0.5)
	return Vector3.INF
