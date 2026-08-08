class_name SpawnManager
extends Node
## Spawns zombies just outside the visible camera region and gradually
## ramps the active population up to a configurable cap. Purges invalid
## references every tick instead of trusting scene-tree bookkeeping.

## Selectable zombie-population ceilings for performance testing across
## device tiers. Values match the profiles requested for Android tuning.
enum PopulationProfile { LOW, MEDIUM, HIGH, STRESS }

const POPULATION_PROFILES := {
	PopulationProfile.LOW: 50,
	PopulationProfile.MEDIUM: 100,
	PopulationProfile.HIGH: 150,
	PopulationProfile.STRESS: 250,
}

@export var zombie_scene: PackedScene
## Desktop/default profile. Preserves the Phase 0/1-validated 150 cap.
@export var population_profile: PopulationProfile = PopulationProfile.HIGH
## Used instead of `population_profile` whenever OS.has_feature("mobile")
## is true. Kept at MEDIUM (100) per Android tuning policy until a real
## device has been profiled -- raise this only after that testing.
@export var mobile_population_profile: PopulationProfile = PopulationProfile.MEDIUM
@export var max_population: int = 150
@export var spawn_interval: float = 0.25
@export var spawn_batch_size: int = 2
@export var spawn_margin: float = 80.0
@export var initial_population: int = 20
@export var entity_container_path: NodePath
## -1 (default) auto-randomizes _gameplay_rng from OS entropy, matching the
## previous bare randf()/randf_range() behavior. A non-negative value seeds
## it explicitly -- used by tests to prove spawn-position output is
## unaffected by however much CosmeticRng is drawn from elsewhere.
@export var rng_seed: int = -1

var _entity_container: Node = null
var _camera: Camera2D = null
var _active_zombies: Array[Node2D] = []
var _spawn_timer: float = 0.0
var _last_reported_count: int = -1
var _kill_count: int = 0
## Private gameplay-only RNG stream (spawn position angle/radius) --
## deliberately separate from CosmeticRng. See docs/architecture.md
## "RNG isolation".
var _gameplay_rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("spawn_manager")
	if rng_seed >= 0:
		_gameplay_rng.seed = rng_seed
	else:
		_gameplay_rng.randomize()
	_entity_container = get_node_or_null(entity_container_path)
	if _entity_container == null:
		_entity_container = get_tree().get_first_node_in_group("entity_container")
	GameEvents.zombie_killed_by_player.connect(_on_zombie_killed_by_player)
	apply_population_profile(mobile_population_profile if OS.has_feature("mobile") else population_profile)

func apply_population_profile(profile: PopulationProfile) -> void:
	population_profile = profile
	max_population = POPULATION_PROFILES.get(profile, max_population)

func begin() -> void:
	spawn_burst(initial_population)

func _process(delta: float) -> void:
	_purge_invalid()
	_spawn_timer += delta
	if _spawn_timer >= spawn_interval:
		_spawn_timer = 0.0
		_try_spawn_batch()
	_report_count()

func set_camera(camera: Camera2D) -> void:
	_camera = camera

func active_zombie_count() -> int:
	return _active_zombies.size()

func spawn_burst(count: int) -> void:
	for i in range(count):
		if _active_zombies.size() >= max_population:
			break
		_spawn_one()

func reset() -> void:
	for zombie in _active_zombies:
		if is_instance_valid(zombie):
			zombie.queue_free()
	_active_zombies.clear()
	_spawn_timer = 0.0
	_last_reported_count = -1
	_kill_count = 0
	GameEvents.kill_count_changed.emit(_kill_count)

func _try_spawn_batch() -> void:
	var to_spawn: int = mini(spawn_batch_size, max_population - _active_zombies.size())
	for i in range(to_spawn):
		_spawn_one()

const MAX_SPAWN_ATTEMPTS := 4

func _spawn_one() -> Node2D:
	if zombie_scene == null or _entity_container == null:
		return null
	var zombie: Node2D = zombie_scene.instantiate()
	var position: Vector2 = _pick_spawn_position()
	var attempts: int = 0
	while _is_inside_any_settlement(position) and attempts < MAX_SPAWN_ATTEMPTS:
		position = _pick_spawn_position()
		attempts += 1
	zombie.global_position = position
	_entity_container.add_child(zombie)
	_active_zombies.append(zombie)
	GameEvents.zombie_spawned.emit(zombie)
	return zombie

## Never spawn directly inside the safehouse -- checked against every
## registered settlement's own safe_radius rather than a hard-coded
## position, so this stays correct if the safehouse ever moves.
func _is_inside_any_settlement(position: Vector2) -> bool:
	for settlement in get_tree().get_nodes_in_group("settlement"):
		if settlement.has_method("is_position_safe") and settlement.call("is_position_safe", position):
			return true
	return false

func _pick_spawn_position() -> Vector2:
	var center: Vector2 = _camera.global_position if _camera else Vector2.ZERO
	var half_view: Vector2 = _get_half_view()
	var angle: float = _gameplay_rng.randf() * TAU
	var extra: float = _gameplay_rng.randf_range(spawn_margin, spawn_margin + 220.0)
	var radius: float = half_view.length() + extra
	return center + Vector2.RIGHT.rotated(angle) * radius

func _get_half_view() -> Vector2:
	# The actual on-screen visible extent, not the design-time reference
	# resolution -- with stretch/aspect "expand" these differ per device
	# aspect ratio (16:9 phone vs 19.5:9 vs tablet), and spawning relative
	# to the wrong size would put zombies inside the visible camera area.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var zoom: Vector2 = _camera.zoom if _camera else Vector2.ONE
	return (viewport_size / zoom) * 0.5

func _purge_invalid() -> void:
	var i: int = _active_zombies.size() - 1
	while i >= 0:
		if not is_instance_valid(_active_zombies[i]):
			_active_zombies.remove_at(i)
		i -= 1

func _report_count() -> void:
	if _active_zombies.size() != _last_reported_count:
		_last_reported_count = _active_zombies.size()
		GameEvents.zombie_count_changed.emit(_last_reported_count)

func _on_zombie_killed_by_player(_position: Vector2) -> void:
	_kill_count += 1
	GameEvents.kill_count_changed.emit(_kill_count)
