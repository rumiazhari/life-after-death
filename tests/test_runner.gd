extends Node
## Lightweight headless regression runner -- no external test framework.
## Run with (from the project root):
##   godot --headless --path . res://tests/TestRunner.tscn
## Exits with code 0 if every test passes, nonzero otherwise (so it's
## usable as a CI/pre-commit gate). Runs as an ordinary scene so autoloads
## (WorldState, SimulationClock, ItemDatabase) are live exactly as they are
## in normal gameplay.
##
## Each test gets a fresh WorldState/SimulationClock (reset before it
## runs) so tests can't leak state into each other. Most tests exercise
## the real production code (Inventory, ScavengePoint, Job,
## SettlementJobBoard) directly rather than reimplementing it --
## StorageContainer/SettlementJobBoard instances are constructed with
## `.new()` and have `_ready()` called on them explicitly (a plain virtual
## method, safe to call directly) instead of waiting on scene-tree
## add_child() timing, which keeps those tests fully synchronous.
##
## Several tests need a real, fully-wired Survivor/SurvivorAI/Settlement
## (to drive an actual UtilityAction's enter()/tick()/exit() the same way
## SurvivorAI does, or to exercise Main.tscn's own spawn/restart flow) --
## those DO need add_child() + a frame to let @onready state and _ready()
## resolve, so the whole harness runs as a chain of awaited coroutines
## (`_run_test` awaits each test function; `await` on a plain synchronous
## call is a no-op passthrough, so the old synchronous tests are untouched).

var _pass_count: int = 0
var _fail_count: int = 0
var _current_test: String = ""
var _test_failed: bool = false

const SURVIVOR_SCENE: PackedScene = preload("res://scenes/actors/Survivor.tscn")
const ZOMBIE_SCENE: PackedScene = preload("res://scenes/actors/Zombie.tscn")
const SPAWN_MANAGER_SCRIPT: GDScript = preload("res://scripts/actors/spawn_manager.gd")
const PLAYER_SCENE: PackedScene = preload("res://scenes/actors/Player.tscn")
const DOOR_SCENE: PackedScene = preload("res://scenes/world/Door.tscn")
const WINDOW_SCENE: PackedScene = preload("res://scenes/world/Window.tscn")
const CONVENIENCE_STORE_SCENE: PackedScene = preload("res://scenes/world/buildings/ConvenienceStore01.tscn")
const CLINIC_SCENE: PackedScene = preload("res://scenes/world/buildings/Clinic01.tscn")

func _ready() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	await _run_test("reserved_transfer_success", _test_reserved_transfer_success)
	await _run_test("reserved_transfer_failure_full_destination", _test_reserved_transfer_failure)
	await _run_test("reservation_release_after_interruption", _test_reservation_release_after_interruption)
	await _run_test("partial_scavenge_capacity", _test_partial_scavenge_capacity)
	await _run_test("zero_capacity_scavenge", _test_zero_capacity_scavenge)
	await _run_test("haul_interrupt_before_pickup", _test_haul_interrupt_before_pickup)
	await _run_test("haul_interrupt_after_pickup", _test_haul_interrupt_after_pickup)
	await _run_test("survivor_death_retains_data", _test_survivor_death_retains_data)
	await _run_test("restart_resets_ids_and_time", _test_restart_resets_ids_and_time)
	await _run_test("reservation_create_release_cycle", _test_reservation_cycle)
	await _run_test("retrieve_supplies_failed_transfer_then_interrupted", _test_retrieve_supplies_failed_transfer_then_interrupted)
	await _run_test("scavenge_atomic_transfer_fractional_boundary", _test_scavenge_atomic_boundary)
	await _run_test("haul_in_transit_source_destroyed", _test_haul_in_transit_source_destroyed)
	await _run_test("haul_permanently_full_destination_falls_back", _test_haul_permanently_full_falls_back)
	await _run_test("haul_no_storage_available_creates_world_drop", _test_haul_no_storage_creates_world_drop)
	await _run_test("survivor_death_preserves_carried_cargo", _test_survivor_death_preserves_cargo)
	await _run_test("exact_conservation_across_all_sinks", _test_exact_conservation_all_sinks)
	await _run_test("repeated_restart_lifecycle", _test_repeated_restart_lifecycle)
	await _run_test("storage_container_unregisters_on_exit", _test_storage_container_unregisters_on_exit)
	await _run_test("haul_source_destroyed_before_pickup", _test_haul_source_destroyed_before_pickup)
	await _run_test("haul_destination_destroyed_redirects_to_fallback", _test_haul_destination_destroyed_redirects_to_fallback)
	await _run_test("haul_destination_and_fallback_destroyed_creates_world_drop", _test_haul_destination_and_fallback_destroyed_creates_world_drop)
	await _run_test("repeated_container_create_free_does_not_grow_registry", _test_repeated_container_create_free_does_not_grow_registry)
	await _run_test("storage_destruction_preserves_multiple_item_types", _test_storage_destruction_preserves_multiple_item_types)
	await _run_test("restart_teardown_creates_no_destruction_drops", _test_restart_teardown_creates_no_destruction_drops)
	await _run_test("reparenting_preserves_registration_and_ownership", _test_reparenting_preserves_registration_and_ownership)
	await _run_test("cosmetic_rng_does_not_affect_zombie_retarget_timing", _test_cosmetic_rng_does_not_affect_zombie_retarget_timing)
	await _run_test("cosmetic_rng_does_not_affect_spawn_positions", _test_cosmetic_rng_does_not_affect_spawn_positions)

	## --- Phase 3B.1: authored-region spawning ------------------------------
	await _run_test("spawn_region_production_spawn_lands_in_authored_region", _test_spawn_region_production_spawn_lands_in_authored_region)
	await _run_test("spawn_region_selection_is_deterministic_for_same_seed", _test_spawn_region_selection_is_deterministic_for_same_seed)
	await _run_test("spawn_region_rejects_point_inside_wall", _test_spawn_region_rejects_point_inside_wall)
	await _run_test("spawn_region_rejects_point_inside_player_current_room", _test_spawn_region_rejects_point_inside_player_current_room)
	await _run_test("spawn_region_rejects_point_inside_safehouse", _test_spawn_region_rejects_point_inside_safehouse)
	await _run_test("spawn_region_failed_search_delays_spawn_safely", _test_spawn_region_failed_search_delays_spawn_safely)
	await _run_test("cosmetic_rng_does_not_affect_spawn_region_selection", _test_cosmetic_rng_does_not_affect_spawn_region_selection)
	await _run_test("snapshot_includes_and_restores_phase_3b_state", _test_snapshot_includes_and_restores_phase_3b_state)
	await _run_test("snapshot_restore_is_idempotent_no_duplication", _test_snapshot_restore_is_idempotent_no_duplication)
	await _run_test("detectable_visibility_multiplier_affects_detection_range", _test_detectable_visibility_multiplier_affects_detection_range)
	await _run_test("detectable_missing_component_defaults_to_full_visibility", _test_detectable_missing_component_defaults_to_full_visibility)
	await _run_test("detectable_walking_noise_heard_only_nearby", _test_detectable_walking_noise_heard_only_nearby)
	await _run_test("detectable_running_noise_reaches_farther_than_walking", _test_detectable_running_noise_reaches_farther_than_walking)
	await _run_test("detectable_search_and_salvage_emit_configured_noise", _test_detectable_search_and_salvage_emit_configured_noise)
	await _run_test("detectable_indoor_target_blocked_by_wall_and_visible_through_open_door", _test_detectable_indoor_target_blocked_by_wall_and_visible_through_open_door)
	await _run_test("survivor_routes_around_wall_when_direct_path_blocked", _test_survivor_routes_around_wall_when_direct_path_blocked)
	await _run_test("survivor_route_updates_when_door_state_changes", _test_survivor_route_updates_when_door_state_changes)
	await _run_test("survivor_move_toward_unreachable_point_terminates_safely", _test_survivor_move_toward_unreachable_point_terminates_safely)
	await _run_test("survivor_entering_and_leaving_building_updates_detectable_context", _test_survivor_entering_and_leaving_building_updates_detectable_context)
	await _run_test("building_portal_outside_view_cone_stays_hidden", _test_building_portal_outside_view_cone_stays_hidden)
	await _run_test("building_portal_door_toggle_updates_reveal_immediately_while_stationary", _test_building_portal_door_toggle_updates_reveal_immediately_while_stationary)
	await _run_test("building_portal_reveals_two_hops_through_open_doors", _test_building_portal_reveals_two_hops_through_open_doors)
	await _run_test("building_portal_blocks_two_hop_room_when_either_door_closed", _test_building_portal_blocks_two_hop_room_when_either_door_closed)
	await _run_test("building_portal_intact_window_reveals_but_still_blocks_movement", _test_building_portal_intact_window_reveals_but_still_blocks_movement)
	await _run_test("building_portal_boarded_window_blocks_reveal", _test_building_portal_boarded_window_blocks_reveal)
	await _run_test("building_portal_visual_fade_never_changes_collision", _test_building_portal_visual_fade_never_changes_collision)

	## --- Phase 3B: fixed district, buildings, interaction, perception -----
	await _run_test("district_layout_checksum_matches_committed_baseline", _test_district_layout_checksum_matches_committed_baseline)
	await _run_test("baked_district_scene_has_expected_structure", _test_baked_district_scene_has_expected_structure)
	await _run_test("door_closed_blocks_and_open_permits_movement_and_vision", _test_door_closed_blocks_and_open_permits_movement_and_vision)
	await _run_test("door_interact_toggles_exactly_once_and_persists", _test_door_interact_toggles_exactly_once_and_persists)
	await _run_test("door_refuses_to_close_on_blocking_body", _test_door_refuses_to_close_on_blocking_body)
	await _run_test("window_state_controls_vision_blocking_but_always_blocks_movement", _test_window_state_controls_vision_blocking_but_always_blocks_movement)
	await _run_test("loot_container_search_transfers_exact_and_prevents_duplication", _test_loot_container_search_transfers_exact_and_prevents_duplication)
	await _run_test("salvage_component_prevents_duplicate_salvage", _test_salvage_component_prevents_duplicate_salvage)
	await _run_test("persistent_prop_container_same_instance_across_calls", _test_persistent_prop_container_same_instance_across_calls)
	await _run_test("world_state_reset_clears_phase_3b_state", _test_world_state_reset_clears_phase_3b_state)
	await _run_test("building_roof_hides_and_room_reveals_on_enter_restores_on_exit", _test_building_roof_hides_and_room_reveals_on_enter_restores_on_exit)
	await _run_test("building_adjacent_room_reveals_through_open_door", _test_building_adjacent_room_reveals_through_open_door)
	await _run_test("zombie_perception_detects_and_chases_visible_target", _test_zombie_perception_detects_and_chases_visible_target)
	await _run_test("zombie_perception_ignores_target_outside_vision_distance", _test_zombie_perception_ignores_target_outside_vision_distance)
	await _run_test("zombie_perception_ignores_target_outside_view_cone", _test_zombie_perception_ignores_target_outside_view_cone)
	await _run_test("zombie_perception_blocked_by_wall", _test_zombie_perception_blocked_by_wall)
	await _run_test("zombie_perception_hearing_triggers_investigate", _test_zombie_perception_hearing_triggers_investigate)
	await _run_test("zombie_perception_search_expires_to_return_to_idle", _test_zombie_perception_search_expires_to_return_to_idle)
	await _run_test("urban_navigation_service_door_toggling_changes_cell_solidity", _test_urban_navigation_service_door_toggling_changes_cell_solidity)
	await _run_test("urban_navigation_service_find_path_respects_frame_budget", _test_urban_navigation_service_find_path_respects_frame_budget)
	await _run_test("spawn_region_random_point_within_radius", _test_spawn_region_random_point_within_radius)
	await _run_test("survivor_ignores_zombie_behind_wall_unless_within_emergency_radius", _test_survivor_ignores_zombie_behind_wall_unless_within_emergency_radius)

	## --- Phase 3B.2: movement noise, navigation hardening, interaction conservation ---
	await _run_test("detectable_stationary_emits_no_movement_noise", _test_detectable_stationary_emits_no_movement_noise)
	await _run_test("detectable_walking_emits_bounded_footstep_events", _test_detectable_walking_emits_bounded_footstep_events)
	await _run_test("detectable_running_emits_louder_and_more_frequent_events", _test_detectable_running_emits_louder_and_more_frequent_events)
	await _run_test("nearby_zombie_hears_running_movement_noise", _test_nearby_zombie_hears_running_movement_noise)
	await _run_test("distant_zombie_does_not_hear_walking_movement_noise", _test_distant_zombie_does_not_hear_walking_movement_noise)
	await _run_test("detectable_event_count_remains_bounded_over_time", _test_detectable_event_count_remains_bounded_over_time)
	await _run_test("detectable_concealment_reduces_effective_hearing_range", _test_detectable_concealment_reduces_effective_hearing_range)
	await _run_test("activity_noise_routes_through_actor_detectable_component", _test_activity_noise_routes_through_actor_detectable_component)
	await _run_test("activity_noise_falls_back_safely_without_detectable_component", _test_activity_noise_falls_back_safely_without_detectable_component)
	await _run_test("door_programmatic_toggle_emits_noise_without_an_actor", _test_door_programmatic_toggle_emits_noise_without_an_actor)
	await _run_test("salvage_full_capacity_transfers_exact_yield", _test_salvage_full_capacity_transfers_exact_yield)
	await _run_test("salvage_partial_capacity_preserves_remainder", _test_salvage_partial_capacity_preserves_remainder)
	await _run_test("salvage_zero_capacity_changes_nothing", _test_salvage_zero_capacity_changes_nothing)
	await _run_test("salvage_repeated_partial_reaches_exact_total", _test_salvage_repeated_partial_reaches_exact_total)
	await _run_test("salvage_remaining_yield_survives_snapshot_restore", _test_salvage_remaining_yield_survives_snapshot_restore)
	await _run_test("survivor_budget_exhaustion_does_not_walk_into_wall", _test_survivor_budget_exhaustion_does_not_walk_into_wall)
	await _run_test("survivor_no_path_result_terminates_safely", _test_survivor_no_path_result_terminates_safely)
	await _run_test("survivor_cached_path_invalidated_when_door_closes", _test_survivor_cached_path_invalidated_when_door_closes)
	await _run_test("zombie_cached_path_invalidated_when_door_closes", _test_zombie_cached_path_invalidated_when_door_closes)
	await _run_test("survivor_does_not_repeatedly_push_against_closed_door", _test_survivor_does_not_repeatedly_push_against_closed_door)
	await _run_test("navigation_shared_budget_enforced_across_calls", _test_navigation_shared_budget_enforced_across_calls)
	await _run_test("door_two_bodies_one_exits_still_blocked", _test_door_two_bodies_one_exits_still_blocked)
	await _run_test("door_closes_once_both_bodies_exit", _test_door_closes_once_both_bodies_exit)
	await _run_test("door_prunes_freed_body_while_overlapping", _test_door_prunes_freed_body_while_overlapping)
	await _run_test("door_duplicate_enter_signals_do_not_corrupt_count", _test_door_duplicate_enter_signals_do_not_corrupt_count)
	await _run_test("spawn_rejects_candidate_with_edge_overlapping_wall", _test_spawn_rejects_candidate_with_edge_overlapping_wall)
	await _run_test("spawn_clear_region_candidate_succeeds", _test_spawn_clear_region_candidate_succeeds)
	await _run_test("spawn_deterministic_selection_unchanged_with_shape_validation", _test_spawn_deterministic_selection_unchanged_with_shape_validation)
	await _run_test("room_context_a_to_b_crossing_stays_indoors", _test_room_context_a_to_b_crossing_stays_indoors)
	await _run_test("room_context_clears_on_leaving_building", _test_room_context_clears_on_leaving_building)
	await _run_test("room_context_rapid_oscillation_settles_correctly", _test_room_context_rapid_oscillation_settles_correctly)
	await _run_test("phase_3b4_noise_reset_epoch_accepts_new_events", _test_phase_3b4_noise_reset_epoch_accepts_new_events)
	await _run_test("phase_3b4_navigation_reset_invalidates_revision", _test_phase_3b4_navigation_reset_invalidates_revision)
	await _run_test("phase_3b4_suppressed_noise_is_not_global", _test_phase_3b4_suppressed_noise_is_not_global)
	await _run_test("phase_3b5_navigation_counters_are_bounded_hooks", _test_phase_3b5_navigation_counters_are_bounded_hooks)
	await _run_test("phase_3b5_handled_noise_history_is_bounded", _test_phase_3b5_handled_noise_history_is_bounded)
	await _run_test("phase_3b5_noise_ring_sequences_are_bounded", _test_phase_3b5_noise_ring_sequences_are_bounded)
	await _run_test("phase_3b6_survivor_direct_checks_are_interval_bounded", _test_phase_3b6_survivor_direct_checks_are_interval_bounded)
	await _run_test("phase_3b6_zombie_direct_checks_are_interval_bounded", _test_phase_3b6_zombie_direct_checks_are_interval_bounded)

	print("\n=== TEST RESULTS: %d passed, %d failed ===" % [_pass_count, _fail_count])
	get_tree().quit(0 if _fail_count == 0 else 1)

func _test_phase_3b4_noise_reset_epoch_accepts_new_events() -> void:
	NoiseManager.reset()
	var old_epoch: int = NoiseManager.epoch()
	NoiseManager.emit_noise(Vector2.ZERO, 4.0, &"test")
	NoiseManager.reset()
	_assert(NoiseManager.recent_noises_near(Vector2.ZERO, 100.0).is_empty(), "noise reset must remove pre-reset events")
	_assert(NoiseManager.epoch() != old_epoch, "noise reset must advance the event epoch")
	NoiseManager.emit_noise(Vector2.ZERO, 4.0, &"test")
	_assert(not NoiseManager.recent_noises_near(Vector2.ZERO, 100.0).is_empty(), "post-reset noise must be available to surviving listeners")

func _test_phase_3b4_navigation_reset_invalidates_revision() -> void:
	var before: int = UrbanNavigationService.revision()
	UrbanNavigationService.build(Vector2(128, 128))
	var built: int = UrbanNavigationService.revision()
	UrbanNavigationService.reset()
	_assert(UrbanNavigationService.revision() > built and UrbanNavigationService.revision() > before, "navigation reset must invalidate cached revisions")
	_assert(UrbanNavigationService.find_path_ex(Vector2.ZERO, Vector2(32, 32))["status"] == UrbanNavigationService.PathResult.NOT_READY, "navigation reset must clear the built grid")

func _test_phase_3b4_suppressed_noise_is_not_global() -> void:
	NoiseManager.reset()
	NoiseManager.emit_noise(Vector2.ZERO, 0.0, &"suppressed")
	_assert(NoiseManager.recent_noises_near(Vector2.ZERO, 100.0).is_empty(), "fully suppressed noise must not occupy the global buffer")

func _test_phase_3b5_navigation_counters_are_bounded_hooks() -> void:
	UrbanNavigationService.reset()
	UrbanNavigationService.is_direct_path_clear(Vector2.ZERO, Vector2.ONE)
	_assert(UrbanNavigationService.direct_path_checks_total == 1, "direct-route checks must expose a production counter")

func _test_phase_3b5_handled_noise_history_is_bounded() -> void:
	NoiseManager.reset()
	for i in range(100):
		NoiseManager.emit_noise(Vector2.ZERO, 2.0, &"footstep")
	_assert(NoiseManager.current_sequences().size() <= NoiseManager.MAX_RECENT, "noise history must remain bounded to the ring buffer")

func _test_phase_3b5_noise_ring_sequences_are_bounded() -> void:
	NoiseManager.reset()
	for i in range(NoiseManager.MAX_RECENT + 8):
		NoiseManager.emit_noise(Vector2.ZERO, 2.0, &"test")
	var sequences := NoiseManager.current_sequences()
	_assert(sequences.size() == NoiseManager.MAX_RECENT, "current sequence exposure must match the bounded ring")
	_assert(sequences[0] < sequences[-1], "retained noise sequences must remain ordered")

func _test_phase_3b6_survivor_direct_checks_are_interval_bounded() -> void:
	var settlement: Settlement = await _make_settlement(["general"])
	var survivor: Survivor = await _make_survivor({"name": "Cadence"}, settlement)
	survivor.global_position = Vector2.ZERO
	UrbanNavigationService.reset()
	var before: int = UrbanNavigationService.direct_path_checks_total
	for i in range(30):
		survivor._seek_direction(Vector2(200, 0), Vector2(200, 0), 200.0)
	var checks: int = UrbanNavigationService.direct_path_checks_total - before
	_assert(checks <= 2, "a continuously clear survivor goal must not raycast every physics tick")
	survivor.queue_free()
	settlement.free()
	await get_tree().process_frame

func _test_phase_3b6_zombie_direct_checks_are_interval_bounded() -> void:
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(zombie)
	await get_tree().process_frame
	zombie.global_position = Vector2.ZERO
	UrbanNavigationService.reset()
	var before: int = UrbanNavigationService.direct_path_checks_total
	for i in range(30):
		zombie._seek_point(Vector2(200, 0))
	var checks: int = UrbanNavigationService.direct_path_checks_total - before
	_assert(checks <= 2, "a continuously clear zombie goal must not raycast every physics tick")
	zombie.queue_free()
	await get_tree().process_frame

## --- Harness ---------------------------------------------------------

func _run_test(test_name: String, fn: Callable) -> void:
	_current_test = test_name
	_test_failed = false
	WorldState.reset()
	SimulationClock.reset()
	NoiseManager.reset()
	UrbanNavigationService.reset()
	await fn.call()
	if _test_failed:
		_fail_count += 1
		print("FAIL: %s" % test_name)
	else:
		_pass_count += 1
		print("PASS: %s" % test_name)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_test_failed = true
		push_error("[%s] %s" % [_current_test, message])

