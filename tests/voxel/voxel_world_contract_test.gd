extends Node

const COORDINATES := preload("res://scripts/voxel/voxel_coordinates.gd")
const CHUNK_DATA := preload("res://scripts/voxel/voxel_chunk_data.gd")
const WORLD_DATA := preload("res://scripts/voxel/voxel_world_data.gd")
const VOXELIZER := preload("res://scripts/voxel/semantic_voxelizer.gd")
const ADAPTER := preload("res://scripts/voxel/voxel_world_state_adapter.gd")
const CITY_GENERATOR := preload("res://scripts/world/procedural_city_generator.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")

var _failed := false


func _ready() -> void:
	_run()


func _run() -> void:
	_test_coordinates()
	_test_chunk_snapshot_and_fingerprint()
	_test_world_snapshot_and_adapter()
	_test_existing_semantic_city_voxelization()
	WorldState.reset()
	if _failed:
		get_tree().quit(1)
		return
	print("VOXEL_WORLD_CONTRACT: PASS")
	get_tree().quit(0)


func _test_coordinates() -> void:
	_assert(COORDINATES.world_cell_to_chunk(Vector3i(-44, 0, -44)) == Vector2i.ZERO, "origin chunk includes its negative edge")
	_assert(COORDINATES.world_cell_to_chunk(Vector3i(43, 0, 43)) == Vector2i.ZERO, "origin chunk includes its positive interior edge")
	_assert(COORDINATES.world_cell_to_chunk(Vector3i(44, 0, 0)) == Vector2i.RIGHT, "east boundary enters the east chunk")
	_assert(COORDINATES.world_cell_to_chunk(Vector3i(-45, 0, 0)) == Vector2i.LEFT, "west boundary enters the west chunk")
	var local := Vector2(-320.0, 640.0)
	var position: Vector3 = COORDINATES.semantic_local_to_world_position(local, Vector2i(2, -1), 3.0)
	_assert(COORDINATES.world_position_to_semantic_local(position, Vector2i(2, -1)).is_equal_approx(local), "semantic/world conversion round-trips")


func _test_chunk_snapshot_and_fingerprint() -> void:
	var chunk = CHUNK_DATA.new(Vector2i(-2, 3))
	chunk.set_cell(Vector3i(-44, 0, 43), 2)
	chunk.set_cell(Vector3i(4, 1, -7), 4, &"building/test")
	var first_fingerprint: String = chunk.fingerprint()
	var restored = CHUNK_DATA.from_snapshot(chunk.to_snapshot())
	_assert(restored.fingerprint() == first_fingerprint, "chunk snapshot preserves its deterministic fingerprint")
	_assert(restored.source_at(Vector3i(4, 1, -7)) == &"building/test", "chunk snapshot preserves semantic ownership")
	restored.set_cell(Vector3i(5, 1, -7), 4, &"building/test")
	_assert(restored.fingerprint() != first_fingerprint, "voxel changes alter the chunk fingerprint")


func _test_world_snapshot_and_adapter() -> void:
	WorldState.reset()
	var world = WORLD_DATA.new(20260822)
	var chunk = CHUNK_DATA.new(Vector2i.ZERO)
	chunk.set_cell(Vector3i.ZERO, 1)
	world.add_chunk(chunk)
	world.register_object(&"city/building/door", Vector3i(2, 1, -3))
	world.set_voxel_override(Vector3i(4, 2, 1), 0, 0.0)
	var fingerprint: String = world.fingerprint()
	var restored = WORLD_DATA.from_snapshot(world.to_snapshot())
	_assert(restored != null and restored.fingerprint() == fingerprint, "world snapshot round-trips exactly")
	_assert(restored.stable_object_cells[&"city/building/door"] == Vector3i(2, 1, -3), "stable object cells survive restore")
	_assert(restored.get_voxel_override(Vector3i(4, 2, 1)).get("material_id", -1) == 0, "destroyed voxel override survives restore")
	ADAPTER.store(world)
	var adapted = ADAPTER.restore()
	_assert(adapted != null and adapted.fingerprint() == fingerprint, "WorldState adapter preserves voxel snapshot data")
	var full_snapshot: Dictionary = WorldState.to_snapshot()
	var restored_from_full = ADAPTER.restore_from_world_state_snapshot(full_snapshot)
	_assert(restored_from_full != null and restored_from_full.fingerprint() == fingerprint, "voxel data survives the existing full WorldState snapshot boundary")
	ADAPTER.clear()
	_assert(ADAPTER.restore() == null, "WorldState adapter clears without affecting other flags")


func _test_existing_semantic_city_voxelization() -> void:
	var seed_value := 20260821
	var generator = CITY_GENERATOR.new()
	var city: Dictionary = generator.generate_streamed_chunk(seed_value, Vector2i.ZERO)
	var voxelizer = VOXELIZER.new()
	var first = voxelizer.voxelize_chunk(city, seed_value, Vector2i.ZERO)
	var second = voxelizer.voxelize_chunk(city, seed_value, Vector2i.ZERO)
	_assert(first.fingerprint() == second.fingerprint(), "same semantic model produces the same voxel fingerprint")
	var different_city: Dictionary = generator.generate_streamed_chunk(seed_value + 1, Vector2i.ZERO)
	var different = voxelizer.voxelize_chunk(different_city, seed_value + 1, Vector2i.ZERO)
	_assert(first.fingerprint() != different.fingerprint(), "different semantic seeds produce different voxel fingerprints")
	var chunk = first.get_chunk(Vector2i.ZERO)
	_assert(chunk != null and chunk.cells.size() > COORDINATES.CHUNK_CELLS * COORDINATES.CHUNK_CELLS, "voxelized chunk contains ground and building volume")
	_assert(first.stable_object_cells.size() == (city.get("buildings", []) as Array).size(), "every semantic building registers one stable voxel anchor")
	var has_owned_structure := false
	for source_id in chunk.cell_sources.values():
		if StringName(source_id) != &"":
			has_owned_structure = true
			break
	_assert(has_owned_structure, "structural voxels retain their semantic building owner")
	var east_city: Dictionary = generator.generate_streamed_chunk(seed_value, Vector2i.RIGHT)
	var east = voxelizer.voxelize_chunk(east_city, seed_value, Vector2i.RIGHT)
	var east_chunk = east.get_chunk(Vector2i.RIGHT)
	var origin_portal_rows := _edge_transport_rows(chunk, COORDINATES.HALF_CHUNK_CELLS - 1)
	var east_portal_rows := _edge_transport_rows(east_chunk, -COORDINATES.HALF_CHUNK_CELLS)
	_assert(origin_portal_rows == east_portal_rows and not origin_portal_rows.is_empty(), "adjacent semantic chunks rasterize matching east-west road portals")


func _edge_transport_rows(chunk, x: int) -> Array[int]:
	var rows: Array[int] = []
	for z in range(-COORDINATES.HALF_CHUNK_CELLS, COORDINATES.HALF_CHUNK_CELLS):
		var material_id: int = chunk.get_cell(Vector3i(x, 0, z))
		if material_id == MATERIALS.Id.ROAD or material_id == MATERIALS.Id.COBBLE:
			rows.append(z)
	return rows


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("VOXEL_WORLD_CONTRACT: FAIL: %s" % message)
