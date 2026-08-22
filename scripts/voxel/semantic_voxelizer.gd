class_name SemanticVoxelizer
extends RefCounted

const WALL_HEIGHT_CELLS := 3
const WORLD_DATA_SCRIPT := preload("res://scripts/voxel/voxel_world_data.gd")
const CHUNK_DATA_SCRIPT := preload("res://scripts/voxel/voxel_chunk_data.gd")
const COORDINATES := preload("res://scripts/voxel/voxel_coordinates.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")

var _persistent_state: Dictionary = {}


func voxelize_chunk(city_model: Dictionary, world_seed: int, chunk_coordinate: Vector2i, persistent_state: Dictionary = {}):
	_persistent_state = persistent_state
	var world = WORLD_DATA_SCRIPT.new(world_seed)
	var chunk = CHUNK_DATA_SCRIPT.new(chunk_coordinate)
	var roads: Array = city_model.get("roads", [])
	var blocks: Array = city_model.get("blocks", [])
	for z in range(-COORDINATES.HALF_CHUNK_CELLS, COORDINATES.HALF_CHUNK_CELLS):
		for x in range(-COORDINATES.HALF_CHUNK_CELLS, COORDINATES.HALF_CHUNK_CELLS):
			var local_cell := Vector3i(x, 0, z)
			var semantic_center: Vector2 = Vector2(x + 0.5, z + 0.5) * COORDINATES.SEMANTIC_PIXELS_PER_VOXEL
			chunk.set_cell(local_cell, _ground_material(semantic_center, roads, blocks))
	for building_variant in city_model.get("buildings", []):
		_voxelize_building(chunk, world, building_variant, chunk_coordinate)
	for prop_variant in city_model.get("props", []):
		_voxelize_exterior_prop(chunk, world, prop_variant, chunk_coordinate)
	for point_variant in city_model.get("scavenge_points", []):
		_register_scavenge_point(world, point_variant, chunk_coordinate)
	_register_settlement_services(world, city_model, chunk_coordinate)
	world.add_chunk(chunk)
	return world


func _ground_material(point: Vector2, roads: Array, blocks: Array) -> int:
	for road_variant in roads:
		var road: Dictionary = road_variant
		if (road.get("rect", Rect2()) as Rect2).has_point(point):
			return MATERIALS.material_id_for_surface(StringName(road.get("surface", &"asphalt")))
	for block_variant in blocks:
		var block: Dictionary = block_variant
		var rect: Rect2 = block.get("rect", Rect2())
		if rect.has_point(point):
			return MATERIALS.material_id_for_surface(StringName(block.get("surface", &"pavement")))
	return MATERIALS.Id.GRASS


func _voxelize_building(chunk, world, building: Dictionary, chunk_coordinate: Vector2i) -> void:
	var footprint: Rect2 = building.get("footprint", Rect2())
	if footprint.size.x <= 0.0 or footprint.size.y <= 0.0:
		return
	var stable_id := StringName(building.get("stable_id", building.get("id", &"")))
	var building_position: Vector2 = building.get("position", footprint.position)
	var interior: Dictionary = building.get("interior", {})
	var wall_height := WALL_HEIGHT_CELLS
	var perimeter_rects: Array = interior.get("perimeter_rects", [])
	if perimeter_rects.is_empty():
		perimeter_rects = [Rect2(footprint.position - building_position, footprint.size)]
	for local_rect_variant in perimeter_rects:
		var local_rect: Rect2 = local_rect_variant
		var world_rect := Rect2(building_position + local_rect.position, local_rect.size)
		_paint_perimeter_and_roof(chunk, world_rect, wall_height, stable_id)
	for room_variant in interior.get("rooms", []):
		_voxelize_room(chunk, world, building_position, room_variant, chunk_coordinate)
	for partition_variant in interior.get("partitions", []):
		_voxelize_partition(chunk, building_position, partition_variant, wall_height, stable_id)
	for door_variant in interior.get("doors", []):
		_voxelize_door(chunk, world, building_position, door_variant, wall_height, chunk_coordinate, stable_id)
	for window_variant in interior.get("windows", []):
		_voxelize_window(chunk, world, building_position, window_variant, chunk_coordinate, stable_id)
	for furniture_variant in interior.get("furniture", []):
		_voxelize_furniture(chunk, world, building_position, furniture_variant, chunk_coordinate)
	var entrance: Vector2 = building.get("entrance_position", footprint.get_center())
	var entrance_cell := COORDINATES.semantic_local_to_chunk_cell(entrance, 1)
	var anchor_world := COORDINATES.local_to_world_cell(entrance_cell, chunk_coordinate)
	if stable_id != &"":
		var building_bounds := _cell_bounds(footprint)
		var bounds_min := COORDINATES.local_to_world_cell(building_bounds[0], chunk_coordinate)
		var bounds_max := COORDINATES.local_to_world_cell(building_bounds[1], chunk_coordinate)
		world.register_object(stable_id, anchor_world)
		world.register_stable_object(stable_id, &"building", anchor_world, {
			"archetype": String(building.get("archetype", &"")),
			"form": String(interior.get("form", &"rectangle")),
			"wall_height": wall_height,
			"bounds": [bounds_min.x, bounds_min.z, bounds_max.x, bounds_max.z],
		})


