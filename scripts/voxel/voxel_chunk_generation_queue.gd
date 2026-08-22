class_name VoxelChunkGenerationQueue
extends RefCounted

const CITY_GENERATOR := preload("res://scripts/world/procedural_city_generator.gd")
const VOXELIZER := preload("res://scripts/voxel/semantic_voxelizer.gd")

var world_seed := 0
var max_concurrent_jobs := 2
var _queued: Array[Vector2i] = []
var _active: Dictionary = {} # Vector2i -> Thread
var _ready: Dictionary = {} # Vector2i -> city model
var _wanted: Dictionary = {}
var _persistent_state: Dictionary = {}
var total_requested := 0
var total_completed := 0
var total_discarded := 0


func configure(seed_value: int, concurrent_jobs := 2, persistent_state: Dictionary = {}) -> void:
	world_seed = seed_value
	max_concurrent_jobs = maxi(1, concurrent_jobs)
	_persistent_state = persistent_state.duplicate(true)


func update_persistent_state(persistent_state: Dictionary) -> void:
	_persistent_state = persistent_state.duplicate(true)


func request(coordinate: Vector2i) -> void:
	_wanted[coordinate] = true
	if _ready.has(coordinate) or _active.has(coordinate) or coordinate in _queued:
		return
	_queued.append(coordinate)
	total_requested += 1
	_start_queued_jobs()


func retain_only(coordinates: Array[Vector2i]) -> void:
	_wanted.clear()
	for coordinate in coordinates:
		_wanted[coordinate] = true
	for index in range(_queued.size() - 1, -1, -1):
		if not _wanted.has(_queued[index]):
			_queued.remove_at(index)
			total_discarded += 1
	for coordinate in _ready.keys():
		if not _wanted.has(coordinate):
			_ready.erase(coordinate)
			total_discarded += 1
	_start_queued_jobs()


func poll() -> int:
	var completed := 0
	for coordinate_variant in _active.keys():
		var coordinate: Vector2i = coordinate_variant
		var thread: Thread = _active[coordinate]
		if thread.is_alive():
			continue
		var city = thread.wait_to_finish()
		_active.erase(coordinate)
		total_completed += 1
		completed += 1
		if _wanted.has(coordinate) and city is Dictionary and not city.is_empty():
			_ready[coordinate] = city
		else:
			total_discarded += 1
	_start_queued_jobs()
	return completed


func has_ready(coordinate: Vector2i) -> bool:
	return _ready.has(coordinate)


func take_ready(coordinate: Vector2i) -> Dictionary:
	var city: Dictionary = _ready.get(coordinate, {})
	_ready.erase(coordinate)
	return city


func metrics() -> Dictionary:
	return {
		"queued": _queued.size(),
		"active": _active.size(),
		"ready": _ready.size(),
		"requested": total_requested,
		"completed": total_completed,
		"discarded": total_discarded,
	}


func shutdown() -> void:
	_queued.clear()
	_ready.clear()
	_wanted.clear()
	for coordinate in _active.keys():
		var thread: Thread = _active[coordinate]
		thread.wait_to_finish()
	_active.clear()


func _start_queued_jobs() -> void:
	while _active.size() < max_concurrent_jobs and not _queued.is_empty():
		var coordinate: Vector2i = _queued.pop_front()
		if not _wanted.has(coordinate):
			total_discarded += 1
			continue
		var thread := Thread.new()
		_active[coordinate] = thread
		var error := thread.start(_generate_payload.bind(world_seed, coordinate, _persistent_state.duplicate(true)))
		if error != OK:
			_active.erase(coordinate)
			total_discarded += 1


static func _generate_payload(seed_value: int, coordinate: Vector2i, persistent_state: Dictionary) -> Dictionary:
	var city: Dictionary = CITY_GENERATOR.new().generate_streamed_chunk(seed_value, coordinate)
	if city.is_empty() or not String(city.get("generation_error", "")).is_empty():
		return {}
	var generated_world = VOXELIZER.new().voxelize_chunk(city, seed_value, coordinate, persistent_state)
	return {"city": city, "world": generated_world}
