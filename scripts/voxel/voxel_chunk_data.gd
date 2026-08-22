class_name VoxelChunkData
extends RefCounted

var coordinate := Vector2i.ZERO
var cells: Dictionary = {} # local Vector3i -> material id
var cell_sources: Dictionary = {} # local Vector3i -> stable semantic StringName


func _init(chunk_coordinate: Vector2i = Vector2i.ZERO) -> void:
	coordinate = chunk_coordinate


func set_cell(local_cell: Vector3i, material_id: int, source_id: StringName = &"") -> void:
	if material_id <= 0:
		cells.erase(local_cell)
		cell_sources.erase(local_cell)
		return
	cells[local_cell] = material_id
	if source_id != &"":
		cell_sources[local_cell] = source_id
	else:
		cell_sources.erase(local_cell)


func get_cell(local_cell: Vector3i) -> int:
	return int(cells.get(local_cell, 0))


func source_at(local_cell: Vector3i) -> StringName:
	return StringName(cell_sources.get(local_cell, &""))


func to_snapshot() -> Dictionary:
	var cell_rows: Array = []
	for raw_cell in _sorted_cells(cells.keys()):
		var cell: Vector3i = raw_cell
		cell_rows.append([cell.x, cell.y, cell.z, int(cells[cell])])
	var source_rows: Array = []
	for raw_cell in _sorted_cells(cell_sources.keys()):
		var cell: Vector3i = raw_cell
		source_rows.append([cell.x, cell.y, cell.z, String(cell_sources[cell])])
	return {
		"coordinate": [coordinate.x, coordinate.y],
		"cells": cell_rows,
		"cell_sources": source_rows,
	}


static func from_snapshot(snapshot: Dictionary):
	var coordinate_data: Array = snapshot.get("coordinate", [0, 0])
	var result = load("res://scripts/voxel/voxel_chunk_data.gd").new(Vector2i(int(coordinate_data[0]), int(coordinate_data[1])))
	for row_variant in snapshot.get("cells", []):
		var row: Array = row_variant
		result.set_cell(Vector3i(int(row[0]), int(row[1]), int(row[2])), int(row[3]))
	for row_variant in snapshot.get("cell_sources", []):
		var row: Array = row_variant
		var cell := Vector3i(int(row[0]), int(row[1]), int(row[2]))
		if result.cells.has(cell):
			result.cell_sources[cell] = StringName(row[3])
	return result


func fingerprint() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(to_snapshot()).to_utf8_buffer())
	return context.finish().hex_encode()


static func _sorted_cells(values: Array) -> Array:
	var result := values.duplicate()
	result.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.x != b.x: return a.x < b.x
		if a.y != b.y: return a.y < b.y
		return a.z < b.z
	)
	return result
