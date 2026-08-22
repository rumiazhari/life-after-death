class_name VoxelRoofOcclusionController3D
extends Node

## Drives per-building presentation state from the tracked actor position:
## roofs hide while the actor stands inside a building's stable bounds, and
## the matching VoxelBuildingShellRuntime lowers its camera-facing walls
## ("cutaway") so interiors stay readable, Project-Zomboid style.

signal building_cutaway_changed(building_id: StringName, active: bool)

const SHELL_SIDE_NORMALS := preload("res://scripts/voxel/voxel_building_shell_runtime.gd").SIDE_NORMALS

var world_data
var tracked_actor: Node3D
var camera: Camera3D
var shell_runtime
var _registrations: Dictionary = {} # building stable id -> roof renderer
var _inside_buildings: Dictionary = {} # building stable id -> true
var _last_front_sides: Array[StringName] = []


func configure(data, actor: Node3D, view_camera: Camera3D = null, shells = null) -> void:
	world_data = data
	tracked_actor = actor
	camera = view_camera
	shell_runtime = shells


func register_roof(stable_id: StringName, renderer: Node3D) -> void:
	_registrations[stable_id] = renderer
	update_visibility()


func unregister_roof(stable_id: StringName) -> void:
	_registrations.erase(stable_id)


func update_visibility() -> void:
	if world_data == null or not is_instance_valid(tracked_actor):
		return
	var front_sides := _compute_front_sides()
	if shell_runtime != null and front_sides != _last_front_sides:
		_last_front_sides = front_sides.duplicate()
		shell_runtime.set_front_sides(front_sides)
	for stable_id in _registrations:
		var renderer: Node3D = _registrations[stable_id]
		if not is_instance_valid(renderer):
			continue
		var state: Dictionary = world_data.get_stable_object(stable_id).get("state", {})
		var bounds: Array = state.get("bounds", [])
		var inside := _contains_xz(bounds, tracked_actor.global_position)
		renderer.visible = not inside
		if inside:
			_inside_buildings[stable_id] = true
		elif _inside_buildings.has(stable_id):
			_inside_buildings.erase(stable_id)
		if shell_runtime != null and shell_runtime.is_cutaway(stable_id) != inside:
			shell_runtime.set_cutaway(stable_id, inside, front_sides)
			building_cutaway_changed.emit(stable_id, inside)


func refresh_cutaway() -> void:
	if shell_runtime == null:
		return
	var front_sides := _compute_front_sides()
	for stable_id in _inside_buildings:
		shell_runtime.set_cutaway(stable_id, true, front_sides)


func is_inside_building(stable_id: StringName) -> bool:
	return _inside_buildings.has(stable_id)


func _compute_front_sides() -> Array[StringName]:
	var result: Array[StringName] = []
	var toward_camera := Vector2.ZERO
	if is_instance_valid(camera):
		var forward := -camera.global_transform.basis.z
		toward_camera = Vector2(-forward.x, -forward.z)
		if toward_camera.length_squared() < 0.0001:
			toward_camera = Vector2.ONE.normalized()
		else:
			toward_camera = toward_camera.normalized()
	else:
		toward_camera = Vector2(1.0, 1.0).normalized()
	for side_name_variant in SHELL_SIDE_NORMALS:
		var side_name: StringName = side_name_variant
		var normal: Vector2 = SHELL_SIDE_NORMALS[side_name]
		if normal.dot(toward_camera) > 0.25:
			result.append(side_name)
	return result


func _contains_xz(bounds: Array, position: Vector3) -> bool:
	if bounds.size() != 4:
		return false
	return position.x >= float(bounds[0]) and position.x < float(bounds[2]) + 1.0 and position.z >= float(bounds[1]) and position.z < float(bounds[3]) + 1.0
