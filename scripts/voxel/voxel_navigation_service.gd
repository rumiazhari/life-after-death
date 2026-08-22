class_name VoxelNavigationService
extends RefCounted

const COORDINATES := preload("res://scripts/voxel/voxel_coordinates.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")
const CARDINALS: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]

var world_data
var max_expansions := 12000


func configure(data) -> void:
	world_data = data


func is_walkable(world_cell: Vector3i) -> bool:
	if world_data == null:
		return false
	var ground := Vector3i(world_cell.x, 0, world_cell.z)
	var coordinate := COORDINATES.world_cell_to_chunk(ground)
	var chunk = world_data.get_chunk(coordinate)
	if chunk == null:
		return false
	var local := COORDINATES.world_cell_to_local(ground, coordinate)
	var ground_definition: Dictionary = MATERIALS.definition(chunk.get_cell(local))
	if not bool(ground_definition.get("walkable", false)):
		return false
	for y in [1, 2]:
		var obstacle_definition: Dictionary = MATERIALS.definition(chunk.get_cell(Vector3i(local.x, y, local.z)))
		if bool(obstacle_definition.get("solid", false)):
			return false
	return true


func find_path(from_position: Vector3, to_position: Vector3) -> PackedVector3Array:
	var start := _ground_cell(from_position)
	var goal := _ground_cell(to_position)
	if not is_walkable(start) or not is_walkable(goal):
		return PackedVector3Array()
	if start == goal:
		return PackedVector3Array([_cell_center(goal)])
	var frontier: Array[Vector3i] = [start]
	var came_from: Dictionary = {start: start}
	var cost: Dictionary = {start: 0}
	var expansions := 0
	while not frontier.is_empty() and expansions < max_expansions:
		var current := _take_lowest(frontier, cost, goal)
		expansions += 1
		if current == goal:
			return _reconstruct(came_from, start, goal)
		for offset in CARDINALS:
			var neighbor := current + offset
			if not is_walkable(neighbor):
				continue
			var new_cost := int(cost[current]) + 1
			if not cost.has(neighbor) or new_cost < int(cost[neighbor]):
				cost[neighbor] = new_cost
				came_from[neighbor] = current
				if neighbor not in frontier:
					frontier.append(neighbor)
	return PackedVector3Array()


func is_direct_path_clear(from_position: Vector3, to_position: Vector3) -> bool:
	var from := _ground_cell(from_position)
	var to := _ground_cell(to_position)
	var x := from.x
	var z := from.z
	var dx := absi(to.x - x)
	var dz := -absi(to.z - z)
	var step_x := 1 if x < to.x else -1
	var step_z := 1 if z < to.z else -1
	var error := dx + dz
	while true:
		if not is_walkable(Vector3i(x, 0, z)):
			return false
		if x == to.x and z == to.z:
			return true
		var doubled := 2 * error
		if doubled >= dz:
			error += dz
			x += step_x
		if doubled <= dx:
			error += dx
			z += step_z
	return true


func are_positions_connected(from_position: Vector3, to_position: Vector3) -> bool:
	return not find_path(from_position, to_position).is_empty()


func _ground_cell(position: Vector3) -> Vector3i:
	var cell := COORDINATES.world_position_to_world_cell(position)
	return Vector3i(cell.x, 0, cell.z)


func _cell_center(cell: Vector3i) -> Vector3:
	return COORDINATES.world_cell_to_world_position(cell) + Vector3(0.5, 1.0, 0.5)


func _take_lowest(frontier: Array[Vector3i], cost: Dictionary, goal: Vector3i) -> Vector3i:
	var best_index := 0
	var best_score := INF
	for index in range(frontier.size()):
		var cell := frontier[index]
		var score := float(cost[cell] + absi(goal.x - cell.x) + absi(goal.z - cell.z))
		if score < best_score:
			best_score = score
			best_index = index
	return frontier.pop_at(best_index)


func _reconstruct(came_from: Dictionary, start: Vector3i, goal: Vector3i) -> PackedVector3Array:
	var reverse: Array[Vector3i] = []
	var current := goal
	while current != start:
		reverse.append(current)
		current = came_from[current]
	reverse.reverse()
	var result := PackedVector3Array()
	for cell in reverse:
		result.append(_cell_center(cell))
	return result
