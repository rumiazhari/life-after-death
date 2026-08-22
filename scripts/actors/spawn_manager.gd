class_name SpawnManager
extends Node
## Spawns zombies inside generated or retained-authored `SpawnRegion` nodes
## and gradually ramps the active population up to a
## configurable cap. Purges invalid references every tick instead of
## trusting scene-tree bookkeeping.
##
## Production spawning (`_spawn_one()`) never falls back to an arbitrary
## camera-relative position when every region candidate fails its
## rejection checks -- it simply skips that spawn attempt, which the
## periodic `spawn_interval` timer retries on its own next tick (a
## natural "delay," not a stall). `_pick_spawn_position()` (the old
## camera-ring picker) is kept only because an existing RNG-isolation
## test exercises it directly; nothing in the production spawn path calls
## it anymore.

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

## -- Environment-region spawning -------------------------------------
## A candidate must clear every one of these before it's used. See
## `_pick_region_spawn_position()`.
@export var min_distance_to_player: float = 260.0
## How far a raycast-based "is this candidate directly visible to the
## player" check reaches -- bounded rather than an unconditional raycast
## across the whole district, since a spawn point across a long straight
## road being technically unoccluded shouldn't disqualify it.
@export var player_visibility_check_range: float = 480.0
## Bounded search per spawn attempt -- see class doc "no arbitrary
## camera-ring fallback."
@export var max_region_search_attempts: int = 24
## Zombie's own physical collision radius (CircleShape2D, Zombie.tscn) --
## candidates are validated by this full footprint, not just their center
## point, so a candidate whose center clears a wall/actor but whose body
## would still clip it gets rejected too.
@export var zombie_collision_radius: float = 13.0
## Extra clearance beyond the raw collision radius -- keeps a spawn from
## landing pixel-perfect flush against a wall or another actor.
@export var spawn_clearance_margin: float = 4.0
const ACTOR_OVERLAP_MASK := 2 | 4 | 16 # Player | Zombie | Survivor
const WORLD_MASK := 1 # World collision (walls, furniture, closed doors)
const FOOTPRINT_MASK := WORLD_MASK | ACTOR_OVERLAP_MASK

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
var _active_rng_seed: int = -1
var _exterior_navigation_anchor: Vector2 = Vector2.ZERO
var _spawn_phase: StringName = &"replenishment"
var _started: bool = false

func _ready() -> void:
	add_to_group("spawn_manager")
	# Main owns the startup order. Keep replenishment disabled while the
	# procedural district is still generating collision/navigation, and keep it
	# disabled permanently if generation fails before begin() is reached.
	set_process(false)
	if rng_seed >= 0:
		_gameplay_rng.seed = rng_seed
		_active_rng_seed = rng_seed
	else:
		_gameplay_rng.randomize()
		_active_rng_seed = int(_gameplay_rng.seed)
	_entity_container = get_node_or_null(entity_container_path)
	if _entity_container == null:
		_entity_container = get_tree().get_first_node_in_group("entity_container")
	GameEvents.zombie_killed_by_player.connect(_on_zombie_killed_by_player)
	apply_population_profile(mobile_population_profile if OS.has_feature("mobile") else population_profile)

func apply_population_profile(profile: PopulationProfile) -> void:
	population_profile = profile
	max_population = POPULATION_PROFILES.get(profile, max_population)

func begin() -> void:
	if _started:
		return
	_started = true
	set_process(true)
	_spawn_phase = &"initial"
	spawn_burst(initial_population, &"initial")
	_spawn_phase = &"replenishment"

## Binds zombie selection and point sampling to the generated city seed.
## The salt keeps the spawn stream independent from structural generation.
func set_world_seed(world_seed: int, exterior_anchor: Vector2 = Vector2.ZERO) -> void:
	_active_rng_seed = int((world_seed ^ 0x5A17F00D) & 0x7FFFFFFF)
	rng_seed = _active_rng_seed
	_gameplay_rng.seed = _active_rng_seed
	_exterior_navigation_anchor = exterior_anchor

func _process(delta: float) -> void:
	if not _started:
		return
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

func spawn_burst(count: int, phase: StringName = &"replenishment") -> void:
	for i in range(count):
		if _active_zombies.size() >= max_population:
			break
		_spawn_one(phase)

func reset() -> void:
	_started = false
	set_process(false)
	for zombie in _active_zombies:
		if is_instance_valid(zombie):
			zombie.queue_free()
	_active_zombies.clear()
	_spawn_timer = 0.0
	_last_reported_count = -1
	_kill_count = 0
	_spawn_phase = &"replenishment"
	if _active_rng_seed >= 0:
		_gameplay_rng.seed = _active_rng_seed
	GameEvents.kill_count_changed.emit(_kill_count)

