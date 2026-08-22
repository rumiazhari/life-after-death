class_name VoxelChunkStreamController
extends Node3D

const COORDINATES := preload("res://scripts/voxel/voxel_coordinates.gd")
const CHUNK_RENDERER := preload("res://scripts/voxel/voxel_chunk.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")

signal chunk_loaded(coordinate: Vector2i)
signal chunk_unloaded(coordinate: Vector2i)

@export_range(0, 4, 1) var load_radius := 1
@export_range(0, 5, 1) var retain_radius := 1
@export_range(0, 4, 1) var collision_radius := 0
@export_range(1, 8, 1) var max_chunk_builds_per_frame := 1

var chunk_provider: Callable
var chunk_requester: Callable
var material_data: Array[Material] = []
var center_coordinate := Vector2i.ZERO
var loaded_chunks: Dictionary = {} # Vector2i -> VoxelChunk
var pending_coordinates: Array[Vector2i] = []
var total_chunk_builds := 0
var total_chunk_unloads := 0
var maximum_build_step_usec := 0
var last_build_step_usec := 0
var _desired_coordinates: Dictionary = {}


func configure(provider: Callable, render_materials: Array[Material] = [], requester := Callable()) -> void:
	chunk_provider = provider
	chunk_requester = requester
	material_data = render_materials.duplicate() if not render_materials.is_empty() else MATERIALS.create_render_materials()
	set_center(center_coordinate)


func _process(_delta: float) -> void:
	process_build_budget()


func set_center_from_world_position(world_position: Vector3) -> void:
	set_center(COORDINATES.world_cell_to_chunk(COORDINATES.world_position_to_world_cell(world_position)))


func set_center(coordinate: Vector2i) -> void:
	center_coordinate = coordinate
	_desired_coordinates.clear()
	for z in range(coordinate.y - load_radius, coordinate.y + load_radius + 1):
		for x in range(coordinate.x - load_radius, coordinate.x + load_radius + 1):
			_desired_coordinates[Vector2i(x, z)] = true
	for loaded_coordinate_variant in loaded_chunks.keys():
		var loaded_coordinate: Vector2i = loaded_coordinate_variant
		if _chebyshev_distance(loaded_coordinate, center_coordinate) > retain_radius:
			_unload(loaded_coordinate)
		else:
			loaded_chunks[loaded_coordinate].set_collision_enabled(_chebyshev_distance(loaded_coordinate, center_coordinate) <= collision_radius)
	var retained_pending: Array[Vector2i] = []
	for pending_coordinate in pending_coordinates:
		if _desired_coordinates.has(pending_coordinate) and not loaded_chunks.has(pending_coordinate):
			retained_pending.append(pending_coordinate)
	pending_coordinates = retained_pending
	for desired_coordinate_variant in _desired_coordinates:
		var desired_coordinate: Vector2i = desired_coordinate_variant
		if not loaded_chunks.has(desired_coordinate) and desired_coordinate not in pending_coordinates:
			pending_coordinates.append(desired_coordinate)
			if chunk_requester.is_valid():
				chunk_requester.call(desired_coordinate)
	pending_coordinates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var distance_a := _chebyshev_distance(a, center_coordinate)
		var distance_b := _chebyshev_distance(b, center_coordinate)
		if distance_a != distance_b:
			return distance_a < distance_b
		return a.x < b.x or (a.x == b.x and a.y < b.y)
	)


func process_build_budget() -> int:
	if not chunk_provider.is_valid():
		return 0
	var built := 0
	var attempts := pending_coordinates.size()
	while built < max_chunk_builds_per_frame and attempts > 0 and not pending_coordinates.is_empty():
		attempts -= 1
		var coordinate: Vector2i = pending_coordinates.pop_front()
		if loaded_chunks.has(coordinate) or not _desired_coordinates.has(coordinate):
			continue
		var started_at := Time.get_ticks_usec()
		var chunk_data = chunk_provider.call(coordinate)
		if chunk_data == null:
			pending_coordinates.append(coordinate)
			continue
		var renderer = _create_renderer(coordinate, chunk_data)
		loaded_chunks[coordinate] = renderer
		total_chunk_builds += 1
		built += 1
		chunk_loaded.emit(coordinate)
		last_build_step_usec = Time.get_ticks_usec() - started_at
		maximum_build_step_usec = maxi(maximum_build_step_usec, last_build_step_usec)
	return built


func desired_coordinates() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coordinate_variant in _desired_coordinates:
		result.append(coordinate_variant)
	return result


func is_loaded(coordinate: Vector2i) -> bool:
	return loaded_chunks.has(coordinate)


func set_collision_coordinates(coordinates: Array[Vector2i]) -> void:
	var enabled: Dictionary = {}
	for coordinate in coordinates:
		enabled[coordinate] = true
	for coordinate_variant in loaded_chunks:
		var coordinate: Vector2i = coordinate_variant
		loaded_chunks[coordinate].set_collision_enabled(enabled.has(coordinate))


func metrics() -> Dictionary:
	var collision_chunks := 0
	var voxels := 0
	var visible_faces := 0
	for coordinate in loaded_chunks:
		var renderer = loaded_chunks[coordinate]
		collision_chunks += 1 if renderer.generate_collision else 0
		voxels += renderer.voxels.size()
		visible_faces += renderer.visible_face_count()
	return {
		"center": center_coordinate,
		"loaded_chunks": loaded_chunks.size(),
		"pending_chunks": pending_coordinates.size(),
		"collision_chunks": collision_chunks,
		"voxel_count": voxels,
		"visible_faces": visible_faces,
		"total_builds": total_chunk_builds,
		"total_unloads": total_chunk_unloads,
		"last_build_step_usec": last_build_step_usec,
		"maximum_build_step_usec": maximum_build_step_usec,
	}


func reset_build_timing() -> void:
	last_build_step_usec = 0
	maximum_build_step_usec = 0


func _create_renderer(coordinate: Vector2i, chunk_data):
	var renderer = CHUNK_RENDERER.new()
	renderer.name = "VoxelChunk_%d_%d" % [coordinate.x, coordinate.y]
	renderer.position = Vector3(coordinate.x * COORDINATES.CHUNK_CELLS, 0.0, coordinate.y * COORDINATES.CHUNK_CELLS)
	renderer.generate_collision = _chebyshev_distance(coordinate, center_coordinate) <= collision_radius
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	renderer.add_child(mesh)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	renderer.add_child(collision)
	renderer.configure(chunk_data.cells, material_data)
	add_child(renderer)
	return renderer


func _unload(coordinate: Vector2i) -> void:
	var renderer: Node = loaded_chunks.get(coordinate)
	loaded_chunks.erase(coordinate)
	if is_instance_valid(renderer):
		renderer.queue_free()
	total_chunk_unloads += 1
	chunk_unloaded.emit(coordinate)


func _chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