## Builds a real StorageContainer as a child of this TestRunner (in the
## live scene tree), so both _ready() (registers with WorldState) and
## _exit_tree() (unregisters on free/removal -- see
## StorageContainer._exit_tree()) fire exactly as they do in normal play.
## Standalone/orphan construction (this helper's old pattern, still used
## by _make_job_board() below since SettlementJobBoard has no such
## lifecycle hook to exercise) can't test _exit_tree() at all: that
## notification only fires for nodes that were actually in the tree.
func _make_container(role: String, capacity_weight: float = 0.0) -> StorageContainer:
	var container := StorageContainer.new()
	container.storage_role = role
	container.capacity_weight = capacity_weight
	add_child(container)
	await get_tree().process_frame
	return container

func _make_job_board() -> SettlementJobBoard:
	var board := SettlementJobBoard.new()
	board._ready()
	return board

## --- Real-node fixtures (for tests that drive an actual UtilityAction) ---

## Builds a minimal but real Settlement (in the scene tree, in group
## "settlement", with a JobBoard child in group "job_board") so
## SurvivorAI.begin()'s get_first_node_in_group() lookups succeed exactly
## as they do in normal play. Awaiting a frame lets _ready() fire for the
## whole subtree (Settlement/StorageContainer/SettlementJobBoard all use
## @export + plain _ready() logic, no @onready, so bottom-up _ready()
## ordering -- children before parent -- is the only timing this depends on).
func _make_settlement(container_roles: Array = ["general", "food", "water", "medical"]) -> Settlement:
	var settlement := Settlement.new()
	settlement.settlement_name = "TestSettlement"
	for role in container_roles:
		var container := StorageContainer.new()
		container.name = "Storage_%s" % role
		container.storage_role = role
		settlement.add_child(container)
	var board := SettlementJobBoard.new()
	board.name = "JobBoard"
	settlement.add_child(board)
	add_child(settlement)
	await get_tree().process_frame
	return settlement

## Builds a real Survivor (in the scene tree, fully @onready-resolved) and
## calls the same setup() Main.gd calls when spawning one for real, so its
## SurvivorAI/HealthComponent/Weapon are wired exactly as in normal play.
func _make_survivor(profile: Dictionary, home_settlement: Settlement) -> Survivor:
	var survivor: Survivor = SURVIVOR_SCENE.instantiate()
	add_child(survivor)
	await get_tree().process_frame
	survivor.setup(profile, home_settlement)
	return survivor

## --- Tests --------------------------------------------------------------

func _test_reserved_transfer_success() -> void:
	var from := Inventory.new(0.0)
	var to := Inventory.new(0.0)
	from.add_item(&"food_ration", 5)
	var total_before: int = from.get_count(&"food_ration") + to.get_count(&"food_ration")

	var rid: int = from.reserve(&"food_ration", 3)
	_assert(rid != 0, "reserve() should succeed with enough unreserved stock")

	var ok: bool = from.confirm_reserved_transfer(rid, to)
	_assert(ok, "confirm_reserved_transfer should succeed into an unlimited-capacity destination")
	_assert(from.get_count(&"food_ration") == 2, "source should retain the unmoved 2")
	_assert(to.get_count(&"food_ration") == 3, "destination should receive exactly the reserved 3")
	_assert(from.reservation_count() == 0, "reservation must be cleared on success")

	var total_after: int = from.get_count(&"food_ration") + to.get_count(&"food_ration")
	_assert(total_before == total_after, "exact item conservation across a successful transfer")

func _test_reserved_transfer_failure() -> void:
	var from := Inventory.new(0.0)
	var to := Inventory.new(0.1) # too small to fit even 1 food_ration (0.5 weight/unit)
	from.add_item(&"food_ration", 5)

	var rid: int = from.reserve(&"food_ration", 3)
	_assert(rid != 0, "reserve() should succeed")

	var ok: bool = from.confirm_reserved_transfer(rid, to)
	_assert(not ok, "confirm_reserved_transfer must fail when the destination can't fit it")
	_assert(from.has_reservation(rid), "a destination-capacity failure must NOT orphan the reservation -- ActionRetrieveSupplies relies on being able to see it's still there and retry")
	_assert(from.get_count(&"food_ration") == 5, "source must be untouched by a failed transfer")
	_assert(to.get_count(&"food_ration") == 0, "destination must receive nothing from a failed transfer")

	# This mirrors ActionRetrieveSupplies.exit()'s interruption path: it can
	# always safely release a reservation left intact by a failed transfer.
	from.release_reservation(rid)
	_assert(from.reservation_count() == 0, "reservation count must return to zero after an explicit release")
	_assert(from.get_count(&"food_ration") == 5, "no items lost or gained by reserve-fail-release")

func _test_reservation_release_after_interruption() -> void:
	var inv := Inventory.new(0.0)
	inv.add_item(&"water_bottle", 4)

	var rid: int = inv.reserve(&"water_bottle", 2)
	_assert(rid != 0, "reserve() should succeed")
	_assert(inv.get_available(&"water_bottle") == 2, "2 units should be unavailable to other claims while reserved")

	inv.release_reservation(rid)
	_assert(inv.reservation_count() == 0, "reservation count returns to zero after release")
	_assert(inv.get_available(&"water_bottle") == 4, "full stock available again after release")
	_assert(inv.get_count(&"water_bottle") == 4, "release must not change the actual stock count")

func _test_partial_scavenge_capacity() -> void:
	var point := ScavengePoint.new()
	point.item_id = &"materials"
	point.yield_per_scavenge = 5
	point.remaining_stock = 5
	var carried := Inventory.new(2.0) # materials weigh 1.0/unit -> exactly 2 fit

	var potential: int = mini(point.yield_per_scavenge, point.remaining_stock)
	var capacity: int = carried.max_fit(point.item_id)
	_assert(capacity == 2, "max_fit should compute exactly 2 units fitting in a 2.0 weight budget")

	var harvested: int = point.harvest(mini(potential, capacity))
	_assert(harvested == 2, "harvest must return exactly the capacity-limited amount")
	_assert(point.remaining_stock == 3, "the point must retain the 3 units that didn't fit -- not discard them")

	var added: int = carried.add_item(point.item_id, harvested)
	_assert(added == 2, "the survivor's inventory should accept exactly what was harvested")
	_assert(harvested + point.remaining_stock == 5, "exact conservation: harvested + left-behind == original stock")

	point.free()

func _test_zero_capacity_scavenge() -> void:
	var point := ScavengePoint.new()
	point.item_id = &"materials"
	point.yield_per_scavenge = 3
	point.remaining_stock = 3
	var carried := Inventory.new(0.5) # materials weigh 1.0/unit -> zero fit

	var potential: int = mini(point.yield_per_scavenge, point.remaining_stock)
	var capacity: int = carried.max_fit(point.item_id)
	_assert(capacity == 0, "max_fit must be 0 when nothing fits")

	var harvested: int = point.harvest(mini(potential, capacity))
	_assert(harvested == 0, "harvest(0) must remove nothing")
	_assert(point.remaining_stock == 3, "point stock must be completely untouched when zero units fit")
	_assert(not point.is_depleted(), "a point that yielded nothing must not read as depleted")

	point.free()

func _test_haul_interrupt_before_pickup() -> void:
	var source := await _make_container("general")
	source.get_inventory().add_item(&"food_ration", 5)
	var dest := await _make_container("food")
	var board := _make_job_board()

	var job: Job = board.create_haul_job(source, dest, &"food_ration", 3, 1.0)
	_assert(job != null, "haul job creation should succeed with enough unreserved stock")
	_assert(source.get_inventory().get_available(&"food_ration") == 2, "3 of 5 should already be reserved the moment the job exists")

	var survivor_id := 42
	_assert(board.claim_job(job, survivor_id), "claim_job should succeed")
	_assert(job.status == Job.Status.RESERVED, "job should be RESERVED once claimed")
	_assert(job.haul_phase == Job.HaulPhase.AWAITING_PICKUP, "haul_phase should still be AWAITING_PICKUP before any travel")

	# Interruption before pickup: ActionHaulSupplies.exit() calls
	# release_survivor() here since _picked_up is still false.
	board.release_survivor(survivor_id)
	_assert(job.status == Job.Status.AVAILABLE, "job must reopen to AVAILABLE so another survivor can take over")
	_assert(job.assigned_survivor_ids.is_empty(), "the worker claim must be fully cleared")
	_assert(source.get_inventory().has_reservation(job.reservation_id), "the source reservation must survive the interruption untouched")
	_assert(source.get_inventory().get_available(&"food_ration") == 2, "reserved stock must still be excluded from availability")

	_assert(board.claim_job(job, 99), "a different survivor must be able to claim the reopened job and its intact reservation")

	board.free()
	source.free()
	dest.free()

func _test_haul_interrupt_after_pickup() -> void:
	var source := await _make_container("general")
	source.get_inventory().add_item(&"materials", 5)
	var dest := await _make_container("general_dest")
	var board := _make_job_board()

	var job: Job = board.create_haul_job(source, dest, &"materials", 3, 1.0)
	var survivor_id := 7
	board.claim_job(job, survivor_id)

	var carried := Inventory.new(0.0)
	var picked_up: bool = source.get_inventory().confirm_reserved_transfer(job.reservation_id, carried)
	_assert(picked_up, "pickup transfer should succeed")
	_assert(carried.get_count(&"materials") == 3, "the carrier should now physically hold the cargo")

	board.mark_picked_up(job, survivor_id)
	_assert(job.haul_phase == Job.HaulPhase.IN_TRANSIT, "job should be marked IN_TRANSIT once cargo is picked up")
	_assert(job.reservation_id == 0, "the consumed source reservation id should be cleared, not left stale")

	# Emergency interruption post-pickup: ActionHaulSupplies.exit() must NOT
	# call release_survivor() while _picked_up is true. Verify the job
	# board itself refuses to reopen an in-transit job even if release_survivor()
	# were called anyway (defense in depth, not just caller discipline).
	board.release_survivor(survivor_id)
	_assert(job.assigned_survivor_ids.has(survivor_id), "the carrier must remain the sole assignee -- a plain release must not touch an in-transit haul job")
	_assert(job.status != Job.Status.AVAILABLE, "an in-transit job must never read as AVAILABLE for another survivor to claim")

	var resumed: Job = board.get_in_transit_haul_job(survivor_id)
	_assert(resumed == job, "the same survivor must be able to find and resume its own in-transit job")
	var other_survivor_view: Job = board.get_in_transit_haul_job(999)
	_assert(other_survivor_view == null, "no other survivor may see this job as theirs to resume")

	var still_claimable := false
	for available_job in board.get_available_jobs(&"", Vector2.ZERO, -1.0):
		if available_job.id == job.id:
			still_claimable = true
	_assert(not still_claimable, "an in-transit job must never appear in get_available_jobs() for anyone")

	# Resume: the survivor finishes the delivery.
	var delivered: bool = Inventory.transfer_item(carried, dest.get_inventory(), &"materials", 3)
	_assert(delivered, "the resumed delivery should succeed")
	board.complete_job(job)

	_assert(dest.get_inventory().get_count(&"materials") == 3, "destination must receive exactly the hauled amount")
	_assert(carried.get_count(&"materials") == 0, "carrier inventory must be emptied by delivery")
	var total: int = source.get_inventory().get_count(&"materials") + dest.get_inventory().get_count(&"materials") + carried.get_count(&"materials")
	_assert(total == 5, "exact conservation: 2 left at source + 3 delivered + 0 still carried == original 5")

	board.free()
	source.free()
	dest.free()

func _test_survivor_death_retains_data() -> void:
	var data := SurvivorData.new()
	data.survivor_name = "TestVictim"
	var id: int = WorldState.register_survivor(data)
	_assert(id != 0, "registration should assign a stable id")
	_assert(WorldState.is_survivor_alive(id), "should read as alive before death")

	# An in-transit haul job the victim was carrying when it died.
	var source := await _make_container("general")
	source.get_inventory().add_item(&"materials", 4)
	var dest := await _make_container("general_dest")
	var board := _make_job_board()
	var job: Job = board.create_haul_job(source, dest, &"materials", 2, 1.0)
	board.claim_job(job, id)
	var carried := Inventory.new(0.0)
	source.get_inventory().confirm_reserved_transfer(job.reservation_id, carried)
	board.mark_picked_up(job, id)

	# Simulate death (mirrors Survivor._on_died() + SurvivorAI.stop()).
	data.is_dead = true
	board.release_survivor_permanently(id)

	_assert(job.status == Job.Status.FAILED, "the in-transit job carried by the dead survivor must be FAILED, not silently reopened")
	var still_claimable := false
	for available_job in board.get_available_jobs(&"", Vector2.ZERO, -1.0):
		if available_job.id == job.id:
			still_claimable = true
	_assert(not still_claimable, "the failed job must never resurface as claimable")

	_assert(WorldState.survivors.has(id), "SurvivorData must remain registered after death -- a persistent record, not deleted")
	_assert(WorldState.get_survivor(id).is_dead, "the persisted record must reflect is_dead = true")
	_assert(not WorldState.is_survivor_alive(id), "should no longer read as alive")
	_assert(not WorldState.get_living_survivors().has(data), "get_living_survivors() must exclude the dead")

	var snapshot: Dictionary = WorldState.to_snapshot()
	_assert(snapshot["survivors"].has(id), "the dead survivor's record must still appear in to_snapshot()")

	_assert(dest.get_inventory().get_count(&"materials") == 0, "cargo that died with its carrier must never appear at the destination -- no duplication")
	_assert(source.get_inventory().get_count(&"materials") == 2, "the 2 units never reserved for this haul remain untouched at the source")

	board.free()
	source.free()
	dest.free()

func _test_restart_resets_ids_and_time() -> void:
	WorldState.register_survivor(SurvivorData.new())
	var id2: int = WorldState.register_survivor(SurvivorData.new())
	_assert(id2 == 2, "second registration should get id 2 before any reset")

	SimulationClock.game_day = 3
	SimulationClock.game_hour = 5
	SimulationClock.game_minute = 30
	SimulationClock.tick_count = 100
	SimulationClock.speed = SimulationClock.SimSpeed.FAST
	_assert(SimulationClock.total_game_minutes() == 2 * 24 * 60 + 5 * 60 + 30, "sanity check on total_game_minutes before reset (day 3 == 2 full days elapsed)")

	WorldState.reset()
	SimulationClock.reset()

	_assert(WorldState.survivors.is_empty(), "WorldState.survivors must be empty after reset")
	var fresh_id: int = WorldState.register_survivor(SurvivorData.new())
	_assert(fresh_id == 1, "the id generator must restart from 1 after reset, not continue incrementing")

	_assert(SimulationClock.game_day == 1, "day resets to 1")
	_assert(SimulationClock.game_hour == 0, "hour resets to 0")
	_assert(SimulationClock.game_minute == 0, "minute resets to 0")
	_assert(SimulationClock.tick_count == 0, "tick count resets to 0")
	_assert(SimulationClock.speed == SimulationClock.SimSpeed.NORMAL, "speed resets to NORMAL")
	_assert(SimulationClock.total_game_minutes() == 0, "day 1, 00:00 must evaluate to exactly zero")

func _test_reservation_cycle() -> void:
	var inv := Inventory.new(0.0)
	inv.add_item(&"ammunition", 10)
	for i in range(20):
		var rid: int = inv.reserve(&"ammunition", 4)
		_assert(rid != 0, "reserve() #%d should succeed" % i)
		_assert(inv.get_available(&"ammunition") == 6, "6 available while a reservation of 4 is live, cycle %d" % i)
		inv.release_reservation(rid)
		_assert(inv.get_available(&"ammunition") == 10, "full stock available again after release, cycle %d" % i)
	_assert(inv.reservation_count() == 0, "no leftover reservations after 20 create/release cycles")
	_assert(inv.get_count(&"ammunition") == 10, "no items lost or gained across repeated reservation cycles")

## --- Phase 2A.1.1: real production-path tests ---------------------------

## Drives the real ActionRetrieveSupplies through a destination-capacity
## failure (survivor's own carried inventory too full to accept the
## reservation) and then an interruption, exactly as SurvivorAI would.
func _test_retrieve_supplies_failed_transfer_then_interrupted() -> void:
	var settlement: Settlement = await _make_settlement(["general", "food", "water", "medical"])
	var food_container: StorageContainer = settlement.storage_containers["food"]
	food_container.get_inventory().add_item(&"food_ration", 5)

	var survivor: Survivor = await _make_survivor({"name": "Retriever"}, settlement)
	# Fill the survivor's own (20.0-capacity) carried inventory so a
	# food_ration reservation (0.5 weight/unit) can't possibly fit.
	survivor.carried_inventory.add_item(&"materials", 20)
	survivor.data.hunger = 50.0 # above ActionRetrieveSupplies.HUNGER_THRESHOLD

	var action := ActionRetrieveSupplies.new()
	action.enter(survivor.ai)
	_assert(action._reservation_id != 0, "enter() should reserve food_ration at the food storage container")
	_assert(food_container.get_inventory().has_reservation(action._reservation_id), "the reservation should be live on the real StorageContainer's Inventory")

	survivor.global_position = food_container.global_position # skip travel: already "arrived"
	var finished: bool = action.tick(survivor.ai, 0.1)
	_assert(not finished, "a destination-capacity failure must not report the action as finished")
	_assert(action._reservation_id != 0, "tick() must not clear its local reservation id when confirm_reserved_transfer() failed on capacity")
	_assert(food_container.get_inventory().has_reservation(action._reservation_id), "the reservation must survive the failed transfer, not be orphaned")
	_assert(survivor.carried_inventory.get_count(&"food_ration") == 0, "nothing should have been added to carried inventory on a failed transfer")

	action.exit(survivor.ai) # simulate an emergency interruption right after the failed attempt
	_assert(food_container.get_inventory().reservation_count() == 0, "exit() must release the still-live reservation on interruption")
	_assert(food_container.get_inventory().get_count(&"food_ration") == 5, "exact conservation: all 5 remain at the source after reserve-fail-interrupt")
	_assert(survivor.carried_inventory.get_count(&"food_ration") == 0, "the survivor never received any food_ration")

	settlement.free()

## Drives the real ActionScavenge through ScavengePoint.harvest_into() at a
## fractional-weight capacity boundary (medical_supplies, 0.4 weight/unit,
## against an exactly-divisible 2.0 capacity) -- the boundary that used to
## be vulnerable to max_fit()/add_item() disagreeing by one unit before
## both were unified onto Inventory._fit_count().
func _test_scavenge_atomic_boundary() -> void:
	var settlement: Settlement = await _make_settlement(["general"])
	var survivor: Survivor = await _make_survivor({"name": "Scavenger"}, settlement)
	survivor.carried_inventory.capacity_weight = 2.0 # override the default 20.0 for this boundary

	var point := ScavengePoint.new()
	point.item_id = &"medical_supplies" # 0.4 weight/unit
	point.yield_per_scavenge = 10
	point.remaining_stock = 10
	point.scavenge_duration = 0.0

	var board: SettlementJobBoard = get_tree().get_first_node_in_group("job_board")
	var job: Job = board.create_job(Job.Type.SCAVENGE, 2.0, &"", 1, point)

	var action := ActionScavenge.new()
	survivor.global_position = point.global_position # skip travel
	action.enter(survivor.ai)
	_assert(action._job == job, "enter() should claim the only available SCAVENGE job")

	var finished: bool = action.tick(survivor.ai, 0.1)
	_assert(finished, "with scavenge_duration == 0.0 a single tick should complete the harvest")
	_assert(survivor.carried_inventory.get_count(&"medical_supplies") == 5, "exactly 5 units of a 0.4-weight item must fit a 2.0 capacity -- the atomic fractional-weight boundary")
	_assert(point.remaining_stock == 5, "the point must retain exactly the 5 units that didn't fit")
	_assert(survivor.carried_inventory.get_count(&"medical_supplies") + point.remaining_stock == 10, "exact conservation across the atomic harvest")
	_assert(not point.is_depleted(), "the point still has stock left, so it must not read as depleted")
	_assert(job.status == Job.Status.AVAILABLE, "a not-yet-depleted point's job should reopen (AVAILABLE) rather than complete")

	point.free()
	settlement.free()

## Job.is_target_valid() must not cancel an IN_TRANSIT haul job merely
## because its source container was destroyed after pickup (requirement:
## "make haul target validity phase-aware").
func _test_haul_in_transit_source_destroyed() -> void:
	var carrier_data := SurvivorData.new()
	var carrier_id: int = WorldState.register_survivor(carrier_data)

	var source := await _make_container("general")
	source.get_inventory().add_item(&"materials", 5)
	var dest := await _make_container("general_dest")
	var board := _make_job_board()

	var job: Job = board.create_haul_job(source, dest, &"materials", 3, 1.0)
	board.claim_job(job, carrier_id)
	var carried := Inventory.new(0.0)
	source.get_inventory().confirm_reserved_transfer(job.reservation_id, carried)
	board.mark_picked_up(job, carrier_id)
	_assert(job.haul_phase == Job.HaulPhase.IN_TRANSIT, "sanity check: job should be in transit before the source is destroyed")

	source.free() # the job's AWAITING_PICKUP-era target, now gone -- 2 unreserved materials were still in it
	_assert(job.is_target_valid(), "an IN_TRANSIT job must stay valid after its source is destroyed -- the cargo already left it")

	# The 2 leftover unreserved materials that were still physically in the
	# source when it was destroyed must be preserved, not lost.
	_assert(WorldState.drops.size() == 1, "the source's remaining stock at time of destruction must produce a WorldDrop")
	var drop: WorldDrop = WorldState.drops.values()[0]
	_assert(drop.inventory.get_count(&"materials") == 2, "the drop holds exactly the 2 materials that were still in the source")
	_assert(drop.reason == &"storage_destroyed", "the drop's reason should identify it as a destroyed-storage drop")
	_assert(carried.get_count(&"materials") == 3, "the 3 already-in-transit units are unaffected, still with the carrier")
	var total: int = carried.get_count(&"materials") + drop.inventory.get_count(&"materials")
	_assert(total == 5, "global conservation across the carrier and the drop: 3 in transit + 2 in the drop == original 5")

	board._validate_some_jobs()
	_assert(board.get_in_transit_haul_job(carrier_id) == job, "periodic job-board validation must not cancel an in-transit job over a destroyed source")

	carrier_data.is_dead = true
	_assert(not job.is_target_valid(), "once the carrier itself is gone, an in-transit job with nobody to deliver it must read as invalid")

	dest.free()
	board.free()

