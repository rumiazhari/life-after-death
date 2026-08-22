extends Node

const STREAM_CONTROLLER := preload("res://scripts/voxel/voxel_chunk_stream_controller.gd")
const CHUNK_DATA := preload("res://scripts/voxel/voxel_chunk_data.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")

var _failed := false
var _provider_calls: Array[Vector2i] = []
var _delayed_ready := false


func _ready() -> void:
	var controller = STREAM_CONTROLLER.new()
	controller.load_radius = 1
	controller.retain_radius = 1
	controller.collision_radius = 0
	controller.max_chunk_builds_per_frame = 1
	add_child(controller)
	controller.configure(_provide_chunk)
	_assert(controller.pending_coordinates.size() == 9, "radius-one stream queues exactly nine chunks")
	_assert(controller.process_build_budget() == 1, "stream budget builds only one queued chunk per frame")
	_assert(controller.loaded_chunks.has(Vector2i.ZERO), "distance ordering loads the active center first")
	for index in range(8):
		_assert(controller.process_build_budget() == 1, "each streaming step respects the one-chunk build budget")
	var initial: Dictionary = controller.metrics()
	_assert(int(initial.loaded_chunks) == 9 and int(initial.pending_chunks) == 0, "stream reaches the bounded radius-one working set")
	_assert(int(initial.collision_chunks) == 1, "collision generation is limited to the active center chunk")
	_assert(int(initial.voxel_count) == 18 and int(initial.visible_faces) == 90, "stream metrics aggregate merged voxel geometry")
	controller.set_center(Vector2i.RIGHT)
	_assert(controller.loaded_chunks.size() == 6 and controller.pending_coordinates.size() == 3, "center shift retains six overlapping chunks and queues three new chunks")
	for index in range(3):
		controller.process_build_budget()
	var shifted: Dictionary = controller.metrics()
	_assert(int(shifted.loaded_chunks) == 9 and int(shifted.total_builds) == 12, "center shift restores the nine-chunk working set without rebuilding retained chunks")
	_assert(int(shifted.total_unloads) == 3 and int(shifted.collision_chunks) == 1, "center shift unloads only the expired edge and moves the collision budget")
	_assert(_provider_calls.size() == 12, "chunk provider is called only for chunks that are actually built")
	var delayed = STREAM_CONTROLLER.new()
	delayed.load_radius = 0
	delayed.retain_radius = 0
	delayed.max_chunk_builds_per_frame = 1
	add_child(delayed)
	delayed.configure(_provide_delayed_chunk)
	_assert(delayed.process_build_budget() == 0 and delayed.pending_coordinates == [Vector2i.ZERO], "a not-ready provider retains its coordinate instead of dropping the stream request")
	_delayed_ready = true
	_assert(delayed.process_build_budget() == 1 and delayed.loaded_chunks.has(Vector2i.ZERO), "a retained request builds on the first frame its payload becomes ready")
	if _failed:
		get_tree().quit(1)
	else:
		print("VOXEL_STREAMING_BUDGET: PASS")
		get_tree().quit(0)


func _provide_chunk(coordinate: Vector2i):
	_provider_calls.append(coordinate)
	var chunk = CHUNK_DATA.new(coordinate)
	chunk.set_cell(Vector3i.ZERO, MATERIALS.Id.GRASS)
	chunk.set_cell(Vector3i.RIGHT, MATERIALS.Id.BRICK)
	return chunk


func _provide_delayed_chunk(coordinate: Vector2i):
	return _provide_chunk(coordinate) if _delayed_ready else null


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("VOXEL_STREAMING_BUDGET: FAIL: %s" % message)
