class_name VoxelWorldData
extends RefCounted

const SNAPSHOT_VERSION := 2
const COORDINATES := preload("res://scripts/voxel/voxel_coordinates.gd")
const CHUNK_DATA := preload("res://scripts/voxel/voxel_chunk_data.gd")

var world_seed := 0
var chunks: Dictionary = {} # Vector2i -> VoxelChunkData
var stable_object_cells: Dictionary = {} # StringName -> world Vector3i
var stable_objects: Dictionary = {} # StringName -> {kind, cell, state}
var voxel_overrides: Dictionary = {} # stable cell id -> {material_id, durability}


func _init(seed_value: int = 0) -> void:
	world_seed = seed_value


func add_chunk(chunk) -> void:
	chunks[chunk.coordinate] = chunk


func merge_chunk_world(other) -> void:
	if other == null:
		return
	for coordinate in other.chunks:
		chunks[coordinate] = other.chunks[coordinate]
	for stable_id in other.stable_object_cells:
		stable_object_cells[stable_id] = other.stable_object_cells[stable_id]
	for stable_id in other.stable_objects:
		stable_objects[stable_id] = (other.stable_objects[stable_id] as Dictionary).duplicate(true)
	for cell_id in other.voxel_overrides:
		voxel_overrides[cell_id] = (other.voxel_overrides[cell_id] as Dictionary).duplicate(true)


func remove_chunk(coordinate: Vector2i) -> void:
	chunks.erase(coordinate)
	for stable_id in stable_objects.keys():
		var cell: Vector3i = stable_objects[stable_id].get("cell", Vector3i.ZERO)
		if COORDINATES.world_cell_to_chunk(cell) == coordinate:
			stable_objects.erase(stable_id)
			stable_object_cells.erase(stable_id)


func apply_overrides_to_chunk(coordinate: Vector2i) -> int:
	var chunk = get_chunk(coordinate)
	if chunk == null:
		return 0
	var applied := 0
	for stable_id_variant in voxel_overrides:
		var parts := String(stable_id_variant).split("/")
		if parts.size() != 4 or parts[0] != "voxel":
			continue
		var world_cell := Vector3i(int(parts[1]), int(parts[2]), int(parts[3]))
		if COORDINATES.world_cell_to_chunk(world_cell) != coordinate:
			continue
		var state: Dictionary = voxel_overrides[stable_id_variant]
		chunk.set_cell(COORDINATES.world_cell_to_local(world_cell, coordinate), int(state.get("material_id", 0)))
		applied += 1
	return applied


func get_chunk(coordinate: Vector2i):
	return chunks.get(coordinate)


func register_object(stable_id: StringName, world_cell: Vector3i) -> void:
	stable_object_cells[stable_id] = world_cell


func register_stable_object(stable_id: StringName, kind: StringName, world_cell: Vector3i, state: Dictionary = {}) -> void:
	stable_objects[stable_id] = {
		"kind": kind,
		"cell": world_cell,
		"state": state.duplicate(true),
	}


func get_stable_object(stable_id: StringName) -> Dictionary:
	return (stable_objects.get(stable_id, {}) as Dictionary).duplicate(true)


func set_stable_object_state(stable_id: StringName, state: Dictionary) -> void:
	if not stable_objects.has(stable_id):
		return
	stable_objects[stable_id]["state"] = state.duplicate(true)


func set_voxel_override(world_cell: Vector3i, material_id: int, durability: float) -> void:
	voxel_overrides[COORDINATES.stable_cell_id(world_cell)] = {
		"material_id": material_id,
		"durability": durability,
	}


func get_voxel_override(world_cell: Vector3i) -> Dictionary:
	return (voxel_overrides.get(COORDINATES.stable_cell_id(world_cell), {}) as Dictionary).duplicate()


func to_snapshot() -> Dictionary:
	var chunk_rows: Array = []
	var coordinates: Array = chunks.keys()
	coordinates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	for coordinate in coordinates:
		chunk_rows.append(chunks[coordinate].to_snapshot())
	var object_rows: Array = []
	var object_ids: Array = stable_object_cells.keys()
	object_ids.sort_custom(func(a, b) -> bool: return String(a) < String(b))
	for stable_id in object_ids:
		var cell: Vector3i = stable_object_cells[stable_id]
		object_rows.append([String(stable_id), cell.x, cell.y, cell.z])
	var stable_rows: Array = []
	var stable_ids: Array = stable_objects.keys()
	stable_ids.sort_custom(func(a, b) -> bool: return String(a) < String(b))
	for stable_id in stable_ids:
		var record: Dictionary = stable_objects[stable_id]
		var cell: Vector3i = record["cell"]
		stable_rows.append([String(stable_id), String(record["kind"]), cell.x, cell.y, cell.z, _canonical_variant(record.get("state", {}))])
	var override_rows: Array = []
	var override_ids: Array = voxel_overrides.keys()
	override_ids.sort_custom(func(a, b) -> bool: return String(a) < String(b))
	for stable_id in override_ids:
		var state: Dictionary = voxel_overrides[stable_id]
		override_rows.append([String(stable_id), int(state["material_id"]), float(state["durability"])])
	return {
		"version": SNAPSHOT_VERSION,
		"world_seed": world_seed,
		"chunks": chunk_rows,
		"stable_object_cells": object_rows,
		"stable_objects": stable_rows,
		"voxel_overrides": override_rows,
	}


static func from_snapshot(snapshot: Dictionary):
	var version := int(snapshot.get("version", -1))
	if version < 1 or version > SNAPSHOT_VERSION:
		return null
	var result = load("res://scripts/voxel/voxel_world_data.gd").new(int(snapshot.get("world_seed", 0)))
	for chunk_snapshot in snapshot.get("chunks", []):
		result.add_chunk(CHUNK_DATA.from_snapshot(chunk_snapshot))
	for row_variant in snapshot.get("stable_object_cells", []):
		var row: Array = row_variant
		result.register_object(StringName(row[0]), Vector3i(int(row[1]), int(row[2]), int(row[3])))
	for row_variant in snapshot.get("stable_objects", []):
		var row: Array = row_variant
		result.register_stable_object(StringName(row[0]), StringName(row[1]), Vector3i(int(row[2]), int(row[3]), int(row[4])), row[5])
	for row_variant in snapshot.get("voxel_overrides", []):
		var row: Array = row_variant
		result.voxel_overrides[StringName(row[0])] = {"material_id": int(row[1]), "durability": float(row[2])}
	return result


func fingerprint() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(to_snapshot()).to_utf8_buffer())
	return context.finish().hex_encode()


static func _canonical_variant(value):
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort_custom(func(a, b) -> bool: return String(a) < String(b))
		for key in keys:
			result[String(key)] = _canonical_variant(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_canonical_variant(item))
		return result
	if value is StringName:
		return String(value)
	return value
