extends Node

const GENERATION_QUEUE := preload("res://scripts/voxel/voxel_chunk_generation_queue.gd")
const CITY_GENERATOR := preload("res://scripts/world/procedural_city_generator.gd")

var _failed := false


func _ready() -> void:
	await _run()


func _run() -> void:
	var queue = GENERATION_QUEUE.new()
	queue.configure(20260822, 2, {"door_states": {}, "prop_states": {}})
	var requested: Array[Vector2i] = []
	for z in range(-1, 2):
		for x in range(-1, 3):
			var coordinate := Vector2i(x, z)
			requested.append(coordinate)
			queue.request(coordinate)
	var retained: Array[Vector2i] = []
	for coordinate in requested:
		if coordinate.x <= 1:
			retained.append(coordinate)
	queue.retain_only(retained)
	var initial: Dictionary = queue.metrics()
	_assert(int(initial.active) <= 2, "generation queue enforces its two-thread concurrency cap")
	_assert(int(initial.active) + int(initial.queued) <= retained.size(), "generation queue discards queued coordinates outside the retained working set")
	for frame in range(1200):
		queue.poll()
		var metrics: Dictionary = queue.metrics()
		if int(metrics.active) == 0 and int(metrics.queued) == 0:
			break
		await get_tree().process_frame
	var completed: Dictionary = queue.metrics()
	print("VOXEL_CHUNK_GENERATION_QUEUE_METRICS ", completed)
	_assert(int(completed.active) == 0 and int(completed.queued) == 0, "all retained background jobs complete within the bounded frame allowance")
	_assert(int(completed.ready) == retained.size(), "exactly the retained 3-by-3 city payloads become ready")
	for coordinate in retained:
		var payload: Dictionary = queue.take_ready(coordinate)
		var city: Dictionary = payload.get("city", {})
		_assert(not city.is_empty() and city.get("chunk_coordinate", coordinate) == coordinate, "ready payload preserves its requested deterministic chunk coordinate")
		_assert(payload.get("world") != null and payload.get("world").get_chunk(coordinate) != null, "ready payload includes its off-thread voxelized world data")
		if coordinate == Vector2i.ZERO:
			var direct_city: Dictionary = CITY_GENERATOR.new().generate_streamed_chunk(20260822, coordinate)
			_assert(JSON.stringify(city) == JSON.stringify(direct_city), "background generation exactly matches direct deterministic generation")
	_assert(int(queue.metrics().ready) == 0, "consumed background payloads leave no ready-cache residue")
	queue.shutdown()
	if _failed:
		get_tree().quit(1)
	else:
		print("VOXEL_CHUNK_GENERATION_QUEUE: PASS")
		get_tree().quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("VOXEL_CHUNK_GENERATION_QUEUE: FAIL: %s" % message)