func _paint_perimeter_and_roof(chunk, rect: Rect2, wall_height: int, source_id: StringName) -> void:
	var bounds := _cell_bounds(rect)
	for z in range(bounds[0].z, bounds[1].z + 1):
		for x in range(bounds[0].x, bounds[1].x + 1):
			var perimeter := x == bounds[0].x or x == bounds[1].x or z == bounds[0].z or z == bounds[1].z
			if perimeter:
				for y in range(1, wall_height + 1):
					chunk.set_cell(Vector3i(x, y, z), MATERIALS.Id.BRICK, source_id)
			chunk.set_cell(Vector3i(x, wall_height + 1, z), MATERIALS.Id.ROOF, source_id)
			if perimeter:
				chunk.set_cell(Vector3i(x, wall_height + 2, z), MATERIALS.Id.ROOF, source_id)


func _voxelize_room(chunk, world, building_position: Vector2, room: Dictionary, chunk_coordinate: Vector2i) -> void:
	var stable_id := StringName(room.get("stable_id", &""))
	var local_rect: Rect2 = room.get("rect", Rect2())
	var rect := Rect2(building_position + local_rect.position, local_rect.size)
	var bounds := _cell_bounds(rect.grow(-1.0))
	for z in range(bounds[0].z, bounds[1].z + 1):
		for x in range(bounds[0].x, bounds[1].x + 1):
			chunk.set_cell(Vector3i(x, 0, z), MATERIALS.Id.FLOOR, stable_id)
	var center_cell := COORDINATES.semantic_local_to_chunk_cell(rect.get_center(), 1)
	var world_cell := COORDINATES.local_to_world_cell(center_cell, chunk_coordinate)
	if stable_id != &"":
		world.register_stable_object(stable_id, &"room", world_cell, {
			"room_id": String(room.get("id", &"")),
			"role": String(room.get("role", &"")),
			"required": bool(room.get("required", false)),
		})


func _voxelize_partition(chunk, building_position: Vector2, partition: Dictionary, wall_height: int, source_id: StringName) -> void:
	var from: Vector2 = building_position + (partition.get("from", Vector2.ZERO) as Vector2)
	var to: Vector2 = building_position + (partition.get("to", Vector2.ZERO) as Vector2)
	var gaps: Array[Rect2] = []
	for gap_variant in partition.get("gaps", []):
		var gap: Rect2 = gap_variant
		gaps.append(Rect2(building_position + gap.position, gap.size))
	var vertical := is_equal_approx(from.x, to.x)
	var line_rect: Rect2
	if vertical:
		line_rect = Rect2(from.x - 1.0, minf(from.y, to.y), 2.0, absf(to.y - from.y) + 1.0)
	else:
		line_rect = Rect2(minf(from.x, to.x), from.y - 1.0, absf(to.x - from.x) + 1.0, 2.0)
	var bounds := _cell_bounds(line_rect)
	for z in range(bounds[0].z, bounds[1].z + 1):
		for x in range(bounds[0].x, bounds[1].x + 1):
			var center := _cell_semantic_center(x, z)
			if _point_in_any_rect(center, gaps):
				continue
			for y in range(1, wall_height + 1):
				chunk.set_cell(Vector3i(x, y, z), MATERIALS.Id.BRICK, source_id)