## After dropoff_retry_timeout, a permanently-full destination must
## redirect the cargo to general storage as a fallback rather than
## retrying forever.
func _test_haul_permanently_full_falls_back() -> void:
	var settlement: Settlement = await _make_settlement(["general", "food"])
	var general_container: StorageContainer = settlement.storage_containers["general"]
	var food_container: StorageContainer = settlement.storage_containers["food"]
	general_container.get_inventory().add_item(&"food_ration", 10)
	food_container.get_inventory().capacity_weight = 0.01 # too small to ever fit even 1 unit

	var survivor: Survivor = await _make_survivor({"name": "Hauler"}, settlement)
	var board: SettlementJobBoard = get_tree().get_first_node_in_group("job_board")
	var job: Job = board.create_haul_job(general_container, food_container, &"food_ration", 4, 1.0)

	var action := ActionHaulSupplies.new()
	action.dropoff_retry_timeout = 0.05 # shrink so the test doesn't wait out the real 8s default
	survivor.global_position = general_container.global_position
	action.enter(survivor.ai)
	_assert(action._job == job, "enter() should claim the only available HAUL job")

	var finished: bool = action.tick(survivor.ai, 0.1) # pickup leg
	_assert(not finished and action._picked_up, "the pickup leg should complete in one tick once already at the source")

	survivor.global_position = food_container.global_position # skip travel to the (permanently full) destination
	var iterations: int = 0
	finished = false
	while not finished and iterations < 20:
		finished = action.tick(survivor.ai, 0.1)
		iterations += 1
	_assert(finished, "the stalled dropoff must eventually resolve, not loop forever")
	_assert(iterations < 20, "the stall timeout (0.05s at 0.1s/tick) should resolve within a couple of ticks, not the full 20-iteration budget")

	_assert(job.status == Job.Status.FAILED, "a redirected haul never reached its original destination, so it resolves FAILED even though the cargo is safe")
	_assert(general_container.get_inventory().get_count(&"food_ration") == 10, "fallback delivery returns the cargo to general storage: 6 never hauled + 4 redirected back == 10")
	_assert(food_container.get_inventory().get_count(&"food_ration") == 0, "the permanently-full original destination must never receive anything")
	_assert(survivor.carried_inventory.get_count(&"food_ration") == 0, "the survivor is no longer carrying it once redirected")
	_assert(WorldState.drops.is_empty(), "the fallback succeeded, so no world drop should have been created")

	settlement.free()

## When neither the original destination nor general storage (the
## fallback) can accept the cargo, it must become a recoverable WorldDrop
## instead of being lost.
func _test_haul_no_storage_creates_world_drop() -> void:
	var settlement: Settlement = await _make_settlement(["general", "food"])
	var general_container: StorageContainer = settlement.storage_containers["general"]
	var food_container: StorageContainer = settlement.storage_containers["food"]
	general_container.get_inventory().add_item(&"food_ration", 4)
	food_container.get_inventory().capacity_weight = 0.01 # never fits

	var survivor: Survivor = await _make_survivor({"name": "Hauler"}, settlement)
	var board: SettlementJobBoard = get_tree().get_first_node_in_group("job_board")
	var job: Job = board.create_haul_job(general_container, food_container, &"food_ration", 4, 1.0)

	var action := ActionHaulSupplies.new()
	action.dropoff_retry_timeout = 0.05
	survivor.global_position = general_container.global_position
	action.enter(survivor.ai)
	action.tick(survivor.ai, 0.1) # pickup leg

	# Now make the fallback (general) unable to accept it too. Note: a
	# capacity_weight <= 0.0 means UNLIMITED in this Inventory (see its
	# doc comment) -- a tiny positive value is what represents "no room."
	general_container.get_inventory().capacity_weight = 0.01
	survivor.global_position = food_container.global_position

	var finished: bool = false
	var iterations: int = 0
	while not finished and iterations < 20:
		finished = action.tick(survivor.ai, 0.1)
		iterations += 1
	_assert(finished, "the stalled dropoff must resolve even when no storage can accept it")

	_assert(job.status == Job.Status.FAILED, "the job resolves FAILED exactly once")
	_assert(WorldState.drops.size() == 1, "with no storage able to accept it, exactly one WorldDrop must be created")
	var drop: WorldDrop = WorldState.drops.values()[0]
	_assert(drop.inventory.get_count(&"food_ration") == 4, "the drop must hold exactly the redirected cargo")
	_assert(drop.reason == &"haul_stalled", "the drop's reason should identify it as a stalled haul, not a death")
	_assert(drop.source_survivor_id == survivor.data.id, "the drop must be attributed to the survivor carrying the cargo")

	_assert(general_container.get_inventory().get_count(&"food_ration") == 0, "general never received the redirected cargo -- it couldn't fit either")
	_assert(food_container.get_inventory().get_count(&"food_ration") == 0, "the original destination never received anything")
	_assert(survivor.carried_inventory.get_count(&"food_ration") == 0, "the survivor is no longer carrying it")
	var total: int = general_container.get_inventory().get_count(&"food_ration") + food_container.get_inventory().get_count(&"food_ration") + drop.inventory.get_count(&"food_ration") + survivor.carried_inventory.get_count(&"food_ration")
	_assert(total == 4, "exact conservation: the original 4 units are fully accounted for in the drop")

	settlement.free()

## A real survivor dying while carrying both in-transit HAUL cargo and an
## unrelated personal item must preserve all of it in a WorldDrop, never
## duplicate it into the original destination, and retain the persistent
## SurvivorData record (requirement 1 + the earlier persistent-death-record
## guarantee, exercised together through the real death path).
func _test_survivor_death_preserves_cargo() -> void:
	var settlement: Settlement = await _make_settlement(["general", "food"])
	var general_container: StorageContainer = settlement.storage_containers["general"]
	var food_container: StorageContainer = settlement.storage_containers["food"]
	general_container.get_inventory().add_item(&"food_ration", 3)

	var survivor: Survivor = await _make_survivor({"name": "Doomed"}, settlement)
	var expected_id: int = survivor.data.id
	var death_position: Vector2 = Vector2(123.0, 456.0)
	survivor.global_position = death_position

	# In-transit HAUL cargo.
	var board: SettlementJobBoard = get_tree().get_first_node_in_group("job_board")
	var job: Job = board.create_haul_job(general_container, food_container, &"food_ration", 3, 1.0)
	board.claim_job(job, expected_id)
	general_container.get_inventory().confirm_reserved_transfer(job.reservation_id, survivor.carried_inventory)
	board.mark_picked_up(job, expected_id)

	# Unrelated personal item, never tied to any job.
	survivor.carried_inventory.add_item(&"water_bottle", 2)

	survivor.health_component.take_damage(9999.0) # triggers HealthComponent.died -> Survivor._on_died()

	_assert(job.status == Job.Status.FAILED, "the in-transit job the dead survivor was carrying must resolve FAILED, not linger")
	_assert(WorldState.drops.size() == 1, "death while carrying items must create exactly one WorldDrop")
	var drop: WorldDrop = WorldState.drops.values()[0]
	_assert(drop.reason == &"death", "the drop's reason should identify it as a death drop")
	_assert(drop.source_survivor_id == expected_id, "the drop must be attributed to the dead survivor's id")
	_assert(drop.position.distance_to(death_position) < 0.01, "the drop must be recorded at the survivor's death position")
	_assert(drop.inventory.get_count(&"food_ration") == 3, "the in-transit haul cargo must be preserved in full")
	_assert(drop.inventory.get_count(&"water_bottle") == 2, "the unrelated personal item must be preserved in full alongside it")

	_assert(food_container.get_inventory().get_count(&"food_ration") == 0, "cargo that died with its carrier must never reach the original destination -- no duplication")
	_assert(WorldState.survivors.has(expected_id), "SurvivorData must remain registered after death -- a persistent record")
	_assert(WorldState.get_survivor(expected_id).is_dead, "the persisted record must reflect is_dead = true")

	settlement.free()

## A combined scenario deliberately touching all five named sinks in one
## conservation check: SOURCE and FALLBACK STORAGE (general, playing both
## roles), DESTINATION (food, made permanently full), the SURVIVOR's own
## carried inventory, and a CORPSE/DROP (created twice -- once from a
## stalled haul redirect, once from death).
func _test_exact_conservation_all_sinks() -> void:
	var settlement: Settlement = await _make_settlement(["general", "food"])
	var general_container: StorageContainer = settlement.storage_containers["general"]
	var food_container: StorageContainer = settlement.storage_containers["food"]
	general_container.get_inventory().add_item(&"food_ration", 10)
	food_container.get_inventory().capacity_weight = 0.01 # permanently full: never accepts food_ration

	var survivor: Survivor = await _make_survivor({"name": "Combo"}, settlement)
	var board: SettlementJobBoard = get_tree().get_first_node_in_group("job_board")

	# 1) A HAUL job (general -> food) that will stall and get redirected
	#    back to general (SOURCE doubling as FALLBACK STORAGE, a success).
	var haul_job: Job = board.create_haul_job(general_container, food_container, &"food_ration", 4, 1.0)
	var haul_action := ActionHaulSupplies.new()
	haul_action.dropoff_retry_timeout = 0.05
	survivor.global_position = general_container.global_position
	haul_action.enter(survivor.ai)
	haul_action.tick(survivor.ai, 0.1) # pickup
	survivor.global_position = food_container.global_position
	var finished: bool = false
	var guard: int = 0
	while not finished and guard < 20:
		finished = haul_action.tick(survivor.ai, 0.1)
		guard += 1
	_assert(finished, "the stalled haul must resolve")
	_assert(general_container.get_inventory().get_count(&"food_ration") == 10, "food_ration: 6 never hauled + 4 redirected back to general (SOURCE/FALLBACK) == 10")
	_assert(food_container.get_inventory().get_count(&"food_ration") == 0, "food_ration: the permanently-full DESTINATION receives nothing")

	# 2) A successful personal-carry-home of materials, landing in general
	#    (FALLBACK STORAGE as an unambiguous success, distinct item type).
	survivor.carried_inventory.add_item(&"materials", 3)
	var carry_action := ActionHaulSupplies.new()
	survivor.global_position = general_container.global_position
	carry_action.enter(survivor.ai)
	_assert(carry_action._personal_item == &"materials", "with no HAUL job left, personal-carry should pick up the carried materials")
	var carry_finished: bool = carry_action.tick(survivor.ai, 0.1)
	_assert(carry_finished, "personal-carry-home should complete in one tick once already at general storage")
	_assert(general_container.get_inventory().get_count(&"materials") == 3, "materials: fully delivered via the fallback/general-storage success path")
	_assert(survivor.carried_inventory.get_count(&"materials") == 0, "materials: none left with the SURVIVOR after delivery")

	# 3) An unrelated personal item still on the survivor when it dies,
	#    landing in a death CORPSE/DROP.
	survivor.carried_inventory.add_item(&"water_bottle", 2)
	survivor.health_component.take_damage(9999.0)

	# Only one drop is expected here: the haul redirect (step 1) succeeded
	# via the general-storage fallback, so it never needed a world drop --
	# only death (step 3) does.
	_assert(WorldState.drops.size() == 1, "exactly one drop: the haul redirect succeeded via fallback storage, only death should have needed a world drop")
	var haul_drop: WorldDrop = null
	var death_drop: WorldDrop = null
	for drop in WorldState.drops.values():
		if drop.reason == &"haul_stalled":
			haul_drop = drop
		elif drop.reason == &"death":
			death_drop = drop
	_assert(haul_drop == null, "the haul redirect succeeded via fallback storage in this scenario, so it must NOT have needed a world drop")
	_assert(death_drop != null, "the death drop must exist")
	_assert(death_drop.inventory.get_count(&"water_bottle") == 2, "water_bottle: fully preserved in the death CORPSE/DROP")

	settlement.free()

## Exercises repeated REAL Main.tscn instantiate -> populate WorldState via
## its real _ready()/_spawn_survivors() -> reset -> free -> reinstantiate
## cycles (not just calling WorldState.reset()/SimulationClock.reset() in
## isolation, which _test_restart_resets_ids_and_time already covers at
## the data level alone). Deliberately does NOT call Main._restart_game()'s
## own get_tree().reload_current_scene() directly: that targets whatever
## SceneTree.current_scene is, which is this TestRunner (the actual
## process's launched scene) -- calling it here would tear down the very
## node this test runs from. Instead this drives the same sequence
## _restart_game() performs (reset both simulation autoloads, then let a
## fresh scene instance re-register everything) against real Main.tscn
## instances added as ordinary children, which exercises everything
## observable about the restart contract -- no accumulating ids/records,
## clean node teardown across repeated cycles -- without that hazard. The
## literal restart-button flow was separately verified interactively
## through the godot-ai MCP session.
func _test_repeated_restart_lifecycle() -> void:
	var main_scene: PackedScene = load("res://scenes/main/Main.tscn")
	var baseline_max_id: int = -1

	for run in range(3):
		var main_instance: Node = main_scene.instantiate()
		add_child(main_instance)
		await get_tree().process_frame
		await get_tree().process_frame

		var survivor_count: int = WorldState.survivors.size()
		_assert(survivor_count == 4, "run %d: Main.tscn should register exactly 4 survivors, not accumulate across restarts" % run)

		var max_id: int = 0
		for id in WorldState.survivors.keys():
			max_id = maxi(max_id, id)
		if run == 0:
			baseline_max_id = max_id
		else:
			_assert(max_id == baseline_max_id, "run %d: survivor ids must restart from the same baseline every time (got max id %d, expected %d), not drift upward across repeated restarts" % [run, max_id, baseline_max_id])

		_assert(SimulationClock.game_day == 1 and SimulationClock.game_hour == 0 and SimulationClock.game_minute == 0, "run %d: a fresh run starts at day 1, 00:00" % run)
		_assert(SimulationClock.total_game_minutes() == 0, "run %d: total_game_minutes() must be exactly zero on a fresh run" % run)

		var job_board: SettlementJobBoard = get_tree().get_first_node_in_group("job_board")
		_assert(job_board != null and job_board.total_job_count() > 0, "run %d: the settlement's standing jobs (scavenge/guard) should exist after a fresh spawn" % run)

		# Mirror exactly what Main._restart_game() does (WorldState.reset(),
		# SimulationClock.reset()) before tearing this run's scene down and
		# building the next one fresh, so the next iteration's registrations
		# start from a genuinely clean registry -- just as a real restart's
		# freshly-reloaded Main.tscn would.
		WorldState.reset()
		SimulationClock.reset()
		main_instance.free()
		await get_tree().process_frame

## --- Destroyed storage-container lifecycle -------------------------------

## Direct test of StorageContainer._exit_tree(): the id must resolve to
## nothing the instant the node leaves the tree (free() is immediate, not
## deferred), not just eventually.
func _test_storage_container_unregisters_on_exit() -> void:
	var container: StorageContainer = await _make_container("general")
	var id: int = container.container_id
	_assert(id != 0, "a real, tree-added container should have registered and gotten a stable id")
	_assert(WorldState.get_container(id) != null, "WorldState should resolve the id to the container's Inventory while it's alive")

	container.free()
	_assert(WorldState.get_container(id) == null, "WorldState.get_container(old_id) must become null the moment the container node exits the tree")
	_assert(WorldState.drops.is_empty(), "destroying an EMPTY container must not create an empty WorldDrop")

## A HAUL job's source container destroyed before pickup (still
## AWAITING_PICKUP) must be cancelled cleanly by periodic validation, AND
## its contents (reserved and unreserved alike) must be PRESERVED in a
## WorldDrop, not simply vanish.
##
## An earlier version of this test asserted the opposite (WorldState.drops
## must stay empty when a source is destroyed before pickup) and called
## that "conservation" -- it only proved non-duplication (nothing appeared
## twice), not conservation (every item still exists somewhere). This is
## the corrected version, exercising the exact scenario called out for it:
## a source with 5 items, 3 reserved, destroyed before pickup.
func _test_haul_source_destroyed_before_pickup() -> void:
	var source: StorageContainer = await _make_container("general")
	source.get_inventory().add_item(&"food_ration", 5)
	var dest: StorageContainer = await _make_container("food")
	var board := _make_job_board()

	var job: Job = board.create_haul_job(source, dest, &"food_ration", 3, 1.0)
	_assert(job != null, "haul job creation should succeed")
	board.claim_job(job, 55)
	_assert(job.haul_phase == Job.HaulPhase.AWAITING_PICKUP, "sanity check: not yet picked up")
	_assert(source.get_inventory().get_available(&"food_ration") == 2, "sanity check: 3 of 5 reserved, 2 available")

	var global_total_before: int = source.get_inventory().get_count(&"food_ration") + dest.get_inventory().get_count(&"food_ration")
	_assert(global_total_before == 5, "sanity check: 5 total items exist before destruction")

	var source_id: int = source.container_id
	source.free() # destroyed before the survivor ever reaches it: 2 unreserved + 3 reserved

	_assert(WorldState.get_container(source_id) == null, "the source's registration must be gone once it's freed")
	_assert(not job.is_target_valid(), "an AWAITING_PICKUP job whose source no longer exists must read as invalid")

	# Reservation-backed job cancels and cannot be reclaimed.
	board._validate_some_jobs()
	_assert(WorldState.get_job(job.id) == null, "periodic validation must cancel (and deregister) the job once its source is gone")
	_assert(job.status == Job.Status.CANCELLED, "the job should resolve to CANCELLED, not linger or get stuck")
	var still_claimable := false
	for available_job in board.get_available_jobs(&"", Vector2.ZERO, -1.0):
		if available_job.id == job.id:
			still_claimable = true
	_assert(not still_claimable, "a cancelled job must never resurface as claimable")
	_assert(not board.claim_job(job, 99), "a cancelled job must not be reclaimable by any survivor")

	# Exactly 5 items appear in one WorldDrop -- both the 2 that were never
	# reserved and the 3 that were reserved for the now-cancelled job.
	_assert(WorldState.drops.size() == 1, "destroying a non-empty source must create exactly one WorldDrop")
	var drop: WorldDrop = WorldState.drops.values()[0]
	_assert(drop.inventory.get_count(&"food_ration") == 5, "the drop must hold all 5 original items, reserved and unreserved alike")
	_assert(drop.reason == &"storage_destroyed", "the drop's reason should identify it as a destroyed-storage drop")
	_assert(drop.source_container_id == source_id, "the drop must be attributed to the destroyed container's id")
	_assert(drop.storage_role == "general", "the drop must record the destroyed container's storage role")
	_assert(drop.inventory.reservation_count() == 0, "items in the drop must be unreserved and recoverable")

	# Destination and survivor receive zero items in this scenario.
	_assert(dest.get_inventory().get_count(&"food_ration") == 0, "the never-reached destination must receive nothing")
	var carried := Inventory.new(0.0) # stands in for "the survivor" -- pickup never happened, so it holds nothing
	_assert(carried.get_count(&"food_ration") == 0, "the survivor (which never picked anything up) carries nothing")

	# Global total before destruction equals global total afterward, summed
	# across every valid sink: containers + survivor inventories + drops.
	var global_total_after: int = (source.get_inventory().get_count(&"food_ration") if is_instance_valid(source) else 0)
	global_total_after += dest.get_inventory().get_count(&"food_ration") + drop.inventory.get_count(&"food_ration") + carried.get_count(&"food_ration")
	_assert(global_total_after == global_total_before, "global total must be identical before and after destruction: %d != %d" % [global_total_after, global_total_before])

	dest.free()
	board.free()

## A HAUL destination destroyed after pickup (while cargo is in transit)
## must be treated as permanently missing -- immediate redirect, no
## retrying -- and land safely in a still-valid fallback (general storage).
func _test_haul_destination_destroyed_redirects_to_fallback() -> void:
	var settlement: Settlement = await _make_settlement(["general", "food"])
	var general_container: StorageContainer = settlement.storage_containers["general"]
	var food_container: StorageContainer = settlement.storage_containers["food"]
	general_container.get_inventory().add_item(&"food_ration", 10)

	var survivor: Survivor = await _make_survivor({"name": "Hauler"}, settlement)
	var board: SettlementJobBoard = get_tree().get_first_node_in_group("job_board")
	var job: Job = board.create_haul_job(general_container, food_container, &"food_ration", 4, 1.0)
	var dest_position: Vector2 = job.dest_position
	var dest_id: int = food_container.container_id

	var action := ActionHaulSupplies.new()
	survivor.global_position = general_container.global_position
	action.enter(survivor.ai)
	var pickup_finished: bool = action.tick(survivor.ai, 0.1) # pickup leg
	_assert(not pickup_finished and action._picked_up, "the pickup leg should complete in one tick once already at the source")

	food_container.free() # destination destroyed while cargo is in transit
	_assert(WorldState.get_container(dest_id) == null, "the destroyed destination's registration must be gone")

	survivor.global_position = dest_position # walk to where it used to be
	var finished: bool = action.tick(survivor.ai, 0.1)
	_assert(finished, "a destroyed (permanently missing) destination must redirect immediately, not retry")

	_assert(job.status == Job.Status.FAILED, "the job resolves FAILED -- it never reached its original, now-destroyed destination")
	_assert(general_container.get_inventory().get_count(&"food_ration") == 10, "fallback delivery returns the cargo to general: 6 never hauled + 4 redirected == 10")
	_assert(survivor.carried_inventory.get_count(&"food_ration") == 0, "the survivor is no longer carrying it")
	_assert(WorldState.drops.is_empty(), "the fallback succeeded, so no world drop was needed (food_container was empty when destroyed, and the cargo landed safely in general)")

	var drop_total: int = 0
	for drop in WorldState.drops.values():
		drop_total += drop.inventory.get_count(&"food_ration")
	var global_total: int = general_container.get_inventory().get_count(&"food_ration") + survivor.carried_inventory.get_count(&"food_ration") + drop_total
	_assert(global_total == 10, "global conservation summed across containers + survivor + drops: all 10 original units accounted for")

	settlement.free()

