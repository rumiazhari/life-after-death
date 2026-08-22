class_name VoxelSemanticRuntime
extends Node3D

const SEMANTIC_INTERACTABLE := preload("res://scripts/voxel/voxel_semantic_interactable_3d.gd")
const COORDINATES := preload("res://scripts/voxel/voxel_coordinates.gd")

var _chunk_nodes: Dictionary = {} # Vector2i -> Array[Node]
var _stable_nodes: Dictionary = {} # StringName -> semantic interaction Area3D


func populate(world_data, structural_damage_service: VoxelStructuralDamageService) -> void:
	for coordinate in _chunk_nodes.keys():
		clear_chunk(coordinate)
	var stable_ids: Array = world_data.stable_objects.keys()
	stable_ids.sort_custom(func(a, b) -> bool: return String(a) < String(b))
	for stable_id_variant in stable_ids:
		var stable_id := StringName(stable_id_variant)
		var record: Dictionary = world_data.get_stable_object(stable_id)
		_add_record(world_data, structural_damage_service, stable_id, record)


func populate_chunk(world_data, structural_damage_service: VoxelStructuralDamageService, coordinate: Vector2i) -> int:
	clear_chunk(coordinate)
	var stable_ids: Array = world_data.stable_objects.keys()
	stable_ids.sort_custom(func(a, b) -> bool: return String(a) < String(b))
	var created := 0
	for stable_id_variant in stable_ids:
		var stable_id := StringName(stable_id_variant)
		var record: Dictionary = world_data.get_stable_object(stable_id)
		var cell: Vector3i = record.get("cell", Vector3i.ZERO)
		if COORDINATES.world_cell_to_chunk(cell) != coordinate:
			continue
		created += 1 if _add_record(world_data, structural_damage_service, stable_id, record) else 0
	return created


func clear_chunk(coordinate: Vector2i) -> void:
	var nodes: Array = _chunk_nodes.get(coordinate, [])
	for node_variant in nodes:
		var node: Node = node_variant
		if is_instance_valid(node):
			if "stable_id" in node:
				_stable_nodes.erase(node.stable_id)
			node.queue_free()
	_chunk_nodes.erase(coordinate)


func _add_record(world_data, structural_damage_service: VoxelStructuralDamageService, stable_id: StringName, record: Dictionary) -> bool:
	if not _is_interactive(record):
		return false
	var area = SEMANTIC_INTERACTABLE.new()
	area.name = _safe_node_name(stable_id)
	add_child(area)
	area.configure(world_data, structural_damage_service, stable_id, record)
	_stable_nodes[stable_id] = area
	var cell: Vector3i = record.get("cell", Vector3i.ZERO)
	var coordinate := COORDINATES.world_cell_to_chunk(cell)
	if not _chunk_nodes.has(coordinate):
		_chunk_nodes[coordinate] = []
	(_chunk_nodes[coordinate] as Array).append(area)
	return true


func node_for(stable_id: StringName):
	var node = _stable_nodes.get(stable_id)
	return node if is_instance_valid(node) else null


func _is_interactive(record: Dictionary) -> bool:
	var kind := StringName(record.get("kind", &""))
	if kind in [&"door", &"scavenge_point"]:
		return true
	if kind not in [&"furniture", &"exterior_prop"]:
		return false
	var state: Dictionary = record.get("state", {})
	return not (state.get("items", {}) as Dictionary).is_empty() or int(state.get("yield", 0)) > 0


func _safe_node_name(stable_id: StringName) -> String:
	return String(stable_id).replace("/", "__").replace(":", "_")
