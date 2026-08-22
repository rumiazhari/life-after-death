class_name VoxelStructuralDamageService
extends Node

const COORDINATES := preload("res://scripts/voxel/voxel_coordinates.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")
const CHUNK_DATA := preload("res://scripts/voxel/voxel_chunk_data.gd")

var world_data
var _renderers: Array[Dictionary] = []
var _batch_depth := 0
var _dirty_coordinates: Dictionary = {}
var renderer_refresh_count := 0


func configure(data) -> void:
	world_data = data


func register_renderer(chunk_coordinate: Vector2i, renderer: Node, material_ids: Array[int], refresh_now := true, source_id: StringName = &"", excluded_kinds: Array[StringName] = [], cell_filter := Callable()) -> void:
	_renderers.append({"coordinate": chunk_coordinate, "renderer": renderer, "materials": material_ids.duplicate(), "source_id": source_id, "excluded_kinds": excluded_kinds.duplicate(), "cell_filter": cell_filter})
	if refresh_now:
		_refresh_renderer(_renderers.back())


func unregister_coordinate(chunk_coordinate: Vector2i) -> void:
	for index in range(_renderers.size() - 1, -1, -1):
		if _renderers[index]["coordinate"] == chunk_coordinate:
			_renderers.remove_at(index)


func apply_hit(world_position: Vector3, hit_normal: Vector3, amount: float, damage_class: int) -> bool:
	var sample_position := world_position - hit_normal.normalized() * 0.01
	return apply_cell(COORDINATES.world_position_to_world_cell(sample_position), amount, damage_class)


func apply_cell(world_cell: Vector3i, amount: float, damage_class: int) -> bool:
	if world_data == null or amount <= 0.0:
		return false
	var coordinate: Vector2i = COORDINATES.world_cell_to_chunk(world_cell)
	var chunk = world_data.get_chunk(coordinate)
	if chunk == null:
		return false
	var local_cell: Vector3i = COORDINATES.world_cell_to_local(world_cell, coordinate)
	var material_id: int = chunk.get_cell(local_cell)
	var definition: Dictionary = MATERIALS.definition(material_id)
	if definition.is_empty() or float(definition.get("durability", -1.0)) < 0.0:
		return false
	if damage_class < int(definition.get("minimum_damage_class", 0)):
		return false
	var state: Dictionary = world_data.get_voxel_override(world_cell)
	var durability := float(state.get("durability", definition["durability"]))
	durability = maxf(0.0, durability - amount)
	var resulting_material := material_id if durability > 0.0 else MATERIALS.Id.AIR
	world_data.set_voxel_override(world_cell, resulting_material, durability)
	if durability <= 0.0:
		chunk.set_cell(local_cell, MATERIALS.Id.AIR)
		_request_refresh(coordinate)
	return true


func set_cell_material(world_cell: Vector3i, material_id: int, source_id: StringName = &"") -> bool:
	if world_data == null:
		return false
	var coordinate: Vector2i = COORDINATES.world_cell_to_chunk(world_cell)
	var chunk = world_data.get_chunk(coordinate)
	if chunk == null:
		return false
	var local_cell: Vector3i = COORDINATES.world_cell_to_local(world_cell, coordinate)
	chunk.set_cell(local_cell, material_id, source_id)
	_request_refresh(coordinate)
	return true


func refresh_chunk(coordinate: Vector2i) -> void:
	_request_refresh(coordinate)


func begin_batch() -> void:
	_batch_depth += 1


func end_batch() -> void:
	if _batch_depth <= 0:
		return
	_batch_depth -= 1
	if _batch_depth > 0:
		return
	var coordinates: Array = _dirty_coordinates.keys()
	_dirty_coordinates.clear()
	for coordinate in coordinates:
		_refresh_coordinate(coordinate)


func apply_explosion(origin: Vector3, radius: float, amount: float, damage_class: int) -> int:
	if radius <= 0.0 or amount <= 0.0:
		return 0
	var minimum := COORDINATES.world_position_to_world_cell(origin - Vector3.ONE * radius)
	var maximum := COORDINATES.world_position_to_world_cell(origin + Vector3.ONE * radius)
	var applied := 0
	begin_batch()
	for y in range(minimum.y, maximum.y + 1):
		for z in range(minimum.z, maximum.z + 1):
			for x in range(minimum.x, maximum.x + 1):
				var cell := Vector3i(x, y, z)
				var center := COORDINATES.world_cell_to_world_position(cell) + Vector3.ONE * 0.5
				var distance := origin.distance_to(center)
				if distance > radius:
					continue
				var falloff := clampf(1.0 - distance / radius, 0.25, 1.0)
				applied += 1 if apply_cell(cell, amount * falloff, damage_class) else 0
	end_batch()
	return applied


func _request_refresh(coordinate: Vector2i) -> void:
	if _batch_depth > 0:
		_dirty_coordinates[coordinate] = true
		return
	_refresh_coordinate(coordinate)


func _refresh_coordinate(coordinate: Vector2i) -> void:
	for registration in _renderers:
		if registration["coordinate"] == coordinate:
			_refresh_renderer(registration)


func _refresh_renderer(registration: Dictionary) -> void:
	if world_data == null or not is_instance_valid(registration["renderer"]):
		return
	var source = world_data.get_chunk(registration["coordinate"])
	if source == null:
		return
	var filtered = CHUNK_DATA.new(registration["coordinate"])
	var accepted: Array = registration["materials"]
	var source_id := StringName(registration.get("source_id", &""))
	var excluded_kinds: Array = registration.get("excluded_kinds", [])
	var cell_filter: Callable = registration.get("cell_filter", Callable())
	for cell in source.cells:
		var cell_source: StringName = source.source_at(cell)
		var material_id := int(source.cells[cell])
		if material_id not in accepted or (source_id != &"" and cell_source != source_id):
			continue
		if not excluded_kinds.is_empty() and cell_source != &"":
			var record: Dictionary = world_data.get_stable_object(cell_source)
			if StringName(record.get("kind", &"")) in excluded_kinds:
				continue
		if cell_filter.is_valid() and not cell_filter.call(cell, material_id, cell_source):
			continue
		filtered.set_cell(cell, material_id, cell_source)
	registration["renderer"].configure_from_chunk_data(filtered)
	renderer_refresh_count += 1