## When both the HAUL destination and the fallback (general storage) are
## destroyed, the cargo must become a recoverable WorldDrop through a
## ghost/stale Inventory reference never accepting it in between.
func _test_haul_destination_and_fallback_destroyed_creates_world_drop() -> void:
	var settlement: Settlement = await _make_settlement(["general", "food"])
	var general_container: StorageContainer = settlement.storage_containers["general"]
	var food_container: StorageContainer = settlement.storage_containers["food"]
	general_container.get_inventory().add_item(&"food_ration", 4)

	var survivor: Survivor = await _make_survivor({"name": "Hauler"}, settlement)
	var board: SettlementJobBoard = get_tree().get_first_node_in_group("job_board")
	var job: Job = board.create_haul_job(general_container, food_container, &"food_ration", 4, 1.0)
	var dest_position: Vector2 = job.dest_position

	var action := ActionHaulSupplies.new()
	survivor.global_position = general_container.global_position
	action.enter(survivor.ai)
	action.tick(survivor.ai, 0.1) # pickup leg
	_assert(action._picked_up, "pickup should have completed")

	food_container.free() # destination destroyed
	general_container.free() # fallback (general) ALSO destroyed

	survivor.global_position = dest_position
	var finished: bool = action.tick(survivor.ai, 0.1)
	_assert(finished, "with no valid destination or fallback, the redirect must still resolve (to a world drop), not stall or crash reading a destroyed reference")

	_assert(job.status == Job.Status.FAILED, "the job resolves FAILED exactly once")
	_assert(WorldState.drops.size() == 1, "with neither the destination nor the fallback available, exactly one WorldDrop must be created")
	var drop: WorldDrop = WorldState.drops.values()[0]
	_assert(drop.inventory.get_count(&"food_ration") == 4, "the drop must hold exactly the cargo that could go nowhere else")
	_assert(drop.reason == &"haul_stalled", "the drop's reason should identify it as a stalled haul")
	_assert(survivor.carried_inventory.get_count(&"food_ration") == 0, "the survivor is no longer carrying it")

	var drop_total: int = 0
	for d in WorldState.drops.values():
		drop_total += d.inventory.get_count(&"food_ration")
	var global_total: int = survivor.carried_inventory.get_count(&"food_ration") + drop_total # both containers are gone (destroyed empty)
	_assert(global_total == 4, "global conservation summed across the survivor + drops: all 4 original units accounted for")

	settlement.free()

## Repeated create/free cycles on standalone containers must not leave
## WorldState.containers growing without bound, and must produce exactly
## one WorldDrop per destroyed (non-empty) container -- not zero (items
## quietly lost) and not more than one per container (duplicated).
func _test_repeated_container_create_free_does_not_grow_registry() -> void:
	var initial_container_count: int = WorldState.containers.size()
	var initial_drop_count: int = WorldState.drops.size()
	for i in range(15):
		var container: StorageContainer = await _make_container("general")
		container.get_inventory().add_item(&"materials", 2)
		var id: int = container.container_id
		_assert(WorldState.get_container(id) != null, "cycle %d: a freshly created container should be registered" % i)
		container.free() # container is invalid from here on -- read id, not container, below
		_assert(WorldState.get_container(id) == null, "cycle %d: a freed container should be unregistered immediately" % i)
		_assert(WorldState.drops.size() == initial_drop_count + i + 1, "cycle %d: exactly one new WorldDrop per destroyed non-empty container -- got %d drops" % [i, WorldState.drops.size()])
	_assert(WorldState.containers.size() == initial_container_count, "15 create/free cycles must not grow WorldState.containers -- got %d, expected %d" % [WorldState.containers.size(), initial_container_count])
	_assert(WorldState.drops.size() == initial_drop_count + 15, "exactly 15 drops total, one per destroyed container")

	var total_materials_in_drops: int = 0
	for drop in WorldState.drops.values():
		total_materials_in_drops += drop.inventory.get_count(&"materials")
	_assert(total_materials_in_drops == 30, "exact conservation across repeated destruction: 15 containers x 2 materials each == 30 total preserved in drops")

## Destroying a container holding multiple distinct item types must
## preserve every stack in the resulting WorldDrop, not just one.
func _test_storage_destruction_preserves_multiple_item_types() -> void:
	var container: StorageContainer = await _make_container("general")
	container.get_inventory().add_item(&"food_ration", 4)
	container.get_inventory().add_item(&"water_bottle", 6)
	container.get_inventory().add_item(&"materials", 2)
	var global_total_before: int = 4 + 6 + 2

	container.free()

	_assert(WorldState.drops.size() == 1, "one drop total, holding every stack from the destroyed container")
	var drop: WorldDrop = WorldState.drops.values()[0]
	_assert(drop.inventory.get_count(&"food_ration") == 4, "food_ration stack fully preserved")
	_assert(drop.inventory.get_count(&"water_bottle") == 6, "water_bottle stack fully preserved")
	_assert(drop.inventory.get_count(&"materials") == 2, "materials stack fully preserved")

	var global_total_after: int = drop.inventory.get_count(&"food_ration") + drop.inventory.get_count(&"water_bottle") + drop.inventory.get_count(&"materials")
	_assert(global_total_after == global_total_before, "global total across every item type must be identical before and after destruction")

## A restart tears the whole scene (and every StorageContainer in it) down
## at once via WorldState.reset() running BEFORE the old scene's nodes are
## freed -- by the time each container's NOTIFICATION_PREDELETE fires,
## WorldState no longer has it registered (WorldState.reset() already
## cleared it), so _handle_permanent_destruction() must recognize that and
## skip creating a drop: this is "the whole registry was torn down at
## once," not "this one container was individually destroyed."
func _test_restart_teardown_creates_no_destruction_drops() -> void:
	var main_scene: PackedScene = load("res://scenes/main/Main.tscn")
	var main_instance: Node = main_scene.instantiate()
	add_child(main_instance)
	await get_tree().process_frame
	await get_tree().process_frame

	_assert(WorldState.containers.size() > 0, "sanity check: the fresh scene should have registered its storage containers")
	_assert(WorldState.drops.is_empty(), "sanity check: no drops yet")

	# Mirror Main._restart_game(): reset both simulation autoloads BEFORE
	# tearing down the old scene, exactly as a real restart does.
	WorldState.reset()
	SimulationClock.reset()
	main_instance.free()
	await get_tree().process_frame

	_assert(WorldState.drops.is_empty(), "an ordinary restart teardown must never create destruction drops for the containers (with real starting stock -- food/water/medical/materials) it's discarding wholesale")
	_assert(WorldState.containers.is_empty(), "the reset registry must stay empty -- nothing re-registered itself during teardown")

## Reparenting a StorageContainer between settlements must never be
## treated as destruction: same id, same Inventory instance and contents,
## and correct ownership handoff to the new settlement.
func _test_reparenting_preserves_registration_and_ownership() -> void:
	var old_settlement: Settlement = await _make_settlement(["general"])
	var new_settlement: Settlement = await _make_settlement(["food"]) # distinct role: no collision on the move

	var container: StorageContainer = old_settlement.storage_containers["general"]
	container.get_inventory().add_item(&"materials", 7)
	var original_id: int = container.container_id
	var original_inventory: Inventory = container.get_inventory()

	_assert(old_settlement.storage_containers.get("general") == container, "sanity check: the old settlement owns it before the move")

	old_settlement.remove_child(container)
	new_settlement.add_child(container)
	await get_tree().process_frame

	_assert(WorldState.drops.is_empty(), "reparenting must never produce a WorldDrop")
	_assert(WorldState.get_container(original_id) == original_inventory, "the container must remain registered under the SAME id, resolving to the SAME Inventory instance")
	_assert(container.container_id == original_id, "the container's own id must not change across a reparent")
	_assert(container.get_inventory() == original_inventory, "the container must keep the SAME Inventory instance (identity), not a fresh empty one")
	_assert(container.get_inventory().get_count(&"materials") == 7, "contents must survive the reparent untouched")

	_assert(old_settlement.storage_containers.get("general") == null, "the OLD settlement must no longer reference the moved container")
	_assert(new_settlement.storage_containers.get("general") == container, "the NEW settlement must now own it under its storage_role")
	_assert(new_settlement.data.storage_container_ids.get("general") == original_id, "the new settlement's persistent record must reflect the same container id")

	old_settlement.free()
	new_settlement.free()

## RNG isolation: a Zombie's gameplay-relevant RNG output (its
## ZombiePerceptionComponent's perception-tick stagger, seeded via
## rng_seed) must be identical across two runs with the same seed,
## regardless of how much the shared CosmeticRng stream (visual variant
## selection, blood decals, ...) is drawn from in between -- proving
## cosmetic randomness can never contaminate a gameplay RNG sequence.
func _test_cosmetic_rng_does_not_affect_zombie_retarget_timing() -> void:
	# Read the perception component's _update_timer immediately after
	# add_child() -- _ready() (and its @onready resolution) runs
	# synchronously during add_child() in Godot 4, so this captures the
	# seeded initial value before any _physics_process tick has had a
	# chance to decrement it (an `await get_tree().process_frame` here
	# would let a stray physics frame through non-deterministically and
	# make the comparison flaky for reasons unrelated to RNG isolation).
	var zombie_a: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(zombie_a)
	zombie_a.perception.rng_seed = 42424
	zombie_a.perception._ready()
	var timer_a: float = zombie_a.perception._update_timer
	zombie_a.queue_free()
	await get_tree().process_frame

	# Simulate "visual effects heavily active" between the two seeded runs.
	for i in range(1000):
		CosmeticRng.randf()
		CosmeticRng.randi_range(0, 7)

	var zombie_b: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(zombie_b)
	zombie_b.perception.rng_seed = 42424
	zombie_b.perception._ready()
	var timer_b: float = zombie_b.perception._update_timer
	zombie_b.queue_free()
	await get_tree().process_frame

	_assert(is_equal_approx(timer_a, timer_b), "same rng_seed must produce identical zombie perception timing regardless of interleaved CosmeticRng usage (got %f vs %f)" % [timer_a, timer_b])

## Same isolation guarantee, for SpawnManager's spawn-position RNG.
func _test_cosmetic_rng_does_not_affect_spawn_positions() -> void:
	var manager_a: SpawnManager = SPAWN_MANAGER_SCRIPT.new()
	manager_a.zombie_scene = ZOMBIE_SCENE
	manager_a.rng_seed = 99001
	add_child(manager_a)
	await get_tree().process_frame
	var pos_a: Vector2 = manager_a._pick_spawn_position()
	manager_a.free()
	await get_tree().process_frame

	for i in range(1000):
		CosmeticRng.randf()
		CosmeticRng.randi_range(0, 7)

	var manager_b: SpawnManager = SPAWN_MANAGER_SCRIPT.new()
	manager_b.zombie_scene = ZOMBIE_SCENE
	manager_b.rng_seed = 99001
	add_child(manager_b)
	await get_tree().process_frame
	var pos_b: Vector2 = manager_b._pick_spawn_position()
	manager_b.free()
	await get_tree().process_frame

	_assert(pos_a.is_equal_approx(pos_b), "same rng_seed must produce identical spawn positions regardless of interleaved CosmeticRng usage (got %s vs %s)" % [pos_a, pos_b])

## --- Phase 3B.1: authored-region spawning --------------------------------

func _make_spawn_manager(seed_value: int) -> SpawnManager:
	var manager := SpawnManager.new()
	manager.zombie_scene = ZOMBIE_SCENE
	manager.rng_seed = seed_value
	add_child(manager)
	await get_tree().process_frame
	return manager

func _make_spawn_region(region_id: StringName, pos: Vector2, radius: float) -> SpawnRegion:
	var region := SpawnRegion.new()
	region.region_id = region_id
	region.radius = radius
	add_child(region)
	region.global_position = pos
	await get_tree().process_frame
	return region

func _test_spawn_region_production_spawn_lands_in_authored_region() -> void:
	var container := Node2D.new()
	add_child(container)
	container.add_to_group("entity_container")
	var region := await _make_spawn_region(&"test/region_a", Vector2(70000, 70000), 100.0)
	var manager := await _make_spawn_manager(555)

	var zombie: Node2D = manager._spawn_one()
	_assert(zombie != null, "with one valid authored region, a production spawn must succeed")
	_assert(zombie.global_position.distance_to(region.global_position) <= region.radius + 0.01, "the spawned position must fall within the authored region's own radius")

	zombie.queue_free()
	region.queue_free()
	container.queue_free()
	manager.queue_free()
	await get_tree().process_frame

func _test_spawn_region_selection_is_deterministic_for_same_seed() -> void:
	var region_a := await _make_spawn_region(&"test/det_a", Vector2(70500, 70000), 120.0)
	var region_b := await _make_spawn_region(&"test/det_b", Vector2(70500, 70400), 120.0)

	var manager_1 := await _make_spawn_manager(9001)
	var pos_1: Variant = manager_1._pick_region_spawn_position()
	manager_1.queue_free()
	await get_tree().process_frame

	var manager_2 := await _make_spawn_manager(9001)
	var pos_2: Variant = manager_2._pick_region_spawn_position()
	manager_2.queue_free()
	await get_tree().process_frame

	_assert(pos_1 != null and pos_2 != null, "sanity: both picks should succeed with two open regions")
	_assert((pos_1 as Vector2).is_equal_approx(pos_2), "the same rng_seed against the same regions must pick the identical region and point")

	region_a.queue_free()
	region_b.queue_free()
	await get_tree().process_frame

func _test_spawn_region_rejects_point_inside_wall() -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(400, 400)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector2(71000, 70000)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Small region fully inside the wall's own footprint -- every candidate must be rejected.
	var region := await _make_spawn_region(&"test/walled_region", Vector2(71000, 70000), 50.0)
	var manager := await _make_spawn_manager(42)

	var position: Variant = manager._pick_region_spawn_position()
	_assert(position == null, "a region entirely inside World collision must never yield a valid spawn candidate")

	manager.queue_free()
	region.queue_free()
	wall.queue_free()
	await get_tree().process_frame

func _test_spawn_region_rejects_point_inside_player_current_room() -> void:
	var room := Room.new()
	room.room_id = &"test_room"
	room.building_id = &"test_building"
	var room_shape := RectangleShape2D.new()
	room_shape.size = Vector2(300, 300)
	var room_collider := CollisionShape2D.new()
	room_collider.shape = room_shape
	room.add_child(room_collider)
	room.position = Vector2(72000, 70000)
	add_child(room)
	await get_tree().physics_frame

	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = room.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame

	_assert(Room.room_containing(player) == room, "sanity: the player must read as inside the room once physically overlapping it")

	# Region entirely inside the room's own bounds.
	var region := await _make_spawn_region(&"test/room_region", room.global_position, 80.0)
	var manager := await _make_spawn_manager(7)

	var position: Variant = manager._pick_region_spawn_position()
	_assert(position == null, "a region entirely inside the player's current room must never yield a valid spawn candidate")

	manager.queue_free()
	region.queue_free()
	player.queue_free()
	room.queue_free()
	await get_tree().process_frame

func _test_spawn_region_rejects_point_inside_safehouse() -> void:
	var settlement := Settlement.new()
	settlement.settlement_name = "TestSafehouse"
	settlement.safe_radius = 200.0
	add_child(settlement)
	settlement.global_position = Vector2(73000, 70000)
	await get_tree().process_frame

	var region := await _make_spawn_region(&"test/safehouse_region", settlement.global_position, 60.0)
	var manager := await _make_spawn_manager(11)

	var position: Variant = manager._pick_region_spawn_position()
	_assert(position == null, "a region entirely inside the safehouse's safe_radius must never yield a valid spawn candidate")

	manager.queue_free()
	region.queue_free()
	settlement.queue_free()
	await get_tree().process_frame

## "Delay" is observed as a skipped spawn (null, zero-count) rather than a
## crash or a forced arbitrary-position fallback -- SpawnManager's own
## periodic timer is what retries it later, nothing this test needs to
## simulate directly.
func _test_spawn_region_failed_search_delays_spawn_safely() -> void:
	var container := Node2D.new()
	add_child(container)
	container.add_to_group("entity_container")

	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := RectangleShape2D.new()
	shape.size = Vector2(400, 400)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector2(74000, 70000)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var region := await _make_spawn_region(&"test/always_blocked", Vector2(74000, 70000), 50.0)
	var manager := await _make_spawn_manager(3)

	var zombie: Node2D = manager._spawn_one()
	_assert(zombie == null, "a spawn attempt with no valid candidate must be skipped, not forced through")
	_assert(manager.active_zombie_count() == 0, "a skipped spawn must not register a phantom zombie")

	manager.queue_free()
	region.queue_free()
	wall.queue_free()
	container.queue_free()
	await get_tree().process_frame

func _test_cosmetic_rng_does_not_affect_spawn_region_selection() -> void:
	var region_a := await _make_spawn_region(&"test/rng_a", Vector2(75000, 70000), 120.0)
	var region_b := await _make_spawn_region(&"test/rng_b", Vector2(75000, 70400), 120.0)

	var manager_1 := await _make_spawn_manager(4242)
	var pos_1: Variant = manager_1._pick_region_spawn_position()
	manager_1.queue_free()
	await get_tree().process_frame

	for i in range(1000):
		CosmeticRng.randf()
		CosmeticRng.randi_range(0, 7)

	var manager_2 := await _make_spawn_manager(4242)
	var pos_2: Variant = manager_2._pick_region_spawn_position()
	manager_2.queue_free()
	await get_tree().process_frame

	_assert(pos_1 != null and pos_2 != null, "sanity: both picks should succeed")
	_assert((pos_1 as Vector2).is_equal_approx(pos_2), "same rng_seed must produce identical spawn-region selection regardless of interleaved CosmeticRng usage")

	region_a.queue_free()
	region_b.queue_free()
	await get_tree().process_frame

## --- Phase 3B.1: snapshot serialization of persistent prop state ---------

## The full round trip Section 7 asks for: state -> snapshot -> reset ->
## restore -> identical state, covering an open door, a salvaged prop
## flag, a partially-searched (non-empty) container, AND a fully-depleted
## (empty) one -- "depleted" is exactly the case a naive restore could get
## wrong by treating an empty counts dict as "nothing to restore."
func _test_snapshot_includes_and_restores_phase_3b_state() -> void:
	WorldState.set_door_open(&"test/snap_door", true)
	WorldState.set_prop_state_flag(&"test/snap_wreck", &"salvaged", true)
	var partial: Inventory = WorldState.get_or_create_prop_container(&"test/snap_shelf", 50.0, {"food_ration": 3, "materials": 2})
	partial.remove_item(&"food_ration", 1) # 2 food_ration + 2 materials left -- a "partially searched" container
	var depleted: Inventory = WorldState.get_or_create_prop_container(&"test/snap_empty_fridge", 40.0, {"water_bottle": 1})
	depleted.remove_item(&"water_bottle", 1) # now fully empty -- a "depleted" container

	var snapshot: Dictionary = WorldState.to_snapshot()
	_assert(snapshot.has("door_states") and snapshot.has("prop_states") and snapshot.has("prop_containers"), "to_snapshot() must include all three Phase 3B.1 dictionaries")
	_assert(snapshot["door_states"][&"test/snap_door"] == true, "the snapshot must capture the door's open state")
	_assert(snapshot["prop_states"][&"test/snap_wreck"][&"salvaged"] == true, "the snapshot must capture the salvaged flag")
	_assert(snapshot["prop_containers"][&"test/snap_shelf"]["counts"][&"food_ration"] == 2, "the snapshot must capture the exact partially-searched contents")
	_assert(snapshot["prop_containers"][&"test/snap_empty_fridge"]["counts"].is_empty(), "the snapshot must capture a depleted container as truly empty, not omit it")

	WorldState.reset()
	_assert(WorldState.door_states.is_empty() and WorldState.prop_states.is_empty() and WorldState.prop_containers.is_empty(), "sanity: reset() must clear all three before restoring")

	WorldState.restore_phase_3b_state(snapshot)
	_assert(WorldState.get_door_open(&"test/snap_door"), "restore must reproduce the door's exact open state")
	_assert(WorldState.get_prop_state_flag(&"test/snap_wreck", &"salvaged", false), "restore must reproduce the salvaged flag")

	var restored_shelf: Inventory = WorldState.get_or_create_prop_container(&"test/snap_shelf", 999.0, {"materials": 999})
	_assert(restored_shelf.get_count(&"food_ration") == 2, "restore must reproduce the exact partially-searched food_ration count")
	_assert(restored_shelf.get_count(&"materials") == 2, "restore must reproduce the exact partially-searched materials count")
	_assert(restored_shelf.capacity_weight == 50.0, "restore must reproduce the container's original capacity, not whatever a later get_or_create_prop_container call happens to pass")

	var restored_fridge: Inventory = WorldState.get_or_create_prop_container(&"test/snap_empty_fridge", 999.0, {"water_bottle": 999})
	_assert(restored_fridge.is_empty(), "restore must reproduce a depleted container as still empty, not resurrect its original stock")

func _test_snapshot_restore_is_idempotent_no_duplication() -> void:
	WorldState.set_door_open(&"test/idem_door", true)
	WorldState.get_or_create_prop_container(&"test/idem_shelf", 50.0, {"materials": 4})
	var snapshot: Dictionary = WorldState.to_snapshot()

	WorldState.restore_phase_3b_state(snapshot)
	WorldState.restore_phase_3b_state(snapshot) # restoring twice must not double anything

	_assert(WorldState.prop_containers.size() == 1, "restoring the same snapshot twice must not grow prop_containers")
	_assert(WorldState.get_or_create_prop_container(&"test/idem_shelf", 50.0, {}).get_count(&"materials") == 4, "restoring the same snapshot twice must not duplicate a container's contents")
	_assert(WorldState.door_states.size() == 1, "restoring the same snapshot twice must not grow door_states")

## --- Phase 3B.1: DetectableComponent + noise-aware perception -----------
## All fixtures live in an isolated coordinate region (80000+) for the
## same reason the Phase 3B perception tests do -- see the note near
## _test_zombie_perception_detects_and_chases_visible_target.

func _make_detectable(owner_node: Node2D) -> DetectableComponent:
	var detectable := DetectableComponent.new()
	detectable.name = "DetectableComponent" # get_node_or_null("DetectableComponent") depends on this exact name
	owner_node.add_child(detectable)
	return detectable

