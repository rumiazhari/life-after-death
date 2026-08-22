extends Node

const WORLD_DATA := preload("res://scripts/voxel/voxel_world_data.gd")
const CHUNK_DATA := preload("res://scripts/voxel/voxel_chunk_data.gd")
const NAVIGATION := preload("res://scripts/voxel/voxel_navigation_service.gd")
const SPAWN_SAMPLER := preload("res://scripts/voxel/voxel_spawn_sampler.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")

var _failed := false


func _ready() -> void:
	var world = WORLD_DATA.new(77)
	var chunk = CHUNK_DATA.new(Vector2i.ZERO)
	for z in range(-6, 7):
		for x in range(-6, 7):
			chunk.set_cell(Vector3i(x, 0, z), MATERIALS.Id.FLOOR)
	for z in range(-6, 7):
		if z != 0:
			chunk.set_cell(Vector3i(0, 1, z), MATERIALS.Id.BRICK)
			chunk.set_cell(Vector3i(0, 2, z), MATERIALS.Id.BRICK)
	chunk.set_cell(Vector3i(0, 1, 0), MATERIALS.Id.WOOD, &"test/door")
	chunk.set_cell(Vector3i(0, 2, 0), MATERIALS.Id.WOOD, &"test/door")
	world.add_chunk(chunk)
	var navigation = NAVIGATION.new()
	navigation.configure(world)
	var start := Vector3(-4.5, 1.0, 0.5)
	var goal := Vector3(4.5, 1.0, 0.5)
	_assert(navigation.find_path(start, goal).is_empty(), "closed voxel door separates navigation regions")
	chunk.set_cell(Vector3i(0, 1, 0), MATERIALS.Id.AIR)
	chunk.set_cell(Vector3i(0, 2, 0), MATERIALS.Id.AIR)
	var open_path := navigation.find_path(start, goal)
	_assert(not open_path.is_empty(), "opening the voxel door creates a path without rebuilding a separate grid")
	_assert(navigation.is_direct_path_clear(start, goal), "voxel line traversal crosses an open aperture")
	chunk.set_cell(Vector3i(0, 1, 0), MATERIALS.Id.WOOD)
	_assert(not navigation.is_direct_path_clear(start, goal), "voxel line traversal is blocked by a closed door")
	chunk.set_cell(Vector3i(0, 1, 0), MATERIALS.Id.AIR)
	var sampler = SPAWN_SAMPLER.new()
	sampler.configure(navigation)
	var region := {"id": &"test/region", "position": Vector2(64, 64), "radius": 64.0}
	var first: Vector3 = sampler.sample_region(region, Vector2i.ZERO, 9001)
	var second: Vector3 = sampler.sample_region(region, Vector2i.ZERO, 9001)
	_assert(first == second and first != Vector3.INF, "voxel spawn sampling is deterministic and returns a walkable cell")
	_assert(navigation.is_walkable(Vector3i(floori(first.x), 0, floori(first.z))), "spawn sampler never accepts an obstructed cell")
	if _failed:
		get_tree().quit(1)
	else:
		print("VOXEL_NAVIGATION: PASS")
		get_tree().quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("VOXEL_NAVIGATION: FAIL: %s" % message)