func _voxelize_door(chunk, world, building_position: Vector2, door: Dictionary, wall_height: int, chunk_coordinate: Vector2i, stable_building_id: StringName) -> void:
	var stable_id := StringName(door.get("id", &""))
	var position: Vector2 = building_position + (door.get("position", Vector2.ZERO) as Vector2)
	var aperture_size: Vector2 = door.get("aperture_size", Vector2(64, 32))
	var aperture := Rect2(position - aperture_size * 0.5, aperture_size)
	var occupied_cells: Array = []
	for cell in _cells_in_rect(aperture):
		for y in range(1, mini(wall_height, 2) + 1):
			chunk.set_cell(Vector3i(cell.x, y, cell.z), MATERIALS.Id.AIR)
			occupied_cells.append([cell.x, y, cell.z])
	var is_open := _door_open(stable_id)
	if not is_open:
		for row in occupied_cells:
			chunk.set_cell(Vector3i(int(row[0]), int(row[1]), int(row[2])), MATERIALS.Id.WOOD, stable_id)
	var anchor_local := COORDINATES.semantic_local_to_chunk_cell(position, 1)
	var anchor_world := COORDINATES.local_to_world_cell(anchor_local, chunk_coordinate)
	world.register_stable_object(stable_id, &"door", anchor_world, {
		"open": is_open,
		"building": stable_building_id,
		"exterior": bool(door.get("exterior", false)),
		"service": bool(door.get("service", false)),
		"room_a": String(door.get("room_a", &"")),
		"room_b": String(door.get("room_b", &"")),
		"axis": "x" if aperture_size.x >= aperture_size.y else "z",
		"width_cells": maxi(1, ceili(maxf(aperture_size.x, aperture_size.y) / COORDINATES.SEMANTIC_PIXELS_PER_VOXEL)),
		"height_cells": mini(wall_height, 2),
		"cells": occupied_cells,
	})


func _voxelize_window(chunk, world, building_position: Vector2, window: Dictionary, chunk_coordinate: Vector2i, stable_building_id: StringName) -> void:
	var stable_id := StringName(window.get("id", &""))
	var position: Vector2 = building_position + (window.get("position", Vector2.ZERO) as Vector2)
	var local_cell := COORDINATES.semantic_local_to_chunk_cell(position, 2)
	var destroyed := bool(_prop_flag(stable_id, &"destroyed", false))
	var boarded := bool(window.get("boarded", false))
	var material_id := MATERIALS.Id.AIR if destroyed else (MATERIALS.Id.BOARD if boarded else MATERIALS.Id.GLASS)
	chunk.set_cell(local_cell, material_id, stable_id)
	var world_cell := COORDINATES.local_to_world_cell(local_cell, chunk_coordinate)
	world.register_stable_object(stable_id, &"window", world_cell, {
		"boarded": boarded,
		"building": stable_building_id,
		"destroyed": destroyed,
		"room_id": String(window.get("room_id", &"")),
	})


func _voxelize_furniture(chunk, world, building_position: Vector2, furniture: Dictionary, chunk_coordinate: Vector2i) -> void:
	var stable_id := StringName(furniture.get("id", &""))
	var position: Vector2 = building_position + (furniture.get("position", Vector2.ZERO) as Vector2)
	var local_cell := COORDINATES.semantic_local_to_chunk_cell(position, 1)
	var destroyed := bool(_prop_flag(stable_id, &"destroyed", false))
	if not destroyed:
		chunk.set_cell(local_cell, MATERIALS.Id.WOOD, stable_id)
	var world_cell := COORDINATES.local_to_world_cell(local_cell, chunk_coordinate)
	world.register_stable_object(stable_id, &"furniture", world_cell, {
		"mode": String(furniture.get("mode", &"physical")),
		"kind": String(furniture.get("kind", &"")),
		"room_id": String(furniture.get("room_id", &"")),
		"items": (furniture.get("items", {}) as Dictionary).duplicate(),
		"yield": int(furniture.get("yield", 0)),
		"capacity": float(furniture.get("capacity", 0.0)),
		"minimum_damage_class": int(furniture.get("minimum_damage_class", 0)),
		"destroyed": destroyed,
		"searched": bool(_prop_flag(stable_id, &"searched", false)),
		"salvaged": bool(_prop_flag(stable_id, &"salvaged", false)),
	})


func _voxelize_exterior_prop(chunk, world, prop: Dictionary, chunk_coordinate: Vector2i) -> void:
	var stable_id := StringName(prop.get("id", &""))
	if stable_id == &"":
		return
	var position: Vector2 = prop.get("position", Vector2.ZERO)
	var local_cell := COORDINATES.semantic_local_to_chunk_cell(position, 1)
	var destroyed := bool(_prop_flag(stable_id, &"destroyed", false))
	if not destroyed:
		chunk.set_cell(local_cell, MATERIALS.Id.WOOD, stable_id)
	var world_cell := COORDINATES.local_to_world_cell(local_cell, chunk_coordinate)
	world.register_stable_object(stable_id, &"exterior_prop", world_cell, {
		"mode": String(prop.get("interaction", &"physical")),
		"kind": String(prop.get("kind", &"")),
		"items": (prop.get("items", {}) as Dictionary).duplicate(),
		"yield": int(prop.get("yield", 0)),
		"minimum_damage_class": int(prop.get("minimum_damage_class", 0)),
		"destroyed": destroyed,
		"searched": bool(_prop_flag(stable_id, &"searched", false)),
		"salvaged": bool(_prop_flag(stable_id, &"salvaged", false)),
	})