## A target beyond the STATIONARY-reduced effective vision range (but
## within the full range) must go undetected while stationary and become
## detectable the instant it starts moving, at the identical distance --
## the range-based version of "stationary takes longer to detect" (in the
## limit, "never" while it stays out of the reduced range).
func _test_detectable_visibility_multiplier_affects_detection_range() -> void:
	var target := _make_attackable_target(Vector2(80000, 80220)) # 220 units away
	var detectable := _make_detectable(target)

	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(zombie)
	zombie.global_position = Vector2(80000, 80000)
	zombie.perception.facing = Vector2.DOWN

	detectable.report_movement_speed(0.0) # stationary: effective range 260 * 0.7 = 182 -- 220 is out of range
	zombie.perception._tick_perception()
	_assert(zombie.perception.state == ZombiePerceptionComponent.State.IDLE, "a stationary target beyond the reduced stationary-visibility range must not be detected")

	detectable.report_movement_speed(200.0) # moving: effective range back to the full 260 -- 220 is in range
	zombie.perception._tick_perception()
	_assert(zombie.perception.state == ZombiePerceptionComponent.State.SUSPICIOUS, "the same target, now moving, must become detectable at the same distance a stationary reading missed")

	zombie.queue_free()
	target.queue_free()
	await get_tree().process_frame

func _test_detectable_missing_component_defaults_to_full_visibility() -> void:
	var target := _make_attackable_target(Vector2(80100, 80100)) # no DetectableComponent attached at all
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(zombie)
	zombie.global_position = Vector2(80100, 80000)
	zombie.perception.facing = Vector2.DOWN

	zombie.perception._tick_perception()
	_assert(zombie.perception.state == ZombiePerceptionComponent.State.SUSPICIOUS, "a target with no DetectableComponent must still be detectable normally -- the 1.0-visibility fallback default")

	zombie.queue_free()
	target.queue_free()
	await get_tree().process_frame

func _test_detectable_walking_noise_heard_only_nearby() -> void:
	var actor := Node2D.new()
	add_child(actor)
	actor.global_position = Vector2(81000, 80000)
	var detectable := _make_detectable(actor)
	detectable.report_movement_speed(50.0) # walking (below running_speed_threshold)
	detectable.report_activity_noise(detectable.effective_movement_loudness(), &"footstep")

	var near: Array[Dictionary] = NoiseManager.recent_noises_near(Vector2(81000, 80030), 220.0) # 30 units -- within walking's ~40 radius
	var far: Array[Dictionary] = NoiseManager.recent_noises_near(Vector2(81000, 80100), 220.0) # 100 units -- beyond it
	_assert(not near.is_empty(), "walking noise must be heard by a listener close by")
	_assert(far.is_empty(), "walking noise must NOT be heard by a listener far away")

	actor.queue_free()
	await get_tree().process_frame

func _test_detectable_running_noise_reaches_farther_than_walking() -> void:
	var actor := Node2D.new()
	add_child(actor)
	actor.global_position = Vector2(82000, 80000)
	var detectable := _make_detectable(actor)
	detectable.report_movement_speed(200.0) # running
	detectable.report_activity_noise(detectable.effective_movement_loudness(), &"footstep")

	var listener_pos := Vector2(82000, 80090) # 90 units -- beyond walking's ~40 radius, within running's ~120 radius
	var heard: Array[Dictionary] = NoiseManager.recent_noises_near(listener_pos, 220.0)
	_assert(not heard.is_empty(), "running noise must reach a listener that walking noise from the same spot would not")

	actor.queue_free()
	await get_tree().process_frame

func _test_detectable_search_and_salvage_emit_configured_noise() -> void:
	var parent := Node2D.new()
	add_child(parent)
	BuildingShellBuilder.add_loot_furniture(parent, Vector2(83000, 80000), null, Vector2(20, 20), &"test/detect_shelf", 60.0, {"food_ration": 1})
	BuildingShellBuilder.add_salvage_prop(parent, Vector2(83100, 80000), null, Vector2(20, 20), &"test/detect_wreck", 2)
	await get_tree().process_frame

	var loot_area: Area2D = null
	for child in (parent.get_child(0) as Node2D).get_children():
		if child is Area2D:
			loot_area = child
	var salvage_area: Area2D = null
	for child in (parent.get_child(1) as Node2D).get_children():
		if child is Area2D:
			salvage_area = child

	var actor: Player = PLAYER_SCENE.instantiate()
	add_child(actor)
	await get_tree().process_frame

	actor.global_position = Vector2(83000, 80000)
	(loot_area.get_node("InteractableComponent") as InteractableComponent).interact(actor)
	var search_noise: Array[Dictionary] = NoiseManager.recent_noises_near(actor.global_position, 220.0)
	_assert(not search_noise.is_empty() and search_noise[-1]["category"] == &"search", "searching a loot container must emit a 'search' noise")

	NoiseManager.reset()
	actor.global_position = Vector2(83100, 80000)
	(salvage_area.get_node("InteractableComponent") as InteractableComponent).interact(actor)
	var salvage_noise: Array[Dictionary] = NoiseManager.recent_noises_near(actor.global_position, 220.0)
	_assert(not salvage_noise.is_empty() and salvage_noise[-1]["category"] == &"salvage", "salvaging a prop must emit a 'salvage' noise")

	parent.free()
	actor.free()
	await get_tree().process_frame

## Proves indoor status is purely descriptive (DetectableComponent.is_indoors)
## and never grants automatic invisibility -- a closed door (a wall) blocks
## detection of the exact same indoor target that an open door reveals.
func _test_detectable_indoor_target_blocked_by_wall_and_visible_through_open_door() -> void:
	var door: Door = DOOR_SCENE.instantiate()
	add_child(door)
	door.global_position = Vector2(84000, 80050)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var target := _make_attackable_target(Vector2(84000, 80100))
	var detectable := _make_detectable(target)
	detectable.set_indoor_context(&"test_building", &"test_room")
	_assert(detectable.is_indoors, "sanity: the target reads as indoors")

	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(zombie)
	zombie.global_position = Vector2(84000, 80000)
	zombie.perception.facing = Vector2.DOWN

	zombie.perception._tick_perception()
	_assert(zombie.perception.state == ZombiePerceptionComponent.State.IDLE, "a closed door must block detection of an indoor target -- being indoors is never itself what hides it")

	door.toggle() # open it
	await get_tree().physics_frame
	zombie.perception._tick_perception()
	_assert(zombie.perception.state == ZombiePerceptionComponent.State.SUSPICIOUS, "the same indoor target, now visible through the open door, must become detectable")

	zombie.queue_free()
	target.queue_free()
	door.queue_free()
	await get_tree().process_frame

## --- Phase 3B.1: survivor navigation via UrbanNavigationService ---------

## A direct path blocked by a real wall must produce a routed path around
## it -- mirrors Zombie._seek_point()'s own contract, exercised here at
## Survivor.move_toward_point() (the single shared steering helper every
## UtilityAction already calls, so this covers all of them at once rather
## than needing a per-action test).
func _test_survivor_routes_around_wall_when_direct_path_blocked() -> void:
	UrbanNavigationService.build(Vector2(400, 400))
	await get_tree().physics_frame

	var settlement: Settlement = await _make_settlement(["general"])
	var survivor: Survivor = await _make_survivor({"name": "Router"}, settlement)
	survivor.global_position = Vector2(0, 0)

	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(200, 20)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector2(0, 100)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	UrbanNavigationService.build(Vector2(400, 400)) # rebuild AFTER the wall exists so the grid knows about it

	var target := Vector2(0, 200)
	survivor._nav_recheck_timer = 0.0 # force an immediate recheck instead of waiting out NAV_RECHECK_INTERVAL
	survivor.move_toward_point(target, 0.1)

	_assert(not survivor._nav_path.is_empty(), "a direct path blocked by a wall must produce a real routed path around it, not just stall on a blocked straight line")

	wall.queue_free()
	settlement.free()
	await get_tree().process_frame

## The mechanism Survivor's route-recheck depends on: a closed door blocks
## the direct line, and opening it restores that line -- proven through a
## real Door (not just direct grid manipulation), matching how
## DistrictBuilder wires door state into UrbanNavigationService in
## production.
func _test_survivor_route_updates_when_door_state_changes() -> void:
	UrbanNavigationService.build(Vector2(400, 400))
	await get_tree().physics_frame

	var door: Door = DOOR_SCENE.instantiate()
	door.door_id = &"test/survivor_nav_door"
	add_child(door)
	door.global_position = Vector2(0, 100)
	await get_tree().physics_frame
	await get_tree().physics_frame
	UrbanNavigationService.register_door(door.door_id, door.global_position)
	UrbanNavigationService.mark_door_closed(door.door_id)

	var target := Vector2(0, 200)
	_assert(not UrbanNavigationService.is_direct_path_clear(Vector2(0, 0), target), "sanity: the closed door must block the direct line to the target")

	door.toggle() # open it
	await get_tree().physics_frame
	_assert(UrbanNavigationService.is_direct_path_clear(Vector2(0, 0), target), "opening the door must restore the direct line")

	door.queue_free()
	await get_tree().process_frame

## A target so far away no reasonable route exists (grid unbuilt/no path)
## must never crash or produce NaN/Inf velocity -- move_toward_point's
## fallback (plain direct-line steering) always terminates safely.
func _test_survivor_move_toward_unreachable_point_terminates_safely() -> void:
	UrbanNavigationService.reset()
	var settlement: Settlement = await _make_settlement(["general"])
	var survivor: Survivor = await _make_survivor({"name": "Stuck"}, settlement)
	survivor.global_position = Vector2(0, 0)
	survivor._nav_recheck_timer = 0.0

	var arrived: bool = survivor.move_toward_point(Vector2(999999, 999999), 0.1)
	_assert(not arrived, "a very distant target should not report arrival in one tick")
	_assert(is_finite(survivor.velocity.x) and is_finite(survivor.velocity.y), "movement toward an unreachable/out-of-bounds target must never produce NaN/Inf velocity")

	settlement.free()
	await get_tree().process_frame

## Section 5 ("enters and leaves every authored building") + Section 6
## (DetectableComponent indoor context) together: a real Survivor
## physically entering/leaving a room updates its own DetectableComponent,
## the same mechanism already proven for the player.
func _test_survivor_entering_and_leaving_building_updates_detectable_context() -> void:
	var building: ConvenienceStore01 = CONVENIENCE_STORE_SCENE.instantiate()
	add_child(building)
	building.global_position = Vector2(90000, 90000)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var settlement: Settlement = await _make_settlement(["general"])
	var survivor: Survivor = await _make_survivor({"name": "Visitor"}, settlement)
	var retail_room: Room = building.get_node("Rooms/RetailFloor")
	survivor.global_position = retail_room.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	_assert(survivor.detectable.is_indoors, "a survivor physically inside a room must read as indoors via its DetectableComponent")
	_assert(survivor.detectable.current_room_id == &"retail_floor", "the survivor's DetectableComponent must record the correct current room")
	_assert(survivor.detectable.current_building_id == &"convenience_store_01", "the survivor's DetectableComponent must record the correct current building")

	survivor.global_position = Vector2(99000, 99000) # leave entirely
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	_assert(not survivor.detectable.is_indoors, "leaving every room must clear indoor status")

	settlement.free()
	building.queue_free()
	await get_tree().process_frame

## --- Phase 3B.1: bounded room-portal visibility --------------------------

func _find_first_static_body(node: Node) -> StaticBody2D:
	for child in node.get_children():
		if child is StaticBody2D:
			return child
		var nested: StaticBody2D = _find_first_static_body(child)
		if nested:
			return nested
	return null

## An open door's room only reveals if the player is actually facing
## toward it -- a door open behind the player's back must stay hidden.
func _test_building_portal_outside_view_cone_stays_hidden() -> void:
	var building: ConvenienceStore01 = CONVENIENCE_STORE_SCENE.instantiate()
	add_child(building)
	building.global_position = Vector2(91000, 91000)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var back_door: Door = building.get_node("Doors/BackRoomDoor")
	back_door.toggle() # open before the player enters

	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	var retail_room: Room = building.get_node("Rooms/RetailFloor")
	player.global_position = retail_room.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Set aim_direction as the LAST synchronous step, then force a recompute
	# directly -- no further physics frame may elapse first, since Player's
	# own _physics_process re-derives aim_direction from
	# InputRouter.aim_vector (a fixed, meaningless value in this headless
	# test context) every tick and would otherwise clobber this assignment.
	player.aim_direction = Vector2.UP # facing AWAY from the back door (which is south/down)
	building._apply_states()

	var back_room: Room = building.get_node("Rooms/BackRoom")
	_assert(back_room.modulate.a < 0.01, "an open door's room must stay hidden while the player is facing away from it")

	player.queue_free()
	building.queue_free()
	await get_tree().process_frame

## Toggling a door must recompute visibility synchronously, with the
## player never moving -- proves the event-driven Door.state_changed wiring,
## not just the room-enter/exit path.
func _test_building_portal_door_toggle_updates_reveal_immediately_while_stationary() -> void:
	var building: ConvenienceStore01 = CONVENIENCE_STORE_SCENE.instantiate()
	add_child(building)
	building.global_position = Vector2(92000, 92000)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	var retail_room: Room = building.get_node("Rooms/RetailFloor")
	player.global_position = retail_room.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var back_room: Room = building.get_node("Rooms/BackRoom")
	var back_door: Door = building.get_node("Doors/BackRoomDoor")
	_assert(back_room.modulate.a < 0.01, "sanity: closed door -- back room starts hidden")

	# Set aim_direction as the LAST synchronous step before toggling -- no
	# further physics frame may elapse in between, since Player's own
	# _physics_process re-derives aim_direction from InputRouter.aim_vector
	# each tick (a fixed, meaningless value in this headless test context)
	# and would otherwise clobber this assignment before it's ever read.
	player.aim_direction = Vector2.DOWN
	back_door.toggle() # open, WITHOUT the player moving or any frame elapsing
	_assert(back_room.modulate.a > 0.99, "opening a door must reveal its room immediately, even while the player is stationary (a=%f)" % back_room.modulate.a)

	player.aim_direction = Vector2.DOWN
	back_door.toggle() # close again
	_assert(back_room.modulate.a < 0.01, "closing a door must hide its room immediately, even while the player is stationary")

	player.queue_free()
	building.queue_free()
	await get_tree().process_frame

## Builds an isolated, furniture-free 3-room chain
## (room_a -door_ab- room_b -door_bc- room_c), fully wired and added to the
## tree at `origin`, for portal-depth tests. A synthetic fixture rather
## than a real building's hand-authored geometry -- deliberately so, since
## a real building's tightly-fit wall gaps and furniture placement made
## the exact raycast angles this test needs fragile to hand-tune; this
## isolates the portal-graph ALGORITHM itself from any one building's
## specific layout.
func _make_room_chain_fixture(origin: Vector2, id_prefix: String) -> Dictionary:
	var controller := BuildingVisibilityController.new()
	controller.building_id = StringName(id_prefix)
	controller.rooms_container_path = NodePath("Rooms")

	var rooms_container := Node2D.new()
	rooms_container.name = "Rooms"

	var room_a := Room.new()
	room_a.room_id = &"room_a"
	var shape_a := RectangleShape2D.new()
	shape_a.size = Vector2(80, 80)
	var collider_a := CollisionShape2D.new()
	collider_a.shape = shape_a
	room_a.add_child(collider_a)
	room_a.position = Vector2(-120, 0)

	var room_b := Room.new()
	room_b.room_id = &"room_b"
	var shape_b := RectangleShape2D.new()
	shape_b.size = Vector2(80, 80)
	var collider_b := CollisionShape2D.new()
	collider_b.shape = shape_b
	room_b.add_child(collider_b)
	room_b.position = Vector2(0, 0)

	var room_c := Room.new()
	room_c.room_id = &"room_c"
	var shape_c := RectangleShape2D.new()
	shape_c.size = Vector2(80, 80)
	var collider_c := CollisionShape2D.new()
	collider_c.shape = shape_c
	room_c.add_child(collider_c)
	room_c.position = Vector2(120, 0)

	rooms_container.add_child(room_a)
	rooms_container.add_child(room_b)
	rooms_container.add_child(room_c)
	controller.add_child(rooms_container)

	var door_ab: Door = DOOR_SCENE.instantiate()
	door_ab.door_id = StringName(id_prefix + "/door_ab")
	door_ab.position = Vector2(-60, 0)
	controller.add_child(door_ab)

	var door_bc: Door = DOOR_SCENE.instantiate()
	door_bc.door_id = StringName(id_prefix + "/door_bc")
	door_bc.position = Vector2(60, 0)
	controller.add_child(door_bc)

	add_child(controller)
	controller.global_position = origin
	room_a.doors = [door_ab]
	room_b.doors = [door_ab, door_bc]
	room_c.doors = [door_bc]

	return {
		"controller": controller,
		"room_a": room_a, "room_b": room_b, "room_c": room_c,
		"door_ab": door_ab, "door_bc": door_bc,
	}

## A room two portals away reveals only when BOTH hops are open and
## line-of-sight-clear -- the positive case for MAX_PORTAL_DEPTH = 2.
func _test_building_portal_reveals_two_hops_through_open_doors() -> void:
	var f := _make_room_chain_fixture(Vector2(98000, 98000), "test_chain_open")
	await get_tree().physics_frame
	await get_tree().physics_frame

	f["door_ab"].toggle()
	f["door_bc"].toggle()

	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = f["room_a"].global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	player.aim_direction = Vector2.RIGHT # straight down the a -> b -> c line
	f["controller"]._apply_states()

	_assert(f["room_b"].modulate.a > 0.99, "the middle room (depth 1, open door, inside the view cone) must be revealed")
	_assert(f["room_c"].modulate.a > 0.99, "the far room (depth 2, through a second open door) must also be revealed")

	player.queue_free()
	f["controller"].queue_free()
	await get_tree().process_frame

## The same two-hop room stays hidden if EITHER boundary along the chain
## is closed -- "room behind two opaque boundaries stays hidden" (closing
## the FIRST hop alone already blocks the whole chain, which is the
## correct/expected behavior, not a partial reveal).
func _test_building_portal_blocks_two_hop_room_when_either_door_closed() -> void:
	var f := _make_room_chain_fixture(Vector2(99000, 99000), "test_chain_closed")
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Both doors start closed -- left untouched.

	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = f["room_a"].global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	player.aim_direction = Vector2.RIGHT
	f["controller"]._apply_states()

	_assert(f["room_b"].modulate.a < 0.01, "a closed door at depth 1 must keep that room hidden")
	_assert(f["room_c"].modulate.a < 0.01, "a room only reachable behind a closed depth-1 door must stay hidden too, regardless of the depth-2 door's own state")

	player.queue_free()
	f["controller"].queue_free()
	await get_tree().process_frame

## An intact window is a portal too (visual reveal only) -- built from raw
## Room/BuildingWindow fixtures since none of the 5 authored buildings
## happen to have an interior-facing window; see
## building_visibility_controller.gd's own doc comment.
func _test_building_portal_intact_window_reveals_but_still_blocks_movement() -> void:
	var controller := BuildingVisibilityController.new()
	controller.building_id = &"test_synthetic_window"
	controller.rooms_container_path = NodePath("Rooms")

	var rooms_container := Node2D.new()
	rooms_container.name = "Rooms"
	var room_a := Room.new()
	room_a.room_id = &"room_a"
	var shape_a := RectangleShape2D.new()
	shape_a.size = Vector2(100, 100)
	var collider_a := CollisionShape2D.new()
	collider_a.shape = shape_a
	room_a.add_child(collider_a)
	room_a.position = Vector2(-60, 0)
	var room_b := Room.new()
	room_b.room_id = &"room_b"
	var shape_b := RectangleShape2D.new()
	shape_b.size = Vector2(100, 100)
	var collider_b := CollisionShape2D.new()
	collider_b.shape = shape_b
	room_b.add_child(collider_b)
	room_b.position = Vector2(60, 0)
	rooms_container.add_child(room_a)
	rooms_container.add_child(room_b)
	controller.add_child(rooms_container)

	var window: BuildingWindow = WINDOW_SCENE.instantiate()
	window.window_id = &"test/synthetic_window"
	window.is_boarded = false
	controller.add_child(window)

	add_child(controller)
	controller.global_position = Vector2(95000, 95000)
	await get_tree().physics_frame
	await get_tree().physics_frame
	room_a.windows = [window]
	room_b.windows = [window]

	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = room_a.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	player.aim_direction = Vector2.RIGHT # toward room_b/the window
	controller._apply_states()

	_assert(controller.current_room_id() == &"room_a", "sanity: the player is in room_a")
	_assert(room_b.modulate.a > 0.99, "an intact window connecting two rooms, inside the view cone with clear line of sight, must reveal the far room")

	var space_state := get_tree().root.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = window.global_position
	query.collision_mask = 1 # World
	query.collide_with_bodies = true
	_assert(not space_state.intersect_point(query, 1).is_empty(), "a window must still physically block movement even while permitting visual reveal")

	player.queue_free()
	controller.queue_free()
	await get_tree().process_frame

func _test_building_portal_boarded_window_blocks_reveal() -> void:
	var controller := BuildingVisibilityController.new()
	controller.building_id = &"test_synthetic_boarded_window"
	controller.rooms_container_path = NodePath("Rooms")

	var rooms_container := Node2D.new()
	rooms_container.name = "Rooms"
	var room_a := Room.new()
	room_a.room_id = &"room_a"
	var shape_a := RectangleShape2D.new()
	shape_a.size = Vector2(100, 100)
	var collider_a := CollisionShape2D.new()
	collider_a.shape = shape_a
	room_a.add_child(collider_a)
	room_a.position = Vector2(-60, 0)
	var room_b := Room.new()
	room_b.room_id = &"room_b"
	var shape_b := RectangleShape2D.new()
	shape_b.size = Vector2(100, 100)
	var collider_b := CollisionShape2D.new()
	collider_b.shape = shape_b
	room_b.add_child(collider_b)
	room_b.position = Vector2(60, 0)
	rooms_container.add_child(room_a)
	rooms_container.add_child(room_b)
	controller.add_child(rooms_container)

	var window: BuildingWindow = WINDOW_SCENE.instantiate()
	window.window_id = &"test/synthetic_boarded_window"
	window.is_boarded = true
	controller.add_child(window)

	add_child(controller)
	controller.global_position = Vector2(96000, 96000)
	await get_tree().physics_frame
	await get_tree().physics_frame
	room_a.windows = [window]
	room_b.windows = [window]

	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = room_a.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	player.aim_direction = Vector2.RIGHT # facing directly toward the (boarded) window/room_b
	controller._apply_states()

	_assert(room_b.modulate.a < 0.01, "a boarded window must never act as a reveal portal, even facing it directly")

	player.queue_free()
	controller.queue_free()
	await get_tree().process_frame

