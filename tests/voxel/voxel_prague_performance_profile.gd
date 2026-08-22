extends Node

const CITY_GENERATOR := preload("res://scripts/world/procedural_city_generator.gd")
const VOXELIZER := preload("res://scripts/voxel/semantic_voxelizer.gd")
const CHUNK_RENDERER := preload("res://scripts/voxel/voxel_chunk.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")
const COORDINATES := preload("res://scripts/voxel/voxel_coordinates.gd")

const PROFILE_BUDGET_USEC := 3_000_000
const CHUNK_BUILD_BUDGET_USEC := 1_000_000

var _failed := false


func _ready() -> void:
	var started_at := Time.get_ticks_usec()
	var total_voxels := 0
	var total_faces := 0
	var total_vertices := 0
	var total_objects := 0
	var maximum_build_usec := 0
	for coordinate in [Vector2i.ZERO, Vector2i.RIGHT]:
		var city: Dictionary = CITY_GENERATOR.new().generate_streamed_chunk(20260822, coordinate)
		var world = VOXELIZER.new().voxelize_chunk(city, 20260822, coordinate)
		var renderer = _create_renderer(coordinate, world.get_chunk(coordinate))
		var metrics: Dictionary = renderer.build_metrics()
		total_voxels += int(metrics.voxel_count)
		total_faces += int(metrics.visible_faces)
		total_vertices += int(metrics.vertex_count)
		total_objects += world.stable_objects.size()
		maximum_build_usec = maxi(maximum_build_usec, int(metrics.rebuild_usec))
		_assert(int(metrics.surface_count) <= MATERIALS.Id.WOOD, "Prague chunk uses no more than one merged surface per registered material")
		_assert(not bool(metrics.collision_enabled), "non-active Prague profile chunks skip trimesh collision generation")
	var elapsed_usec := Time.get_ticks_usec() - started_at
	_assert(total_voxels > 0 and total_faces > 0, "profile generated non-empty Prague voxel geometry")
	_assert(total_vertices == total_faces * 6, "profiled Prague meshes retain exact exposed-quad vertex accounting")
	_assert(total_objects > 0, "profile includes generated stable semantic objects")
	_assert(maximum_build_usec <= CHUNK_BUILD_BUDGET_USEC, "single Prague mesh build remains below the one-second safety budget")
	_assert(elapsed_usec <= PROFILE_BUDGET_USEC, "two Prague chunks generate, voxelize, and mesh below the three-second safety budget")
	var report := {
		"chunks": 2,
		"elapsed_usec": elapsed_usec,
		"maximum_mesh_build_usec": maximum_build_usec,
		"voxels": total_voxels,
		"visible_faces": total_faces,
		"vertices": total_vertices,
		"stable_objects": total_objects,
	}
	print("VOXEL_PRAGUE_PROFILE: %s" % JSON.stringify(report))
	if _failed:
		get_tree().quit(1)
	else:
		print("VOXEL_PRAGUE_PERFORMANCE: PASS")
		get_tree().quit(0)


func _create_renderer(coordinate: Vector2i, chunk_data):
	var renderer = CHUNK_RENDERER.new()
	renderer.name = "ProfileChunk_%d_%d" % [coordinate.x, coordinate.y]
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


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("VOXEL_PRAGUE_PERFORMANCE: FAIL: %s" % message)
