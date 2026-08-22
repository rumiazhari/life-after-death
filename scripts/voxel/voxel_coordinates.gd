class_name VoxelCoordinates
extends RefCounted

## Existing procedural-world measurements: StreamingWorld.CHUNK_SIZE / 32px tiles.
const SEMANTIC_PIXELS_PER_VOXEL := 32.0
const CHUNK_SEMANTIC_SIZE := 2816.0
const CHUNK_CELLS := 88
const HALF_CHUNK_CELLS := 44
const VOXEL_WORLD_SIZE := 1.0


static func semantic_local_to_world_position(local_position: Vector2, chunk_coordinate: Vector2i, elevation: float = 0.0) -> Vector3:
	var global_semantic := Vector2(chunk_coordinate) * CHUNK_SEMANTIC_SIZE + local_position
	return Vector3(global_semantic.x / SEMANTIC_PIXELS_PER_VOXEL, elevation, global_semantic.y / SEMANTIC_PIXELS_PER_VOXEL)


static func world_position_to_semantic_local(world_position: Vector3, chunk_coordinate: Vector2i) -> Vector2:
	var global_semantic := Vector2(world_position.x, world_position.z) * SEMANTIC_PIXELS_PER_VOXEL
	return global_semantic - Vector2(chunk_coordinate) * CHUNK_SEMANTIC_SIZE


static func semantic_local_to_world_cell(local_position: Vector2, chunk_coordinate: Vector2i, elevation_cell: int = 0) -> Vector3i:
	var position := semantic_local_to_world_position(local_position, chunk_coordinate, elevation_cell)
	return Vector3i(floori(position.x), elevation_cell, floori(position.z))


static func world_position_to_world_cell(world_position: Vector3) -> Vector3i:
	return Vector3i(floori(world_position.x / VOXEL_WORLD_SIZE), floori(world_position.y / VOXEL_WORLD_SIZE), floori(world_position.z / VOXEL_WORLD_SIZE))


static func world_cell_to_world_position(world_cell: Vector3i) -> Vector3:
	return Vector3(world_cell) * VOXEL_WORLD_SIZE


static func world_cell_to_chunk(world_cell: Vector3i) -> Vector2i:
	return Vector2i(
		floori(float(world_cell.x + HALF_CHUNK_CELLS) / CHUNK_CELLS),
		floori(float(world_cell.z + HALF_CHUNK_CELLS) / CHUNK_CELLS)
	)


static func world_cell_to_local(world_cell: Vector3i, chunk_coordinate: Vector2i) -> Vector3i:
	return world_cell - Vector3i(chunk_coordinate.x * CHUNK_CELLS, 0, chunk_coordinate.y * CHUNK_CELLS)


static func local_to_world_cell(local_cell: Vector3i, chunk_coordinate: Vector2i) -> Vector3i:
	return local_cell + Vector3i(chunk_coordinate.x * CHUNK_CELLS, 0, chunk_coordinate.y * CHUNK_CELLS)


static func semantic_local_to_chunk_cell(local_position: Vector2, elevation_cell: int = 0) -> Vector3i:
	return Vector3i(
		floori(local_position.x / SEMANTIC_PIXELS_PER_VOXEL),
		elevation_cell,
		floori(local_position.y / SEMANTIC_PIXELS_PER_VOXEL)
	)


static func stable_cell_id(world_cell: Vector3i) -> StringName:
	return StringName("voxel/%d/%d/%d" % [world_cell.x, world_cell.y, world_cell.z])