## BuildingVisibilityController must only ever touch modulate/.visible --
## a prop's own collision must be identical whether its room is currently
## revealed or hidden.
func _test_building_portal_visual_fade_never_changes_collision() -> void:
	var building: ConvenienceStore01 = CONVENIENCE_STORE_SCENE.instantiate()
	add_child(building)
	building.global_position = Vector2(97000, 97000)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var back_room: Room = building.get_node("Rooms/BackRoom")
	_assert(back_room.modulate.a < 0.01, "sanity: back_room starts hidden (outside, no player yet)")
	var fridge_body: StaticBody2D = _find_first_static_body(back_room)
	_assert(fridge_body != null, "sanity: found the back room's fridge collision body")
	var collider: CollisionShape2D = null
	for child in fridge_body.get_children():
		if child is CollisionShape2D:
			collider = child
	_assert(collider != null, "sanity: found the fridge body's collision shape")
	_assert(not collider.disabled, "a prop's collision must never be disabled while its room is hidden")

	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	var retail_room: Room = building.get_node("Rooms/RetailFloor")
	player.global_position = retail_room.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	_assert(not collider.disabled, "the same prop's collision must remain unchanged after the player entered and the building's overall reveal state changed")

	player.queue_free()
	building.queue_free()
	await get_tree().process_frame

## --- Phase 3B: fixed district, buildings, interaction, perception ---------

## A Node2D fixture standing in for a survivor/player as a raw perception
## target -- only needs global_position and "attackable" group membership,
## since ZombiePerceptionComponent never calls anything on the candidate
## itself.
func _make_attackable_target(pos: Vector2) -> Node2D:
	var target := Node2D.new()
	add_child(target)
	target.global_position = pos
	target.add_to_group("attackable")
	return target

