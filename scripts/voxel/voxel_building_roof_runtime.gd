class_name VoxelBuildingRoofRuntime
extends Node3D

const COORDINATES := preload("res://scripts/voxel/voxel_coordinates.gd")
const CHUNK_DATA := preload("res://scripts/voxel/voxel_chunk_data.gd")
const CHUNK_RENDERER := preload("res://scripts/voxel/voxel_chunk.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")

var _chunk_roofs: Dictionary = {} # Vector2i -> {stable id -> renderer}


func populate_chunk(world_data, coordinate: Vector2i, occlusion_controller, damage_service) -> int:
	clear_chunk(coordinate, occlusion_controller)
	var source = world_data.get_chunk(coordinate)
	if source == null:
		return 0
	var groups: Dictionary = {}
	for cell_variant in source.cells:
		var cell: Vector3i = cell_variant
		if int(source.cells[cell]) != MATERIALS.Id.ROOF:
			continue
		var stable_id: StringName = source.source_at(cell)
		if stable_id == &"":
			continue
		if not groups.has(stable_id):
			groups[stable_id] = CHUNK_DATA.new(coordinate)
		groups[stable_id].set_cell(cell, MATERIALS.Id.ROOF, stable_id)
	var renderers: Dictionary = {}
	for stable_id_variant in groups:
		var stable_id := StringName(stable_id_variant)
		var renderer = _create_renderer(coordinate, stable_id, groups[stable_id])
		renderers[stable_id] = renderer
		occlusion_controller.register_roof(stable_id, renderer)
		var roof_materials: Array[int] = [MATERIALS.Id.ROOF]
		damage_service.register_renderer(coordinate, renderer, roof_materials, false, stable_id)
	_chunk_roofs[coordinate] = renderers
	return renderers.size()


func clear_chunk(coordinate: Vector2i, occlusion_controller) -> void:
	var renderers: Dictionary = _chunk_roofs.get(coordinate, {})
	for stable_id in renderers:
		occlusion_controller.unregister_roof(StringName(stable_id))
		var renderer: Node = renderers[stable_id]
		if is_instance_valid(renderer):
			renderer.queue_free()
	_chunk_roofs.erase(coordinate)


func roof_count() -> int:
	var total := 0
	for coordinate in _chunk_roofs:
		total += (_chunk_roofs[coordinate] as Dictionary).size()
	return total


func renderer_for(stable_id: StringName):
	for coordinate in _chunk_roofs:
		var renderers: Dictionary = _chunk_roofs[coordinate]
		if renderers.has(stable_id):
			return renderers[stable_id]
	return null


func _create_renderer(coordinate: Vector2i, stable_id: StringName, chunk_data):
	var renderer = CHUNK_RENDERER.new()
	renderer.name = "Roof_%s" % String(stable_id).replace("/", "__").replace(":", "_")
	renderer.position = Vector3(coordinate.x * COORDINATES.CHUNK_CELLS, 0.0, coordinate.y * COORDINATES.CHUNK_CELLS)
	renderer.generate_collision = false
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	renderer.add_child(mesh)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	renderer.add_child(collision)
	renderer.configure(chunk_data.cells, MATERIALS.create_render_materials())
	add_child(renderer)
	return renderer
