class_name StreamingWorld
extends Node2D
## Bounded renderer for an unbounded deterministic chunk coordinate space.
## At most a small square around the player is resident; semantic chunks are
## regenerated from world_seed + coordinate after leaving and returning.

signal generation_completed(seed_value: int)
signal generation_failed(seed_value: int, errors: Array[String])
signal chunk_activated(coordinate: Vector2i)
signal chunk_unloaded(coordinate: Vector2i)

const CHUNK_SCENE := preload("res://scenes/world/maps/ProceduralDistrict.tscn")
const CHUNK_SIZE := Vector2(2816, 2816)

@export var city_seed: int = -1
@export var active_radius: int = 1
@export var retain_radius: int = 2

var resolved_seed: int = 0
var generation_complete := false
var generation_succeeded := false
var generation_duration_ms := 0
var generation_errors: Array[String] = []
var _chunks: Dictionary = {} # Vector2i -> ProceduralDistrict
var _refresh_in_flight := false
var _last_player_chunk := Vector2i(9_999_999, 9_999_999)

func _ready() -> void:
	var started_at := Time.get_ticks_msec()
	resolved_seed = _resolve_seed()
	var origin := Vector2i.ZERO
	await _ensure_active_square(origin, true)
	if _chunks.is_empty():
		generation_errors.append("initial streaming chunk activation failed")
		generation_complete = true
		generation_succeeded = false
		generation_duration_ms = Time.get_ticks_msec() - started_at
		generation_failed.emit(resolved_seed, generation_errors)
		generation_completed.emit(resolved_seed)
		return
	await _rebuild_navigation()
	generation_complete = true
	generation_succeeded = true
	generation_duration_ms = Time.get_ticks_msec() - started_at
	_last_player_chunk = origin
	generation_completed.emit(resolved_seed)

func _process(_delta: float) -> void:
	if not generation_succeeded or _refresh_in_flight:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var coordinate := world_to_chunk(player.global_position)
	if coordinate == _last_player_chunk:
		return
	_last_player_chunk = coordinate
	_refresh_stream(coordinate)

func _refresh_stream(center: Vector2i) -> void:
	_refresh_in_flight = true
	await _ensure_active_square(center, false)
	_unload_distant_chunks(center)
	await _rebuild_navigation()
	_refresh_in_flight = false

func _ensure_active_square(center: Vector2i, initial: bool) -> void:
	for y in range(center.y - active_radius, center.y + active_radius + 1):
		for x in range(center.x - active_radius, center.x + active_radius + 1):
			var coordinate := Vector2i(x, y)
			if _chunks.has(coordinate):
				continue
			var chunk := CHUNK_SCENE.instantiate() as ProceduralDistrict
			chunk.name = "Chunk_%d_%d" % [coordinate.x, coordinate.y]
			chunk.position = chunk_to_world(coordinate)
			chunk.chunk_coordinate = coordinate
			chunk.streamed_chunk = true
			chunk.defer_navigation = true
			chunk.build_boundaries = false
			chunk.stream_world_seed = resolved_seed
			add_child(chunk)
			if not chunk.generation_complete:
				await chunk.generation_completed
			if not chunk.generation_succeeded:
				generation_errors.append_array(chunk.generation_errors)
				chunk.queue_free()
				continue
			_chunks[coordinate] = chunk
			chunk_activated.emit(coordinate)
	if initial:
		await get_tree().physics_frame

func _unload_distant_chunks(center: Vector2i) -> void:
	for coordinate_variant in _chunks.keys().duplicate():
		var coordinate: Vector2i = coordinate_variant
		if max(abs(coordinate.x - center.x), abs(coordinate.y - center.y)) <= retain_radius:
			continue
		var chunk: ProceduralDistrict = _chunks[coordinate]
		_despawn_transients_in(chunk.chunk_world_rect())
		_chunks.erase(coordinate)
		chunk.queue_free()
		chunk_unloaded.emit(coordinate)

func _despawn_transients_in(world_rect: Rect2) -> void:
	for zombie_node in get_tree().get_nodes_in_group("zombies"):
		var zombie := zombie_node as Node2D
		if zombie and world_rect.has_point(zombie.global_position):
			zombie.queue_free()

func _rebuild_navigation() -> void:
	if _chunks.is_empty():
		return
	var bounds := Rect2()
	var initialized := false
	for chunk in _chunks.values():
		var world_rect: Rect2 = (chunk as ProceduralDistrict).chunk_world_rect()
		bounds = world_rect if not initialized else bounds.merge(world_rect)
		initialized = true
	await get_tree().physics_frame
	UrbanNavigationService.build_rect(bounds)
	for chunk in _chunks.values():
		(chunk as ProceduralDistrict).register_doors_with_navigation()

func world_to_chunk(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / CHUNK_SIZE.x + 0.5), floori(world_position.y / CHUNK_SIZE.y + 0.5))

func chunk_to_world(coordinate: Vector2i) -> Vector2:
	return Vector2(coordinate.x * CHUNK_SIZE.x, coordinate.y * CHUNK_SIZE.y)

func get_player_spawn() -> Vector2:
	var origin: ProceduralDistrict = _chunks.get(Vector2i.ZERO)
	return origin.get_player_spawn() if origin else Vector2.ZERO

func get_safehouse_position() -> Vector2:
	var origin: ProceduralDistrict = _chunks.get(Vector2i.ZERO)
	return origin.get_safehouse_position() if origin else Vector2.ZERO

func get_arena_size() -> Vector2:
	return Vector2.INF

func get_chunk(coordinate: Vector2i) -> ProceduralDistrict:
	return _chunks.get(coordinate)

func active_chunk_count() -> int:
	return _chunks.size()

func _resolve_seed() -> int:
	if city_seed >= 0:
		WorldState.world_flags[&"city_seed"] = city_seed
		return city_seed
	if WorldState.world_flags.has(&"city_seed"):
		return int(WorldState.world_flags[&"city_seed"])
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var generated := rng.randi_range(1, 0x7FFFFFFF)
	WorldState.world_flags[&"city_seed"] = generated
	return generated
