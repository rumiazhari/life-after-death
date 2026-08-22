class_name VoxelWorldDropRuntime3D
extends Node3D

const DROP_NODE := preload("res://scripts/voxel/voxel_world_drop_3d.gd")

var _nodes_by_id: Dictionary = {}


func _ready() -> void:
	WorldState.drop_registered.connect(_on_drop_registered)
	WorldState.drop_removed.connect(_on_drop_removed)
	for drop_id in WorldState.drops:
		_add_drop(WorldState.drops[drop_id])


func active_drop_count() -> int:
	return _nodes_by_id.size()


func node_for(drop_id: int):
	return _nodes_by_id.get(drop_id)


func _on_drop_registered(drop: WorldDrop) -> void:
	_add_drop(drop)


func _on_drop_removed(drop_id: int) -> void:
	var node: Node = _nodes_by_id.get(drop_id)
	_nodes_by_id.erase(drop_id)
	if is_instance_valid(node):
		node.queue_free()


func _add_drop(drop: WorldDrop) -> void:
	if drop == null or _nodes_by_id.has(drop.id):
		return
	var node = DROP_NODE.new()
	node.configure(drop)
	add_child(node)
	_nodes_by_id[drop.id] = node