func _register_scavenge_point(world, point: Dictionary, chunk_coordinate: Vector2i) -> void:
	var stable_id := StringName(point.get("id", &""))
	if stable_id == &"":
		return
	var local_cell := COORDINATES.semantic_local_to_chunk_cell(point.get("position", Vector2.ZERO), 1)
	var world_cell := COORDINATES.local_to_world_cell(local_cell, chunk_coordinate)
	world.register_stable_object(stable_id, &"scavenge_point", world_cell, {
		"item_id": String(point.get("item_id", &"")),
		"yield": int(point.get("yield", 0)),
		"stock": int(_prop_flag(stable_id, &"remaining_stock", point.get("stock", 0))),
		"danger": float(point.get("danger", 0.0)),
	})


func _register_settlement_services(world, city_model: Dictionary, chunk_coordinate: Vector2i) -> void:
	if not bool(city_model.get("has_safehouse", false)):
		return
	var city_seed := int(city_model.get("seed", 0))
	var center: Vector2 = city_model.get("safehouse_position", Vector2.ZERO)
	var entrance: Vector2 = city_model.get("safehouse_entrance", center)
	_register_service(world, StringName("city_%d/safehouse/storage_general" % city_seed), &"settlement_storage", center + Vector2(-48, 0), chunk_coordinate, {"capacity": 1000.0, "role": "general"})
	_register_service(world, StringName("city_%d/safehouse/storage_food" % city_seed), &"settlement_storage", center + Vector2(-16, 0), chunk_coordinate, {"capacity": 500.0, "role": "food"})
	_register_service(world, StringName("city_%d/safehouse/storage_water" % city_seed), &"settlement_storage", center + Vector2(16, 0), chunk_coordinate, {"capacity": 500.0, "role": "water"})
	_register_service(world, StringName("city_%d/safehouse/storage_medical" % city_seed), &"settlement_storage", center + Vector2(48, 0), chunk_coordinate, {"capacity": 300.0, "role": "medical"})
	_register_service(world, StringName("city_%d/safehouse/bed" % city_seed), &"rest_point", center + Vector2(0, -32), chunk_coordinate)
	_register_service(world, StringName("city_%d/safehouse/guard" % city_seed), &"guard_post", entrance, chunk_coordinate)


func _register_service(world, stable_id: StringName, kind: StringName, position: Vector2, chunk_coordinate: Vector2i, state: Dictionary = {}) -> void:
	var local_cell := COORDINATES.semantic_local_to_chunk_cell(position, 1)
	world.register_stable_object(stable_id, kind, COORDINATES.local_to_world_cell(local_cell, chunk_coordinate), state)


func _cell_bounds(rect: Rect2) -> Array[Vector3i]:
	return [
		COORDINATES.semantic_local_to_chunk_cell(rect.position),
		COORDINATES.semantic_local_to_chunk_cell(rect.end - Vector2.ONE),
	]


func _cells_in_rect(rect: Rect2) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var bounds := _cell_bounds(rect)
	for z in range(bounds[0].z, bounds[1].z + 1):
		for x in range(bounds[0].x, bounds[1].x + 1):
			result.append(Vector3i(x, 0, z))
	return result


func _cell_semantic_center(x: int, z: int) -> Vector2:
	return Vector2(x + 0.5, z + 0.5) * COORDINATES.SEMANTIC_PIXELS_PER_VOXEL


func _point_in_any_rect(point: Vector2, rects: Array[Rect2]) -> bool:
	for rect in rects:
		if rect.has_point(point):
			return true
	return false


func _door_open(stable_id: StringName) -> bool:
	if _persistent_state.has("door_states"):
		return bool((_persistent_state.get("door_states", {}) as Dictionary).get(stable_id, false))
	return WorldState.get_door_open(stable_id)


func _prop_flag(stable_id: StringName, flag: StringName, default_value):
	if _persistent_state.has("prop_states"):
		var states: Dictionary = _persistent_state.get("prop_states", {})
		return (states.get(stable_id, {}) as Dictionary).get(flag, default_value)
	return WorldState.get_prop_state_flag(stable_id, flag, default_value)