func _make_vision_wall(local_position: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1 | 32 # World | Vision
	wall.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(64, 8)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	wall.add_child(collider)
	wall.position = local_position
	add_child(wall)
	return wall

## The committed baseline is DistrictLayoutChecksum.compute() as of this
## commit -- an unintentional edit to ROADS/BUILDING_POSITIONS/
## SHELL_BUILDINGS/SPAWN_REGIONS/SCAVENGE_POINTS changes this hash, which is
## exactly the "detect accidental drift" contract Section 1 asks for. A
## deliberate map change should update this literal alongside the edit.
func _test_district_layout_checksum_matches_committed_baseline() -> void:
	var checksum: String = DistrictLayoutChecksum.compute()
	_assert(checksum == "6166fdb924030593248c418cc6c39e7eb51176777cc9d470cbd1d0ddb71aa389", "the fixed district's layout checksum drifted from the committed baseline (got %s) -- update the baseline deliberately if this was an intentional map change" % checksum)
	_assert(DistrictLayoutChecksum.compute() == checksum, "compute() must be perfectly deterministic across repeated calls")

## Section 1 ("the fixed-layout checksum must validate the baked scene
## content rather than only hashing constants in a script"): loads and
## instantiates the ACTUAL baked UrbanDistrict01.tscn and validates its
## real node structure directly -- complementing (not replacing) the
## constants-based checksum above, which still guards
## district_builder.gd's own authored source data (the bake tool's own
## input). A bake that silently dropped a building, door, or spawn region
## would fail here even if the source constants were untouched, and this
## is also what proves the SHIPPED scene runs the lightweight
## AuthoredDistrict glue script, not the heavy procedural DistrictBuilder.
func _test_baked_district_scene_has_expected_structure() -> void:
	var district_scene: PackedScene = load("res://scenes/world/maps/UrbanDistrict01.tscn")
	var district: Node2D = district_scene.instantiate()
	add_child(district)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_assert(district is AuthoredDistrict, "the shipped district scene must run the lightweight AuthoredDistrict glue script, not DistrictBuilder, at runtime")

	# get_node_or_null (not $-style get_node) deliberately here: a missing
	# container must fail this test loudly via _assert, not abort the whole
	# test function silently -- calling a method on a null get_node() result
	# raises a script error that aborts fn.call() without setting
	# _test_failed, which once let a badly-baked scene missing every
	# top-level container still print PASS.
	var buildings: Node = district.get_node_or_null("Buildings")
	_assert(buildings != null, "the baked scene must contain a top-level Buildings container")
	if buildings != null:
		var building_ids: Array = []
		for child in buildings.get_children():
			if "building_id" in child:
				building_ids.append(child.building_id)
		for expected_id in [&"restaurant_01", &"convenience_store_01", &"clinic_01", &"apartment_01", &"workshop_01"]:
			_assert(building_ids.has(expected_id), "the baked scene must contain a real, enterable %s building instance" % expected_id)

	var doors: Array = []
	for node in get_tree().get_nodes_in_group("doors"):
		if district.is_ancestor_of(node):
			doors.append(node)
	_assert(doors.size() == 19, "the baked scene must contain exactly the 19 authored doors across all 5 buildings (got %d)" % doors.size())

	var spawn_regions: Array = []
	for node in get_tree().get_nodes_in_group("spawn_regions"):
		if district.is_ancestor_of(node):
			spawn_regions.append(node)
	_assert(spawn_regions.size() == 7, "the baked scene must contain exactly the 7 authored spawn regions (got %d)" % spawn_regions.size())

	# DynamicEntities holds every prop that needs Y-sorting against actors at
	# runtime, not just ScavengePoint instances -- it also carries the
	# abandoned/wrecked cars and the alley dumpster (see
	# district_builder.gd's _build_street_props(), which places those
	# specific props via the same "entity_container" group lookup as
	# _build_scavenge_points()). Checking the "scavenge_point" group
	# directly is what actually pins down "exactly 5 scavenge points",
	# independent of that container also holding other entities.
	var dynamic_entities: Node = district.get_node_or_null("DynamicEntities")
	_assert(dynamic_entities != null, "the baked scene must contain a top-level DynamicEntities container")
	if dynamic_entities != null:
		var scavenge_points: Array = []
		for node in get_tree().get_nodes_in_group("scavenge_point"):
			if dynamic_entities.is_ancestor_of(node):
				scavenge_points.append(node)
		_assert(scavenge_points.size() == 5, "the baked scene must contain exactly the 5 authored scavenge points (got %d)" % scavenge_points.size())
		_assert(dynamic_entities.get_child_count() == 8, "the baked scene's DynamicEntities container must hold exactly the 5 scavenge points plus the 3 Y-sorted street props (car_1, car_wreck_1, dumpster_alley) (got %d)" % dynamic_entities.get_child_count())

	var ground: TileMapLayer = district.get_node_or_null("GroundLayers/Ground")
	_assert(ground != null, "the baked scene must contain a GroundLayers/Ground TileMapLayer")
	if ground != null:
		_assert(ground.get_used_cells().size() > 0, "the baked Ground TileMapLayer must carry real painted cell data, not an empty layer")

	district.queue_free()
	await get_tree().process_frame

## A closed door's own CollisionShape2D must block a straight World|Vision
## raycast through it (movement AND vision, the same shape for both);
## opening it must let the same raycast straight through.
func _test_door_closed_blocks_and_open_permits_movement_and_vision() -> void:
	var door: Door = DOOR_SCENE.instantiate()
	add_child(door)
	door.global_position = Vector2(500, 500)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space_state := get_tree().root.get_world_2d().direct_space_state
	var from: Vector2 = door.global_position + Vector2(-40, 0)
	var to: Vector2 = door.global_position + Vector2(40, 0)
	var query := PhysicsRayQueryParameters2D.create(from, to, 1 | 32) # World | Vision

	var hit_closed: Dictionary = space_state.intersect_ray(query)
	_assert(not hit_closed.is_empty(), "a closed door must block a World|Vision raycast straight through it")

	door.toggle()
	await get_tree().physics_frame
	var hit_open: Dictionary = space_state.intersect_ray(query)
	_assert(hit_open.is_empty(), "an open door must let a World|Vision raycast pass straight through")

	door.queue_free()
	await get_tree().process_frame

## A single interact() call must toggle a door exactly once, and its state
## must persist to WorldState under its stable door_id so a fresh Door
## instance sharing that id reads the same state back on _ready().
func _test_door_interact_toggles_exactly_once_and_persists() -> void:
	var door: Door = DOOR_SCENE.instantiate()
	door.door_id = &"test/door_persist"
	add_child(door)
	# An explicit, isolated position (not the default origin) plus a real
	# physics frame -- other tests' fixtures also default to/pass through
	# world origin, and Area2D body_entered/exited signals need at least
	# one physics step to fully settle after add_child(); without both,
	# this test has occasionally picked up a stray _blocked_by_body=true
	# from unrelated leftover physics state.
	door.global_position = Vector2(600, 600)
	await get_tree().physics_frame
	await get_tree().process_frame
	_assert(not door.is_open, "sanity: a fresh door starts closed")

	var interactable: InteractableComponent = door.get_node("InteractReachArea/InteractableComponent")
	var actor := Node.new()
	interactable.interact(actor)
	_assert(door.is_open, "a single interact() call must open a closed door")
	_assert(WorldState.get_door_open(&"test/door_persist"), "the open state must be persisted to WorldState under the door's stable id")

	interactable.interact(actor)
	_assert(not door.is_open, "a second interact() call toggles it closed again -- one call, one toggle")

	door.queue_free()
	actor.free()
	await get_tree().process_frame

	var door_b: Door = DOOR_SCENE.instantiate()
	door_b.door_id = &"test/door_persist"
	add_child(door_b)
	await get_tree().process_frame
	_assert(not door_b.is_open, "a fresh Door instance sharing the same door_id must read its persisted (closed) state from WorldState on _ready(), not default open")

	door_b.queue_free()
	await get_tree().process_frame

## An open door must refuse to close while an actor physically occupies its
## footprint, and succeed normally once that actor clears it. (Regression
## test for an inverted guard: toggle() previously refused to OPEN a closed
## door instead of refusing to CLOSE an open one on top of an actor.)
func _test_door_refuses_to_close_on_blocking_body() -> void:
	var door: Door = DOOR_SCENE.instantiate()
	add_child(door)
	await get_tree().process_frame

	door.toggle() # open it first
	_assert(door.is_open, "sanity: door is open")

	var fake_body := Node.new()
	door._on_body_entered(fake_body) # simulate an actor standing in the doorway
	door.toggle() # attempt to close on top of the actor
	_assert(door.is_open, "a door must refuse to close while an actor is standing in its footprint")

	door._on_body_exited(fake_body)
	door.toggle()
	_assert(not door.is_open, "once the actor clears the doorway, closing must succeed normally")

	door.queue_free()
	fake_body.free()
	await get_tree().process_frame

## A window always blocks movement regardless of state; vision blocking is
## authored per-instance (intact lets sight through, boarded doesn't).
func _test_window_state_controls_vision_blocking_but_always_blocks_movement() -> void:
	var intact: BuildingWindow = WINDOW_SCENE.instantiate()
	intact.is_boarded = false
	add_child(intact)
	await get_tree().process_frame
	_assert(not intact.blocks_vision(), "an intact window must not block vision")
	_assert(intact._collision_body.collision_layer & 1 != 0, "a window must always be physically solid (blocks movement) regardless of boarded state")
	_assert(intact._collision_body.collision_layer & 32 == 0, "an intact window must not carry the Vision-blocking layer")

	var boarded: BuildingWindow = WINDOW_SCENE.instantiate()
	boarded.is_boarded = true
	add_child(boarded)
	await get_tree().process_frame
	_assert(boarded.blocks_vision(), "a boarded window must block vision")
	_assert(boarded._collision_body.collision_layer & 1 != 0, "a boarded window must still be physically solid")
	_assert(boarded._collision_body.collision_layer & 32 != 0, "a boarded window must carry the Vision-blocking layer")

	intact.queue_free()
	boarded.queue_free()
	await get_tree().process_frame

## Searching a loot container must transfer its exact declared contents to
## the actor's carried inventory, and a second search of the now-depleted
## container must add nothing more (no duplication).
func _test_loot_container_search_transfers_exact_and_prevents_duplication() -> void:
	var parent := Node2D.new()
	add_child(parent)
	BuildingShellBuilder.add_loot_furniture(parent, Vector2.ZERO, null, Vector2(20, 20), &"test/shelf_1", 60.0, {"food_ration": 3, "materials": 2})
	await get_tree().process_frame

	var prop_root: Node2D = parent.get_child(0)
	var area: Area2D = null
	for child in prop_root.get_children():
		if child is Area2D:
			area = child
	var interactable: InteractableComponent = area.get_node("InteractableComponent")
	var loot: LootContainerComponent = area.get_node("LootContainerComponent")

	var actor: Player = PLAYER_SCENE.instantiate()
	add_child(actor)
	await get_tree().process_frame

	interactable.interact(actor)
	_assert(actor.carried_inventory.get_count(&"food_ration") == 3, "a search must transfer the container's exact declared food_ration count")
	_assert(actor.carried_inventory.get_count(&"materials") == 2, "a search must transfer the container's exact declared materials count")
	_assert(loot.get_inventory().is_empty(), "the container must be empty after a full search")

	interactable.interact(actor)
	_assert(actor.carried_inventory.get_count(&"food_ration") == 3, "searching an already-depleted container a second time must not duplicate loot")
	_assert(actor.carried_inventory.get_count(&"materials") == 2, "searching an already-depleted container a second time must not duplicate loot")

	parent.free()
	actor.free()
	await get_tree().process_frame

## Salvaging a prop must add exactly material_yield materials once, persist
## the salvaged flag under its stable prop_id, and disable its own
## InteractableComponent so it can never be salvaged a second time.
func _test_salvage_component_prevents_duplicate_salvage() -> void:
	var parent := Node2D.new()
	add_child(parent)
	BuildingShellBuilder.add_salvage_prop(parent, Vector2.ZERO, null, Vector2(20, 20), &"test/wreck_1", 4)
	await get_tree().process_frame

	var prop_root: Node2D = parent.get_child(0)
	var area: Area2D = null
	for child in prop_root.get_children():
		if child is Area2D:
			area = child
	var interactable: InteractableComponent = area.get_node("InteractableComponent")

	var actor: Player = PLAYER_SCENE.instantiate()
	add_child(actor)
	await get_tree().process_frame
	var before: int = actor.carried_inventory.get_count(&"materials")

	_assert(interactable.can_interact(actor), "sanity: a fresh salvage prop starts interactable")
	interactable.interact(actor)
	_assert(actor.carried_inventory.get_count(&"materials") == before + 4, "a single salvage must add exactly material_yield materials")
	_assert(WorldState.get_prop_state_flag(&"test/wreck_1", &"remaining_yield", -1) == 0, "remaining_yield must persist in WorldState under the prop's stable id, reaching exactly zero after a full-capacity salvage")
	_assert(not interactable.can_interact(actor), "the InteractableComponent must disable itself once remaining_yield reaches zero -- PlayerInteractor will never offer it again")

	parent.free()
	actor.free()
	await get_tree().process_frame

## get_or_create_prop_container() must return the SAME Inventory instance
## across repeated calls for one prop_id, ignoring initial_items after the
## first registration -- the mechanism that makes depletion survive being
## re-queried instead of respawning fresh stock.
func _test_persistent_prop_container_same_instance_across_calls() -> void:
	var inv_a: Inventory = WorldState.get_or_create_prop_container(&"test/shelf_x", 50.0, {"food_ration": 5})
	_assert(inv_a.get_count(&"food_ration") == 5, "first access should seed from starting_items")

	var inv_b: Inventory = WorldState.get_or_create_prop_container(&"test/shelf_x", 50.0, {"water_bottle": 99})
	_assert(inv_b == inv_a, "repeated calls for the same prop_id must return the SAME Inventory instance")
	_assert(inv_b.get_count(&"food_ration") == 5, "a second call must not reset an already-registered container")
	_assert(inv_b.get_count(&"water_bottle") == 0, "initial_items on a second call for an already-registered id must be ignored entirely")

## WorldState.reset() must clear all three Phase 3B persistent-state
## dictionaries, restoring a clean new-game state.
func _test_world_state_reset_clears_phase_3b_state() -> void:
	WorldState.set_door_open(&"test/door_x", true)
	WorldState.set_prop_state_flag(&"test/prop_x", &"salvaged", true)
	WorldState.get_or_create_prop_container(&"test/container_x", 10.0, {"materials": 1})
	_assert(WorldState.door_states.size() == 1 and WorldState.prop_states.size() == 1 and WorldState.prop_containers.size() == 1, "sanity: all three Phase 3B dictionaries are populated")

	WorldState.reset()

	_assert(WorldState.door_states.is_empty(), "reset() must clear door_states")
	_assert(WorldState.prop_states.is_empty(), "reset() must clear prop_states")
	_assert(WorldState.prop_containers.is_empty(), "reset() must clear prop_containers")
	_assert(not WorldState.get_door_open(&"test/door_x"), "a reset world must report any door as closed by default again")

## Outside: roof visible, no current room. Entering a room hides the roof,
## reports the correct current room, and keeps an adjacent room behind a
## CLOSED door fully hidden. Leaving the building entirely restores the
## roof and clears the current room.
func _test_building_roof_hides_and_room_reveals_on_enter_restores_on_exit() -> void:
	var building: ConvenienceStore01 = CONVENIENCE_STORE_SCENE.instantiate()
	add_child(building)
	building.global_position = Vector2(2000, 2000)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_assert(building.is_roof_visible(), "the roof must be visible while nobody is inside")

	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	var retail_room: Room = building.get_node("Rooms/RetailFloor")
	player.global_position = retail_room.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	_assert(not building.is_roof_visible(), "the roof must hide once the player is inside")
	_assert(building.current_room_id() == &"retail_floor", "the player's current room must be reported correctly")
	var back_room: Room = building.get_node("Rooms/BackRoom")
	_assert(back_room.modulate.a < 0.01, "an adjacent room behind a CLOSED door must stay fully hidden, not merely dimmed")

	player.global_position = Vector2(9000, 9000) # walk far outside the building entirely
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	_assert(building.is_roof_visible(), "the roof must restore once the player fully leaves the building")
	_assert(building.current_room_id() == &"", "no current room once outside")

	player.queue_free()
	building.queue_free()
	await get_tree().process_frame

## A room sharing a currently-OPEN door with the player's current room must
## be revealed too (the simplified subset of the full portal-graph reveal --
## see docs/building_system.md).
func _test_building_adjacent_room_reveals_through_open_door() -> void:
	var building: ConvenienceStore01 = CONVENIENCE_STORE_SCENE.instantiate()
	add_child(building)
	building.global_position = Vector2(2000, 2000)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var back_door: Door = building.get_node("Doors/BackRoomDoor")
	back_door.toggle() # open before the player ever enters -- reveal state is only recomputed on room-enter/exit
	_assert(back_door.is_open, "sanity: the back room door is now open")

	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	var retail_room: Room = building.get_node("Rooms/RetailFloor")
	player.global_position = retail_room.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Set aim_direction as the LAST synchronous step, then force a recompute
	# directly -- Player's own _physics_process re-derives aim_direction
	# from InputRouter.aim_vector (a fixed, meaningless value in this
	# headless test context) every tick and would otherwise clobber this
	# assignment before the controller ever reads it.
	player.aim_direction = Vector2.DOWN # facing toward the back door -- the portal graph only reveals through a portal inside the player's view cone
	building._apply_states()

	_assert(building.current_room_id() == &"retail_floor", "sanity: the player is in the retail floor")
	var back_room: Room = building.get_node("Rooms/BackRoom")
	_assert(back_room.modulate.a > 0.99, "an adjacent room sharing a currently-OPEN door, inside the player's view cone and with a clear line of sight to it, must be revealed")

	player.queue_free()
	building.queue_free()
	await get_tree().process_frame

## A visible target within vision distance and view cone must first raise
## suspicion (not jump straight to CHASE), then promote to CHASE once
## suspicion crosses the threshold across a second sighting.
func _test_zombie_perception_detects_and_chases_visible_target() -> void:
	# NOTE: several PRE-EXISTING tests above (via _make_survivor()) add a real
	# Survivor to the tree and never free it -- Survivor joins the
	# "attackable" group, so by the time these tests run, the scene may hold
	# several leaked survivors clustered near world origin. Every fixture
	# below is placed far away (the 50000,50000 region) so
	# ZombiePerceptionComponent's group-wide "attackable" scan can never
	# accidentally pick up a leftover survivor from an unrelated earlier test.
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(zombie)
	zombie.global_position = Vector2(50000, 50000)
	zombie.perception.facing = Vector2.DOWN
	var target := _make_attackable_target(Vector2(50000, 50100)) # ahead, within vision_distance, outside attack_range

	zombie.perception._tick_perception()
	_assert(zombie.perception.state == ZombiePerceptionComponent.State.SUSPICIOUS, "first sighting should only raise suspicion, not jump straight to CHASE")
	_assert(zombie.perception.target == target, "the visible candidate must become the current target even while still building suspicion")

	zombie.perception._tick_perception()
	_assert(zombie.perception.state == ZombiePerceptionComponent.State.CHASE, "suspicion crossing the threshold on a second sighting must promote to CHASE")
	_assert(zombie.perception.has_target(), "has_target() must be true in CHASE")

	zombie.queue_free()
	target.queue_free()
	await get_tree().process_frame

func _test_zombie_perception_ignores_target_outside_vision_distance() -> void:
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(zombie)
	zombie.global_position = Vector2(50000, 50000)
	zombie.perception.facing = Vector2.DOWN
	var target := _make_attackable_target(Vector2(50000, 50000 + zombie.perception.vision_distance + 50.0))

	zombie.perception._tick_perception()
	_assert(zombie.perception.state == ZombiePerceptionComponent.State.IDLE, "a target beyond vision_distance must never be detected")
	_assert(not zombie.perception.has_target(), "has_target() must be false")

	zombie.queue_free()
	target.queue_free()
	await get_tree().process_frame

func _test_zombie_perception_ignores_target_outside_view_cone() -> void:
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(zombie)
	zombie.global_position = Vector2(50000, 50000)
	zombie.perception.facing = Vector2.DOWN # looking toward +Y
	var target := _make_attackable_target(Vector2(50000, 49900)) # directly behind, well within vision distance

	zombie.perception._tick_perception()
	_assert(zombie.perception.state == ZombiePerceptionComponent.State.IDLE, "a target directly behind the zombie's facing must fall outside its view cone and never be detected")

	zombie.queue_free()
	target.queue_free()
	await get_tree().process_frame

func _test_zombie_perception_blocked_by_wall() -> void:
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(zombie)
	zombie.global_position = Vector2(50000, 50000)
	zombie.perception.facing = Vector2.DOWN
	var target := _make_attackable_target(Vector2(50000, 50100))
	var wall := _make_vision_wall(Vector2(50000, 50050)) # directly between zombie and target
	await get_tree().physics_frame
	await get_tree().physics_frame

	zombie.perception._tick_perception()
	_assert(zombie.perception.state == ZombiePerceptionComponent.State.IDLE, "a wall directly between the zombie and an otherwise-visible target must block detection")

	zombie.queue_free()
	target.queue_free()
	wall.queue_free()
	await get_tree().process_frame

## A nearby noise must promote an idle zombie straight to INVESTIGATE
## without ever seeing anything, recording the noise's position as its
## last-known-position lead.
func _test_zombie_perception_hearing_triggers_investigate() -> void:
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(zombie)
	zombie.global_position = Vector2(50000, 50000)
	NoiseManager.emit_noise(Vector2(50050, 50000), 10.0, &"gunshot") # effective radius 200, well within hearing_radius(220)

	zombie.perception._tick_perception() # no visible candidate -> falls through to hearing
	_assert(zombie.perception.state == ZombiePerceptionComponent.State.INVESTIGATE, "a nearby loud noise must promote an idle zombie straight to INVESTIGATE")
	_assert(zombie.perception.last_known_position.distance_to(Vector2(50050, 50000)) < 0.01, "last_known_position must be set to the noise's location")

	zombie.queue_free()
	await get_tree().process_frame

## SEARCH must time out to RETURN_TO_IDLE once search_duration elapses,
## clearing the stale target -- losing a target is never permanent tracking.
func _test_zombie_perception_search_expires_to_return_to_idle() -> void:
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(zombie)
	zombie.global_position = Vector2(50000, 50000) # isolated from any leaked "attackable" nodes -- see note above
	zombie.perception._enter_state(ZombiePerceptionComponent.State.SEARCH)
	_assert(zombie.perception.state == ZombiePerceptionComponent.State.SEARCH, "sanity: entered SEARCH")

	zombie.perception.update(zombie.perception.search_duration + 0.1, Vector2.ZERO)
	_assert(zombie.perception.state == ZombiePerceptionComponent.State.RETURN_TO_IDLE, "SEARCH must time out to RETURN_TO_IDLE once search_duration elapses")
	_assert(zombie.perception.target == null, "RETURN_TO_IDLE must clear the stale target")
	_assert(not zombie.perception.has_target(), "has_target() must be false once returned to idle")

	zombie.queue_free()
	await get_tree().process_frame

func _test_urban_navigation_service_door_toggling_changes_cell_solidity() -> void:
	UrbanNavigationService.build(Vector2(64, 64))
	await get_tree().physics_frame
	var door_pos := Vector2(0, 0)
	UrbanNavigationService.register_door(&"test/nav_door", door_pos)
	var cell: Vector2i = UrbanNavigationService.world_to_cell(door_pos)

	UrbanNavigationService.mark_door_closed(&"test/nav_door")
	_assert(UrbanNavigationService._grid.is_point_solid(cell), "mark_door_closed must make the door's own cell solid")

	UrbanNavigationService.mark_door_open(&"test/nav_door")
	_assert(not UrbanNavigationService._grid.is_point_solid(cell), "mark_door_open must make the door's own cell passable again")

## find_path() must refuse (return an empty path) once the per-frame request
## budget is exhausted, so a burst of simultaneous requests can never spike
## one frame's cost -- never a silent unbounded queue.
func _test_urban_navigation_service_find_path_respects_frame_budget() -> void:
	UrbanNavigationService.build(Vector2(320, 320))
	await get_tree().physics_frame
	var from := Vector2(-100, -100)
	var to := Vector2(100, 100)
	var successes: int = 0
	for i in range(UrbanNavigationService.MAX_REQUESTS_PER_FRAME + 3):
		var path: PackedVector2Array = UrbanNavigationService.find_path(from, to)
		if not path.is_empty():
			successes += 1
	_assert(successes == UrbanNavigationService.MAX_REQUESTS_PER_FRAME, "find_path must serve at most MAX_REQUESTS_PER_FRAME paths in one frame, refusing the rest")
	_assert(UrbanNavigationService.requests_this_frame() == UrbanNavigationService.MAX_REQUESTS_PER_FRAME, "requests_this_frame must reflect exactly the capped count, not the raw call count")

func _test_spawn_region_random_point_within_radius() -> void:
	var region := SpawnRegion.new()
	region.region_id = &"test_region"
	region.radius = 120.0
	add_child(region)
	region.global_position = Vector2(300, -300)
	await get_tree().process_frame

	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for i in range(25):
		var point: Vector2 = region.random_point(rng)
		_assert(point.distance_to(region.global_position) <= region.radius + 0.01, "random_point() must always land within the region's own radius (iteration %d)" % i)

	region.queue_free()
	await get_tree().process_frame

## A survivor's local threat sensor must ignore a zombie beyond the
## emergency safety radius when a wall blocks line of sight (a threat it
## couldn't reasonably know about), but always count a zombie within the
## close-range safety margin regardless of walls (point-blank threats are
## never filtered out).
func _test_survivor_ignores_zombie_behind_wall_unless_within_emergency_radius() -> void:
	var settlement: Settlement = await _make_settlement(["general"])
	var survivor: Survivor = await _make_survivor({"name": "Wary"}, settlement)
	survivor.global_position = Vector2(0, 0)

	var far_zombie: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(far_zombie)
	far_zombie.global_position = Vector2(0, 250) # beyond emergency_zombie_radius(160), within perception_radius(420)

	var close_zombie: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(close_zombie)
	close_zombie.global_position = Vector2(0, 100) # within emergency_zombie_radius(160)

	var wall := _make_vision_wall(Vector2(0, 50)) # between the survivor and both zombies
	await get_tree().physics_frame
	await get_tree().physics_frame

	survivor.ai._refresh_perception()
	_assert(not survivor.ai.nearby_zombies.has(far_zombie), "a zombie beyond the emergency radius and behind a wall must not read as a locally perceived threat")
	_assert(survivor.ai.nearby_zombies.has(close_zombie), "a zombie within the emergency safety-margin radius must always count as a threat, wall or not")

	far_zombie.queue_free()
	close_zombie.queue_free()
	wall.queue_free()
	settlement.free()
	await get_tree().process_frame

## --- Phase 3B.2: movement noise, navigation hardening, interaction conservation ---

## Even with a large delta and several ticks, a stationary actor's
## DetectableComponent._physics_process must never emit a footstep event --
## calling it directly (like other tests call private per-frame hooks
## directly, e.g. ZombiePerceptionComponent._tick_perception()) for
## deterministic timing instead of waiting out real seconds.
func _test_detectable_stationary_emits_no_movement_noise() -> void:
	var actor := Node2D.new()
	add_child(actor)
	actor.global_position = Vector2(84000, 80000)
	var detectable := _make_detectable(actor)
	detectable.report_movement_speed(0.0)
	for i in range(5):
		detectable._physics_process(0.5)
	var heard: Array[Dictionary] = NoiseManager.recent_noises_near(actor.global_position, 999999.0, 999999)
	_assert(heard.is_empty(), "a stationary actor must never emit a movement/footstep noise event")
	actor.queue_free()
	await get_tree().process_frame

## Walking must emit bounded, interval-gated events -- roughly one per
## walking_step_interval, never one per physics frame (which at 60Hz over
## 2 simulated seconds would be ~120 events, not ~4).
func _test_detectable_walking_emits_bounded_footstep_events() -> void:
	var actor := Node2D.new()
	add_child(actor)
	actor.global_position = Vector2(84100, 80000)
	var detectable := _make_detectable(actor)
	detectable.walking_step_interval = 0.5
	detectable.report_movement_speed(50.0) # walking (below running_speed_threshold)
	var elapsed: float = 0.0
	while elapsed < 2.0:
		detectable._physics_process(1.0 / 60.0)
		elapsed += 1.0 / 60.0
	var events: Array[Dictionary] = NoiseManager.recent_noises_near(actor.global_position, 999999.0, 999999)
	_assert(events.size() >= 3 and events.size() <= 6, "walking for 2s at a 0.5s step interval should emit roughly 4 bounded events, not one per physics frame (got %d)" % events.size())
	for e in events:
		_assert(e["loudness"] <= detectable.walking_noise, "walking footstep loudness must not exceed the configured walking_noise")
	actor.queue_free()
	await get_tree().process_frame

## Running must be both louder (per-event loudness) AND more frequent
## (shorter step interval) than walking over the same simulated duration.
func _test_detectable_running_emits_louder_and_more_frequent_events() -> void:
	var walker := Node2D.new()
	add_child(walker)
	walker.global_position = Vector2(84300, 80000)
	var walk_detectable := _make_detectable(walker)
	walk_detectable.report_movement_speed(50.0)
	var elapsed: float = 0.0
	while elapsed < 1.2:
		walk_detectable._physics_process(1.0 / 60.0)
		elapsed += 1.0 / 60.0
	var walk_count: int = NoiseManager.recent_noises_near(walker.global_position, 999999.0, 999999).size()

	NoiseManager.reset()
	var runner := Node2D.new()
	add_child(runner)
	runner.global_position = Vector2(84400, 80000)
	var run_detectable := _make_detectable(runner)
	run_detectable.report_movement_speed(200.0) # running
	elapsed = 0.0
	while elapsed < 1.2:
		run_detectable._physics_process(1.0 / 60.0)
		elapsed += 1.0 / 60.0
	var run_events: Array[Dictionary] = NoiseManager.recent_noises_near(runner.global_position, 999999.0, 999999)
	_assert(run_events.size() > walk_count, "running for the same duration must produce more footstep events than walking, since its step interval is shorter (got %d running vs %d walking)" % [run_events.size(), walk_count])
	for e in run_events:
		_assert(e["loudness"] >= run_detectable.walking_noise, "running footstep loudness must be at least as loud as walking's")

	walker.queue_free()
	runner.queue_free()
	await get_tree().process_frame

## A zombie with no visible candidate (an isolated Node2D + DetectableComponent
## is not in the "attackable" group, so vision never fires here) must still
## hear a nearby actor's automatic running footstep noise and investigate.
func _test_nearby_zombie_hears_running_movement_noise() -> void:
	var actor := Node2D.new()
	add_child(actor)
	actor.global_position = Vector2(85000, 80000)
	var detectable := _make_detectable(actor)
	detectable.report_movement_speed(200.0) # running
	detectable._physics_process(1.0) # timer starts at 0 -- always emits on the first tick

	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(zombie)
	zombie.global_position = Vector2(85060, 80000) # 60 units -- within running's ~120 effective radius
	zombie.perception._tick_perception()
	_assert(zombie.perception.state == ZombiePerceptionComponent.State.INVESTIGATE, "a nearby zombie must hear a running actor's automatic footstep noise and investigate")

	zombie.queue_free()
	actor.queue_free()
	await get_tree().process_frame

## The same automatic emission, but walking and far enough away that its
## much smaller effective hearing radius (~40 units) doesn't reach.
func _test_distant_zombie_does_not_hear_walking_movement_noise() -> void:
	var actor := Node2D.new()
	add_child(actor)
	actor.global_position = Vector2(86000, 80000)
	var detectable := _make_detectable(actor)
	detectable.report_movement_speed(50.0) # walking
	detectable._physics_process(1.0)

	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(zombie)
	zombie.global_position = Vector2(86300, 80000) # 300 units -- well beyond walking's ~40 effective radius
	zombie.perception._tick_perception()
	_assert(zombie.perception.state != ZombiePerceptionComponent.State.INVESTIGATE, "a distant zombie must not hear a walking actor's quiet footstep noise")

	zombie.queue_free()
	actor.queue_free()
	await get_tree().process_frame

## Event COUNT stays bounded over a longer simulated walk/run mix -- proof
## against a regression back to "emit every physics frame," which would
## otherwise flood NoiseManager's fixed-size ring buffer (MAX_RECENT=32)
## with near-duplicate events every single test that involves movement.
func _test_detectable_event_count_remains_bounded_over_time() -> void:
	var actor := Node2D.new()
	add_child(actor)
	actor.global_position = Vector2(84500, 80000)
	var detectable := _make_detectable(actor)
	detectable.report_movement_speed(200.0) # running -- the more frequent case
	var elapsed: float = 0.0
	while elapsed < 5.0: # 5 simulated seconds
		detectable._physics_process(1.0 / 60.0)
		elapsed += 1.0 / 60.0
	var events: Array[Dictionary] = NoiseManager.recent_noises_near(actor.global_position, 999999.0, 999999)
	# At a 60Hz tick rate, 5s is 300 physics frames -- bounded emission
	# must produce far fewer events than that (running_step_interval=0.3s
	# implies ~16-17), never anywhere close to one-per-frame.
	_assert(events.size() < 30, "5 seconds of continuous running must not emit anywhere near one event per physics frame (got %d)" % events.size())
	actor.queue_free()
	await get_tree().process_frame

## concealment_modifier subtracts from effective loudness before it becomes
## a hearing radius -- a listener that could hear the same movement without
## concealment must not hear it once concealment reduces the effective
## radius below that listener's distance.
func _test_detectable_concealment_reduces_effective_hearing_range() -> void:
	var actor := Node2D.new()
	add_child(actor)
	actor.global_position = Vector2(84600, 80000)
	var detectable := _make_detectable(actor)
	detectable.concealment_modifier = 5.0 # walking_noise(2.0) - 5.0 -> clamped to 0 effective loudness
	detectable.report_movement_speed(50.0) # walking
	detectable._physics_process(1.0)

	var listener_pos := Vector2(84610, 80000) # 10 units away -- would hear ordinary walking noise easily
	var heard: Array[Dictionary] = NoiseManager.recent_noises_near(listener_pos, 999999.0, 999999)
	_assert(heard.is_empty(), "concealment_modifier reducing effective loudness to zero must make even a very close listener unable to hear the movement")

	actor.queue_free()
	await get_tree().process_frame

## LootContainerComponent/SalvageableComponent/Door must route their noise
## through the interacting actor's own DetectableComponent when it has one
## -- proven by last_noise_category/last_noise_time_ticks updating on the
## actor, not just a bare NoiseManager event existing.
func _test_activity_noise_routes_through_actor_detectable_component() -> void:
	var actor: Player = PLAYER_SCENE.instantiate()
	add_child(actor)
	await get_tree().process_frame
	actor.global_position = Vector2(87000, 80000)

	var parent := Node2D.new()
	add_child(parent)
	BuildingShellBuilder.add_loot_furniture(parent, Vector2(87010, 80000), null, Vector2(20, 20), &"test/detect_route_shelf", 60.0, {"food_ration": 1})
	await get_tree().process_frame
	var loot_area: Area2D = null
	for child in (parent.get_child(0) as Node2D).get_children():
		if child is Area2D:
			loot_area = child
	var interactable: InteractableComponent = loot_area.get_node("InteractableComponent")
	interactable.interact(actor)

	_assert(actor.detectable.last_noise_category == &"search", "a search by an actor with a DetectableComponent must route through report_activity_noise, recording last_noise_category")
	_assert(actor.detectable.last_noise_time_ticks >= 0, "last_noise_time_ticks must be recorded once activity noise routes through the actor's DetectableComponent")

	parent.free()
	actor.free()
	await get_tree().process_frame

## An actor with no DetectableComponent at all (e.g. a bare interacting
## Node) must still make noise via NoiseManager.emit_actor_noise()'s safe
## fallback -- never require the component to exist.
func _test_activity_noise_falls_back_safely_without_detectable_component() -> void:
	NoiseManager.reset()
	var actor := _make_bare_inventory_actor(Vector2(87100, 80000), 200.0)

	var parent := Node2D.new()
	add_child(parent)
	BuildingShellBuilder.add_loot_furniture(parent, Vector2(87110, 80000), null, Vector2(20, 20), &"test/detect_route_shelf_2", 60.0, {"food_ration": 1})
	await get_tree().process_frame
	var loot_area: Area2D = null
	for child in (parent.get_child(0) as Node2D).get_children():
		if child is Area2D:
			loot_area = child
	var interactable: InteractableComponent = loot_area.get_node("InteractableComponent")
	interactable.interact(actor)

	var heard: Array[Dictionary] = NoiseManager.recent_noises_near(actor.global_position, 999999.0, 999999)
	_assert(not heard.is_empty(), "an actor without a DetectableComponent must still emit noise via the safe NoiseManager fallback")

	parent.free()
	actor.free()
	await get_tree().process_frame

## A programmatic door toggle (no interacting actor) must still emit its
## noise safely -- Door.toggle()'s `actor` parameter defaults to null and
## must never be required.
func _test_door_programmatic_toggle_emits_noise_without_an_actor() -> void:
	NoiseManager.reset()
	var door: Door = DOOR_SCENE.instantiate()
	add_child(door)
	door.global_position = Vector2(87200, 80000)
	await get_tree().process_frame

	door.toggle() # no actor argument -- must not crash, and must still emit
	var heard: Array[Dictionary] = NoiseManager.recent_noises_near(door.global_position, 999999.0, 999999)
	_assert(not heard.is_empty(), "a programmatic door toggle with no actor must still emit a door noise via the safe fallback")

	door.queue_free()
	await get_tree().process_frame

## A minimal actor with a real (script-declared) carried_inventory property
## but deliberately NO DetectableComponent child -- proves NoiseManager's
## fallback path without a component ever being required. A dynamically
## generated GDScript, since Object.set() cannot add a new property to a
## plain Node2D (only assign an already-declared one), and no existing
## scene fits "has carried_inventory but not detectable."
func _make_bare_inventory_actor(pos: Vector2, capacity_weight: float) -> Node2D:
	var script := GDScript.new()
	script.source_code = "extends Node2D\nvar carried_inventory: Inventory\n"
	script.reload()
	var actor := Node2D.new()
	actor.set_script(script)
	actor.carried_inventory = Inventory.new(capacity_weight)
	add_child(actor)
	actor.global_position = pos
	return actor

## A real Player (has a genuine carried_inventory property, not a
## dynamically-set one -- Object.set() cannot add a new property to a
## plain Node2D, only assign an EXISTING one, so "carried_inventory" in
## actor would read false regardless).
func _make_salvage_actor(pos: Vector2, capacity_weight: float) -> Player:
	var actor: Player = PLAYER_SCENE.instantiate()
	add_child(actor)
	await get_tree().process_frame
	actor.global_position = pos
	actor.carried_inventory.capacity_weight = capacity_weight
	return actor

## Full-capacity salvage: the actor's inventory can accept the entire
## material_yield in one interaction -- exact amount transferred, prop
## fully depleted.
func _test_salvage_full_capacity_transfers_exact_yield() -> void:
	var parent := Node2D.new()
	add_child(parent)
	BuildingShellBuilder.add_salvage_prop(parent, Vector2(88000, 80000), null, Vector2(20, 20), &"test/salvage_full", 5)
	await get_tree().process_frame
	var salvage: SalvageableComponent = _find_salvageable(parent)
	var actor := await _make_salvage_actor(Vector2(88000, 80000), 0.0) # unlimited capacity

	salvage._on_interacted(actor)

	_assert(actor.carried_inventory.get_count(&"materials") == 5, "full-capacity salvage must transfer the exact material_yield")
	_assert(salvage.remaining_yield() == 0, "remaining_yield must reach exactly zero after a full-capacity salvage")

	parent.free()
	actor.free()
	await get_tree().process_frame

## Partial-capacity salvage: the actor can only fit part of material_yield
## right now -- exactly that much transfers, the rest is preserved on the
## prop (never silently destroyed), and the prop stays interactable.
func _test_salvage_partial_capacity_preserves_remainder() -> void:
	var parent := Node2D.new()
	add_child(parent)
	BuildingShellBuilder.add_salvage_prop(parent, Vector2(88100, 80000), null, Vector2(20, 20), &"test/salvage_partial", 5)
	await get_tree().process_frame
	var salvage: SalvageableComponent = _find_salvageable(parent)
	var actor := await _make_salvage_actor(Vector2(88100, 80000), 3.0) # materials weigh 1.0/unit by default -- fits only 3

	salvage._on_interacted(actor)

	var gained: int = actor.carried_inventory.get_count(&"materials")
	_assert(gained <= 3, "partial-capacity salvage must never transfer more than currently fits")
	_assert(gained > 0, "sanity: some amount should have fit")
	_assert(salvage.remaining_yield() == 5 - gained, "the unclaimed remainder must be preserved on the prop, not destroyed")
	_assert(salvage._interactable.enabled, "a partially-salvaged prop (remaining_yield > 0) must remain interactable")

	parent.free()
	actor.free()
	await get_tree().process_frame

## Zero-capacity salvage: the actor has no free capacity at all -- neither
## side changes.
func _test_salvage_zero_capacity_changes_nothing() -> void:
	var parent := Node2D.new()
	add_child(parent)
	BuildingShellBuilder.add_salvage_prop(parent, Vector2(88200, 80000), null, Vector2(20, 20), &"test/salvage_zero", 4)
	await get_tree().process_frame
	var salvage: SalvageableComponent = _find_salvageable(parent)
	var actor := await _make_salvage_actor(Vector2(88200, 80000), 1.0)
	actor.carried_inventory.add_item(&"materials", 1) # fill the only unit of capacity

	salvage._on_interacted(actor)

	_assert(actor.carried_inventory.get_count(&"materials") == 1, "zero free capacity must transfer nothing")
	_assert(salvage.remaining_yield() == 4, "zero free capacity must leave remaining_yield completely untouched")

	parent.free()
	actor.free()
	await get_tree().process_frame

## Repeated partial salvages must eventually transfer the exact original
## total -- conservation holds across the whole sequence, not just one step.
func _test_salvage_repeated_partial_reaches_exact_total() -> void:
	var parent := Node2D.new()
	add_child(parent)
	BuildingShellBuilder.add_salvage_prop(parent, Vector2(88300, 80000), null, Vector2(20, 20), &"test/salvage_repeated", 7)
	await get_tree().process_frame
	var salvage: SalvageableComponent = _find_salvageable(parent)
	var actor := await _make_salvage_actor(Vector2(88300, 80000), 2.0) # only 2 units fit at a time

	var total_gained: int = 0
	var original_yield: int = 7
	var guard: int = 0
	while salvage.remaining_yield() > 0 and guard < 20:
		guard += 1
		actor.carried_inventory.remove_item(&"materials", actor.carried_inventory.get_count(&"materials")) # empty out between attempts
		salvage._on_interacted(actor)
		total_gained += actor.carried_inventory.get_count(&"materials")
		_assert(total_gained + salvage.remaining_yield() == original_yield, "at every step, materials gained plus materials remaining on the prop must equal the original yield exactly")

	_assert(total_gained == original_yield, "repeated partial salvage must eventually transfer the exact original total (got %d of %d)" % [total_gained, original_yield])
	_assert(salvage.remaining_yield() == 0, "the prop must end fully depleted")

	parent.free()
	actor.free()
	await get_tree().process_frame

## Snapshot/restore must preserve remaining_yield exactly, the same
## round-trip contract WorldState.prop_states already provides.
func _test_salvage_remaining_yield_survives_snapshot_restore() -> void:
	var parent := Node2D.new()
	add_child(parent)
	BuildingShellBuilder.add_salvage_prop(parent, Vector2(88400, 80000), null, Vector2(20, 20), &"test/salvage_snapshot", 6)
	await get_tree().process_frame
	var salvage: SalvageableComponent = _find_salvageable(parent)
	var actor := await _make_salvage_actor(Vector2(88400, 80000), 2.0)
	salvage._on_interacted(actor) # partial: remaining_yield becomes 4

	var snapshot: Dictionary = WorldState.to_snapshot()
	WorldState.reset()
	_assert(WorldState.get_prop_state_flag(&"test/salvage_snapshot", &"remaining_yield", 6) == 6, "sanity: reset() must clear the partial progress back to the unset default")
	WorldState.restore_phase_3b_state(snapshot)

	_assert(WorldState.get_prop_state_flag(&"test/salvage_snapshot", &"remaining_yield", -1) == 4, "restoring a snapshot must preserve the exact remaining_yield at the moment it was taken")

	parent.free()
	actor.free()
	await get_tree().process_frame

func _find_salvageable(parent: Node2D) -> SalvageableComponent:
	var prop_root: Node2D = parent.get_child(0)
	for child in prop_root.get_children():
		if child is Area2D:
			return child.get_node("SalvageableComponent")
	return null

## BUDGET_DEFERRED must never make an actor steer straight through a
## blocked direct line -- with the request budget already exhausted this
## frame, a survivor facing a wall must hold position (zero/near-zero
## steering), not push through it.
func _test_survivor_budget_exhaustion_does_not_walk_into_wall() -> void:
	UrbanNavigationService.build(Vector2(400, 400))
	await get_tree().physics_frame

	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(200, 20)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector2(0, 100)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	UrbanNavigationService.build(Vector2(400, 400)) # rebuild AFTER the wall exists

	var settlement: Settlement = await _make_settlement(["general"])
	var survivor: Survivor = await _make_survivor({"name": "Budget"}, settlement)
	survivor.global_position = Vector2(0, 0)
	survivor._nav_recheck_timer = 0.0

	# Exhaust this frame's shared request budget with unrelated calls first.
	for i in range(UrbanNavigationService.MAX_REQUESTS_PER_FRAME):
		UrbanNavigationService.find_path(Vector2(-300, -300), Vector2(300, 300))

	var dir: Vector2 = survivor._seek_direction(Vector2(0, 200), Vector2(0, 200), 200.0)
	_assert(dir.is_equal_approx(Vector2.ZERO), "with the shared budget exhausted and the direct line blocked, a survivor must hold position rather than steer straight into the wall")

	wall.queue_free()
	settlement.free()
	await get_tree().process_frame

## A target that is provably unreachable (isolated far outside any built
## grid, so NO_PATH persists past the bounded retry count) must terminate
## safely: nav_stuck becomes true, and the actor never oscillates forever
## or produces NaN/Inf.
func _test_survivor_no_path_result_terminates_safely() -> void:
	UrbanNavigationService.build(Vector2(200, 200)) # small grid -- a distant target falls outside its bounds -> NO_PATH, not merely deferred
	await get_tree().physics_frame

	var settlement: Settlement = await _make_settlement(["general"])
	var survivor: Survivor = await _make_survivor({"name": "Lost"}, settlement)
	survivor.global_position = Vector2(0, 0)
	survivor._nav_recheck_timer = 0.0

	var target := Vector2(50000, 50000) # outside the grid entirely -- direct line is "clear" (no walls) but NO_PATH is irrelevant here since is_direct_path_clear() will be true
	# Force a genuinely blocked-but-unreachable scenario: block the direct line with a wall so pathfinding is actually consulted.
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(300, 20)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector2(0, 50)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame

	for i in range(Survivor.NAV_MAX_NO_PATH_RETRIES + 2):
		survivor._nav_recheck_timer = 0.0
		var dir: Vector2 = survivor._seek_direction(target, target - survivor.global_position, (target - survivor.global_position).length())
		_assert(is_finite(dir.x) and is_finite(dir.y), "an unreachable target must never produce NaN/Inf steering")

	_assert(survivor.nav_stuck, "repeated NO_PATH results past the bounded retry count must set nav_stuck, terminating the retry loop rather than retrying forever")

	wall.queue_free()
	settlement.free()
	await get_tree().process_frame

## A cached route through a door must be discarded the instant that door
## closes (revision bump), and a fresh route must become available once it
## opens again.
func _test_survivor_cached_path_invalidated_when_door_closes() -> void:
	UrbanNavigationService.build(Vector2(400, 400))
	await get_tree().physics_frame

	var wall_a := StaticBody2D.new()
	wall_a.collision_layer = 1
	wall_a.collision_mask = 0
	var shape_a := RectangleShape2D.new()
	shape_a.size = Vector2(300, 20)
	var collider_a := CollisionShape2D.new()
	collider_a.shape = shape_a
	wall_a.add_child(collider_a)
	wall_a.position = Vector2(0, 100)
	add_child(wall_a)
	await get_tree().physics_frame
	await get_tree().physics_frame
	UrbanNavigationService.build(Vector2(400, 400))

	var door: Door = DOOR_SCENE.instantiate()
	door.door_id = &"test/survivor_cache_invalidation_door"
	add_child(door)
	door.global_position = Vector2(150, 100)
	await get_tree().physics_frame
	await get_tree().physics_frame
	UrbanNavigationService.register_door(door.door_id, door.global_position)
	UrbanNavigationService.mark_door_open(door.door_id) # start open

	var settlement: Settlement = await _make_settlement(["general"])
	var survivor: Survivor = await _make_survivor({"name": "Cacher"}, settlement)
	survivor.global_position = Vector2(0, 0)
	survivor._nav_recheck_timer = 0.0

	var target := Vector2(0, 200)
	survivor._seek_direction(target, target - survivor.global_position, 200.0)
	var revision_before: int = UrbanNavigationService.revision()
	var had_cached_path: bool = not survivor._nav_path.is_empty()
	_assert(had_cached_path, "route-invalidation setup must produce a real cached path before the door closes")

	door.toggle() # close it -- bumps UrbanNavigationService.revision()
	_assert(UrbanNavigationService.revision() != revision_before, "closing a registered door must bump UrbanNavigationService's revision counter")

	survivor._nav_recheck_timer = 0.0
	survivor._seek_direction(target, target - survivor.global_position, 200.0)
	_assert(survivor._nav_path_revision == UrbanNavigationService.revision() or survivor._nav_path.is_empty(), "a cached path must never be used after the revision it was computed against has changed -- it must be discarded and recomputed (or found empty/pending)")

	door.queue_free()
	wall_a.queue_free()
	settlement.free()
	await get_tree().process_frame

## Zombie's own navigation cache follows the identical invalidation rule.
func _test_zombie_cached_path_invalidated_when_door_closes() -> void:
	UrbanNavigationService.build(Vector2(400, 400))
	await get_tree().physics_frame

	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(300, 20)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector2(0, 100)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	UrbanNavigationService.build(Vector2(400, 400))

	var door: Door = DOOR_SCENE.instantiate()
	door.door_id = &"test/zombie_cache_invalidation_door"
	add_child(door)
	door.global_position = Vector2(150, 100)
	await get_tree().physics_frame
	await get_tree().physics_frame
	UrbanNavigationService.register_door(door.door_id, door.global_position)
	UrbanNavigationService.mark_door_open(door.door_id)

	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(zombie)
	zombie.global_position = Vector2(0, 0)
	zombie._nav_recheck_timer = 0.0

	zombie._seek_point(Vector2(0, 200))
	var revision_before: int = UrbanNavigationService.revision()

	door.toggle() # close it
	_assert(UrbanNavigationService.revision() != revision_before, "sanity: closing must bump the revision")

	zombie._nav_recheck_timer = 0.0
	zombie._seek_point(Vector2(0, 200))
	_assert(zombie._nav_path_revision == UrbanNavigationService.revision() or zombie._nav_path.is_empty(), "Zombie's cached path must follow the same revision-based invalidation as Survivor's")

	zombie.queue_free()
	door.queue_free()
	wall.queue_free()
	await get_tree().process_frame

## Once blocked with no route, a survivor repeatedly asked to move toward
## the same unreachable point must hold near the same spot rather than
## grinding against the wall frame after frame (velocity settles toward
## zero, not toward the wall).
func _test_survivor_does_not_repeatedly_push_against_closed_door() -> void:
	UrbanNavigationService.build(Vector2(200, 200))
	await get_tree().physics_frame

	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(300, 20)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector2(0, 50)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var settlement: Settlement = await _make_settlement(["general"])
	var survivor: Survivor = await _make_survivor({"name": "Patient"}, settlement)
	survivor.global_position = Vector2(0, 0)

	for i in range(10):
		survivor._nav_recheck_timer = 0.0
		survivor.move_toward_point(Vector2(0, 5000), 1.0 / 60.0)
	_assert(survivor.global_position.distance_to(Vector2(0, 0)) < 30.0, "a survivor with no route to a blocked, unreachable target must not keep grinding forward into the wall")

	wall.queue_free()
	settlement.free()
	await get_tree().process_frame

## The shared per-frame request budget still caps total requests across
## BOTH actor types combined -- no per-survivor unrestricted pathfinding.
func _test_navigation_shared_budget_enforced_across_calls() -> void:
	UrbanNavigationService.build(Vector2(400, 400))
	await get_tree().physics_frame
	var successes: int = 0
	for i in range(UrbanNavigationService.MAX_REQUESTS_PER_FRAME + 5):
		var result: Dictionary = UrbanNavigationService.find_path_ex(Vector2(-100, -100), Vector2(100, 100))
		if result["status"] == UrbanNavigationService.PathResult.SUCCESS:
			successes += 1
	_assert(successes == UrbanNavigationService.MAX_REQUESTS_PER_FRAME, "find_path_ex must respect the exact same shared per-frame budget as find_path")

## Two bodies overlapping a door's footprint -- one exiting must not clear
## the other's occupancy.
func _test_door_two_bodies_one_exits_still_blocked() -> void:
	var door: Door = DOOR_SCENE.instantiate()
	add_child(door)
	await get_tree().process_frame
	door.toggle() # open first

	var body_a := Node.new()
	var body_b := Node.new()
	door._on_body_entered(body_a)
	door._on_body_entered(body_b)
	door._on_body_exited(body_a)
	door.toggle() # attempt to close with body_b still inside
	_assert(door.is_open, "a door must refuse to close while ANY tracked body still overlaps its footprint")

	door.queue_free()
	body_a.free()
	body_b.free()
	await get_tree().process_frame

## Once every occupying body clears, the door must close normally.
func _test_door_closes_once_both_bodies_exit() -> void:
	var door: Door = DOOR_SCENE.instantiate()
	add_child(door)
	await get_tree().process_frame
	door.toggle()

	var body_a := Node.new()
	var body_b := Node.new()
	door._on_body_entered(body_a)
	door._on_body_entered(body_b)
	door._on_body_exited(body_a)
	door._on_body_exited(body_b)
	door.toggle()
	_assert(not door.is_open, "a door must close normally once every occupying body has cleared")

	door.queue_free()
	body_a.free()
	body_b.free()
	await get_tree().process_frame

## A body freed WITHOUT ever firing body_exited (e.g. queue_free'd mid-
## overlap) must be pruned automatically, never permanently wedging a door
## open.
func _test_door_prunes_freed_body_while_overlapping() -> void:
	var door: Door = DOOR_SCENE.instantiate()
	add_child(door)
	await get_tree().process_frame
	door.toggle()

	var body := Node.new()
	add_child(body)
	door._on_body_entered(body)
	body.free()
	await get_tree().process_frame # let the free complete

	door.toggle() # must not still think body is blocking it
	_assert(not door.is_open, "a body freed mid-overlap without ever firing body_exited must be pruned, not permanently block closing")

	door.queue_free()
	await get_tree().process_frame

## Duplicate body_entered signals for the SAME body (e.g. a re-fired signal)
## must not corrupt the occupancy count -- one exit still fully clears it.
func _test_door_duplicate_enter_signals_do_not_corrupt_count() -> void:
	var door: Door = DOOR_SCENE.instantiate()
	add_child(door)
	await get_tree().process_frame
	door.toggle()

	var body := Node.new()
	door._on_body_entered(body)
	door._on_body_entered(body) # duplicate
	door._on_body_entered(body) # duplicate again
	door._on_body_exited(body) # a single exit must fully clear it
	door.toggle()
	_assert(not door.is_open, "duplicate body_entered signals for the same body must not require multiple exits to clear")

	door.queue_free()
	body.free()
	await get_tree().process_frame

## A candidate whose CENTER clears a wall but whose collision-radius
## footprint would still overlap it must be rejected -- the point-only
## check this replaces would have wrongly accepted it.
func _test_spawn_rejects_candidate_with_edge_overlapping_wall() -> void:
	UrbanNavigationService.reset()
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(400, 400)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector2(76000, 70000)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var manager := await _make_spawn_manager(77)
	# Center just outside the wall's edge (wall half-extent 200 -> edge at
	# x=76200), but within collision_radius+margin (13+4=17) of it.
	var candidate := Vector2(76210, 70000)
	_assert(manager._footprint_overlaps(candidate), "a candidate whose footprint radius still overlaps a wall's edge must be rejected even though its exact center point is outside the wall")

	manager.queue_free()
	wall.queue_free()
	await get_tree().process_frame

## A clear region with nothing nearby must still succeed -- the shape-based
## check isn't simply always-reject.
func _test_spawn_clear_region_candidate_succeeds() -> void:
	UrbanNavigationService.reset()
	var manager := await _make_spawn_manager(78)
	var candidate := Vector2(78000, 70000) # isolated, nothing else registered here
	_assert(not manager._footprint_overlaps(candidate), "a candidate with genuinely clear space around it must not be rejected by the footprint check")

	manager.queue_free()
	await get_tree().process_frame

## Deterministic RNG selection must survive the new shape-based validation
## unchanged -- same seed, same regions -> same chosen point.
func _test_spawn_deterministic_selection_unchanged_with_shape_validation() -> void:
	var region_a := await _make_spawn_region(&"test/shape_det_a", Vector2(79000, 70000), 120.0)
	var region_b := await _make_spawn_region(&"test/shape_det_b", Vector2(79000, 70400), 120.0)

	var manager_1 := await _make_spawn_manager(555111)
	var pos_1: Variant = manager_1._pick_region_spawn_position()
	manager_1.queue_free()
	await get_tree().process_frame

	var manager_2 := await _make_spawn_manager(555111)
	var pos_2: Variant = manager_2._pick_region_spawn_position()
	manager_2.queue_free()
	await get_tree().process_frame

	_assert(pos_1 != null and pos_2 != null, "sanity: both picks should succeed with two open regions")
	_assert((pos_1 as Vector2).is_equal_approx(pos_2), "the same rng_seed must still pick the identical region and point under shape-based validation")

	region_a.queue_free()
	region_b.queue_free()
	await get_tree().process_frame

## Crossing directly from Room A to Room B (both signal orders) must never
## leave the actor reading as outdoors, even momentarily -- the deferred
## recompute must always resolve to B, never a stale "".
func _test_room_context_a_to_b_crossing_stays_indoors() -> void:
	var building: ConvenienceStore01 = CONVENIENCE_STORE_SCENE.instantiate()
	add_child(building)
	building.global_position = Vector2(91000, 91000)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var retail_room: Room = building.get_node("Rooms/RetailFloor")
	var back_room: Room = building.get_node("Rooms/BackRoom")

	var settlement: Settlement = await _make_settlement(["general"])
	var survivor: Survivor = await _make_survivor({"name": "Crosser"}, settlement)
	survivor.global_position = retail_room.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_assert(survivor.detectable.current_room_id == &"retail_floor", "sanity: survivor starts in the retail floor")

	# A real physical crossing -- Godot's own Area2D signal order for this
	# same-frame transition is whatever it is (not something a test can
	# dictate), which is exactly the point: _update_detectable_context()
	# must resolve correctly regardless of that order, by trusting live
	# overlap state rather than any single signal's own room argument.
	survivor.global_position = back_room.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	_assert(survivor.detectable.is_indoors, "crossing A -> B must never leave the actor reading as outdoors")
	_assert(survivor.detectable.current_room_id == &"back_room", "after physically crossing into room B, the context must resolve to B regardless of the real signal order")

	# And back the other way.
	survivor.global_position = retail_room.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	_assert(survivor.detectable.is_indoors, "crossing back B -> A must also never leave the actor reading as outdoors")
	_assert(survivor.detectable.current_room_id == &"retail_floor", "after physically crossing back into room A, the context must resolve to A")

	# Explicitly exercise BOTH synthetic signal orderings too, matching the
	# actual physical position (retail_floor) at the time they fire -- this
	# is what proves the fix doesn't merely happen to work for whichever
	# order Godot picks in practice, but is correct for either order by
	# construction.
	building._on_room_body_entered(survivor, retail_room) # already true -- a harmless duplicate/idempotent re-entry
	building._on_room_body_exited(survivor, back_room) # never really entered -- an exit for a room the body was never in
	await get_tree().process_frame
	_assert(survivor.detectable.is_indoors and survivor.detectable.current_room_id == &"retail_floor", "an exit signal for a room the body isn't (and was signalled to be) inside must never override the room it's ACTUALLY inside")

	survivor.queue_free()
	building.queue_free()
	settlement.free()
	await get_tree().process_frame

## Leaving the building entirely (no room, in either building) must clear
## context back to not-indoors.
func _test_room_context_clears_on_leaving_building() -> void:
	var building: ConvenienceStore01 = CONVENIENCE_STORE_SCENE.instantiate()
	add_child(building)
	building.global_position = Vector2(92000, 92000)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var retail_room: Room = building.get_node("Rooms/RetailFloor")
	var settlement: Settlement = await _make_settlement(["general"])
	var survivor: Survivor = await _make_survivor({"name": "Leaver"}, settlement)
	survivor.global_position = retail_room.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_assert(survivor.detectable.is_indoors, "sanity: survivor starts indoors")

	survivor.global_position = Vector2(99500, 99500) # far outside the building entirely
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_assert(not survivor.detectable.is_indoors, "leaving the building entirely must clear indoor context")
	_assert(survivor.detectable.current_room_id == &"", "leaving the building entirely must clear current_room_id")

	survivor.queue_free()
	building.queue_free()
	settlement.free()
	await get_tree().process_frame

## Rapid doorway oscillation (several enter/exit pairs queued within one
## frame) must still leave the FINAL, correct state once signals settle --
## not a state matching whichever signal happened to fire last.
func _test_room_context_rapid_oscillation_settles_correctly() -> void:
	var building: ConvenienceStore01 = CONVENIENCE_STORE_SCENE.instantiate()
	add_child(building)
	building.global_position = Vector2(93000, 93000)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var retail_room: Room = building.get_node("Rooms/RetailFloor")
	var back_room: Room = building.get_node("Rooms/BackRoom")
	var settlement: Settlement = await _make_settlement(["general"])
	var survivor: Survivor = await _make_survivor({"name": "Oscillator"}, settlement)
	survivor.global_position = retail_room.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Several oscillations queued within a single frame before anything flushes.
	building._on_room_body_exited(survivor, retail_room)
	building._on_room_body_entered(survivor, back_room)
	building._on_room_body_exited(survivor, back_room)
	building._on_room_body_entered(survivor, retail_room)
	building._on_room_body_exited(survivor, retail_room)
	building._on_room_body_entered(survivor, back_room)
	# Final ACTUAL overlap state: survivor's real body never moved, so
	# whichever room its physical position is really inside is the only
	# thing the deferred flush should trust -- not signal call order.
	await get_tree().process_frame

	var actual_room_id: StringName = &"retail_floor" if retail_room.get_overlapping_bodies().has(survivor) else &"back_room"
	_assert(survivor.detectable.current_room_id == actual_room_id, "after rapid same-frame oscillation, the final context must match the body's ACTUAL overlap state, not merely the last signal that happened to fire")
	_assert(survivor.detectable.is_indoors, "the survivor must still read as indoors after oscillation settles")

	survivor.queue_free()
	building.queue_free()
	settlement.free()
	await get_tree().process_frame