func _try_spawn_batch() -> void:
	var to_spawn: int = mini(spawn_batch_size, max_population - _active_zombies.size())
	for i in range(to_spawn):
		_spawn_one(&"replenishment")

## Skips the spawn entirely (returns null) if no eligible region yields a
## valid candidate within `max_region_search_attempts` -- see the class
## doc "no arbitrary camera-ring fallback."
func _spawn_one(phase: StringName = &"replenishment") -> Node2D:
	if zombie_scene == null or _entity_container == null:
		return null
	var position: Variant = _pick_region_spawn_position(phase)
	if position == null:
		return null
	var zombie: Node2D = zombie_scene.instantiate()
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

## Chooses among the district's `SpawnRegion` nodes (never a
## random camera-relative point) using ONLY this manager's own private
## `_gameplay_rng` -- see docs/urban_map_design.md "Spawn regions" for why
## a region's own `random_point()` deliberately takes the caller's RNG
## instead of drawing from a stream of its own. Returns null (never a
## fallback position) if nothing valid turns up within the attempt budget.
func _pick_region_spawn_position(phase: StringName = &"replenishment") -> Variant:
	var regions: Array = get_tree().get_nodes_in_group("spawn_regions")
	if regions.is_empty():
		return null
	var player: Node2D = get_tree().get_first_node_in_group("player")
	var player_room: Room = Room.room_containing(player) if player else null
	for attempt in range(max_region_search_attempts):
		var region: SpawnRegion = _pick_weighted_region(regions, phase)
		if region == null:
			return null
		var candidate: Vector2 = region.random_point(_gameplay_rng)
		if _is_valid_spawn_candidate(candidate, player, player_room, region):
			return candidate
	return null

func _pick_weighted_region(regions: Array, phase: StringName = &"replenishment") -> SpawnRegion:
	var total := 0.0
	for candidate in regions:
		if candidate is SpawnRegion:
			total += (candidate as SpawnRegion).weight_for_phase(phase)
	if total <= 0.0:
		return null
	var roll := _gameplay_rng.randf() * total
	var last_eligible: SpawnRegion = null
	for candidate in regions:
		if not candidate is SpawnRegion:
			continue
		var region := candidate as SpawnRegion
		var weight := region.weight_for_phase(phase)
		if weight <= 0.0:
			continue
		last_eligible = region
		roll -= weight
		if roll <= 0.0:
			return region
	return last_eligible

func _is_valid_spawn_candidate(candidate: Vector2, player: Node2D, player_room: Room, region: SpawnRegion = null) -> bool:
	# Full zombie footprint against World collision (walls, furniture,
	# closed doors) AND every actor layer in one shape query -- not just
	# the center point, so a candidate whose center clears an obstacle but
	# whose body would still overlap it gets rejected too.
	if _footprint_overlaps(candidate):
		return false
	if _is_inside_any_settlement(candidate):
		return false
	if player_room != null and player_room.get_bounds_rect().has_point(candidate):
		return false
	if not _footprint_fully_navigable(candidate):
		return false
	if region != null:
		if not region.is_reachable:
			return false
		if not region.is_indoor and not UrbanNavigationService.are_positions_connected(candidate, _exterior_navigation_anchor):
			return false
	if player:
		var dist: float = candidate.distance_to(player.global_position)
		if dist < min_distance_to_player:
			return false
		if dist <= player_visibility_check_range and _has_line_of_sight(player.global_position, candidate):
			return false
	return true

## True if a circle matching the zombie's own collision radius (plus
## clearance) overlaps World collision or any actor at `candidate` --
## never instantiates a zombie just to test this.
func _footprint_overlaps(candidate: Vector2) -> bool:
	var space_state := get_tree().root.get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = zombie_collision_radius + spawn_clearance_margin
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, candidate)
	query.collision_mask = FOOTPRINT_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return not space_state.intersect_shape(query, 1).is_empty()

## Checks the candidate's center plus 8 points around the footprint's own
## edge against the nav grid -- rejects a candidate sitting in a free cell
## whose edge nonetheless overlaps a wall/out-of-bounds cell (e.g. a narrow
## doorway the zombie's body can't actually fit through), not just the
## single cell the center point happens to land in.
func _footprint_fully_navigable(candidate: Vector2) -> bool:
	if not UrbanNavigationService.is_position_free(candidate):
		return false
	var radius: float = zombie_collision_radius + spawn_clearance_margin
	for i in range(8):
		var angle: float = i * TAU / 8.0
		var sample: Vector2 = candidate + Vector2.RIGHT.rotated(angle) * radius
		if not UrbanNavigationService.is_position_free(sample):
			return false
	return true

## World | Vision raycast -- the same mask convention
## ZombiePerceptionComponent/SurvivorAI use elsewhere for "can these two
## points see each other."
func _has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var space_state := get_tree().root.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, 1 | 32)
	return space_state.intersect_ray(query).is_empty()

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
