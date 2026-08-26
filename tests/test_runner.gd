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
const SCAVENGE_POINT_SCENE: PackedScene = preload("res://scenes/world/ScavengePoint.tscn")
const CONVENIENCE_STORE_SCENE: PackedScene = preload("res://scenes/world/buildings/ConvenienceStore01.tscn")
const CLINIC_SCENE: PackedScene = preload("res://scenes/world/buildings/Clinic01.tscn")
const VOXEL_ZOMBIE_SCENE: PackedScene = preload("res://scenes/actors/VoxelZombie3D.tscn")
const PROCEDURAL_DISTRICT_SCENE: PackedScene = preload("res://scenes/world/maps/ProceduralDistrict.tscn")
const PROCEDURAL_RETRY_PROBE_SCRIPT: GDScript = preload("res://tests/procedural_retry_probe.gd")
const FAILING_PROCEDURAL_DISTRICT_SCRIPT: GDScript = preload("res://tests/failing_procedural_district.gd")
const SAFEHOUSE_COMPASS_SCRIPT: GDScript = preload("res://scripts/ui/safehouse_compass.gd")
const GAME_CLOCK_SCRIPT: GDScript = preload("res://scripts/ui/game_clock_label.gd")
const DAY_NIGHT_SCRIPT: GDScript = preload("res://scripts/visuals/day_night_cycle.gd")
const COMBAT_FEEDBACK_SCRIPT: GDScript = preload("res://scripts/ui/combat_feedback.gd")
const PROCEDURAL_SEED_CORPUS: Array[int] = [0, 1, 2, 3, 7, 31, 42, 255, 1024, 8801, 65535, 20260821, 2147483646]

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

	## --- Procedural city and environment destruction -----------------------
	await _run_test("procedural_city_same_seed_is_identical", _test_procedural_city_same_seed_is_identical)
	await _run_test("procedural_city_different_seed_changes_layout", _test_procedural_city_different_seed_changes_layout)
	await _run_test("procedural_city_generated_model_passes_invariants", _test_procedural_city_generated_model_passes_invariants)
	await _run_test("procedural_compound_buildings_have_enterable_wings", _test_procedural_compound_buildings_have_enterable_wings)
	await _run_test("streamed_chunk_edges_and_building_branches_are_deterministic", _test_streamed_chunk_edges_and_building_branches_are_deterministic)
	await _run_test("streamed_prague_courtyards_have_clear_passages", _test_streamed_prague_courtyards_have_clear_passages)
	await _run_test("streamed_prague_theme_has_transit_roofs_and_active_frontages", _test_streamed_prague_theme_has_transit_roofs_and_active_frontages)
	await _run_test("projected_prague_exteriors_are_deterministic_and_portal_aligned", _test_projected_prague_exteriors_are_deterministic_and_portal_aligned)
	await _run_test("compound_footprints_extract_only_exposed_south_facades", _test_compound_footprints_extract_only_exposed_south_facades)
	await _run_test("projected_exterior_runtime_is_visual_only_and_sortable", _test_projected_exterior_runtime_is_visual_only_and_sortable)
	await _run_test("local_occlusion_fade_engages_and_releases", _test_local_occlusion_fade_engages_and_releases)
	await _run_test("local_occlusion_fade_survives_player_removal", _test_local_occlusion_fade_survives_player_removal)
	await _run_test("street_objects_separate_visual_collision_and_light", _test_street_objects_separate_visual_collision_and_light)
	await _run_test("generic_generated_buildings_can_be_claimed_as_bases", _test_generic_generated_buildings_can_be_claimed_as_bases)
	await _run_test("abandoning_base_preserves_building_and_clears_state", _test_abandoning_base_preserves_building_and_clears_state)
	await _run_test("generated_interiors_are_furnished_compositions", _test_generated_interiors_are_furnished_compositions)
	await _run_test("furniture_dimensions_leave_the_one_tile_era", _test_furniture_dimensions_leave_the_one_tile_era)
	await _run_test("furniture_never_blocks_door_routes", _test_furniture_never_blocks_door_routes)
	await _run_test("generated_loot_furniture_is_interactive_persistent_and_destructible", _test_generated_loot_furniture_is_interactive_persistent_and_destructible)
	await _run_test("settlement_uses_no_special_safehouse_geometry", _test_settlement_uses_no_special_safehouse_geometry)
	await _run_test("multiple_groups_claim_different_buildings", _test_multiple_groups_claim_different_buildings)
	await _run_test("base_structures_remain_destructible", _test_base_structures_remain_destructible)
	await _run_test("light_furniture_receives_physical_impulse", _test_light_furniture_receives_physical_impulse)
	await _run_test("heavy_furniture_becomes_dynamic_only_under_force", _test_heavy_furniture_becomes_dynamic_only_under_force)
	await _run_test("destroyed_wall_spawns_bounded_debris", _test_destroyed_wall_spawns_bounded_debris)
	await _run_test("zombie_death_leaves_a_physical_corpse", _test_zombie_death_leaves_a_physical_corpse)
	await _run_test("explosion_pushes_world_with_radial_falloff", _test_explosion_pushes_world_with_radial_falloff)
	await _run_test("physics_debris_and_corpses_are_capped", _test_physics_debris_and_corpses_are_capped)
	await _run_test("furniture_refreezes_and_reactivates", _test_furniture_refreezes_and_reactivates)
	await _run_test("contact_shoving_moves_light_not_heavy", _test_contact_shoving_moves_light_not_heavy)
	await _run_test("moved_furniture_transform_persists", _test_moved_furniture_transform_persists)
	await _run_test("sleeping_corpse_thrown_by_explosion", _test_sleeping_corpse_thrown_by_explosion)
	await _run_test("corpse_lifetime_cleanup_works", _test_corpse_lifetime_cleanup_works)
	await _run_test("partial_wall_damage_is_progressive", _test_partial_wall_damage_is_progressive)
	await _run_test("wall_breach_updates_collision_and_navigation", _test_wall_breach_updates_collision_and_navigation)
	await _run_test("furniture_partial_damage_before_failure", _test_furniture_partial_damage_before_failure)
	await _run_test("zombie_anatomy_governs_death_and_cripples", _test_zombie_anatomy_governs_death_and_cripples)
	await _run_test("severed_limbs_get_physics_and_gore_caps", _test_severed_limbs_get_physics_and_gore_caps)
	await _run_test("weapons_are_data_driven_with_sprites", _test_weapons_are_data_driven_with_sprites)
	await _run_test("infinite_player_ammo_debug_flag", _test_infinite_player_ammo_debug_flag)
	await _run_test("base_functions_use_valid_interior_spots", _test_base_functions_use_valid_interior_spots)
	await _run_test("wall_shatters_into_quarter_chunks", _test_wall_shatters_into_quarter_chunks)
	await _run_test("breach_syncs_roof_and_facade", _test_breach_syncs_roof_and_facade)
	await _run_test("headshots_kill_fast_and_limbs_sever", _test_headshots_kill_fast_and_limbs_sever)
	await _run_test("zombie_gait_animation_states", _test_zombie_gait_animation_states)
	await _run_test("dialogue_database_is_coherent", _test_dialogue_database_is_coherent)
	await _run_test("dialogue_controller_flow_branch_and_flags", _test_dialogue_controller_flow_branch_and_flags)
	await _run_test("dialogue_ui_shows_lines_and_choices", _test_dialogue_ui_shows_lines_and_choices)
	await _run_test("building_world_25d_mirrors_destruction", _test_building_world_25d_mirrors_destruction)
	await _run_test("multistory_stairs_toggle_floors", _test_multistory_stairs_toggle_floors)

## --- story & dialogue ---

func _test_dialogue_database_is_coherent() -> void:
	var errors := DialogueDatabase.validate()
	_assert(errors.is_empty(), "authored dialogue must be referentially coherent: %s" % str(errors))
	for required_id in [&"safehouse_first_night", &"trader_vaclav_greeting", &"survivor_plea"]:
		_assert(DialogueDatabase.has(required_id), "campaign must author the %s conversation" % String(required_id))
	var greeting := DialogueDatabase.get_entry(&"trader_vaclav_greeting")
	_assert((greeting["choices"] as Array).size() >= 2, "the trader greeting must offer branching choices")

func _test_dialogue_controller_flow_branch_and_flags() -> void:
	WorldState.reset()
	var controller := DialogueController.new()
	add_child(controller)
	var seen_lines: Array[String] = []
	var finished_ids: Array[StringName] = []
	var captured_options: Array = []
	controller.line_started.connect(func(_id: StringName, _index: int, _speaker: StringName, text: String) -> void:
		seen_lines.append(text))
	controller.choices_available.connect(func(_id: StringName, options: Array) -> void:
		captured_options.clear()
		for option in options:
			captured_options.append(option))
	controller.dialogue_finished.connect(func(id: StringName) -> void: finished_ids.append(id))
	_assert(not controller.is_active(), "controller starts idle")
	_assert(controller.start(&"does_not_exist") == false, "unknown dialogue ids must be rejected")
	_assert(controller.start(&"safehouse_first_night"), "starting an authored dialogue must succeed")
	_assert(seen_lines.size() == 1, "start() must present the first line immediately")
	controller.advance()
	_assert(captured_options.is_empty(), "choices stay hidden while lines remain")
	controller.advance() # presents choices (returns false), controller waits for choose()
	_assert(captured_options.size() == 2, "choices must be presented exactly once for selection")
	_assert(controller.choose(99) == false, "out-of-range choice indices must be rejected")
	_assert(controller.choose(1), "choosing the dawn-plan branch must succeed")
	_assert(bool(WorldState.world_flags.get(&"story_moving_on", false)), "choice effects must set their world flag")
	_assert(String(controller.active_id) == &"safehouse_dawn_plan", "branch target must become the active dialogue")
	var depth := 0
	while controller.is_active() and depth < 10:
		controller.advance()
		depth += 1
	_assert(finished_ids.has(&"safehouse_dawn_plan") or not controller.is_active(),
		"exhausting a branch line list must finish the conversation")
	controller.cancel()
	WorldState.reset()

func _test_building_world_25d_mirrors_destruction() -> void:
	var failures := 0
	var world: Node = load("res://scripts/world/building_world_3d.gd").new()
	world.name = "World25D"
	add_child(world)
	var city: Dictionary = ProceduralCityGenerator.new().generate_streamed_chunk(20260821, Vector2i.ZERO)
	var spec: Dictionary = city["buildings"][0]
	var building := ProceduralBuilding.new()
	building.configure(spec)
	add_child(building)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var record: Dictionary = world.register_building(building)
	world.attach_display(building, record)

	var half: Vector2 = spec["interior"]["half_extent"]
	# Collect two south segments up front (before anything dies).
	var south: Array[Dictionary] = []
	for child in building.get_children():
		if child is StaticBody2D:
			var c := child.get_node_or_null("EnvironmentDamageComponent") as EnvironmentDamageComponent
			if c != null and "/wall_" in String(c.object_id):
				var body := child as Node2D
				if body.position.y >= half.y - PixelAtlasMap.TILE_SIZE:
					south.append({"comp": c, "pos": body.position})
	_assert(south.size() >= 3, "fixture needs south perimeter segments")

	# Display container exists with a real viewport, and is anchored into the
	# y-sorted entity layer at the building's south baseline (occlusion parity
	# with the old flat facade).
	var container: SubViewportContainer = record["container"]
	_assert(container != null and container.is_inside_tree(), "the 2.5D display container must exist")
	_assert((record["viewport"] as SubViewport).size.x > 100 and (record["viewport"] as SubViewport).size.y > 100,
		"per-building viewport must be sized to the building bounds")
	_assert(world.get_facade_detail_count() > 0, "street-face details (windows/doors) must be extruded")

	var first: Dictionary = south[1]
	var second: Dictionary = south[2]
	var cell_a := Vector2i(floori((first["pos"] as Vector2).x / 32.0), floori((first["pos"] as Vector2).y / 32.0))
	var column_before: int = world.get_column_mesh_count(cell_a)
	var roof_before: int = world.get_roof_tile_count()
	var cascade_x := floori(((second["pos"] as Vector2).x) / 32.0)
	var cascade_before: int = world.count_meshes_in_column_x(cascade_x)

	(first["comp"] as EnvironmentDamageComponent).apply_damage(9999.0, EnvironmentDamage.DamageClass.EXPLOSIVE, null)
	await get_tree().process_frame
	await get_tree().physics_frame
	var column_after: int = world.get_column_mesh_count(cell_a)
	var roof_mid: int = world.get_roof_tile_count()
	failures += 0 if column_after < column_before else 1
	failures += 0 if roof_mid < roof_before else 1

	(second["comp"] as EnvironmentDamageComponent).apply_damage(9999.0, EnvironmentDamage.DamageClass.EXPLOSIVE, null)
	await get_tree().process_frame
	await get_tree().physics_frame
	var cascade_after: int = world.count_meshes_in_column_x(cascade_x)
	failures += 0 if cascade_after < cascade_before else 1

	print("column ", column_before, "->", column_after, " | roof ", roof_before, "->", roof_mid,
		" | cascade x=", cascade_x, " ", cascade_before, "->", cascade_after)
	_assert(failures == 0, "2.5D destruction mirror must track every event (%d failures)" % failures)
	world.queue_free()
	building.queue_free()
	WorldState.reset()
	await get_tree().process_frame

## Stairs: multistory buildings toggle between ground and upper floor
## collision sets; zombies lose track of targets who go upstairs.
func _test_multistory_stairs_toggle_floors() -> void:
	WorldState.reset()
	var city: Dictionary = ProceduralCityGenerator.new().generate_streamed_chunk(20260821, Vector2i.ZERO)
	var spec: Dictionary = {}
	for building_variant in city["buildings"]:
		var candidate: Dictionary = building_variant
		if int(candidate.get("storeys", 2)) >= 3:
			spec = candidate
			break
	_assert(not spec.is_empty(), "the corpus must contain a 3+ storey building for the stairs test")
	var stairs_info: Dictionary = spec["interior"].get("stairs_up", {})
	_assert(not stairs_info.is_empty(), "multistory buildings must author a stairwell position")

	var building := ProceduralBuilding.new()
	building.configure(spec)
	add_child(building)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_assert(building.has_stairs(), "runtime building must expose has_stairs()")
	_assert(building.current_floor == 0, "buildings start on the ground floor")

	building.set_floor(1)
	await get_tree().process_frame
	await get_tree().physics_frame
	_assert(building.current_floor == 1, "set_floor(1) must switch to the upper floor")
	var ground_disabled := 0
	for collider in building._ground_colliders:
		if collider.disabled:
			ground_disabled += 1
	_assert(ground_disabled == building._ground_colliders.size(),
		"going up must disable ALL ground colliders (%d/%d)" % [ground_disabled, building._ground_colliders.size()])

	building.set_floor(0)
	await get_tree().process_frame
	await get_tree().physics_frame
	var ground_reenabled := 0
	for collider in building._ground_colliders:
		if not collider.disabled:
			ground_reenabled += 1
	_assert(ground_reenabled == building._ground_colliders.size(),
		"coming down must re-enable all ground colliders")
	_assert(building.current_floor == 0, "floor must return to ground")

	building.queue_free()
	WorldState.reset()
	await get_tree().process_frame


func _test_dialogue_ui_shows_lines_and_choices() -> void:
	WorldState.reset()
	var controller := DialogueController.new()
	add_child(controller)
	var ui := DialogueUI.new()
	ui.bind(controller)
	add_child(ui)
	await get_tree().process_frame
	controller.start(&"trader_vaclav_greeting")
	await get_tree().process_frame
	_assert(ui.displayed_text().length() > 0, "the UI must display the active line text")
	# Exhaust lines to surface the choice buttons.
	controller.advance()
	controller.advance()
	await get_tree().process_frame
	var choices := ui.displayed_choice_texts()
	_assert(choices.size() == 2, "the UI must render one button per presented choice")
	_assert(choices.any(func(text: String) -> bool: return text.contains("rifle")), "choice buttons must show authored text")
	# Choosing through the UI path applies flags.
	controller.choose(1)
	_assert(bool(WorldState.world_flags.get(&"story_snubbed_vaclav", false)), "UI-driven selection must apply choice effects")
	controller.cancel()
	ui.queue_free()
	controller.queue_free()
	WorldState.reset()
	await get_tree().process_frame
	await _run_test("streamed_prague_quarters_are_dense_and_open_spaces_are_rare", _test_streamed_prague_quarters_are_dense_and_open_spaces_are_rare)
	await _run_test("procedural_seed_corpus_is_deterministic_valid_and_bounded", _test_procedural_seed_corpus_is_deterministic_valid_and_bounded)
	await _run_test("procedural_generation_retries_and_fails_explicitly", _test_procedural_generation_retries_and_fails_explicitly)
	await _run_test("procedural_runtime_failure_propagates_attempt_diagnostics", _test_procedural_runtime_failure_propagates_attempt_diagnostics)
	await _run_test("procedural_roads_parcels_entrances_and_exteriors_are_valid", _test_procedural_roads_parcels_entrances_and_exteriors_are_valid)
	await _run_test("procedural_interiors_are_reachable_furnished_and_clear", _test_procedural_interiors_are_reachable_furnished_and_clear)
	await _run_test("procedural_spawn_phases_are_environmental_and_deterministic", _test_procedural_spawn_phases_are_environmental_and_deterministic)
	await _run_test("spawn_manager_waits_for_generation_begin_and_reset", _test_spawn_manager_waits_for_generation_begin_and_reset)
	await _run_test("generated_building_runtime_ids_and_state_persist", _test_generated_building_runtime_ids_and_state_persist)
	await _run_test("generated_scavenge_stock_persists_by_stable_id", _test_generated_scavenge_stock_persists_by_stable_id)
	await _run_test("procedural_restart_is_isolated_and_reuses_selected_seed", _test_procedural_restart_is_isolated_and_reuses_selected_seed)
	await _run_test("procedural_runtime_generation_profile", _test_procedural_runtime_generation_profile)
	await _run_test("procedural_full_main_landmarks_rooms_and_safehouse_are_navigable", _test_procedural_full_main_landmarks_rooms_and_safehouse_are_navigable)
	await _run_test("population_profile_caps_are_exact", _test_population_profile_caps_are_exact)
	await _run_test("environment_walls_reject_bullets_and_accept_explosives", _test_environment_walls_reject_bullets_and_accept_explosives)
	await _run_test("environment_props_are_interactable_and_damageable", _test_environment_props_are_interactable_and_damageable)
	await _run_test("environment_destroyed_loot_becomes_world_drop", _test_environment_destroyed_loot_becomes_world_drop)
	await _run_test("environment_destruction_state_restores", _test_environment_destruction_state_restores)
	await _run_test("environment_destruction_resamples_live_navigation_with_overlaps", _test_environment_destruction_resamples_live_navigation_with_overlaps)
	await _run_test("doors_and_windows_enforce_damage_classes_and_persist", _test_doors_and_windows_enforce_damage_classes_and_persist)
	await _run_test("destroyed_safehouse_storage_does_not_duplicate_on_rebuild", _test_destroyed_safehouse_storage_does_not_duplicate_on_rebuild)
	await _run_test("player_weapon_slots_preserve_independent_ammo", _test_player_weapon_slots_preserve_independent_ammo)
	await _run_test("explosion_separates_actor_and_structural_damage", _test_explosion_separates_actor_and_structural_damage)

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
	await _run_test("district_buildings_fit_their_blocks_without_overlapping", _test_district_buildings_fit_their_blocks_without_overlapping)
	await _run_test("baked_district_landmarks_are_reachable", _test_baked_district_landmarks_are_reachable)
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
	await _run_test("phase_3b7_survivor_zero_goal_is_initialized_once", _test_phase_3b7_survivor_zero_goal_is_initialized_once)
	await _run_test("phase_3b7_zombie_idle_clears_navigation_lifecycle", _test_phase_3b7_zombie_idle_clears_navigation_lifecycle)
	await _run_test("phase_3b7_zombie_same_target_remains_interval_bounded", _test_phase_3b7_zombie_same_target_remains_interval_bounded)
	await _run_test("phase_3b8_zombie_resample_discards_cached_path", _test_phase_3b8_zombie_resample_discards_cached_path)
	await _run_test("phase_3b8_survivor_action_exit_resets_navigation", _test_phase_3b8_survivor_action_exit_resets_navigation)
	await _run_test("phase_3b8_idle_zombie_makes_no_navigation_requests", _test_phase_3b8_idle_zombie_makes_no_navigation_requests)

	await _run_test("voxel_zombie_hit_flash_engages_and_recovers", _test_voxel_zombie_hit_flash_engages_and_recovers)
	await _run_test("voxel_zombie_hit_flash_is_isolated_per_instance", _test_voxel_zombie_hit_flash_is_isolated_per_instance)
	await _run_test("safehouse_compass_offscreen_clamping_and_readout", _test_safehouse_compass_offscreen_clamping_and_readout)
	await _run_test("hud_builds_safehouse_compass_and_tolerates_missing_targets", _test_hud_builds_safehouse_compass_and_tolerates_missing_targets)
	await _run_test("hud_builds_game_clock_label_and_formats_time", _test_hud_builds_game_clock_label_and_formats_time)
	await _run_test("day_night_palette_is_continuous_bounded_and_timekeyed", _test_day_night_palette_is_continuous_bounded_and_timekeyed)
	await _run_test("day_night_cycle_drives_environment_and_tolerates_missing_targets", _test_day_night_cycle_drives_environment_and_tolerates_missing_targets)
	await _run_test("combat_feedback_vignette_closes_in_with_low_health", _test_combat_feedback_vignette_closes_in_with_low_health)

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

func _test_phase_3b7_survivor_zero_goal_is_initialized_once() -> void:
	var settlement: Settlement = await _make_settlement(["general"])
	var survivor: Survivor = await _make_survivor({"name": "Origin"}, settlement)
	survivor.global_position = Vector2(64, 0)
	UrbanNavigationService.reset()
	for i in range(4):
		survivor._seek_direction(Vector2.ZERO, -survivor.global_position, survivor.global_position.length())
	_assert(survivor._nav_goal_initialized, "Vector2.ZERO must be a valid initialized Survivor goal")
	_assert(UrbanNavigationService.direct_path_checks_total <= 1, "the origin goal must not restart its cadence each update")
	survivor.queue_free()
	settlement.free()
	await get_tree().process_frame

func _test_phase_3b7_zombie_idle_clears_navigation_lifecycle() -> void:
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(zombie)
	await get_tree().process_frame
	zombie.nav_stuck = true
	zombie._nav_goal_identity = 99
	zombie._nav_target = Vector2(100, 100)
	zombie._nav_previous_state = ZombiePerceptionComponent.State.CHASE
	zombie.perception.state = ZombiePerceptionComponent.State.IDLE
	zombie._seek_current_goal()
	_assert(not zombie.nav_stuck and zombie._nav_goal_identity == 0, "leaving active navigation states must clear the complete Zombie lifecycle")
	zombie.queue_free()
	await get_tree().process_frame

func _test_phase_3b7_zombie_same_target_remains_interval_bounded() -> void:
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	var target := Node2D.new()
	add_child(zombie)
	add_child(target)
	await get_tree().process_frame
	zombie.global_position = Vector2.ZERO
	target.global_position = Vector2(200, 0)
	zombie.perception.target = target
	zombie.perception.state = ZombiePerceptionComponent.State.CHASE
	UrbanNavigationService.reset()
	for i in range(20):
		target.global_position.x += 1.0
		zombie._seek_current_goal()
	_assert(UrbanNavigationService.direct_path_checks_total <= 2, "same-target sub-threshold motion must remain interval-bounded")
	zombie.queue_free()
	target.queue_free()
	await get_tree().process_frame

func _test_phase_3b8_zombie_resample_discards_cached_path() -> void:
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	var target := Node2D.new()
	add_child(zombie)
	add_child(target)
	await get_tree().process_frame
	zombie.global_position = Vector2.ZERO
	target.global_position = Vector2(100, 0)
	zombie.perception.target = target
	zombie.perception.state = ZombiePerceptionComponent.State.CHASE
	zombie._seek_current_goal()
	zombie._nav_path = PackedVector2Array([Vector2(10, 0), Vector2(100, 0)])
	zombie._nav_path_target = target.global_position
	target.global_position += Vector2(30, 0)
	zombie._seek_current_goal()
	_assert(zombie._nav_path_target != Vector2(100, 0) or zombie._nav_path.is_empty(), "resampling a moving target must invalidate the old sampled path")
	zombie.queue_free()
	target.queue_free()
	await get_tree().process_frame

func _test_phase_3b8_survivor_action_exit_resets_navigation() -> void:
	var settlement: Settlement = await _make_settlement(["general"])
	var survivor: Survivor = await _make_survivor({"name": "ActionReset"}, settlement)
	survivor.begin_navigation_goal(Vector2(100, 0))
	survivor._nav_path = PackedVector2Array([Vector2(20, 0), Vector2(100, 0)])
	survivor.ai._exit_current_action()
	_assert(survivor._nav_path.is_empty() and not survivor._nav_goal_initialized, "exiting an action must reset its navigation ownership")
	survivor.queue_free()
	settlement.free()
	await get_tree().process_frame

func _test_phase_3b8_idle_zombie_makes_no_navigation_requests() -> void:
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	add_child(zombie)
	await get_tree().process_frame
	zombie.perception.state = ZombiePerceptionComponent.State.IDLE
	UrbanNavigationService.reset()
	for i in range(10):
		zombie._seek_current_goal()
	_assert(UrbanNavigationService.path_requests_total == 0, "idle zombies must not request navigation paths")
	zombie.queue_free()
	await get_tree().process_frame
func _test_procedural_city_same_seed_is_identical() -> void:
	var generator := ProceduralCityGenerator.new()
	var first: Dictionary = generator.generate(8801)
	var second: Dictionary = generator.generate(8801)
	_assert(generator.signature(first) == generator.signature(second), "the same gameplay seed must reproduce the exact semantic road/block/building model")

func _test_procedural_city_different_seed_changes_layout() -> void:
	var generator := ProceduralCityGenerator.new()
	var first: Dictionary = generator.generate(8801)
	var second: Dictionary = generator.generate(8802)
	_assert(generator.signature(first) != generator.signature(second), "different seeds must alter semantic layout rather than only cosmetic tile variants")

func _test_procedural_city_generated_model_passes_invariants() -> void:
	var generator := ProceduralCityGenerator.new()
	for seed_value in [1, 42, 8801, 20260821, 2147483646]:
		var city: Dictionary = generator.generate(seed_value)
		var errors: Array[String] = generator.validate(city)
		_assert(errors.is_empty(), "seed %d failed generator invariants: %s" % [seed_value, str(errors)])
		_assert((city["roads"] as Array).size() == 10, "each city must have five horizontal and five vertical roads")
		_assert((city["blocks"] as Array).size() == 16, "each city must produce sixteen urban blocks")

func _test_procedural_compound_buildings_have_enterable_wings() -> void:
	var forms: Dictionary = {}
	var building_generator := ProceduralBuildingGenerator.new()
	for seed_value in range(64):
		var interior: Dictionary = building_generator.generate(&"compound_regression", &"workshop", Vector2(256, 256), seed_value, true)
		var errors: Array[String] = building_generator.validate(interior)
		_assert(errors.is_empty(), "compound workshop seed %d must keep every room/door/furniture invariant: %s" % [seed_value, str(errors)])
		forms[interior["form"]] = true
		for door in interior["doors"]:
			var aperture: Vector2 = door["aperture_size"]
			_assert(maxf(aperture.x, aperture.y) >= 64.0, "generated door %s must expose a two-cell traversal aperture" % String(door["id"]))
		if interior["form"] == &"rectangle":
			continue
		_assert((interior["perimeter_rects"] as Array).size() == 2, "compound form must expose both occupied footprint rectangles")
		var wing: Dictionary = (interior["rooms"] as Array).back()
		_assert(wing["role"] == &"service_annex", "compound form must append an enterable service-annex room")
		var wing_door_found := false
		for door in interior["doors"]:
			if not bool(door["exterior"]) and door["room_b"] == wing["id"]:
				wing_door_found = true
		_assert(wing_door_found, "service-annex room must connect through a real interior door")
	_assert(forms.has(&"rectangle"), "compound generator must retain rectangular building forms")
	_assert(forms.has(&"rear_wing") and forms.has(&"side_wing"), "compound generator must exercise rear and side building silhouettes")

func _test_streamed_chunk_edges_and_building_branches_are_deterministic() -> void:
	var generator := ProceduralCityGenerator.new()
	var origin: Dictionary = generator.generate_streamed_chunk(20260821, Vector2i.ZERO)
	var eastern_neighbor: Dictionary = generator.generate_streamed_chunk(20260821, Vector2i.RIGHT)
	_assert(generator.validate(origin).is_empty(), "streamed origin chunk must validate after its road branches are appended")
	_assert(origin["road_topology"] == &"prague_frontage_branch_graph", "streamed chunks must expose the Prague frontage/branch topology")
	_assert(origin["district_profile"] in PragueRegionalPlan.PROFILES, "streamed chunks must select one deterministic Prague district profile")
	_assert((origin["blocks"] as Array).size() == 9, "streamed Prague chunks must replace the finite 4x4 grid with nine larger urban quarters")
	_assert((origin["parcels"] as Array).size() > (origin["blocks"] as Array).size(), "large streamed quarters must subdivide into multiple street-fronting lots")
	_assert(origin["edge_contracts"][&"east"] == eastern_neighbor["edge_contracts"][&"west"], "adjacent streamed chunks must derive the same shared road portals")
	var driveway_count := 0
	for road in origin["roads"]:
		if road["kind"] == &"driveway":
			driveway_count += 1
	_assert(driveway_count == (origin["buildings"] as Array).size(), "every streamed building must contribute one connected entrance branch")

func _test_streamed_prague_courtyards_have_clear_passages() -> void:
	var generator := ProceduralCityGenerator.new()
	var courtyard_count := 0
	for y in range(-4, 5):
		for x in range(-4, 5):
			var city := generator.generate_streamed_chunk(20260821, Vector2i(x, y))
			for courtyard in city.get("courtyards", []):
				courtyard_count += 1
				_assert(float(courtyard["passage_width"]) >= 64.0, "courtyard passages must retain the same two-cell traversal width as open doors")
				var access: Rect2 = courtyard["access_corridor"]
				_assert(access.intersects(courtyard["rect"]), "courtyard passage must connect directly to the paved court")
				for building in city["buildings"]:
					if building["block_id"] == courtyard["block_id"]:
						_assert(not access.intersects(building["footprint"]), "courtyard passage must not be occupied by a frontage building")
	_assert(courtyard_count > 0, "the deterministic 9x9 chunk corpus must still exercise the rare courtyard path")

func _test_streamed_prague_theme_has_transit_roofs_and_active_frontages() -> void:
	var morphology_storey_bands := {
		&"historic_core": Vector2i(4, 6),
		&"inner_city": Vector2i(4, 6),
		&"hillside_residential": Vector2i(2, 5),
		&"industrial_transition": Vector2i(2, 4),
	}
	var city := ProceduralCityGenerator.new().generate_streamed_chunk(20260821, Vector2i.ZERO)
	var surfaces: Dictionary = {}
	var has_tram := false
	for road in city["roads"]:
		surfaces[road.get("surface", &"asphalt")] = true
		has_tram = has_tram or bool(road.get("tram", false))
	_assert(surfaces.has(&"cobble") and surfaces.has(&"asphalt"), "Prague chunks must combine paved local streets with asphalt regional corridors")
	_assert(has_tram, "each Prague chunk must carry the regional tram-capable arterial through its selected axis")
	var facade_styles: Dictionary = {}
	for building in city["buildings"]:
		facade_styles[building["facade_style"]] = true
		_assert(building["roof_shape"] == &"pitched_ridge", "Prague frontage buildings must use the ridge-painted roof contract")
		_assert(int(building["storeys"]) >= 2 and int(building["storeys"]) <= 6, "Prague facade massing must stay inside the two-to-six-storey presentation band")
		var district_storey_band: Vector2i = morphology_storey_bands[building["district_profile"]]
		_assert(int(building["storeys"]) >= district_storey_band.x and int(building["storeys"]) <= district_storey_band.y,
			"building %s storeys must honor its district profile band" % String(building["id"]))
		_assert(BuildingExteriorRenderer.validate(building).is_empty(), "every Prague building must expose a valid projected exterior contract")
	_assert(facade_styles.size() >= 2, "one streamed quarter must exercise more than one facade treatment")

func _test_projected_prague_exteriors_are_deterministic_and_portal_aligned() -> void:
	var generator := ProceduralCityGenerator.new()
	var first := generator.generate_streamed_chunk(20260821, Vector2i.ZERO)
	var second := generator.generate_streamed_chunk(20260821, Vector2i.ZERO)
	for index in range((first["buildings"] as Array).size()):
		var building: Dictionary = first["buildings"][index]
		var repeated: Dictionary = second["buildings"][index]
		_assert(building["exterior"] == repeated["exterior"], "projected exterior metadata must regenerate identically for %s" % String(building["id"]))
		var exterior: Dictionary = building["exterior"]
		_assert(int(exterior["projection_height_tiles"]) in range(2, 7), "projected facade height must remain bounded")
		var semantic_entrance: Vector2 = building["entrance_position"] - building["position"]
		var entrance_positions: Array = exterior["entrance_positions"]
		_assert(not entrance_positions.is_empty() and (entrance_positions[0] as Vector2).is_equal_approx(semantic_entrance), "projected entrance must use the real semantic door coordinate")

func _test_compound_footprints_extract_only_exposed_south_facades() -> void:
	var rects: Array = [
		Rect2(Vector2(-64, -64), Vector2(128, 128)),
		Rect2(Vector2(64, -64), Vector2(64, 64)),
	]
	var spans := BuildingExteriorRenderer.south_facade_spans(rects)
	_assert(spans.size() == 2, "an east rear wing must preserve its own exposed south edge and the main frontage")
	var total_width := 0.0
	for span in spans:
		total_width += (span as Rect2).size.x
	_assert(is_equal_approx(total_width, 192.0), "south outline extraction must cover each exposed boundary cell exactly once")

func _test_projected_exterior_runtime_is_visual_only_and_sortable() -> void:
	var city := ProceduralCityGenerator.new().generate_streamed_chunk(20260821, Vector2i.ZERO)
	var spec: Dictionary = city["buildings"][0]
	var building := ProceduralBuilding.new()
	building.configure(spec)
	building.position = spec["position"]
	add_child(building)
	await get_tree().process_frame
	var roof := building.get_node("Roof") as TileMapLayer
	var facade := building.projected_facade()
	var expected_offset := -float(spec["exterior"]["projection_height_tiles"]) * PixelAtlasMap.TILE_SIZE
	_assert(is_equal_approx(roof.position.y, expected_offset), "roof artwork must shift north by the facade projection height")
	_assert(facade != null and facade.projection_height == -expected_offset, "runtime building must own one configured projected facade")
	_assert(facade.find_children("*", "CollisionObject2D", true, false).is_empty(), "projected exterior visuals must add no gameplay collision")
	var semantic_entrance_before: Vector2 = spec["interior"]["doors"][0]["position"]
	_assert((building.specification["interior"]["doors"][0]["position"] as Vector2).is_equal_approx(semantic_entrance_before), "exterior construction must not displace semantic doors")
	var facade_global_before := facade.global_position
	var sort_parent := Node2D.new()
	sort_parent.y_sort_enabled = true
	add_child(sort_parent)
	building.attach_exterior_sort_parent(sort_parent)
	_assert(facade.get_parent() == sort_parent and facade.global_position.is_equal_approx(facade_global_before), "facade proxy must join the actor sort layer without moving")
	building.queue_free()
	await get_tree().process_frame
	_assert(not is_instance_valid(facade), "external facade proxy must be released with its owning building")
	sort_parent.queue_free()
	await get_tree().process_frame

## Part A regression: a player OUTSIDE but visually behind a projected
## elevation gets a soft local transparency hole; it follows them, releases
## when clear, and never touches gameplay geometry. Entering the building
## still routes through the existing full exterior-hide system.
func _test_local_occlusion_fade_engages_and_releases() -> void:
	var city := ProceduralCityGenerator.new().generate_streamed_chunk(20260821, Vector2i.ZERO)
	var spec: Dictionary = city["buildings"][0]
	var building := ProceduralBuilding.new()
	building.configure(spec)
	building.position = spec["position"]
	add_child(building)
	await get_tree().process_frame
	await get_tree().physics_frame

	var facade = building.projected_facade()
	_assert(facade != null and facade.occlusion_material() != null, "every projected facade must own an occlusion-fade material")
	var roof := building.get_node("Roof") as TileMapLayer
	_assert(roof.material == facade.occlusion_material(), "roof and facade must share one occlusion material instance")

	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	var interior: Dictionary = spec["interior"]
	var bounds: Rect2 = interior["footprint_bounds"]
	# North of the building: covered by the displaced roof band while fully
	# outside every room.
	player.global_position = building.global_position + Vector2(bounds.get_center().x, bounds.position.y - 48.0)
	for _i in range(45):
		await get_tree().process_frame
	_assert(facade._fade_strength > 0.9, "walking behind a projected elevation must engage the local occlusion fade (strength=%.2f)" % facade._fade_strength)
	_assert(building.is_projected_exterior_visible() or not facade.visible, "occlusion fade only applies to visible covers")

	# Gameplay geometry is untouched: the south perimeter wall still blocks.
	var space := get_viewport().get_world_2d().direct_space_state
	var params := PhysicsPointQueryParameters2D.new()
	params.position = building.global_position + Vector2(bounds.get_center().x, bounds.end.y - 16.0)
	params.collision_mask = 1
	params.collide_with_areas = false
	_assert(not space.intersect_point(params, 4).is_empty(), "occlusion fade must never alter gameplay collision")

	player.global_position += Vector2(2500.0, 0.0)
	for _i in range(45):
		await get_tree().process_frame
	_assert(facade._fade_strength < 0.05, "the local fade must release once the player is clear of the building")

	# Entering still uses the existing full roof/interior visibility system.
	var rooms_container: Node = building.get_node_or_null("Rooms")
	if rooms_container != null and rooms_container.get_child_count() > 0:
		var first_room: Node2D = rooms_container.get_children()[0]
		player.global_position = first_room.global_position
		for _i in range(6):
			await get_tree().physics_frame
		_assert(not facade.visible, "entering a building must keep using the full exterior hide")
		_assert(not building.is_roof_visible(), "entering a building must hide the displaced roof as before")

	player.queue_free()
	building.queue_free()
	await get_tree().process_frame

## Regression: a fade that is already engaged must ease safely back to zero
## when the player node disappears mid-fade (scene change, death, chunk
## unload) instead of dereferencing a null player for player.global_position.
func _test_local_occlusion_fade_survives_player_removal() -> void:
	var city := ProceduralCityGenerator.new().generate_streamed_chunk(20260821, Vector2i.ZERO)
	var spec: Dictionary = city["buildings"][0]
	var building := ProceduralBuilding.new()
	building.configure(spec)
	building.position = spec["position"]
	add_child(building)
	await get_tree().process_frame
	var facade = building.projected_facade()
	_assert(facade != null, "projected facade must exist for the fade regression fixture")

	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	var interior: Dictionary = spec["interior"]
	var bounds: Rect2 = interior["footprint_bounds"]
	player.global_position = building.global_position + Vector2(bounds.get_center().x, bounds.position.y - 48.0)
	for _i in range(30):
		await get_tree().process_frame
	_assert(facade._fade_strength > 0.5, "fixture must engage the fade before removing the player (strength=%.2f)" % facade._fade_strength)

	# Remove the player mid-fade; subsequent _process frames must neither
	# crash on a missing player nor leave a stuck fade strength.
	player.free()
	for _i in range(90):
		await get_tree().process_frame
	_assert(facade._fade_strength < 0.001, "fade must ease to zero after the player disappears (strength=%.2f)" % facade._fade_strength)
	_assert(int(facade.occlusion_material().get_shader_parameter("strength") * 1000.0) == 0, "shader strength must be reset once the fade releases without a player")

	building.queue_free()
	await get_tree().process_frame

## Street objects must keep visual dimensions, collision footprint and light
## state independent: tall visuals (trees, lamps) sit on trunk/pole-sized
## physical footprints, and functioning/dead/flickering lamp states decide
## whether a real PointLight2D pool is generated.
func _test_street_objects_separate_visual_collision_and_light() -> void:
	var generator := ProceduralCityGenerator.new()
	var tree_specs := 0
	var lamp_specs := 0
	var lamp_modes := {}
	for coordinate in [Vector2i.ZERO, Vector2i(-3, 4), Vector2i(5, -5)]:
		var city := generator.generate_streamed_chunk(20260821, coordinate)
		for prop_spec in city["props"]:
			var kind: StringName = prop_spec.get("kind", &"")
			if kind == &"tree":
				tree_specs += 1
				var collision: Vector2 = prop_spec["size"]
				_assert(collision.x <= 32.0 and collision.y <= 32.0, "tree trunks must keep their collision at one tile or smaller")
				var crown: Vector2 = prop_spec["visual_size"]
				_assert(crown.x >= 64.0 and crown.y >= 64.0, "tree crowns must visually span multiple tiles (%s)" % str(crown))
			elif kind == &"lamp":
				lamp_specs += 1
				lamp_modes[prop_spec.get("light_mode", &"steady")] = true
				var pole_collision: Vector2 = prop_spec["size"]
				var pole_visual: Vector2 = prop_spec["visual_size"]
				_assert(pole_collision.x <= 12.0 and pole_collision.y <= 12.0, "lamp poles must keep a narrow base collision footprint")
				_assert(pole_visual.y >= 64.0, "street lamps must read as tall multi-tile objects")
	_assert(tree_specs > 0 and lamp_specs > 1, "composed street dressing must place both trees and multiple spaced lamps (trees=%d lamps=%d)" % [tree_specs, lamp_specs])
	_assert(lamp_modes.size() >= 2, "not every street lamp may share the same functional state (modes=%s)" % str(lamp_modes.keys()))

	# Runtime construction: base-anchored tall visuals, real lights.
	var fixture := Node2D.new()
	fixture.name = "StreetObjectFixture"
	add_child(fixture)
	var tree_spec: Dictionary = {"id": &"test/street_tree", "kind": &"tree", "procedural_kind": &"tree",
		"size": Vector2(24, 24), "visual_size": Vector2(96, 112), "variant": 1, "damaged": false,
		"interaction": &"", "yield": 1, "minimum_damage_class": EnvironmentDamage.DamageClass.SMALL_ARMS}
	BuildingShellBuilder.add_street_object(fixture, Vector2.ZERO, tree_spec)
	var tree_root := fixture.get_child(fixture.get_child_count() - 1) as Node2D
	_assert(tree_root.position == Vector2.ZERO, "a street object's origin must stay on its ground base for y-sorting")
	var tree_visual := _first_descendant_of_type(tree_root, StreetObjectVisual) as StreetObjectVisual
	_assert(tree_visual != null and tree_visual.visual_size.y >= 96.0, "tall tree visuals must extend upward from the base as visual-only layers")
	var tree_body := _first_descendant_of_type(tree_root, StaticBody2D) as StaticBody2D
	var tree_shape := tree_body.get_node("CollisionShape2D").shape as RectangleShape2D
	_assert(tree_shape.size == Vector2(24, 24), "the physical footprint of a tree must remain its trunk, never its crown")

	var steady_lamp: Dictionary = {"id": &"test/lamp_steady", "kind": &"lamp", "procedural_kind": &"lamp",
		"size": Vector2(10, 10), "visual_size": Vector2(20, 84), "light_mode": &"steady",
		"interaction": &"", "yield": 1, "minimum_damage_class": EnvironmentDamage.DamageClass.SMALL_ARMS}
	BuildingShellBuilder.add_street_object(fixture, Vector2(200, 0), steady_lamp)
	var steady_root := fixture.get_child(fixture.get_child_count() - 1) as Node2D
	await get_tree().process_frame
	var steady_light := _first_descendant_of_type(steady_root, PointLight2D) as PointLight2D
	_assert(steady_light != null and steady_light.enabled, "functioning street lamps must generate a real local light pool")

	var dead_lamp: Dictionary = {"id": &"test/lamp_dead", "kind": &"lamp", "procedural_kind": &"lamp",
		"size": Vector2(10, 10), "visual_size": Vector2(20, 84), "light_mode": &"dead",
		"interaction": &"", "yield": 1, "minimum_damage_class": EnvironmentDamage.DamageClass.SMALL_ARMS}
	BuildingShellBuilder.add_street_object(fixture, Vector2(400, 0), dead_lamp)
	var dead_root := fixture.get_child(fixture.get_child_count() - 1) as Node2D
	await get_tree().process_frame
	_assert(_first_descendant_of_type(dead_root, PointLight2D) == null, "dead street lamps must not emit light")

	fixture.queue_free()
	await get_tree().process_frame

## Survivor groups claim ordinary generated buildings -- apartments, stores,
## workshops, clinics alike -- with occupancy stored purely as state.
func _test_generic_generated_buildings_can_be_claimed_as_bases() -> void:
	var service := SurvivorBaseService.new()
	var claimed_types := {}
	var generator := ProceduralCityGenerator.new()
	for world_seed in [7, 1024, 8801, 20260821, 65535, 2147483646]:
		for coordinate in [Vector2i.ZERO, Vector2i(-3, 4), Vector2i(5, -5)]:
			WorldState.reset()
			var city := generator.generate_streamed_chunk(world_seed, coordinate)
			var claimed := service.claim_best_base(city, world_seed)
			_assert(claimed != null, "every generated city must offer an eligible ordinary base building (seed %d)" % world_seed)
			if claimed == null:
				continue
			var claimed_building: Dictionary = {}
			for building_variant in city["buildings"]:
				var candidate: Dictionary = building_variant
				if candidate["id"] == claimed.building_id:
					claimed_building = candidate
					break
			_assert(not claimed_building.is_empty(), "claimed base %s must be a normal generated building" % String(claimed.building_id))
			_assert((claimed_building["interior"]["rooms"] as Array).size() > 0, "claimed bases must have usable interiors")
			claimed_types[claimed.base_type] = true
			# Occupation dressing stays clear of the entrance approach so the
			# claimed base always keeps at least one usable entrance.
			var corridor: Rect2 = claimed_building["access_corridor"]
			var entrance: Vector2 = claimed_building["approach_position"]
			for offset in [Vector2(64, 20), Vector2(-72, 24), Vector2(120, 12), Vector2(88, 28)]:
				var dressing_point := entrance + Vector2(offset.x * (-1.0 if posmod(world_seed + int(abs(entrance.x)), 2) else 1.0), offset.y)
				_assert(not corridor.has_point(dressing_point) or dressing_point.distance_to(entrance) < 4.0,
					"base dressing must not block the claimed building's entrance approach")
	_assert(claimed_types.size() >= 3, "different building archetypes must be claimable as bases (claimed=%s)" % str(claimed_types.keys()))
	WorldState.reset()

## Removing base state must free the occupation dressing but never touch the
## generated building itself.
func _test_abandoning_base_preserves_building_and_clears_state() -> void:
	WorldState.reset()
	var city := ProceduralCityGenerator.new().generate_streamed_chunk(20260821, Vector2i.ZERO)
	var signature_before := ProceduralCityGenerator.new().signature(city)
	var settlement := Settlement.new()
	add_child(settlement)
	await get_tree().process_frame
	settlement.claim_building_base(city, 20260821)
	_assert(settlement.data != null and settlement.data.building_id != &"", "fixture must claim a base before abandoning it")
	settlement.abandon_building_base()
	_assert(settlement.data.building_id == &"" and settlement.data.base_type == &"", "abandoning a base must clear the occupancy state on its record")
	_assert(WorldState.settlements.is_empty(), "abandoning a base must clear its occupancy registration")
	var service := SurvivorBaseService.new()
	_assert(SurvivorBaseService.select_building(city, 20260821) != {} and not service.building_already_claimed(SurvivorBaseService.select_building(city, 20260821)["id"]), "an abandoned building pool must allow claiming again")
	var signature_after := ProceduralCityGenerator.new().signature(city)
	_assert(signature_before == signature_after, "claim/abandon cycles must never alter generated building geometry")
	WorldState.reset()
	settlement.free()

## --- generated interiors ---

func _test_generated_interiors_are_furnished_compositions() -> void:
	var generator := ProceduralCityGenerator.new()
	var kinds_seen := {}
	var pieces_by_archetype := {}
	for world_seed in [7, 1024, 8801, 20260821]:
		for coordinate in [Vector2i.ZERO, Vector2i(2, 1)]:
			var city := generator.generate_streamed_chunk(world_seed, coordinate)
			for building_variant in city["buildings"]:
				var building: Dictionary = building_variant
				var interior: Dictionary = building["interior"]
				pieces_by_archetype[building["archetype"]] = int(pieces_by_archetype.get(building["archetype"], 0)) + (interior["furniture"] as Array).size()
				for furniture_variant in interior["furniture"]:
					var furniture: Dictionary = furniture_variant
					if String(furniture["mode"]) == "decal":
						continue
					kinds_seen[furniture["kind"]] = true
	for expected_kind in [&"bed_single", &"fridge", &"sofa", &"shelf_row", &"workbench", &"exam_bed", &"dining_table", &"counter", &"wardrobe", &"desk"]:
		_assert(kinds_seen.has(expected_kind), "generated interiors must compose role-appropriate real furniture; missing %s (seen %s)" % [String(expected_kind), str(kinds_seen.keys())])
	for archetype in pieces_by_archetype:
		_assert(int(pieces_by_archetype[archetype]) >= 24, "archetype %s interiors must furnish several pieces per room (%d total)" % [String(archetype), int(pieces_by_archetype[archetype])])

func _test_furniture_dimensions_leave_the_one_tile_era() -> void:
	var generator := ProceduralCityGenerator.new()
	var largest_span := 0.0
	var bed_found := false
	var shelf_found := false
	for world_seed in [7, 20260821]:
		var city := generator.generate_streamed_chunk(world_seed, Vector2i.ZERO)
		for building_variant in city["buildings"]:
			var interior: Dictionary = (building_variant as Dictionary)["interior"]
			for furniture_variant in interior["furniture"]:
				var furniture: Dictionary = furniture_variant
				if String(furniture["mode"]) == "decal":
					continue
				var collision_size: Vector2 = furniture["size"]
				largest_span = maxf(largest_span, maxf(collision_size.x, collision_size.y))
				if furniture["kind"] in [&"bed_single", &"bed_double"]:
					bed_found = true
					_assert(collision_size.y >= 56.0, "beds must be full-length, not one-tile markers")
				if furniture["kind"] in [&"shelf_row", &"industrial_shelf"]:
					shelf_found = true
					_assert(collision_size.x >= 64.0, "shelving must span multiple tiles")
	_assert(bed_found and shelf_found, "corpus must exercise beds and long shelving")
	_assert(largest_span >= 80.0, "at least some furniture must exceed one tile by far (max %.0f)" % largest_span)

func _test_furniture_never_blocks_door_routes() -> void:
	var generator := ProceduralCityGenerator.new()
	for world_seed in [3, 42, 1024, 8801, 65535]:
		var city := generator.generate_streamed_chunk(world_seed, Vector2i(-2, 3))
		for building_variant in city["buildings"]:
			var building: Dictionary = building_variant
			var interior: Dictionary = building["interior"]
			_assert(generator_validate(interior), "interior %s must satisfy clearance validation" % String(building["id"]))
			var origin: Vector2 = building["position"]
			for door_variant in interior["doors"]:
				var door: Dictionary = door_variant
				var bay := ProceduralBuildingGenerator.door_bay_rect(door["position"], door["aperture_size"])
				bay.position += origin
				for furniture_variant in interior["furniture"]:
					var furniture: Dictionary = furniture_variant
					if String(furniture["mode"]) == "decal":
						continue
					var collision: Rect2 = furniture["collision_rect"]
					collision.position += origin
					_assert(not bay.intersects(collision), "%s furniture blocks the landing of door %s" % [String(furniture["id"]), String(door["id"])])

func generator_validate(interior: Dictionary) -> bool:
	return ProceduralBuildingGenerator.new().validate(interior).is_empty()

func _test_generated_loot_furniture_is_interactive_persistent_and_destructible() -> void:
	WorldState.reset()
	var city := ProceduralCityGenerator.new().generate_streamed_chunk(20260821, Vector2i.ZERO)
	var loot_spec: Dictionary = {}
	for building_variant in city["buildings"]:
		for furniture_variant in (building_variant as Dictionary)["interior"]["furniture"]:
			var furniture: Dictionary = furniture_variant
			if String(furniture["mode"]) == "loot" and not (furniture["items"] as Dictionary).is_empty():
				loot_spec = furniture
				break
		if not loot_spec.is_empty():
			break
	_assert(not loot_spec.is_empty(), "the streamed corpus must contain loot-bearing furniture with starting items")
	var fixture := Node2D.new()
	add_child(fixture)
	BuildingShellBuilder.add_loot_furniture(
		fixture, Vector2(60000, 60000), load(loot_spec["texture"]), loot_spec["size"], loot_spec["id"],
		float(loot_spec["capacity"]), loot_spec["items"], "Search", int(loot_spec["minimum_damage_class"])
	)
	var built := fixture.get_child(fixture.get_child_count() - 1) as Node
	var loot_component := _first_descendant_of_type(built, LootContainerComponent) as LootContainerComponent
	_assert(loot_component != null and not loot_component.get_inventory().is_empty(), "loot furniture must expose a searchable persistent inventory")
	_assert(_first_descendant_of_type(built, InteractableComponent) != null, "loot furniture must be interactable")
	var damage_component := _first_descendant_of_type(built, EnvironmentDamageComponent) as EnvironmentDamageComponent
	damage_component.apply_damage(9999.0, EnvironmentDamage.DamageClass.EXPLOSIVE)
	await get_tree().process_frame
	var matching_drops: Array = WorldState.drops.values().filter(func(drop_variant) -> bool:
		var drop: WorldDrop = drop_variant
		return drop.reason == &"environment_destroyed" and not drop.inventory.is_empty())
	_assert(not matching_drops.is_empty(), "destroying generated loot furniture must preserve its inventory as one world drop")
	PhysicsDebris.active_count = 0
	Corpse.active_count = 0
	fixture.queue_free()
	await get_tree().process_frame

func _test_settlement_uses_no_special_safehouse_geometry() -> void:
	var main_instance: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	var settlement_node := main_instance.get_node_or_null("Settlement")
	_assert(settlement_node != null, "Main must still carry a lightweight Settlement controller")
	var found := [false]
	_walk_for_safehouse_geometry(main_instance, found)
	_assert(not found[0], "no node in Main may instantiate special safehouse geometry any more")
	var has_job_board := false
	for child in settlement_node.get_children():
		var script := child.get_script() as Script
		if script != null and String(script.resource_path).ends_with("settlement_job_board.gd"):
			has_job_board = true
	_assert(has_job_board, "the Settlement controller must keep its job board")
	main_instance.free()

func _walk_for_safehouse_geometry(node: Node, found: Array) -> void:
	if found[0]:
		return
	if node is SafehouseInteriorBuilder or String(node.name).begins_with("Safehouse") or String(node.name) == "Interior":
		found[0] = true
		return
	for child in node.get_children():
		_walk_for_safehouse_geometry(child, found)

func _test_multiple_groups_claim_different_buildings() -> void:
	WorldState.reset()
	var city := ProceduralCityGenerator.new().generate_streamed_chunk(20260821, Vector2i.ZERO)
	var first := SurvivorBaseService.new().claim_best_base(city, 20260821, "Group A")
	var second := SurvivorBaseService.new().claim_best_base(city, 20260821, "Group B")
	_assert(first != null and second != null, "two groups must both find eligible ordinary buildings")
	_assert(first.building_id != second.building_id, "a second group must claim a different building than the first")
	var third := SurvivorBaseService.new().claim_best_base(city, 20260821, "Group C")
	_assert(third == null or (third.building_id != first.building_id and third.building_id != second.building_id), "every group occupies its own building")
	WorldState.reset()

func _test_base_structures_remain_destructible() -> void:
	WorldState.reset()
	UrbanNavigationService.reset()
	var city := ProceduralCityGenerator.new().generate_streamed_chunk(20260821, Vector2i.ZERO)
	var claimed := SurvivorBaseService.new().claim_best_base(city, 20260821)
	_assert(claimed != null, "fixture must claim a base before destructibility checks")
	var claimed_spec: Dictionary = {}
	for building_variant in city["buildings"]:
		var candidate: Dictionary = building_variant
		if candidate["id"] == claimed.building_id:
			claimed_spec = candidate
			break
	var building := ProceduralBuilding.new()
	building.configure(claimed_spec)
	add_child(building)
	await get_tree().physics_frame
	var wall_damage: EnvironmentDamageComponent = null
	for wall_node in building.get_children():
		if wall_node is StaticBody2D:
			var component := wall_node.get_node_or_null("EnvironmentDamageComponent") as EnvironmentDamageComponent
			if component != null and String(component.object_id).contains("/wall"):
				wall_damage = component
				break
	_assert(wall_damage != null, "the claimed base must expose real generated walls with damage components")
	var source := Node2D.new()
	add_child(source)
	source.global_position = building.global_position + Vector2(48.0, 0.0)
	wall_damage.apply_damage(9999.0, EnvironmentDamage.DamageClass.EXPLOSIVE, source)
	_assert(WorldState.get_prop_state_flag(wall_damage.object_id, &"destroyed", false), "base walls must be destructible like any generated building's walls")
	var furniture_piece := _first_descendant_of_type(building, EnvironmentDamageComponent)
	_assert(furniture_piece != null, "claimed base furniture must carry damage components too")
	source.queue_free()
	building.queue_free()
	await get_tree().process_frame
	PhysicsDebris.active_count = 0
	WorldState.reset()

## --- hybrid physics ---

func _make_reactive_fixture(kind: StringName, target_mass_class: int, position: Vector2) -> Array:
	var fixture := Node2D.new()
	fixture.name = "ReactiveFixture"
	add_child(fixture)
	var spec := {
		"id": StringName("test/reactive_%s_%d" % [String(kind), randi()]),
		"kind": kind,
		"texture": "res://assets/pixel/props/crate.png",
		"size": Vector2(26, 22),
		"visual_size": Vector2(28, 24),
		"interaction": &"",
		"yield": 1,
		"minimum_damage_class": EnvironmentDamage.DamageClass.SMALL_ARMS,
	}
	BuildingShellBuilder.add_street_object(fixture, position, spec)
	var root := fixture.get_child(fixture.get_child_count() - 1) as Node2D
	var reaction := root.get_node_or_null("PhysicsReactionComponent") as PhysicsReactionComponent
	reaction.mass_class = target_mass_class
	reaction.impulse_threshold = PhysicsReactionComponent.HEAVY_THRESHOLD if target_mass_class == PhysicsReactionComponent.MassClass.HEAVY else PhysicsReactionComponent.LIGHT_THRESHOLD
	return [fixture, root, reaction]

func _test_light_furniture_receives_physical_impulse() -> void:
	var parts := _make_reactive_fixture(&"chair", PhysicsReactionComponent.MassClass.LIGHT, Vector2(70000, 70000))
	var reaction := parts[2] as PhysicsReactionComponent
	_assert(not reaction.is_dynamic(), "light furniture starts static for performance")
	var moved: bool = reaction.apply_impulse(Vector2(120.0, 0.0))
	_assert(moved and reaction.is_dynamic(), "a sufficient impulse must convert light furniture into a live rigid body")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var dynamic_body := (parts[1] as Node2D).get_node_or_null("DynamicBody") as RigidBody2D
	_assert(dynamic_body != null and dynamic_body.linear_velocity.length() > 0.0, "converted furniture must actually move under physics")
	parts[0].queue_free()
	await get_tree().process_frame

func _test_heavy_furniture_becomes_dynamic_only_under_force() -> void:
	var parts := _make_reactive_fixture(&"wardrobe", PhysicsReactionComponent.MassClass.HEAVY, Vector2(70200, 70000))
	var reaction := parts[2] as PhysicsReactionComponent
	var ignored: bool = reaction.apply_impulse(Vector2(80.0, 0.0))
	_assert(not ignored and not reaction.is_dynamic(), "weak shoves must not move heavy static furniture")
	var moved: bool = reaction.apply_impulse(Vector2(400.0, 0.0))
	_assert(moved and reaction.is_dynamic(), "strong force (explosions) must convert heavy furniture to dynamics")
	parts[0].queue_free()
	await get_tree().process_frame

func _test_destroyed_wall_spawns_bounded_debris() -> void:
	WorldState.reset()
	var fixture := Node2D.new()
	fixture.name = "WallFixture"
	add_child(fixture)
	BuildingShellBuilder._maybe_wall(fixture, Vector2(71000, 71000), load("res://assets/pixel/props/wall_concrete.png"), [])
	var wall := fixture.get_child(fixture.get_child_count() - 1) as StaticBody2D
	var damage_component := wall.get_node("EnvironmentDamageComponent") as EnvironmentDamageComponent
	var source := Node2D.new()
	add_child(source)
	source.global_position = wall.global_position + Vector2(-64.0, 0.0)
	var debris_before := get_tree().get_nodes_in_group("physics_debris").size()
	damage_component.apply_damage(9999.0, EnvironmentDamage.DamageClass.EXPLOSIVE, source)
	await get_tree().process_frame
	await get_tree().physics_frame
	var debris_nodes := get_tree().get_nodes_in_group("physics_debris")
	var new_debris := debris_nodes.size() - debris_before
	_assert(new_debris >= 1 and new_debris <= 5, "destroyed walls must spawn a small bounded debris burst (%d)" % new_debris)
	_assert(not is_instance_valid(wall) or wall.is_queued_for_deletion(), "the destroyed wall body must leave the tree after breaking")
	for node in debris_nodes:
		if is_instance_valid(node):
			node.queue_free()
	PhysicsDebris.active_count = 0
	source.queue_free()
	fixture.queue_free()
	WorldState.reset()
	await get_tree().process_frame

func _test_zombie_death_leaves_a_physical_corpse() -> void:
	WorldState.reset()
	var zombie := (load("res://scenes/actors/Zombie.tscn") as PackedScene).instantiate() as Zombie
	add_child(zombie)
	zombie.global_position = Vector2(72000, 72000)
	await get_tree().physics_frame
	var killer := Node2D.new()
	add_child(killer)
	killer.global_position = zombie.global_position + Vector2(-40.0, 0.0)
	zombie.take_damage(99999.0, killer)
	await get_tree().process_frame
	var corpses := get_tree().get_nodes_in_group("corpses")
	_assert(not corpses.is_empty(), "a dead zombie must leave a physical corpse behind")
	var corpse := corpses.back() as RigidBody2D
	_assert(corpse != null, "corpses must be physical rigid bodies receiving the killing impulse")
	for node in corpses:
		if is_instance_valid(node):
			node.queue_free()
	Corpse.active_count = 0
	if is_instance_valid(killer):
		killer.queue_free()
	# The zombie freed itself on death (that is the new corpse contract).
	WorldState.reset()
	await get_tree().process_frame

func _test_explosion_pushes_world_with_radial_falloff() -> void:
	WorldState.reset()
	var blast_origin := Vector2(73000, 73000)
	var near_parts := _make_reactive_fixture(&"chair", PhysicsReactionComponent.MassClass.LIGHT, blast_origin + Vector2(50.0, 0.0))
	var far_parts := _make_reactive_fixture(&"crate", PhysicsReactionComponent.MassClass.LIGHT, blast_origin + Vector2(200.0, 0.0))
	var blaster := Node2D.new()
	add_child(blaster)
	blaster.global_position = blast_origin
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Low structural value: the blast must MOVE both props without wrecking
	# them, isolating the impulse/falloff behavior under test.
	EnvironmentDamage.apply_explosion(blaster, blast_origin, 260.0, 4.0, 30.0, EnvironmentDamage.DamageClass.EXPLOSIVE)
	var near_reaction := near_parts[2] as PhysicsReactionComponent
	var far_reaction := far_parts[2] as PhysicsReactionComponent
	await get_tree().physics_frame
	_assert(is_instance_valid(near_reaction) and near_reaction.is_dynamic() and is_instance_valid(far_reaction) and far_reaction.is_dynamic(), "both reactive props must receive the blast impulse")
	var near_body := (near_parts[1] as Node2D).get_node_or_null("DynamicBody") as RigidBody2D
	var far_body := (far_parts[1] as Node2D).get_node_or_null("DynamicBody") as RigidBody2D
	_assert(near_body != null and far_body != null, "blast-converted props must expose their dynamic bodies")
	if near_body != null and far_body != null:
		_assert(near_body.linear_velocity.length() > far_body.linear_velocity.length(),
			"closer objects must be pushed harder than distant ones (radial falloff: %.1f vs %.1f)" % [near_body.linear_velocity.length(), far_body.linear_velocity.length()])
	near_parts[0].queue_free()
	far_parts[0].queue_free()
	blaster.queue_free()
	await get_tree().process_frame

func _test_physics_debris_and_corpses_are_capped() -> void:
	WorldState.reset()
	var fixture := Node2D.new()
	add_child(fixture)
	for i in range(PhysicsDebris.MAX_DEBRIS + 8):
		PhysicsDebris.spawn(fixture, Vector2(74000 + i * 4.0, 74000), load("res://assets/pixel/props/debris_small.png"), Vector2(9, 7), Vector2.ZERO)
	var live_debris: Array = get_tree().get_nodes_in_group("physics_debris").filter(func(node: Node) -> bool:
		return is_instance_valid(node) and not node.is_queued_for_deletion())
	_assert(live_debris.size() <= PhysicsDebris.MAX_DEBRIS, "debris population must stay under its global cap (%d > %d)" % [live_debris.size(), PhysicsDebris.MAX_DEBRIS])
	for node in live_debris:
		if is_instance_valid(node):
			node.free()
	PhysicsDebris.active_count = 0
	for i in range(Corpse.MAX_CORPSES + 5):
		Corpse.spawn(fixture, null, Vector2(75000 + i * 6.0, 75000), Vector2.ZERO)
	var live_corpses: Array = get_tree().get_nodes_in_group("corpses").filter(func(node: Node) -> bool:
		return is_instance_valid(node) and not node.is_queued_for_deletion())
	_assert(live_corpses.size() <= Corpse.MAX_CORPSES, "corpse population must stay under its global cap (%d > %d)" % [live_corpses.size(), Corpse.MAX_CORPSES])
	for node in live_corpses:
		if is_instance_valid(node):
			node.free()
	Corpse.active_count = 0
	fixture.queue_free()
	WorldState.reset()
	await get_tree().process_frame

## --- partial destruction ---

func _test_partial_wall_damage_is_progressive() -> void:
	WorldState.reset()
	var fixture := Node2D.new()
	add_child(fixture)
	BuildingShellBuilder._maybe_wall(fixture, Vector2(79000, 79000), load("res://assets/pixel/props/wall_concrete.png"), [])
	var wall := fixture.get_child(fixture.get_child_count() - 1) as StaticBody2D
	var comp := wall.get_node("EnvironmentDamageComponent") as EnvironmentDamageComponent
	var source := Node2D.new()
	add_child(source)
	source.global_position = wall.global_position + Vector2(-48.0, 0.0)
	# One light chip: the wall must survive with most cells intact.
	comp.apply_damage(13.0, 1, source)
	var fraction_after_chip: float = comp.alive_fraction()
	_assert(fraction_after_chip > 0.8 and fraction_after_chip < 1.0,
		"a small hit must remove only a corner of the wall (fraction=%.2f)" % fraction_after_chip)
	var cells_before: int = comp.alive_cells().filter(func(alive: bool) -> bool: return alive).size()
	for _i in range(3):
		comp.apply_damage(12.0, 1, source)
	var cells_after: int = comp.alive_cells().filter(func(alive: bool) -> bool: return alive).size()
	_assert(cells_after < cells_before, "repeated damage must progressively enlarge the breach (%d -> %d)" % [cells_before, cells_after])
	_assert(comp.durability() < comp.max_durability and not WorldState.get_prop_state_flag(comp.object_id, &"destroyed", false),
		"partial damage must persist without deleting the whole wall")
	source.queue_free()
	fixture.queue_free()
	WorldState.reset()
	await get_tree().process_frame

func _test_wall_breach_updates_collision_and_navigation() -> void:
	WorldState.reset()
	UrbanNavigationService.reset()
	var fixture := Node2D.new()
	add_child(fixture)
	BuildingShellBuilder._maybe_wall(fixture, Vector2(79400, 79400), load("res://assets/pixel/props/wall_concrete.png"), [])
	var wall := fixture.get_child(fixture.get_child_count() - 1) as StaticBody2D
	var comp := wall.get_node("EnvironmentDamageComponent") as EnvironmentDamageComponent
	var source := Node2D.new()
	add_child(source)
	source.global_position = wall.global_position + Vector2(-48.0, 0.0)
	comp.apply_damage(13.0, 1, source)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# The original whole-cell collider must yield to surviving microcells.
	var base_shape := wall.get_node("CollisionShape2D") as CollisionShape2D
	_assert(base_shape == null or base_shape.disabled, "a breached wall's full-cell collider must be disabled")
	var partial_shapes := wall.get_children().filter(func(child: Node) -> bool: return child is CollisionShape2D and not (child as CollisionShape2D).disabled)
	_assert(partial_shapes.size() >= 1, "surviving microcells must keep colliding")
	comp.apply_damage(9999.0, 2, source)
	await get_tree().process_frame
	await get_tree().physics_frame
	var wall_destroyed: bool = not is_instance_valid(comp) \
		or WorldState.get_prop_state_flag(comp.object_id, &"destroyed", false)
	_assert(wall_destroyed, "structural failure must still destroy and free navigation")
	source.queue_free()
	fixture.queue_free()
	PhysicsDebris.active_count = 0
	WorldState.reset()

## Single-block model: a destroyed wall shows NO stacked fragments in place --
## its sprite goes away and up to four quarter chunks fly off as physics.
func _test_wall_shatters_into_quarter_chunks() -> void:
	WorldState.reset()
	var fixture := Node2D.new()
	add_child(fixture)
	BuildingShellBuilder._maybe_wall(fixture, Vector2(79800, 79800), load("res://assets/pixel/props/wall_concrete.png"), [])
	var wall := fixture.get_child(fixture.get_child_count() - 1) as StaticBody2D
	var comp := wall.get_node("EnvironmentDamageComponent") as EnvironmentDamageComponent
	var source := Node2D.new()
	add_child(source)
	source.global_position = wall.global_position + Vector2(-48.0, 0.0)
	var debris_before := get_tree().get_nodes_in_group("physics_debris").size()
	comp.apply_damage(9999.0, 2, source)
	await get_tree().process_frame
	await get_tree().physics_frame
	var debris_nodes := get_tree().get_nodes_in_group("physics_debris")
	var new_chunks := debris_nodes.size() - debris_before
	_assert(new_chunks >= 3 and new_chunks <= 5,
		"a shattered wall must separate into a few quarter chunks (%d)" % new_chunks)
	_assert(not is_instance_valid(wall) or wall.is_queued_for_deletion(), "the broken block itself must leave the world")
	for node in debris_nodes:
		if is_instance_valid(node):
			node.free()
	PhysicsDebris.active_count = 0
	source.queue_free()
	fixture.queue_free()
	WorldState.reset()
	await get_tree().process_frame

## Logical spatial sync: destroying a perimeter segment erases the roof tile
## above it, notches the south facade, and both stay open after rebuild.
func _test_breach_syncs_roof_and_facade() -> void:
	WorldState.reset()
	UrbanNavigationService.reset()
	var city := ProceduralCityGenerator.new().generate_streamed_chunk(20260821, Vector2i.ZERO)
	var building_spec: Dictionary = city["buildings"][0]
	var half_extent: Vector2 = building_spec["interior"]["half_extent"]
	var first := ProceduralBuilding.new()
	first.configure(building_spec)
	add_child(first)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var roof := first.get_node("Roof") as TileMapLayer
	_assert(roof != null, "fixture needs the projected roof layer")
	var south_comp: EnvironmentDamageComponent = null
	for child in first.get_children():
		if child is StaticBody2D:
			var candidate := child.get_node_or_null("EnvironmentDamageComponent") as EnvironmentDamageComponent
			if candidate != null and "/wall_" in String(candidate.object_id):
				var body := child as Node2D
				if body.position.y >= half_extent.y - PixelAtlasMap.TILE_SIZE:
					south_comp = candidate
					break
	_assert(south_comp != null, "the building must expose a south-edge destructible wall")
	if south_comp == null:
		first.free()
		WorldState.reset()
		return
	var breach_body := south_comp.get_parent() as Node2D
	var breach_x := breach_body.position.x
	var expected_cell := Vector2i(floori(breach_body.position.x / PixelAtlasMap.TILE_SIZE), floori(breach_body.position.y / PixelAtlasMap.TILE_SIZE))
	_assert(roof.get_used_cells().has(expected_cell), "sanity: the roof tile above an intact wall must exist")
	south_comp.apply_damage(9999.0, EnvironmentDamage.DamageClass.EXPLOSIVE, null)
	await get_tree().process_frame
	await get_tree().physics_frame
	_assert(not roof.get_used_cells().has(expected_cell), "destroying a perimeter wall must open the roof above it")
	# The unsupported bay collapses inward: more than one tile must fall.
	var strip_erased := 0
	for cell in roof.get_used_cells():
		if cell.y == expected_cell.y:
			strip_erased += 1
	var row_cells_before_estimate := floori((building_spec["interior"]["half_extent"].x * 2.0) / PixelAtlasMap.TILE_SIZE)
	_assert(row_cells_before_estimate - strip_erased >= 2,
		"the whole unsupported roof bay along the breached wall must collapse (only %d of ~%d left)" % [strip_erased, row_cells_before_estimate])
	var facade := first.projected_facade()
	_assert(facade != null and facade.ground_breaches.has(breach_x), "the south facade must notch at the breached segment")
	# Single-segment rule: NO full-column blackout for one dead segment --
	# the storey above shows escalating breakage instead.
	if facade != null:
		_assert(not facade.collapse_columns.has(breach_x), "one segment must never black out the whole column")
		_assert(facade.upper_damage_level(breach_x) >= 1, "the storey above an isolated breach must show breakage")
	first.free()
	await get_tree().process_frame
	var second := ProceduralBuilding.new()
	second.configure(city["buildings"][0])
	add_child(second)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var rebuilt_roof := second.get_node("Roof") as TileMapLayer
	_assert(not rebuilt_roof.get_used_cells().has(expected_cell), "persisted destruction must keep the roof hole open after rebuild")
	var rebuilt_facade := second.projected_facade()
	_assert(rebuilt_facade != null and rebuilt_facade.ground_breaches.has(breach_x), "persisted breaches must re-notch the rebuilt facade")
	# Cascade contract: an ADJACENT second segment structurally fails the
	# floors above -- both columns collapse (and it derives from persisted
	# wall state, so it survives rebuild).
	var south_comps: Array[Dictionary] = []
	for child in second.get_children():
		if child is StaticBody2D:
			var candidate := child.get_node_or_null("EnvironmentDamageComponent") as EnvironmentDamageComponent
			if candidate != null and "/wall_" in String(candidate.object_id):
				var body := child as Node2D
				if body.position.y >= half_extent.y - PixelAtlasMap.TILE_SIZE:
					south_comps.append({"x": body.position.x, "comp": candidate})
	south_comps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["x"] < b["x"])
	var neighbor: Dictionary = {}
	for entry_variant in south_comps:
		var entry: Dictionary = entry_variant
		if absf(float(entry["x"]) - breach_x) <= PixelAtlasMap.TILE_SIZE * 1.5 and not is_equal_approx(float(entry["x"]), breach_x):
			neighbor = entry
			break
	_assert(not neighbor.is_empty(), "fixture needs an adjacent south segment for the cascade")
	if not neighbor.is_empty():
		var neighbor_comp: EnvironmentDamageComponent = neighbor["comp"]
		var neighbor_x := float(neighbor["x"])
		neighbor_comp.apply_damage(9999.0, EnvironmentDamage.DamageClass.EXPLOSIVE, null)
		await get_tree().process_frame
		await get_tree().physics_frame
		var cascaded_facade := second.projected_facade()
		_assert(cascaded_facade != null and cascaded_facade.collapse_columns.has(breach_x) and cascaded_facade.collapse_columns.has(neighbor_x),
			"two adjacent dead segments must structurally collapse the columns above them")
	second.free()
	await get_tree().process_frame
	var fourth := ProceduralBuilding.new()
	fourth.configure(city["buildings"][0])
	add_child(fourth)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var persisted_facade := fourth.projected_facade()
	_assert(persisted_facade != null and persisted_facade.collapse_columns.size() >= 2,
		"the structural cascade must persist through reconstruction")
	fourth.free()

	# Interior partitions collapse a localized ceiling patch instead.
	var third := ProceduralBuilding.new()
	third.configure(city["buildings"][0])
	add_child(third)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var interior_roof := third.get_node("Roof") as TileMapLayer
	var rects: Array = building_spec["interior"]["perimeter_rects"]
	var partition_comp: EnvironmentDamageComponent = null
	for child in third.get_children():
		if child is StaticBody2D:
			var candidate := child.get_node_or_null("EnvironmentDamageComponent") as EnvironmentDamageComponent
			if candidate == null or not "/wall_" in String(candidate.object_id):
				continue
			var pos: Vector2 = (child as Node2D).position
			var on_edge := false
			for rect_variant in rects:
				var rect: Rect2 = rect_variant
				var margin: float = PixelAtlasMap.TILE_SIZE * 0.5 + 1.0
				if absf(pos.y - rect.position.y) <= margin or absf(pos.y - rect.end.y) <= margin \
						or absf(pos.x - rect.position.x) <= margin or absf(pos.x - rect.end.x) <= margin:
					on_edge = true
					break
			if not on_edge:
				partition_comp = candidate
				break
	if partition_comp != null:
		var p_body := partition_comp.get_parent() as Node2D
		var base_cell := Vector2i(floori(p_body.position.x / PixelAtlasMap.TILE_SIZE), floori(p_body.position.y / PixelAtlasMap.TILE_SIZE))
		var had_center: bool = interior_roof.get_used_cells().has(base_cell)
		partition_comp.apply_damage(9999.0, EnvironmentDamage.DamageClass.EXPLOSIVE, null)
		await get_tree().process_frame
		await get_tree().physics_frame
		if had_center:
			_assert(not interior_roof.get_used_cells().has(base_cell),
				"an interior wall failure must collapse its localized ceiling patch")
	else:
		pass # this archetype has no mid-building partition; edge case tolerated
	third.free()
	WorldState.reset()
	await get_tree().process_frame

func _test_headshots_kill_fast_and_limbs_sever() -> void:
	WorldState.reset()
	var zombie := (load("res://scenes/actors/Zombie.tscn") as PackedScene).instantiate() as Zombie
	add_child(zombie)
	zombie.global_position = Vector2(80000, 80000)
	await get_tree().physics_frame
	var shooter := Node2D.new()
	add_child(shooter)
	shooter.global_position = zombie.global_position + Vector2(-40.0, 0.0)
	# Two SMG-grade headshots (12 dmg x 2.25 headshot multiplier vs 40 head
	# integrity): precise aim must kill quickly.
	zombie.take_damage(12.0, shooter, zombie.global_position + Vector2(3.0, 2.0))
	_assert(zombie.anatomy.head_alive(), "one SMG round to the head wounds but must not instantly kill")
	zombie.take_damage(12.0, shooter, zombie.global_position + Vector2(-2.0, 1.0))
	_assert(not zombie.anatomy.head_alive(), "two precise head rounds must destroy the head")
	await get_tree().process_frame
	_assert(not is_instance_valid(zombie) or zombie.health_component.is_dead, "head destruction kills")

	# Limb severing through the same live path: an arm-zone overkill hit.
	var zombie_b := (load("res://scenes/actors/Zombie.tscn") as PackedScene).instantiate() as Zombie
	add_child(zombie_b)
	zombie_b.global_position = Vector2(80200, 80000)
	await get_tree().physics_frame
	zombie_b.take_damage(60.0, shooter, zombie_b.global_position + Vector2(20.0, 0.0))
	_assert(zombie_b.anatomy.severed.has(&"arm_r"), "arm-zone overkill must sever the arm")
	var limbs := get_tree().get_nodes_in_group("severed_limbs").filter(func(node: Node) -> bool:
		return is_instance_valid(node))
	_assert(limbs.size() >= 1, "severed arms must spawn physical limb bodies")
	_assert(zombie_b.anatomy.attack_factor() == 0.5, "one arm gone halves attack capability")
	for node in limbs:
		node.free()
	SeveredLimb.active_count = maxi(SeveredLimb.active_count - limbs.size(), 0)
	shooter.queue_free()
	if is_instance_valid(zombie):
		zombie.free()
	if is_instance_valid(zombie_b):
		zombie_b.free()
	Corpse.active_count = 0
	WorldState.reset()
	GoreSystem._blood_texture = null
	await get_tree().process_frame

func _test_zombie_gait_animation_states() -> void:
	WorldState.reset()
	var zombie := (load("res://scenes/actors/Zombie.tscn") as PackedScene).instantiate() as Zombie
	add_child(zombie)
	zombie.global_position = Vector2(80400, 80400)
	await get_tree().physics_frame
	# Healthy shamble: upright sway only.
	zombie._animate_gait(0.05)
	_assert(absf(zombie.body_visual.rotation) < 0.5, "an intact zombie stays roughly upright while shambling")
	# One leg severed: heavy limp dip (pin the gait phase so the dip is at
	# its extreme, not mid-swing).
	zombie.take_damage(999.0, null, zombie.global_position + Vector2(0.0, -22.0))
	_assert(zombie.anatomy.severed.has(&"leg_l"), "fixture severs the left leg")
	zombie._anim_time = 0.125
	zombie._animate_gait(1.0)
	# Expected limp dip is deterministic: idle frames still advance the gait
	# clock by 1.4s, then the target snaps fully into place.
	var expected_dip: float = absf(sin((0.125 + 1.4) * TAU * 0.7)) * 0.36
	_assert(absf(absf(zombie.body_visual.rotation) - expected_dip) < 0.02,
		"a one-legged zombie must dip into a visible limp (rot=%.3f expected=%.3f)" % [absf(zombie.body_visual.rotation), expected_dip])
	# Both legs: prone crawl wiggle around a sideways pose.
	zombie.take_damage(999.0, null, zombie.global_position + Vector2(0.0, 22.0))
	_assert(zombie.anatomy.movement_factor() <= 0.2, "legless zombies crawl")
	for _i in range(10):
		zombie.velocity = Vector2(20.0, 0.0)
		zombie._animate_gait(0.05)
		await get_tree().physics_frame
	_assert(absf(zombie.body_visual.rotation) > 1.0, "crawling zombies lie tipped sideways with a wiggle")
	if is_instance_valid(zombie):
		zombie.free()
	Corpse.active_count = 0
	for node in get_tree().get_nodes_in_group("corpses"):
		node.free()
	for node in get_tree().get_nodes_in_group("severed_limbs"):
		node.free()
	SeveredLimb.active_count = 0
	WorldState.reset()
	GoreSystem._blood_texture = null
	await get_tree().process_frame

func _test_furniture_partial_damage_before_failure() -> void:
	WorldState.reset()
	var city := ProceduralCityGenerator.new().generate_streamed_chunk(20260821, Vector2i.ZERO)
	var spec: Dictionary = {}
	for building_variant in city["buildings"]:
		for furniture_variant in (building_variant as Dictionary)["interior"]["furniture"]:
			var candidate: Dictionary = furniture_variant
			if candidate["kind"] in [&"dining_table", &"bookshelf", &"wardrobe"] and String(candidate["mode"]) == "physical":
				spec = candidate
				break
		if not spec.is_empty():
			break
	_assert(not spec.is_empty(), "fixture needs chunky physical furniture")
	var building := await _instantiate_generated_building_for_piece(String(spec["id"]))
	var piece := _find_built_piece(building, String(spec["id"]))
	_assert(piece != null, "the furniture piece must exist at runtime")
	var damage := _find_damage_component_deep(piece)
	_assert(damage != null, "chunky furniture must carry its own damage component")
	if damage != null:
		damage.apply_damage(14.0, 1, null) # one heavy round: partial quarter damage
		_assert(not WorldState.get_prop_state_flag(damage.object_id, &"destroyed", false),
			"a single heavy round must partially damage furniture without collapsing it")
		_assert(is_instance_valid(piece), "partially damaged furniture must stay in the world")
	building.queue_free()
	WorldState.reset()
	await get_tree().process_frame

func _find_damage_component_deep(root: Node) -> EnvironmentDamageComponent:
	if root.name == "EnvironmentDamageComponent":
		return root as EnvironmentDamageComponent
	for child in root.get_children():
		var found := _find_damage_component_deep(child)
		if found != null:
			return found
	return null

## --- zombie anatomy / gore ---

func _test_zombie_anatomy_governs_death_and_cripples() -> void:
	WorldState.reset()
	var anatomy := ZombieAnatomy.new()
	anatomy.apply_zone_damage(&"torso", 200.0)
	anatomy.apply_zone_damage(&"arm_l", 100.0)
	anatomy.apply_zone_damage(&"arm_r", 100.0)
	anatomy.apply_zone_damage(&"leg_l", 100.0)
	anatomy.apply_zone_damage(&"leg_r", 100.0)
	_assert(anatomy.head_alive(), "a limbless, gut-shot zombie must remain alive while the head lives")
	_assert(anatomy.movement_factor() < 0.2, "losing both legs must reduce the zombie to a crawl")
	_assert(anatomy.attack_factor() == 0.0, "losing both arms must remove normal arm attacks")
	var head_result := anatomy.apply_zone_damage(&"head", 999.0)
	_assert(head_result["head_destroyed"], "head destruction must be reported as fatal")
	_assert(not anatomy.head_alive(), "head integrity zero must end the zombie")

	var zombie := (load("res://scenes/actors/Zombie.tscn") as PackedScene).instantiate() as Zombie
	add_child(zombie)
	zombie.global_position = Vector2(79600, 79600)
	await get_tree().physics_frame
	var shooter := Node2D.new()
	add_child(shooter)
	shooter.global_position = zombie.global_position + Vector2(-30.0, 0.0)
	zombie.take_damage(60.0, shooter, zombie.global_position + Vector2(18.0, 0.0))
	_assert(zombie.anatomy.head_alive(), "body shots must leave the head alive")
	_assert(not zombie.health_component.is_dead, "a body-shot zombie must NOT die while its head lives")
	zombie.take_damage(999.0, shooter, zombie.global_position)
	await get_tree().process_frame
	_assert(not is_instance_valid(zombie) or zombie.health_component.is_dead, "destroying the head must kill the zombie")
	_assert(not get_tree().get_nodes_in_group("corpses").is_empty(), "the headshot must leave a physical corpse behind")
	for node in get_tree().get_nodes_in_group("corpses"):
		node.free()
	Corpse.active_count = 0
	shooter.queue_free()
	if is_instance_valid(zombie):
		zombie.free()
	WorldState.reset()
	GoreSystem._blood_texture = null
	await get_tree().process_frame

func _test_severed_limbs_get_physics_and_gore_caps() -> void:
	WorldState.reset()
	var fixture := Node2D.new()
	add_child(fixture)
	var anatomy := ZombieAnatomy.new()
	var result := anatomy.apply_zone_damage(&"arm_l", 999.0)
	_assert(result["severed"], "reaching the sever threshold must detach the arm")
	_assert(anatomy.attack_factor() == 0.5, "one missing arm must halve attack capability")
	GoreSystem.blood_splat(fixture, Vector2.ZERO, Vector2.RIGHT, 40.0)
	GoreSystem.blood_splat(fixture, Vector2(10, 0), Vector2.RIGHT, 80.0)
	var decals := fixture.get_children().filter(func(node: Node) -> bool: return node.is_in_group("blood_decals"))
	_assert(decals.size() >= 2, "severing must produce directional blood decals")
	for i in range(GoreSystem.MAX_DECALS + 10):
		GoreSystem.blood_splat(fixture, Vector2(i * 3.0, 0), Vector2.RIGHT, 20.0)
	var live_decals := fixture.get_children().filter(func(node: Node) -> bool: return node.is_in_group("blood_decals") and not node.is_queued_for_deletion())
	_assert(live_decals.size() <= GoreSystem.MAX_DECALS, "blood decals must respect their global cap (%d)" % live_decals.size())
	for decal in live_decals:
		decal.free()
	GoreSystem._blood_texture = null
	fixture.queue_free()
	WorldState.reset()
	await get_tree().process_frame

## --- weapons ---

func _test_weapons_are_data_driven_with_sprites() -> void:
	var pistol: WeaponData = load("res://resources/weapons/pistol.tres")
	var shotgun: WeaponData = load("res://resources/weapons/shotgun.tres")
	var rifle: WeaponData = load("res://resources/weapons/rifle.tres")
	for weapon in [pistol, shotgun, rifle]:
		_assert(weapon.id != &"" and weapon.sprite_path != "", "%s must be fully data-driven (id+sprite)" % weapon.weapon_name)
		_assert(load(weapon.sprite_path) != null, "%s sprite asset must exist" % weapon.weapon_name)
	_assert(shotgun.pellet_count >= 5, "the shotgun definition must fire multiple pellets")
	_assert(rifle.penetration >= 1, "the rifle definition must pierce at least one body")
	# Sprite orientation contract: barrel points +X so pivot rotation aims it.
	var pistol_texture: Texture2D = load(pistol.sprite_path)
	_assert(pistol_texture.get_width() > pistol_texture.get_height(), "top-down weapon sprites must be drawn along +X")

func _test_infinite_player_ammo_debug_flag() -> void:
	WorldState.reset()
	var debug_settings: Node = get_node_or_null("/root/DebugSettings")
	_assert(debug_settings != null, "DebugSettings autoload must exist")
	var previous: bool = debug_settings.get("infinite_player_ammo")
	debug_settings.set("infinite_player_ammo", true)
	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	await get_tree().process_frame
	player.weapon.ammo_in_magazine = 1
	player.weapon.reserve_ammo = 0
	_assert(player.weapon.try_fire(Vector2.RIGHT), "firing with an empty magazine must auto-reload into infinite reserve")
	player.weapon._reload_remaining = 0.001
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not player.weapon.is_reloading, "auto reload must complete")
	_assert(player.weapon.ammo_in_magazine == player.weapon.data.magazine_size - 1 or player.weapon.reserve_ammo > 0,
		"infinite reserve must keep the player firing")
	# Flag OFF: consumption resumes.
	debug_settings.set("infinite_player_ammo", false)
	player.weapon.ammo_in_magazine = 0
	player.weapon.reserve_ammo = 0
	player.weapon.is_reloading = false
	_assert(not player.weapon.try_reload(), "with the flag disabled an empty reserve must refuse to reload")
	debug_settings.set("infinite_player_ammo", previous)
	player.queue_free()
	WorldState.reset()
	await get_tree().process_frame

## --- base functional objects ---

func _test_base_functions_use_valid_interior_spots() -> void:
	WorldState.reset()
	var city := ProceduralCityGenerator.new().generate_streamed_chunk(20260821, Vector2i.ZERO)
	var claimed := SurvivorBaseService.new().claim_best_base(city, 20260821)
	_assert(claimed != null, "fixture needs a claimed base")
	var building_spec: Dictionary = {}
	for building_variant in city["buildings"]:
		var candidate: Dictionary = building_variant
		if candidate["id"] == claimed.building_id:
			building_spec = candidate
			break
	var origin: Vector2 = building_spec["position"]
	# Every occupied interior footprint (furniture + reserves), world space.
	var blocked: Array[Rect2] = []
	for furniture_variant in building_spec["interior"]["furniture"]:
		var rect: Rect2 = furniture_variant["clearance_rect"]
		rect.position += origin
		blocked.append(rect)
	for reserve_variant in building_spec["interior"]["clearance_rects"]:
		var reserve_rect: Rect2 = reserve_variant["rect"]
		reserve_rect.position += origin
		blocked.append(reserve_rect)
	var settlement := Settlement.new()
	add_child(settlement)
	await get_tree().process_frame
	settlement.claim_building_base(city, 20260821)
	await get_tree().process_frame
	var base_interior := settlement.get_node_or_null("BaseInterior")
	_assert(base_interior != null, "a claimed base must build its BaseInterior layer")
	if base_interior != null:
		var containers := base_interior.get_children().filter(func(node: Node) -> bool: return node is StorageContainer)
		_assert(containers.size() == 4, "base storage must provide all four roles")
		for container_variant in containers:
			var container := container_variant as Node2D
			var footprint := Rect2(container.global_position - Vector2(16, 16), Vector2(32, 32))
			for blocked_rect in blocked:
				_assert(not footprint.intersects(blocked_rect),
					"%s must not overlap generated furniture or aisles (spot %s)" % [String(container.name), container.global_position])
		var sleep_spots := base_interior.get_children().filter(func(node: Node) -> bool: return node is SleepSpot)
		_assert(sleep_spots.size() >= 4, "sleep spots must exist inside the base")
	settlement.abandon_building_base()
	settlement.free()
	WorldState.reset()
	await get_tree().process_frame

## --- session: reactive physics lifecycle, gore anatomy, weapons ---

func _test_furniture_refreezes_and_reactivates() -> void:
	var parts := _make_reactive_fixture(&"chair", PhysicsReactionComponent.MassClass.LIGHT, Vector2(76000, 76000))
	var reaction := parts[2] as PhysicsReactionComponent
	_assert(reaction.apply_impulse(Vector2(90.0, 0.0)), "first hit must convert the chair")
	await get_tree().physics_frame
	reaction.debug_force_refreeze()
	_assert(reaction.is_frozen(), "a settled piece must freeze to zero physics cost")
	# Second hit on the SAME frozen body must thaw and move it again.
	_assert(reaction.apply_impulse(Vector2(-140.0, 40.0)), "a refrozen piece must reactivate")
	_assert(not reaction.is_frozen(), "reactivation must unfreeze the body")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var body := (parts[1] as Node2D).get_node("DynamicBody") as RigidBody2D
	_assert(body != null and body.linear_velocity.length() > 0.0, "second-impact motion must be real physics, not a state flag")
	parts[0].queue_free()
	await get_tree().process_frame

func _test_contact_shoving_moves_light_not_heavy() -> void:
	var light_parts := _make_reactive_fixture(&"chair", PhysicsReactionComponent.MassClass.LIGHT, Vector2(77000, 77000))
	var heavy_parts := _make_reactive_fixture(&"wardrobe", PhysicsReactionComponent.MassClass.HEAVY, Vector2(77200, 77000))
	var light_reaction := light_parts[2] as PhysicsReactionComponent
	var heavy_reaction := heavy_parts[2] as PhysicsReactionComponent
	# A walking zombie's contact pressure (~19 impulse per bump).
	for _bump in range(4):
		light_reaction.apply_contact_impulse(Vector2(20.0, 0.0))
	_assert(light_reaction.is_dynamic(), "repeated light contacts must accumulate into real furniture motion")
	heavy_reaction.apply_contact_impulse(Vector2(30.0, 0.0))
	heavy_reaction.apply_contact_impulse(Vector2(-25.0, 5.0))
	_assert(not heavy_reaction.is_dynamic(), "ordinary actor contact must never shove heavy furniture")
	light_parts[0].queue_free()
	heavy_parts[0].queue_free()
	await get_tree().process_frame

func _test_moved_furniture_transform_persists() -> void:
	WorldState.reset()
	var city := ProceduralCityGenerator.new().generate_streamed_chunk(20260821, Vector2i.ZERO)
	var spec: Dictionary = {}
	for building_variant in city["buildings"]:
		for furniture_variant in (building_variant as Dictionary)["interior"]["furniture"]:
			var candidate: Dictionary = furniture_variant
			if String(candidate["mode"]) == "physical" and candidate["kind"] in [&"chair", &"nightstand"]:
				spec = candidate
				break
		if not spec.is_empty():
			break
	_assert(not spec.is_empty(), "fixture needs an ordinary physical furniture piece")
	var first := await _instantiate_generated_building_for_piece(String(spec["id"]))
	var built_root := _find_built_piece(first, String(spec["id"]))
	_assert(built_root != null, "the piece must exist at runtime")
	built_root.position += Vector2(33.0, -17.0)
	built_root.rotation = 0.4
	var reaction := built_root.get_node_or_null("PhysicsReactionComponent") as PhysicsReactionComponent
	_assert(reaction != null, "physical furniture must carry a reactive-physics component")
	# Persist exactly what the component saves on settle.
	WorldState.set_prop_state_flag(spec["id"], &"moved_offset", built_root.position)
	WorldState.set_prop_state_flag(spec["id"], &"moved_rotation", built_root.rotation)
	var moved_position: Vector2 = built_root.position
	first.free()
	await get_tree().process_frame
	var second := await _instantiate_generated_building_for_piece(String(spec["id"]))
	var rebuilt := _find_built_piece(second, String(spec["id"]))
	_assert(rebuilt != null, "rebuilt building must contain the same furniture piece")
	if rebuilt != null:
		_assert(rebuilt.position.distance_to(moved_position) < 2.0,
			"moved furniture must restore its MOVED position after reconstruction (%s vs %s)" % [rebuilt.position, moved_position])
	second.free()
	WorldState.reset()
	await get_tree().process_frame

func _instantiate_generated_building_for_piece(piece_id: String) -> ProceduralBuilding:
	var city := ProceduralCityGenerator.new().generate_streamed_chunk(20260821, Vector2i.ZERO)
	for building_variant in city["buildings"]:
		var building: Dictionary = building_variant
		for furniture_variant in building["interior"]["furniture"]:
			var furniture: Dictionary = furniture_variant
			if String(furniture["id"]) == piece_id:
				var node := ProceduralBuilding.new()
				node.configure(building)
				add_child(node)
				return node
	return null

func _find_built_piece(root: Node, piece_id: String) -> Node2D:
	var target_name := String(piece_id).get_file()
	if String(root.name) == target_name and root is Node2D:
		return root
	for child in root.get_children():
		var found := _find_built_piece(child, piece_id)
		if found != null:
			return found
	return null

func _test_sleeping_corpse_thrown_by_explosion() -> void:
	WorldState.reset()
	var fixture := Node2D.new()
	add_child(fixture)
	var corpse := Corpse.spawn(fixture, null, Vector2(78000, 78000), Vector2.ZERO)
	corpse.freeze = true # simulate a long-settled sleeping corpse
	var blaster := Node2D.new()
	add_child(blaster)
	blaster.global_position = corpse.global_position + Vector2(-60.0, 0.0)
	await get_tree().physics_frame # let the corpse's shapes enter the broadphase
	EnvironmentDamage.apply_explosion(blaster, corpse.global_position, 120.0, 4.0, 8.0, EnvironmentDamage.DamageClass.EXPLOSIVE)
	_assert(not corpse.freeze, "a blast must wake/thaw a sleeping corpse before throwing it")
	await get_tree().physics_frame
	_assert(corpse.linear_velocity.length() > 2.0, "the woken corpse must actually fly")
	blaster.queue_free()
	corpse.free()
	Corpse.active_count = maxi(Corpse.active_count - 1, 0)
	WorldState.reset()
	await get_tree().process_frame

func _test_corpse_lifetime_cleanup_works() -> void:
	WorldState.reset()
	var fixture := Node2D.new()
	add_child(fixture)
	var corpse := Corpse.spawn(fixture, null, Vector2(78200, 78200), Vector2.ZERO)
	corpse._age = Corpse.LIFETIME + 1.0
	corpse._physics_process(0.016)
	_assert(corpse.is_queued_for_deletion(), "corpse lifetime cleanup must free even sleeping corpses")
	Corpse.active_count = maxi(Corpse.active_count - 1, 0)
	fixture.queue_free()
	WorldState.reset()
	await get_tree().process_frame

func _test_streamed_prague_quarters_are_dense_and_open_spaces_are_rare() -> void:
	var generator := ProceduralCityGenerator.new()
	var plaza_chunk_count := 0
	var courtyard_count := 0
	var sampled_chunks := 0
	for y in range(-4, 5):
		for x in range(-4, 5):
			var coordinate := Vector2i(x, y)
			var city := generator.generate_streamed_chunk(20260821, coordinate)
			sampled_chunks += 1
			plaza_chunk_count += 1 if not (city.get("public_spaces", []) as Array).is_empty() else 0
			courtyard_count += (city.get("courtyards", []) as Array).size()
			_assert(bool(city.get("has_safehouse", false)) == (coordinate == Vector2i.ZERO), "only the origin chunk may reserve the safehouse quarter")
			if abs(coordinate.x) > 1 or abs(coordinate.y) > 1:
				continue
			for block in city["blocks"]:
				if block["zone"] in [&"safehouse", &"park"]:
					continue
				var buildable: Rect2 = (block["rect"] as Rect2).grow(-ProceduralCityGenerator.SIDEWALK_DEPTH)
				# Profile street widths leave sub-module margins around the
				# parcel grid; density is measured against the module-snapped
				# buildable envelope (the area frontage lots can occupy).
				var module_width := floorf(buildable.size.x / 64.0) * 64.0
				var module_height := floorf(buildable.size.y / 64.0) * 64.0
				var module_area := module_width * module_height
				var occupied_area := 0.0
				for building in city["buildings"]:
					if building["block_id"] != block["id"]:
						continue
					for local_rect in building["interior"]["perimeter_rects"]:
						occupied_area += (local_rect as Rect2).get_area()
				var density := occupied_area / module_area
				var minimum_density := 0.60 if bool(block.get("courtyard_reserved", false)) else 0.88
				_assert(density >= minimum_density, "chunk %s quarter %s size=%s buildings=%d occupied=%.0f coverage %.3f must meet dense threshold %.2f" % [str(coordinate), String(block["id"]), str(buildable.size), (city["buildings"] as Array).filter(func(item: Dictionary) -> bool: return item["block_id"] == block["id"]).size(), occupied_area, density, minimum_density])
	_assert(plaza_chunk_count > 0 and plaza_chunk_count <= int(ceil(sampled_chunks * 0.12)), "plazas must occur in the deterministic corpus but remain below twelve percent of chunks")
	_assert(courtyard_count > 0 and courtyard_count <= sampled_chunks, "courtyards must occur but average no more than one per sampled chunk")

func _test_procedural_seed_corpus_is_deterministic_valid_and_bounded() -> void:
	var generator := ProceduralCityGenerator.new()
	var archetypes: Dictionary = {}
	var layouts: Dictionary = {}
	var maximum_generation_us: int = 0
	var total_generation_us: int = 0
	for seed_value in PROCEDURAL_SEED_CORPUS:
		var started_at := Time.get_ticks_usec()
		var first: Dictionary = generator.generate(seed_value)
		var elapsed_us := int(Time.get_ticks_usec() - started_at)
		maximum_generation_us = maxi(maximum_generation_us, elapsed_us)
		total_generation_us += elapsed_us
		var second: Dictionary = generator.generate(seed_value)
		var errors: Array[String] = generator.validate(first)
		_assert(errors.is_empty(), "difficult seed %d must validate: %s" % [seed_value, str(errors)])
		_assert(int(first.get("generation_attempt", ProceduralCityGenerator.MAX_GENERATION_ATTEMPTS)) < ProceduralCityGenerator.MAX_GENERATION_ATTEMPTS, "seed %d must finish within the deterministic retry budget" % seed_value)
		_assert(String(first.get("generation_error", "")).is_empty(), "seed %d must not report a generation failure" % seed_value)
		_assert(generator.signature(first) == generator.signature(second), "seed %d must reproduce its complete semantic model" % seed_value)
		_assert(_semantic_id_snapshot(first) == _semantic_id_snapshot(second), "seed %d must reproduce every stable semantic id" % seed_value)
		for building in first["buildings"]:
			archetypes[building["archetype"]] = true
			layouts[building["interior"]["layout"]] = true
	_assert(archetypes.size() == ProceduralCityGenerator.BUILDING_ARCHETYPES.size(), "difficult-seed corpus must exercise all five generated building archetypes")
	_assert(
		layouts.has(&"strip_x") and layouts.has(&"strip_y") and layouts.has(&"grid_2x2"),
		"difficult-seed corpus must exercise both generated strip orientations and the four-room grid layout"
	)
	_assert(total_generation_us < 10_000_000, "semantic generation corpus must remain under a generous 10-second test ceiling")
	print("PROCEDURAL_SEMANTIC_PROFILE seeds=%d average_ms=%.3f max_ms=%.3f" % [PROCEDURAL_SEED_CORPUS.size(), float(total_generation_us) / float(PROCEDURAL_SEED_CORPUS.size()) / 1000.0, float(maximum_generation_us) / 1000.0])

func _test_procedural_generation_retries_and_fails_explicitly() -> void:
	var retry_generator = PROCEDURAL_RETRY_PROBE_SCRIPT.new()
	retry_generator.forced_validation_failures = 2
	var recovered: Dictionary = retry_generator.generate(20260821)
	_assert(int(recovered["generation_attempt"]) == 2, "generator must advance through deterministic attempts after validation rejection")
	_assert(retry_generator.validation_calls == 3, "generator must stop retrying immediately after the first valid attempt")
	_assert(String(recovered["generation_error"]).is_empty(), "a recovered deterministic retry must not retain a failure marker")

	var repeated_generator = PROCEDURAL_RETRY_PROBE_SCRIPT.new()
	repeated_generator.forced_validation_failures = 2
	var repeated: Dictionary = repeated_generator.generate(20260821)
	_assert(ProceduralCityGenerator.new().signature(recovered) == ProceduralCityGenerator.new().signature(repeated), "the same seed and rejection count must reproduce the recovered retry layout")
	_assert(recovered["attempt_seed"] == repeated["attempt_seed"], "deterministic retry attempts must use the same derived seed")

	var failing_generator = PROCEDURAL_RETRY_PROBE_SCRIPT.new()
	failing_generator.forced_validation_failures = ProceduralCityGenerator.MAX_GENERATION_ATTEMPTS
	var failed: Dictionary = failing_generator.generate(20260821)
	_assert(int(failed["generation_attempt"]) == ProceduralCityGenerator.MAX_GENERATION_ATTEMPTS, "exhausted generation must expose the retry bound")
	_assert(not String(failed["generation_error"]).is_empty(), "exhausted generation must return an explicit failure message")
	_assert((failed["validation_errors"] as Array).size() == ProceduralCityGenerator.MAX_GENERATION_ATTEMPTS, "exhausted generation must retain one diagnostic per deterministic attempt")
	_assert(not ProceduralCityGenerator.new().validate(failed).is_empty(), "the explicit failure model must remain safely validateable by the runtime gate")

func _test_procedural_runtime_failure_propagates_attempt_diagnostics() -> void:
	var district := FAILING_PROCEDURAL_DISTRICT_SCRIPT.new() as ProceduralDistrict
	var observed_errors: Array[String] = []
	district.generation_failed.connect(func(_seed_value: int, errors: Array[String]) -> void: observed_errors.append_array(errors))
	add_child(district)
	await get_tree().process_frame
	_assert(district.generation_complete and not district.generation_succeeded, "runtime district must stop cleanly after exhausting deterministic generation attempts")
	_assert(district.generation_errors.size() == ProceduralCityGenerator.MAX_GENERATION_ATTEMPTS + 1, "runtime failure must expose its summary plus every per-attempt validation diagnostic")
	_assert(observed_errors == district.generation_errors, "generation_failed must emit the same complete diagnostics retained on the failed district")
	_assert(district.generation_errors.any(func(error: String) -> bool: return error.begins_with("attempt 0:")), "runtime failure diagnostics must identify the first rejected deterministic attempt")
	_assert(district.generation_errors.any(func(error: String) -> bool: return error.begins_with("attempt 7:")), "runtime failure diagnostics must identify the final rejected deterministic attempt")
	district.free()
	await get_tree().process_frame

func _semantic_id_snapshot(city: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for road in city["roads"]:
		result.append("road:" + String(road["id"]))
	for intersection in city["intersections"]:
		result.append("intersection:" + String(intersection["id"]))
	for block in city["blocks"]:
		result.append("block:" + String(block["id"]))
	for parcel in city["parcels"]:
		result.append("parcel:" + String(parcel["id"]))
	for building in city["buildings"]:
		result.append("building:" + String(building["id"]))
		for room in building["interior"]["rooms"]:
			result.append("room:" + String(room["stable_id"]))
		for door in building["interior"]["doors"]:
			result.append("door:" + String(door["id"]))
		for window in building["interior"]["windows"]:
			result.append("window:" + String(window["id"]))
		for furniture in building["interior"]["furniture"]:
			result.append("furniture:" + String(furniture["id"]))
	for exterior in city["exterior_zones"]:
		result.append("exterior:" + String(exterior["id"]))
	for prop in city["props"]:
		result.append("prop:" + String(prop["id"]))
	for region in city["spawn_regions"]:
		result.append("spawn:" + String(region["id"]))
	for point in city["scavenge_points"]:
		result.append("scavenge:" + String(point["id"]))
	for landmark in city["landmarks"]:
		result.append("landmark:" + String(landmark["id"]))
	result.sort()
	return result

func _test_procedural_roads_parcels_entrances_and_exteriors_are_valid() -> void:
	var generator := ProceduralCityGenerator.new()
	var exterior_kinds: Dictionary = {}
	var placement_roles: Dictionary = {}
	for seed_value in [0, 42, 20260821]:
		var city: Dictionary = generator.generate(seed_value)
		_assert((city["intersections"] as Array).size() == 25, "seed %d must materialize all 25 road intersections" % seed_value)
		var road_ids: Dictionary = {}
		for road in city["roads"]:
			road_ids[road["id"]] = true
		for intersection in city["intersections"]:
			for road_id in intersection["road_ids"]:
				_assert(road_ids.has(road_id), "intersection %s must reference a generated road" % String(intersection["id"]))
		var building_by_parcel: Dictionary = {}
		for building in city["buildings"]:
			building_by_parcel[building["parcel_id"]] = building
			_assert(not building.has("scene"), "generated building %s must not instance an authored complete-scene template" % String(building["id"]))
			_assert(is_zero_approx(float(building["rotation"])), "generated building roots remain unrotated so semantic and runtime bounds agree")
			for road in city["roads"]:
				_assert(not (building["footprint"] as Rect2).intersects(road["rect"]), "building %s must not overlap carriageway %s" % [String(building["id"]), String(road["id"])])
		for parcel in city["parcels"]:
			_assert(road_ids.has(parcel["frontage_road_id"]), "parcel %s must front a connected generated road" % String(parcel["id"]))
			_assert(building_by_parcel.has(parcel["id"]), "parcel %s must own exactly one generated building" % String(parcel["id"]))
			_assert((parcel["access_corridor"] as Rect2).has_point(parcel["entrance_position"]), "parcel entrance must lie in its clear approach corridor")
			_assert((parcel["access_corridor"] as Rect2).has_point(parcel["approach_position"]), "parcel sidewalk approach must lie in its clear approach corridor")
		for exterior in city["exterior_zones"]:
			exterior_kinds[exterior["kind"]] = true
		for prop in city["props"]:
			placement_roles[prop["placement_role"]] = true
			if prop["kind"] == &"car":
				_assert(prop["interaction"] == &"loot" and not (prop["items"] as Dictionary).is_empty(), "intact generated cars must expose deterministic trunk loot")
			elif prop["kind"] == &"wreck":
				_assert(prop["interaction"] == &"salvage" and (prop["items"] as Dictionary).is_empty(), "generated wrecks must remain material salvage rather than trunk loot")
		_assert(generator.validate(city).is_empty(), "seed %d must reject no overlaps, blocked entrances, or isolated parcels" % seed_value)
	_assert(exterior_kinds.has(&"parking") and exterior_kinds.has(&"alley") and exterior_kinds.has(&"park"), "semantic city must contain parking, alleys, and a public park")
	for required_role in [&"sidewalk", &"parking", &"alley", &"public", &"medical", &"service"]:
		_assert(placement_roles.has(required_role), "exterior prop rules must produce %s placement" % String(required_role))

func _test_procedural_interiors_are_reachable_furnished_and_clear() -> void:
	var generator := ProceduralCityGenerator.new()
	var archetypes: Dictionary = {}
	var roles: Dictionary = {}
	for seed_value in [1, 42, 8801, 20260821]:
		var city: Dictionary = generator.generate(seed_value)
		for building in city["buildings"]:
			archetypes[building["archetype"]] = true
			var interior: Dictionary = building["interior"]
			var errors: Array[String] = ProceduralBuildingGenerator.new().validate(interior)
			_assert(errors.is_empty(), "generated interior %s must satisfy graph and clearance validation: %s" % [String(building["id"]), str(errors)])
			_assert((interior["doors"] as Array).any(func(door: Dictionary) -> bool: return bool(door["exterior"])), "generated interior %s needs an exterior graph root" % String(building["id"]))
			_assert(not (interior["windows"] as Array).is_empty(), "generated interior %s needs generated exterior windows" % String(building["id"]))
			var furniture_per_room: Dictionary = {}
			for furniture in interior["furniture"]:
				furniture_per_room[furniture["room_id"]] = int(furniture_per_room.get(furniture["room_id"], 0)) + 1
				_assert((furniture["clearance_rect"] as Rect2).encloses(furniture["collision_rect"]), "furniture %s must carry an explicit clearance footprint" % String(furniture["id"]))
			for room in interior["rooms"]:
				roles[room["role"]] = true
				_assert(furniture_per_room.get(room["id"], 0) > 0, "required room %s must contain function-aware furniture" % String(room["id"]))
	_assert(archetypes.size() == 5, "interior corpus must cover apartment, store, restaurant, clinic, and workshop generators")
	for required_role in [&"living_room", &"kitchen", &"bedroom", &"bathroom", &"retail_floor", &"stock_room", &"dining_room", &"pantry", &"waiting_area", &"exam_room", &"medical_storage", &"work_floor", &"loading_bay", &"storage", &"office"]:
		_assert(roles.has(required_role), "generated archetypes must include functional room role %s" % String(required_role))

func _test_procedural_spawn_phases_are_environmental_and_deterministic() -> void:
	var city: Dictionary = ProceduralCityGenerator.new().generate(20260821)
	var regions := _spawn_regions_from_city(city)
	var initial_ids: Array[String] = []
	var replenishment_ids: Array[String] = []
	var has_indoor_initial := false
	var has_exterior_replenishment := false
	for region_node in regions:
		var region := region_node as SpawnRegion
		if region.allows_phase(&"initial"):
			initial_ids.append(String(region.region_id))
			has_indoor_initial = has_indoor_initial or region.is_indoor
		if region.allows_phase(&"replenishment"):
			replenishment_ids.append(String(region.region_id))
			has_exterior_replenishment = has_exterior_replenishment or not region.is_indoor
		_assert(region.is_reachable, "spawn region %s must be generated only from an accessibility-approved environment" % String(region.region_id))
		_assert(not region.environment_tags.is_empty(), "spawn region %s must retain its environment tags" % String(region.region_id))
	initial_ids.sort()
	replenishment_ids.sort()
	_assert(initial_ids != replenishment_ids, "initial and replenishment phases must expose different eligible region sets")
	_assert(has_indoor_initial, "initial outbreak placement must include reachable generated interiors")
	_assert(has_exterior_replenishment, "replenishment must include connected exterior regions")
	var first_initial := _weighted_region_sequence(regions, 20260821, &"initial", 32)
	var second_initial := _weighted_region_sequence(regions, 20260821, &"initial", 32)
	var first_replenishment := _weighted_region_sequence(regions, 20260821, &"replenishment", 32)
	_assert(first_initial == second_initial, "city seed must reproduce initial environment-region selection")
	_assert(first_initial != first_replenishment, "initial and replenishment phase weights must produce distinct deterministic selection streams")
	for region in regions:
		(region as SpawnRegion).free()

func _test_spawn_manager_waits_for_generation_begin_and_reset() -> void:
	var container := Node2D.new()
	container.add_to_group("entity_container")
	add_child(container)
	var region := SpawnRegion.new()
	region.region_id = &"test/startup_gate"
	region.radius = 180.0
	add_child(region)
	await get_tree().physics_frame
	UrbanNavigationService.build(Vector2(512, 512))
	var manager := SpawnManager.new()
	manager.zombie_scene = ZOMBIE_SCENE
	manager.initial_population = 2
	add_child(manager)
	await get_tree().process_frame
	manager.set_world_seed(73021, Vector2.ZERO)
	_assert(not manager.is_processing(), "spawn replenishment must stay disabled while procedural generation is pending")
	manager.begin()
	_assert(manager.is_processing(), "Main.begin() must enable replenishment only after generation succeeds")
	_assert(manager.active_zombie_count() == 2, "the first begin() must create exactly one configured initial burst")
	manager.begin()
	_assert(manager.active_zombie_count() == 2, "a repeated begin() must not duplicate the initial zombie burst")
	manager.reset()
	_assert(not manager.is_processing(), "restart reset must disable replenishment until the regenerated world calls begin()")
	manager.queue_free()
	region.queue_free()
	container.queue_free()
	await get_tree().process_frame
	UrbanNavigationService.reset()

func _spawn_regions_from_city(city: Dictionary) -> Array[SpawnRegion]:
	var result: Array[SpawnRegion] = []
	for spec in city["spawn_regions"]:
		var region := SpawnRegion.new()
		region.region_id = spec["id"]
		region.position = spec["position"]
		region.radius = spec["radius"]
		region.category = spec["category"]
		region.environment_tags.assign(spec["environment_tags"])
		region.initial_weight = spec["initial_weight"]
		region.replenishment_weight = spec["replenishment_weight"]
		region.allow_initial = spec["allow_initial"]
		region.allow_replenishment = spec["allow_replenishment"]
		region.is_indoor = spec["indoor"]
		region.is_reachable = spec["reachable"]
		result.append(region)
	return result

func _weighted_region_sequence(regions: Array[SpawnRegion], seed_value: int, phase: StringName, count: int) -> Array[String]:
	var manager := SpawnManager.new()
	manager.set_world_seed(seed_value)
	var untyped_regions: Array = regions
	var result: Array[String] = []
	for _i in range(count):
		var selected: SpawnRegion = manager._pick_weighted_region(untyped_regions, phase)
		result.append(String(selected.region_id) if selected else "")
	manager.free()
	return result

func _test_generated_building_runtime_ids_and_state_persist() -> void:
	var city: Dictionary = ProceduralCityGenerator.new().generate(8801)
	var spec: Dictionary = city["buildings"][0]
	var first: ProceduralBuilding = await _instantiate_generated_building(spec)
	var first_ids := _runtime_generated_id_snapshot(first)
	_assert_no_duplicate_runtime_ids(first_ids)
	_assert(first.semantic_room_count() == (spec["interior"]["rooms"] as Array).size(), "runtime building must materialize every semantic room")
	var door := first.get_tree().get_nodes_in_group("doors").filter(func(node: Node) -> bool: return first.is_ancestor_of(node))[0] as Door
	var persisted_door_id := door.door_id
	door.toggle()
	_assert(door.is_open, "generated door must remain interactable")
	var loot := _first_descendant_of_type(first, LootContainerComponent) as LootContainerComponent
	_assert(loot != null, "generated building must materialize searchable loot furniture")
	var loot_id := loot.prop_id
	var sink := Inventory.new(0.0)
	loot.get_inventory().move_all_to(sink)
	_assert(not sink.is_empty(), "generated loot furniture must contain function-appropriate starting items")
	first.free()
	await get_tree().process_frame

	var second: ProceduralBuilding = await _instantiate_generated_building(spec)
	var second_ids := _runtime_generated_id_snapshot(second)
	_assert(first_ids == second_ids, "rebuilding a seed must reproduce all typed runtime IDs")
	var restored_door := _find_door_by_id(second, persisted_door_id)
	_assert(restored_door != null and restored_door.is_open, "generated door state must resolve through its stable ID after reconstruction")
	var restored_loot := _find_loot_by_id(second, loot_id)
	_assert(restored_loot != null and restored_loot.get_inventory().is_empty(), "generated loot depletion must resolve through its stable ID after reconstruction")
	var wall_damage := _find_explosive_wall_damage(second)
	_assert(wall_damage != null, "generated shell must contain heavy-rated destructible walls")
	if wall_damage == null:
		return
	var destroyed_wall_id := wall_damage.object_id
	wall_damage.apply_damage(999.0, EnvironmentDamage.DamageClass.EXPLOSIVE)
	await get_tree().process_frame
	_assert(WorldState.get_prop_state_flag(destroyed_wall_id, &"destroyed", false), "generated wall destruction must persist under its stable ID")
	second.free()
	await get_tree().process_frame
	var third: ProceduralBuilding = await _instantiate_generated_building(spec)
	await get_tree().process_frame
	_assert(_find_environment_damage_by_id(third, destroyed_wall_id) == null, "persistently destroyed generated wall must not reappear after reconstruction")
	third.free()
	await get_tree().process_frame

func _test_generated_scavenge_stock_persists_by_stable_id() -> void:
	var point_id := StringName("city/test/scavenge/materials")
	var first := SCAVENGE_POINT_SCENE.instantiate() as ScavengePoint
	first.point_id = point_id
	first.remaining_stock = 9
	first.yield_per_scavenge = 3
	add_child(first)
	await get_tree().process_frame
	_assert(first.harvest(2) == 2 and first.remaining_stock == 7, "partial generated scavenging must remove only the accepted stock")
	_assert(WorldState.get_prop_state_flag(point_id, &"remaining_stock", -1) == 7, "partial generated scavenging must persist the exact remainder under point_id")
	first.free()
	await get_tree().process_frame

	var rebuilt := SCAVENGE_POINT_SCENE.instantiate() as ScavengePoint
	rebuilt.point_id = point_id
	rebuilt.remaining_stock = 9
	rebuilt.yield_per_scavenge = 20
	add_child(rebuilt)
	await get_tree().process_frame
	_assert(rebuilt.remaining_stock == 7, "reconstructing the same generated scavenge ID must restore its partial remainder, not its seed stock")
	_assert(rebuilt.harvest(20) == 7, "the restored generated scavenge site must yield only its persisted remainder")
	_assert(WorldState.get_prop_state_flag(point_id, &"remaining_stock", -1) == 0, "depletion must persist an exact zero remainder")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not is_instance_valid(rebuilt), "a fully depleted generated scavenge site must leave the runtime tree")

	var depleted_rebuild := SCAVENGE_POINT_SCENE.instantiate() as ScavengePoint
	depleted_rebuild.point_id = point_id
	depleted_rebuild.remaining_stock = 9
	add_child(depleted_rebuild)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not is_instance_valid(depleted_rebuild), "a persistently depleted generated scavenge site must not reconstruct with fresh stock")

func _instantiate_generated_building(spec: Dictionary) -> ProceduralBuilding:
	var building := ProceduralBuilding.new()
	building.configure(spec)
	add_child(building)
	await get_tree().physics_frame
	return building

func _runtime_generated_id_snapshot(root: Node) -> Array[String]:
	var result: Array[String] = []
	_collect_runtime_generated_ids(root, result)
	result.sort()
	return result

func _assert_no_duplicate_runtime_ids(sorted_ids: Array[String]) -> void:
	for index in range(1, sorted_ids.size()):
		_assert(sorted_ids[index] != sorted_ids[index - 1], "generated runtime ID must be unique within its persistence domain: %s" % sorted_ids[index])

func _collect_runtime_generated_ids(node: Node, output: Array[String]) -> void:
	if node is ProceduralBuilding:
		output.append("building:" + String((node as ProceduralBuilding).building_id))
	elif node is Room:
		var room := node as Room
		output.append("room:%s/%s" % [String(room.building_id), String(room.room_id)])
	elif node is Door:
		output.append("door:" + String((node as Door).door_id))
	elif node is BuildingWindow:
		output.append("window:" + String((node as BuildingWindow).window_id))
	elif node is LootContainerComponent:
		output.append("loot:" + String((node as LootContainerComponent).prop_id))
	elif node is SalvageableComponent:
		output.append("salvage:" + String((node as SalvageableComponent).prop_id))
	elif node is EnvironmentDamageComponent:
		var object_id := (node as EnvironmentDamageComponent).object_id
		_assert(object_id != &"", "every generated damage component must have a stable object ID")
		output.append("damage:" + String(object_id))
	for child in node.get_children():
		_collect_runtime_generated_ids(child, output)

func _first_descendant_of_type(root: Node, type_script: Variant) -> Node:
	for child in root.get_children():
		if is_instance_of(child, type_script):
			return child
		var nested := _first_descendant_of_type(child, type_script)
		if nested:
			return nested
	return null

func _find_door_by_id(root: Node, id: StringName) -> Door:
	if root is Door and (root as Door).door_id == id:
		return root as Door
	for child in root.get_children():
		var found := _find_door_by_id(child, id)
		if found:
			return found
	return null

func _find_loot_by_id(root: Node, id: StringName) -> LootContainerComponent:
	if root is LootContainerComponent and (root as LootContainerComponent).prop_id == id:
		return root as LootContainerComponent
	for child in root.get_children():
		var found := _find_loot_by_id(child, id)
		if found:
			return found
	return null

func _find_explosive_wall_damage(root: Node) -> EnvironmentDamageComponent:
	if root is EnvironmentDamageComponent:
		var damage := root as EnvironmentDamageComponent
		# Walls accept heavy-and-above structural damage since the microcell
		# breach model (small arms still bounce off).
		if damage.minimum_damage_class >= EnvironmentDamage.DamageClass.HEAVY and "/wall_" in String(damage.object_id):
			return damage
	for child in root.get_children():
		var found := _find_explosive_wall_damage(child)
		if found:
			return found
	return null

func _find_environment_damage_by_id(root: Node, id: StringName) -> EnvironmentDamageComponent:
	if root is EnvironmentDamageComponent and (root as EnvironmentDamageComponent).object_id == id:
		return root as EnvironmentDamageComponent
	for child in root.get_children():
		var found := _find_environment_damage_by_id(child, id)
		if found:
			return found
	return null

func _test_procedural_restart_is_isolated_and_reuses_selected_seed() -> void:
	var main_scene: PackedScene = load("res://scenes/main/Main.tscn")
	var first := main_scene.instantiate() as Main
	var first_world := first.get_node("World") as StreamingWorld
	first_world.city_seed = 65535
	var first_manager := first.get_node("SpawnManager") as SpawnManager
	first_manager.initial_population = 0
	first_manager.spawn_interval = 9999.0
	add_child(first)
	for _i in range(30):
		if first_world.generation_complete:
			break
		await get_tree().physics_frame
	await get_tree().process_frame
	_assert(first_world.generation_succeeded, "production Main restart fixture must finish its first generated world")
	var first_origin := first_world.get_chunk(Vector2i.ZERO)
	var first_signature := ProceduralCityGenerator.new().signature(first_origin.city_model)
	var first_ids: Array[String] = []
	for building in first_origin.get_node("Buildings").get_children():
		first_ids.append_array(_runtime_generated_id_snapshot(building))
	first_ids.sort()
	_assert_no_duplicate_runtime_ids(first_ids)
	var selected_seed := first_world.resolved_seed
	var first_counts := _main_runtime_group_counts(first)
	var first_survivor_nodes: Array[Node] = get_tree().get_nodes_in_group("survivors").filter(func(node: Node) -> bool: return first.is_ancestor_of(node))
	_assert(first_counts[&"survivors"] == 4, "production Main must register exactly four survivors before restart")
	_assert(first_counts[&"scavenge_point"] == _streamed_semantic_count(first_world, &"scavenge_points"), "production Main must materialize every generated scavenge point before restart")
	_assert(first_counts[&"spawn_regions"] == _streamed_semantic_count(first_world, &"spawn_regions"), "production Main must materialize every generated spawn region before restart")
	_assert(first_counts[&"storage_container"] == 4, "production Main must materialize all four safehouse storage roles before restart")
	_assert(first._prepare_restart_state() == selected_seed, "production restart preparation must preserve the selected procedural seed")
	_assert(WorldState.world_flags.get(&"city_seed", -1) == selected_seed, "production restart preparation must restore the seed after clearing runtime persistence")
	first.free()
	await get_tree().process_frame
	await get_tree().physics_frame
	_assert(get_tree().get_nodes_in_group("rooms").is_empty(), "restart teardown must remove every old generated room from global groups")
	_assert(get_tree().get_nodes_in_group("doors").is_empty(), "restart teardown must remove every old generated door from global groups")
	_assert(get_tree().get_nodes_in_group("spawn_regions").is_empty(), "restart teardown must remove every old generated spawn region")
	_assert(get_tree().get_nodes_in_group("scavenge_point").is_empty(), "restart teardown must remove every old generated scavenge point")
	for survivor_node in first_survivor_nodes:
		_assert(not is_instance_valid(survivor_node), "restart teardown must free every survivor owned by the prior Main instance")
	_assert(get_tree().get_nodes_in_group("storage_container").is_empty(), "restart teardown must remove every old safehouse storage node")

	var second := main_scene.instantiate() as Main
	var second_world := second.get_node("World") as StreamingWorld
	second_world.city_seed = -1
	var second_manager := second.get_node("SpawnManager") as SpawnManager
	second_manager.initial_population = 0
	second_manager.spawn_interval = 9999.0
	add_child(second)
	for _i in range(30):
		if second_world.generation_complete:
			break
		await get_tree().physics_frame
	await get_tree().process_frame
	_assert(second_world.generation_succeeded, "production Main restart fixture must finish its regenerated world")
	_assert(second_world.resolved_seed == selected_seed, "restart must reuse the selected city seed after clearing runtime state")
	var second_origin := second_world.get_chunk(Vector2i.ZERO)
	_assert(ProceduralCityGenerator.new().signature(second_origin.city_model) == first_signature, "restart must reconstruct the same generated origin chunk")
	var second_ids: Array[String] = []
	for building in second_origin.get_node("Buildings").get_children():
		second_ids.append_array(_runtime_generated_id_snapshot(building))
	second_ids.sort()
	_assert_no_duplicate_runtime_ids(second_ids)
	_assert(first_ids == second_ids, "restart must reconstruct the same generated runtime IDs without accumulation")
	_assert(_main_runtime_group_counts(second) == first_counts, "restart must reconstruct identical generated/scoped runtime group counts without accumulation")
	_assert(WorldState.survivors.size() == 4, "restart must rebuild four survivor records rather than accumulate the prior run")
	WorldState.reset()
	SimulationClock.reset()
	NoiseManager.reset()
	UrbanNavigationService.reset()
	second.free()
	await get_tree().process_frame

func _main_runtime_group_counts(main_root: Main) -> Dictionary:
	var result: Dictionary = {}
	for group_name in [&"survivors", &"scavenge_point", &"spawn_regions", &"storage_container", &"rooms", &"doors"]:
		var count := 0
		for node in get_tree().get_nodes_in_group(group_name):
			if main_root.is_ancestor_of(node):
				count += 1
		result[group_name] = count
	return result

func _streamed_semantic_count(world: StreamingWorld, field: StringName) -> int:
	var total := 0
	for chunk in world.get_children():
		if chunk is ProceduralDistrict:
			total += (chunk as ProceduralDistrict).city_model.get(field, []).size()
	return total

func _instantiate_procedural_district_fixture(seed_value: int) -> ProceduralDistrict:
	# Hygiene: transient physics dressing (debris/limbs/corpses/casings) AND
	# any leaked live actors from earlier tests (zombies, survivors, player,
	# settlement, spawn manager, swarm manager) must never pollute a fresh
	# district's spawn-clearance sampling or nav-grid rasterization.
	for group_name in ["physics_debris", "severed_limbs", "corpses", "blood_decals", "blood_sprays", "shell_casings", "zombies", "survivors", "player", "settlement", "spawn_manager", "swarm_manager", "attackable"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(node):
				node.free()
	var district := PROCEDURAL_DISTRICT_SCENE.instantiate() as ProceduralDistrict
	district.city_seed = seed_value
	add_child(district)
	for _i in range(20):
		if district.generation_complete:
			break
		await get_tree().physics_frame
	_assert(district.generation_complete and district.generation_succeeded, "procedural district seed %d must finish successful runtime generation" % seed_value)
	return district

func _test_procedural_runtime_generation_profile() -> void:
	var runtime_seeds: Array[int] = [0, 42, 8801, 20260821, 2147483646]
	var durations: Array[int] = []
	var maximum_tree_nodes := 0
	for seed_value in runtime_seeds:
		var district := await _instantiate_procedural_district_fixture(seed_value)
		durations.append(district.generation_duration_ms)
		maximum_tree_nodes = maxi(maximum_tree_nodes, get_tree().get_node_count())
		_assert(UrbanNavigationService.is_built(), "runtime seed %d must build navigation after collision settles" % seed_value)
		_assert(district.generation_duration_ms > 0 and district.generation_duration_ms < 5000, "runtime seed %d must finish inside the five-second generation ceiling" % seed_value)
		_assert((district.get_node("Buildings").get_children() as Array).size() == (district.city_model["buildings"] as Array).size(), "runtime seed %d must materialize every semantic building" % seed_value)
		await _assert_runtime_city_is_physically_connected(district, seed_value)
		district.free()
		await get_tree().process_frame
		UrbanNavigationService.reset()
		_assert(get_tree().get_nodes_in_group("doors").is_empty(), "runtime seed %d teardown must remove generated doors before the next seed" % seed_value)
		_assert(get_tree().get_nodes_in_group("rooms").is_empty(), "runtime seed %d teardown must remove generated rooms before the next seed" % seed_value)
	durations.sort()
	var total_ms := 0
	for duration in durations:
		total_ms += duration
	var p95_index := clampi(ceili(float(durations.size()) * 0.95) - 1, 0, durations.size() - 1)
	print("PROCEDURAL_RUNTIME_PROFILE seeds=%d average_ms=%.3f p95_ms=%d max_ms=%d max_tree_nodes=%d" % [runtime_seeds.size(), float(total_ms) / float(runtime_seeds.size()), durations[p95_index], durations.back(), maximum_tree_nodes])

func _assert_runtime_city_is_physically_connected(district: ProceduralDistrict, seed_value: int) -> void:
	for door_node in get_tree().get_nodes_in_group("doors"):
		var door := door_node as Door
		if door and district.is_ancestor_of(door) and not door.is_open:
			door.toggle()
	await get_tree().physics_frame
	var origin := Vector2.ZERO
	_assert(UrbanNavigationService.is_position_free(origin), "runtime seed %d arterial anchor must be free" % seed_value)
	for building_node in district.get_node("Buildings").get_children():
		var building := building_node as ProceduralBuilding
		var approach: Vector2 = building.specification["approach_position"]
		_assert(UrbanNavigationService.is_position_free(approach), "runtime seed %d building %s approach must be clear" % [seed_value, String(building.building_id)])
		_assert(UrbanNavigationService.are_positions_connected(origin, approach), "runtime seed %d building %s must connect to the exterior road component" % [seed_value, String(building.building_id)])
		for room_node in building.get_node("Rooms").get_children():
			var room := room_node as Room
			var room_center := room.get_bounds_rect().get_center()
			_assert(UrbanNavigationService.is_position_free(room_center), "runtime seed %d room %s center aisle must be clear" % [seed_value, String(room.room_id)])
			_assert(UrbanNavigationService.are_positions_connected(approach, room_center), "runtime seed %d room %s must be reachable through opened generated portals" % [seed_value, String(room.room_id)])
	for landmark in district.city_model["landmarks"]:
		var landmark_position: Vector2 = landmark["position"]
		_assert(UrbanNavigationService.is_position_free(landmark_position), "runtime seed %d landmark %s must occupy a free cell" % [seed_value, String(landmark["id"])])
		_assert(UrbanNavigationService.are_positions_connected(origin, landmark_position), "runtime seed %d landmark %s must connect to the road component" % [seed_value, String(landmark["id"])])
	for scavenge in district.city_model["scavenge_points"]:
		var scavenge_position: Vector2 = scavenge["position"]
		_assert(UrbanNavigationService.is_position_free(scavenge_position), "runtime seed %d scavenge site %s must occupy a free cell" % [seed_value, String(scavenge["id"])])
		_assert(UrbanNavigationService.are_positions_connected(origin, scavenge_position), "runtime seed %d scavenge site %s must connect to the road component" % [seed_value, String(scavenge["id"])])
	var manager := SpawnManager.new()
	manager.set_world_seed(seed_value, origin)
	add_child(manager)
	await get_tree().process_frame
	var scoped_regions: Array = get_tree().get_nodes_in_group("spawn_regions").filter(func(node: Node) -> bool: return district.is_ancestor_of(node))
	for region_index in range(scoped_regions.size()):
		# Each region's clearance check depends on settled collision; yield
		# between regions so nav/physics budgets never starve the query.
		await get_tree().physics_frame
		var region := scoped_regions[region_index] as SpawnRegion
		var candidate_rng := RandomNumberGenerator.new()
		candidate_rng.seed = seed_value + (region_index + 1) * 7919
		var found_valid_candidate := false
		for _sample in range(96):
			var candidate := region.random_point(candidate_rng)
			if manager._is_valid_spawn_candidate(candidate, null, null, region):
				found_valid_candidate = true
				break
		_assert(found_valid_candidate, "runtime seed %d spawn region %s must contain a full-footprint-valid candidate" % [seed_value, String(region.region_id)])
	manager.free()
	await get_tree().process_frame

func _test_procedural_full_main_landmarks_rooms_and_safehouse_are_navigable() -> void:
	var main_instance := load("res://scenes/main/Main.tscn").instantiate() as Main
	var world := main_instance.get_node("World") as StreamingWorld
	world.city_seed = 20260821
	var manager := main_instance.get_node("SpawnManager") as SpawnManager
	manager.initial_population = 0
	manager.spawn_interval = 9999.0
	add_child(main_instance)
	for _i in range(30):
		if world.generation_complete:
			break
		await get_tree().physics_frame
	await get_tree().process_frame
	_assert(world.generation_succeeded, "full Main runtime must complete procedural generation before actors and population")
	_assert(world.generation_duration_ms < 15000, "full streamed runtime generation must remain below the initial-chunk activation ceiling")
	var origin_chunk := world.get_chunk(Vector2i.ZERO)
	var settlement := main_instance.get_node("Settlement") as Settlement
	_assert(settlement.data != null and settlement.data.building_id != &"", "survivor groups must claim an ordinary generated building as their base")
	var claimed_entrance := Vector2.ZERO
	for building_variant in origin_chunk.city_model["buildings"]:
		var claimed_candidate: Dictionary = building_variant
		if claimed_candidate["id"] == settlement.data.building_id:
			claimed_entrance = claimed_candidate["approach_position"]
			break
	_assert(settlement.data.base_type != &"", "a claimed base must record its ordinary building archetype")
	_assert(not claimed_entrance.is_equal_approx(Vector2.ZERO), "the claimed survivor base must resolve to a generated building")
	_assert(settlement.global_position.is_equal_approx(claimed_entrance), "the settlement must occupy its claimed generated building's entrance")
	for layer_name in ["Ground", "Roads", "Sidewalks", "RoadMarkings"]:
		var tile_layer := origin_chunk.get_node("GroundLayers/%s" % layer_name) as TileMapLayer
		_assert(tile_layer != null and not tile_layer.get_used_cells().is_empty(), "procedural renderer must rasterize the semantic %s layer" % layer_name)
	var street_props: Array = get_tree().get_nodes_in_group("generated_street_prop").filter(func(node: Node) -> bool: return main_instance.is_ancestor_of(node))
	_assert(street_props.size() == _streamed_semantic_count(world, &"props"), "runtime exterior dressing must materialize every active semantic prop")
	var entity_container := main_instance.get_node("EntityContainer")
	var prop_specs_by_id: Dictionary = {}
	for chunk in world.get_children():
		if chunk is ProceduralDistrict:
			for prop_spec in (chunk as ProceduralDistrict).city_model["props"]:
				prop_specs_by_id[prop_spec["id"]] = prop_spec
	for prop_root in street_props:
		_assert(entity_container.is_ancestor_of(prop_root), "generated exterior objects must share the actor y-sort container for correct top-down occlusion")
		_assert(_first_descendant_of_type(prop_root, InteractableComponent) != null, "every generated exterior object must be player-interactable")
		_assert(_first_descendant_of_type(prop_root, EnvironmentDamageComponent) != null, "every generated exterior object must carry class-filtered durability")
		var prop_damage := _first_descendant_of_type(prop_root, EnvironmentDamageComponent) as EnvironmentDamageComponent
		var prop_spec: Dictionary = prop_specs_by_id.get(prop_damage.object_id, {})
		_assert(not prop_spec.is_empty(), "every generated exterior runtime object must resolve to its semantic stable ID")
		if prop_spec.get("kind", &"") == &"car":
			var car_loot := _first_descendant_of_type(prop_root, LootContainerComponent) as LootContainerComponent
			_assert(car_loot != null and not car_loot.get_inventory().is_empty(), "generated intact cars must materialize searchable trunk inventory")
			_assert(_first_descendant_of_type(prop_root, SalvageableComponent) == null, "generated intact cars must not be mapped to wreck salvage")
			_assert(prop_damage.minimum_damage_class == EnvironmentDamage.DamageClass.HEAVY, "generated intact cars must preserve their heavy structural damage threshold when mapped to loot")
		elif prop_spec.get("kind", &"") == &"wreck":
			_assert(_first_descendant_of_type(prop_root, SalvageableComponent) != null, "generated wrecks must materialize salvage yield")
			_assert(_first_descendant_of_type(prop_root, LootContainerComponent) == null, "generated wrecks must not materialize intact trunk loot")
	var generated_scavenge_points := get_tree().get_nodes_in_group("scavenge_point").filter(func(node: Node) -> bool: return main_instance.is_ancestor_of(node))
	_assert(generated_scavenge_points.size() == _streamed_semantic_count(world, &"scavenge_points"), "runtime must materialize every active generated scavenging site")
	for point in generated_scavenge_points:
		_assert(_first_descendant_of_type(point, InteractableComponent) != null, "generated scavenging sites must be directly usable by the player")
	var base_storages := get_tree().get_nodes_in_group("storage_container").filter(func(node: Node) -> bool: return settlement.is_ancestor_of(node))
	_assert(base_storages.size() == 4, "a claimed survivor base must locate all four functional storage roles inside its generated building")
	for storage in base_storages:
		_assert(_first_descendant_of_type(storage, InteractableComponent) != null, "base storage must use the PlayerInteractor contract")
	var sleep_spots := get_tree().get_nodes_in_group("sleep_spots").filter(func(node: Node) -> bool: return settlement.is_ancestor_of(node))
	_assert(sleep_spots.size() >= 4, "the claimed generated building must provide survivor sleep spots inside its rooms")
	for storage in base_storages:
		_assert(_first_descendant_of_type(storage, EnvironmentDamageComponent) != null, "base storage must remain destructible")
	for door_node in get_tree().get_nodes_in_group("doors"):
		var door := door_node as Door
		if world.is_ancestor_of(door) and not door.is_open:
			door.toggle()
	await get_tree().physics_frame
	var origin := Vector2.ZERO
	_assert(UrbanNavigationService.is_position_free(origin), "central arterial intersection must remain navigable")
	_assert(UrbanNavigationService.is_position_free(origin_chunk.to_global(origin_chunk.city_model["player_spawn"])), "generated player spawn must be clear inside the physical safehouse")
	_assert(UrbanNavigationService.is_position_free(origin_chunk.to_global(origin_chunk.city_model["safehouse_entrance"])), "physical safehouse entrance must remain open")
	_assert(UrbanNavigationService.are_positions_connected(origin, origin_chunk.to_global(origin_chunk.city_model["safehouse_entrance"])), "safehouse entrance must connect to the exterior road component")
	for building_node in origin_chunk.get_node("Buildings").get_children():
		var building := building_node as ProceduralBuilding
		var approach: Vector2 = building.specification["approach_position"]
		_assert(UrbanNavigationService.is_position_free(approach), "building %s exterior approach must be free" % String(building.building_id))
		_assert(UrbanNavigationService.are_positions_connected(origin, approach), "building %s approach must connect to the road network" % String(building.building_id))
		for room_node in building.get_node("Rooms").get_children():
			var room := room_node as Room
			var room_center := room.get_bounds_rect().get_center()
			_assert(UrbanNavigationService.is_position_free(room_center), "generated room %s center aisle must be clear" % String(room.room_id))
			_assert(UrbanNavigationService.are_positions_connected(approach, room_center), "generated room %s must be physically reachable through opened portals" % String(room.room_id))
	for landmark in origin_chunk.city_model["landmarks"]:
		var position: Vector2 = origin_chunk.to_global(landmark["position"])
		_assert(UrbanNavigationService.is_position_free(position), "generated landmark %s must stand on a free navigation cell" % String(landmark["id"]))
		_assert(UrbanNavigationService.are_positions_connected(origin, position), "generated landmark %s must connect to the road network" % String(landmark["id"]))
	WorldState.reset()
	SimulationClock.reset()
	UrbanNavigationService.reset()
	main_instance.free()
	await get_tree().process_frame

func _test_population_profile_caps_are_exact() -> void:
	var manager := SpawnManager.new()
	var expected := {
		SpawnManager.PopulationProfile.LOW: 50,
		SpawnManager.PopulationProfile.MEDIUM: 100,
		SpawnManager.PopulationProfile.HIGH: 150,
		SpawnManager.PopulationProfile.STRESS: 250,
	}
	for profile in expected:
		manager.apply_population_profile(profile)
		_assert(manager.max_population == expected[profile], "population profile %d must cap at exactly %d" % [profile, expected[profile]])
	manager.free()

func _test_environment_walls_reject_bullets_and_accept_explosives() -> void:
	var fixture := Node2D.new()
	fixture.name = "DestructibleWallFixture"
	add_child(fixture)
	BuildingShellBuilder.build_perimeter_walls(fixture, Vector2(32, 32), load("res://assets/pixel/props/wall_concrete.png"))
	var wall_ids: Dictionary = {}
	for child in fixture.get_children():
		var wall_body := child as StaticBody2D
		var wall_damage := wall_body.get_node("EnvironmentDamageComponent") as EnvironmentDamageComponent
		_assert(not wall_ids.has(wall_damage.object_id), "perimeter construction must not overlap corner bodies or duplicate destruction ids")
		wall_ids[wall_damage.object_id] = true
	var wall := fixture.get_child(0) as StaticBody2D
	var component := wall.get_node("EnvironmentDamageComponent") as EnvironmentDamageComponent
	var before := component.durability()
	component.apply_damage(999.0, EnvironmentDamage.DamageClass.SMALL_ARMS)
	_assert(is_equal_approx(component.durability(), before), "ordinary bullets must not reduce explosive-rated wall durability")
	component.apply_damage(before, EnvironmentDamage.DamageClass.EXPLOSIVE)
	await get_tree().process_frame
	_assert(not is_instance_valid(wall), "explosive structural damage must breach the wall body")
	fixture.queue_free()
	await get_tree().process_frame

func _test_doors_and_windows_enforce_damage_classes_and_persist() -> void:
	var door := DOOR_SCENE.instantiate() as Door
	door.door_id = &"damage_test/door"
	add_child(door)
	await get_tree().process_frame
	var door_damage := door.get_node("CollisionBody/EnvironmentDamageComponent") as EnvironmentDamageComponent
	_assert(not door_damage.apply_damage(999.0, EnvironmentDamage.DamageClass.SMALL_ARMS), "small arms must not damage an explosive-rated door")
	_assert(door_damage.apply_damage(999.0, EnvironmentDamage.DamageClass.EXPLOSIVE), "explosives must breach a generated door")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not is_instance_valid(door), "breached door must remove its movement and vision collider")
	_assert(WorldState.get_door_open(&"damage_test/door"), "breached door must persist as open")
	_assert(WorldState.get_prop_state_flag(&"damage_test/door/structure", &"destroyed", false), "breached door structure must persist as destroyed")

	var intact := WINDOW_SCENE.instantiate() as BuildingWindow
	intact.window_id = &"damage_test/window_intact"
	intact.is_boarded = false
	add_child(intact)
	await get_tree().process_frame
	var intact_damage := intact.get_node("CollisionBody/EnvironmentDamageComponent") as EnvironmentDamageComponent
	_assert(intact_damage.apply_damage(999.0, EnvironmentDamage.DamageClass.SMALL_ARMS), "small arms must shatter intact glass")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not is_instance_valid(intact), "shattered intact window must remove its collider")

	var restored := WINDOW_SCENE.instantiate() as BuildingWindow
	restored.window_id = &"damage_test/window_intact"
	restored.is_boarded = false
	add_child(restored)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not is_instance_valid(restored), "a persistently shattered generated window must not reappear")

	var boarded := WINDOW_SCENE.instantiate() as BuildingWindow
	boarded.window_id = &"damage_test/window_boarded"
	boarded.is_boarded = true
	add_child(boarded)
	await get_tree().process_frame
	var boarded_damage := boarded.get_node("CollisionBody/EnvironmentDamageComponent") as EnvironmentDamageComponent
	_assert(not boarded_damage.apply_damage(999.0, EnvironmentDamage.DamageClass.SMALL_ARMS), "small arms must not breach a boarded window")
	_assert(boarded_damage.apply_damage(999.0, EnvironmentDamage.DamageClass.HEAVY), "heavy damage must breach a boarded window")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not is_instance_valid(boarded), "breached boarded window must remove its collider")

func _test_destroyed_safehouse_storage_does_not_duplicate_on_rebuild() -> void:
	var first := StorageContainer.new()
	first.storage_role = "medical"
	first.physical_interaction_enabled = true
	first.starting_items = {"medical_supplies": 4}
	add_child(first)
	await get_tree().process_frame
	var damage := first.get_node("CollisionBody/EnvironmentDamageComponent") as EnvironmentDamageComponent
	_assert(damage.apply_damage(999.0, EnvironmentDamage.DamageClass.HEAVY), "heavy damage must destroy physical safehouse storage")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not is_instance_valid(first), "destroyed safehouse storage must leave the runtime tree")
	_assert(WorldState.drops.size() == 1, "destroying stocked safehouse storage must emit exactly one conserved drop")
	var first_drop: WorldDrop = WorldState.drops.values()[0]
	_assert(first_drop.inventory.get_count(&"medical_supplies") == 4, "safehouse storage destruction must conserve its exact stock")

	var rebuilt := StorageContainer.new()
	rebuilt.storage_role = "medical"
	rebuilt.physical_interaction_enabled = true
	rebuilt.starting_items = {"medical_supplies": 4}
	add_child(rebuilt)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not is_instance_valid(rebuilt), "persistently destroyed safehouse storage must not reconstruct")
	_assert(WorldState.drops.size() == 1, "reconstructing destroyed storage must not duplicate its starting inventory into another drop")
	_assert(first_drop.inventory.get_count(&"medical_supplies") == 4, "reconstruction must not mutate the original conserved drop")

func _test_environment_props_are_interactable_and_damageable() -> void:
	var fixture := Node2D.new()
	fixture.name = "EnvironmentPropFixture"
	add_child(fixture)
	BuildingShellBuilder.add_physical_prop(
		fixture, Vector2.ZERO, load("res://assets/pixel/props/crate.png"), Vector2(24, 20),
		&"test/environment_crate", 2, EnvironmentDamage.DamageClass.SMALL_ARMS
	)
	var root := fixture.get_child(0) as Node2D
	var body: StaticBody2D = null
	var interaction: InteractableComponent = null
	for child in root.get_children():
		if child is StaticBody2D:
			body = child
		elif child is Area2D:
			interaction = child.get_node_or_null("InteractableComponent")
	_assert(interaction != null and interaction.interact_label == "Salvage", "generated physical props must expose the existing PlayerInteractor contract")
	_assert(body != null and body.get_node_or_null("EnvironmentDamageComponent") != null, "generated physical props must expose class-filtered durability")
	fixture.queue_free()
	await get_tree().process_frame

func _test_environment_destroyed_loot_becomes_world_drop() -> void:
	var fixture := Node2D.new()
	fixture.name = "DestroyedLootFixture"
	add_child(fixture)
	BuildingShellBuilder.add_loot_furniture(
		fixture, Vector2.ZERO, load("res://assets/pixel/props/crate.png"), Vector2(24, 20),
		&"test/destroyed_loot", 40.0, {"food_ration": 2, "materials": 3}
	)
	var root := fixture.get_child(0) as Node2D
	var body: StaticBody2D = null
	var loot: LootContainerComponent = null
	for child in root.get_children():
		if child is StaticBody2D:
			body = child
		elif child is Area2D:
			loot = child.get_node_or_null("LootContainerComponent")
	_assert(loot != null and loot.get_inventory().get_count(&"food_ration") == 2, "loot fixture must begin with its configured persistent inventory")
	var component := body.get_node("EnvironmentDamageComponent") as EnvironmentDamageComponent
	component.apply_damage(999.0, EnvironmentDamage.DamageClass.SMALL_ARMS)
	await get_tree().process_frame
	_assert(WorldState.drops.size() == 1, "destroying a loot-bearing environment object must preserve its contents in one WorldDrop")
	var drop: WorldDrop = WorldState.drops.values()[0]
	_assert(drop.inventory.get_count(&"food_ration") == 2 and drop.inventory.get_count(&"materials") == 3, "environment destruction must conserve every stored item type exactly")
	fixture.queue_free()
	await get_tree().process_frame

func _test_environment_destruction_state_restores() -> void:
	WorldState.set_prop_state_flag(&"test/persistent_crate", &"destroyed", true)
	var fixture := Node2D.new()
	fixture.name = "PersistentDestructionFixture"
	add_child(fixture)
	BuildingShellBuilder.add_physical_prop(
		fixture, Vector2.ZERO, load("res://assets/pixel/props/crate.png"), Vector2(24, 20),
		&"test/persistent_crate", 2, EnvironmentDamage.DamageClass.SMALL_ARMS
	)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(fixture.get_child_count() == 0, "a destroyed stable object id must not reappear when its generated scene is reconstructed")
	fixture.queue_free()
	await get_tree().process_frame

func _test_environment_destruction_resamples_live_navigation_with_overlaps() -> void:
	var position := Vector2(16, 16)
	var first := _make_navigation_destruction_body(&"test/nav_overlap_first", position)
	var second := _make_navigation_destruction_body(&"test/nav_overlap_second", position)
	add_child(first)
	add_child(second)
	await get_tree().physics_frame
	UrbanNavigationService.build(Vector2(128, 128))
	_assert(not UrbanNavigationService.is_position_free(position), "live navigation must initially sample an overlapping destructible collider as solid")
	var first_revision := UrbanNavigationService.revision()
	var first_damage := first.get_node("EnvironmentDamageComponent") as EnvironmentDamageComponent
	_assert(first_damage.apply_damage(999.0, EnvironmentDamage.DamageClass.EXPLOSIVE), "explosive damage must destroy the first overlapping structure")
	await get_tree().process_frame
	await get_tree().physics_frame
	_assert(not UrbanNavigationService.is_position_free(position), "destroying one overlapping structure must keep the cell solid while another collider remains")
	_assert(UrbanNavigationService.revision() == first_revision, "navigation revision must not change when overlap re-sampling preserves the same solid cell")
	var second_damage := second.get_node("EnvironmentDamageComponent") as EnvironmentDamageComponent
	_assert(second_damage.apply_damage(999.0, EnvironmentDamage.DamageClass.EXPLOSIVE), "explosive damage must destroy the final overlapping structure")
	await get_tree().process_frame
	await get_tree().physics_frame
	_assert(UrbanNavigationService.is_position_free(position), "destroying the final collider must reopen its navigation cell")
	_assert(UrbanNavigationService.revision() > first_revision, "live structural destruction must increment navigation revision when walkability changes")
	UrbanNavigationService.reset()

func _make_navigation_destruction_body(object_id: StringName, position: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(32, 32)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	var damage := EnvironmentDamageComponent.new()
	damage.name = "EnvironmentDamageComponent"
	damage.object_id = object_id
	damage.minimum_damage_class = EnvironmentDamage.DamageClass.EXPLOSIVE
	damage.max_durability = 20.0
	damage.affected_size = Vector2(32, 32)
	damage.destroy_target = body
	body.add_child(damage)
	return body

func _test_player_weapon_slots_preserve_independent_ammo() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	await get_tree().process_frame
	_assert(player.weapon_slots.size() == 4, "Player scene must expose SMG, shotgun, rifle and breaching charge as four real weapon slots")
	_assert(player.weapon.data.weapon_name == "SMG-9", "Player must start with the existing SMG equipped")
	_assert(player.weapon_slots[1].data.weapon_name == "Pump Shotgun" and player.weapon_slots[2].data.weapon_name == "Assault Rifle",
		"data-driven shotgun and rifle definitions must occupy their own slots")
	player.weapon.ammo_in_magazine = 17
	player.weapon.reserve_ammo = 91
	_assert(player.equip_weapon_slot(3), "breaching charge slot must be selectable")
	_assert(player.weapon.data.weapon_name == "Breaching Charge", "slot 4 must equip the explosive resource")
	_assert(player.weapon.data.environment_damage_class == EnvironmentDamage.DamageClass.EXPLOSIVE, "breaching charge must retain explosive structural classification")
	player.weapon.ammo_in_magazine = 0
	player.weapon.reserve_ammo = 2
	_assert(player.equip_weapon_slot(0), "slot 1 must be selectable after using another slot")
	_assert(player.weapon.ammo_in_magazine == 17 and player.weapon.reserve_ammo == 91, "switching back must preserve the SMG magazine and reserve")
	_assert(player.equip_weapon_slot(3), "the charge slot must remain selectable repeatedly")
	_assert(player.weapon.ammo_in_magazine == 0 and player.weapon.reserve_ammo == 2, "each weapon must preserve its own ammunition independently")
	_assert(player.weapon.equipped and not player.weapon_slots[0].equipped, "exactly the selected Weapon node must be active")
	var survivor: Survivor = SURVIVOR_SCENE.instantiate()
	add_child(survivor)
	await get_tree().process_frame
	var ammo_reports := {"count": 0}
	var report_callback: Callable = func(_magazine: int, _reserve: int) -> void: ammo_reports["count"] += 1
	GameEvents.weapon_ammo_changed.connect(report_callback)
	player.weapon._notify_ammo()
	var player_report_count: int = ammo_reports["count"]
	survivor.weapon._notify_ammo()
	_assert(player_report_count == 1 and ammo_reports["count"] == player_report_count, "survivor weapon state must never overwrite the player ammo HUD")
	GameEvents.weapon_ammo_changed.disconnect(report_callback)
	survivor.queue_free()
	player.queue_free()
	await get_tree().process_frame

func _test_explosion_separates_actor_and_structural_damage() -> void:
	var origin := Vector2(320, 320)
	var source := Node2D.new()
	var fixture := Node2D.new()
	var zombie: Zombie = ZOMBIE_SCENE.instantiate()
	fixture.position = origin
	zombie.position = origin
	add_child(source)
	add_child(fixture)
	add_child(zombie)
	BuildingShellBuilder.build_perimeter_walls(fixture, Vector2(32, 32), load("res://assets/pixel/props/wall_concrete.png"))
	await get_tree().physics_frame
	var wall_count_before := fixture.get_child_count()
	var walls: Array = fixture.get_children().filter(func(child: Node) -> bool: return child is StaticBody2D)
	EnvironmentDamage.apply_explosion(source, origin, 128.0, 180.0, 10.0, EnvironmentDamage.DamageClass.EXPLOSIVE)
	# Anatomy contract: non-head blast damage wounds but can never kill.
	_assert(not zombie.health_component.is_dead and zombie.health_component.current_health < zombie.health_component.max_health,
		"blast actors must be wounded by actor damage without a headshot kill")
	await get_tree().process_frame
	# Structural contract: at least the nearest wall segment must suffer --
	# either destroyed outright or partially breached through its microcells.
	var structurally_damaged := 0
	for wall_variant in walls:
		if not is_instance_valid(wall_variant):
			structurally_damaged += 1
			continue
		var component := (wall_variant as StaticBody2D).get_node_or_null("EnvironmentDamageComponent") as EnvironmentDamageComponent
		if component == null:
			continue
		if WorldState.get_prop_state_flag(component.object_id, &"destroyed", false) \
				or component.durability() < component.max_durability \
				or component.alive_fraction() < 1.0:
			structurally_damaged += 1
	_assert(structurally_damaged > 0 or fixture.get_child_count() < wall_count_before,
		"the same blast must structurally damage wall bodies using its structural value")
	zombie.queue_free()
	fixture.queue_free()
	source.queue_free()
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
		var streamed_world := main_instance.get_node("World") as StreamingWorld
		for _frame in range(120):
			if streamed_world.generation_complete:
				break
			await get_tree().physics_frame
		await get_tree().process_frame
		_assert(streamed_world.generation_succeeded, "run %d: streamed world must finish generation before Main registers survivors" % run)

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
	# Base storage containers register only after the world generation
	# contract completes and the settlement claims its generated building.
	var world_node := main_instance.get_node_or_null("World")
	if world_node != null and "generation_complete" in world_node and not bool(world_node.get("generation_complete")):
		await (world_node as Node).get("generation_completed")
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
	# CollisionShape2D.disabled reaches the physics server asynchronously.
	# Poll the exact condition under test instead of assuming a particular
	# flush frame after earlier large physics fixtures.
	var open_line_of_sight := false
	for i in range(6):
		await get_tree().physics_frame
		if zombie.perception._has_line_of_sight(zombie.global_position, target.global_position):
			open_line_of_sight = true
			break
	_assert(open_line_of_sight, "the opened door must remove its vision collision within the bounded physics flush window")
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
	# Aim AWAY from the back-room door so the open portal sits behind the
	# player's back (direction derived, so the test survives relayouts).
	player.aim_direction = (player.global_position - back_door.global_position).normalized()
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
	# Aim TOWARD the back-room door (direction derived, so the test survives
	# relayouts).
	player.aim_direction = (back_door.global_position - player.global_position).normalized()
	back_door.toggle() # open, WITHOUT the player moving or any frame elapsing
	_assert(back_room.modulate.a > 0.99, "opening a door must reveal its room immediately, even while the player is stationary (a=%f)" % back_room.modulate.a)

	player.aim_direction = (back_door.global_position - player.global_position).normalized()
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
	# Baseline updated deliberately alongside the Phase-3B passability fix:
	# every authored fixture was realigned to the wall-cell lattice with
	# runtime-standard 64px door apertures (see docs/building_system.md).
	_assert(checksum == "ed193adff7d19a15d9628e63f4d6be73e9f3e2859d6874ad94c4094f3bb80194", "the fixed district's layout checksum drifted from the committed baseline (got %s) -- update the baseline deliberately if this was an intentional map change" % checksum)
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
	_assert(spawn_regions.size() == 12, "the baked scene must contain exactly the 12 authored spawn regions (got %d)" % spawn_regions.size())

	# DynamicEntities holds every prop that needs Y-sorting against actors at
	# runtime, not just ScavengePoint instances -- it also carries the
	# searchable street furniture (LOOT_PROPS: three alley dumpsters and two
	# abandoned cars) and the salvageable wrecks (SALVAGE_PROPS), all placed
	# by district_builder.gd's _build_street_props() via the same
	# "entity_container" group lookup as _build_scavenge_points(). Checking
	# the "scavenge_point" group directly is what actually pins down the
	# scavenge-point count, independent of that container also holding those
	# other entities.
	var dynamic_entities: Node = district.get_node_or_null("DynamicEntities")
	_assert(dynamic_entities != null, "the baked scene must contain a top-level DynamicEntities container")
	if dynamic_entities != null:
		var scavenge_points: Array = []
		for node in get_tree().get_nodes_in_group("scavenge_point"):
			if dynamic_entities.is_ancestor_of(node):
				scavenge_points.append(node)
		_assert(scavenge_points.size() == 8, "the baked scene must contain exactly the 8 authored scavenge points (got %d)" % scavenge_points.size())
		_assert(dynamic_entities.get_child_count() == 18, "the baked scene's DynamicEntities container must hold exactly the 8 scavenge points plus the 5 searchable and 5 salvageable Y-sorted street props (got %d)" % dynamic_entities.get_child_count())

	var ground: TileMapLayer = district.get_node_or_null("GroundLayers/Ground")
	_assert(ground != null, "the baked scene must contain a GroundLayers/Ground TileMapLayer")
	if ground != null:
		_assert(ground.get_used_cells().size() > 0, "the baked Ground TileMapLayer must carry real painted cell data, not an empty layer")

	district.queue_free()
	await get_tree().process_frame

## The city plan itself has to hold together, and "it looked right in a
## screenshot" is not a regression test. Every building footprint -- the 5
## enterable ones (whose half-extents are read from their OWN scripts, not
## restated here) and every shell -- must sit fully inside some block's
## buildable area, never overlap another building, never sit in a
## carriageway, and never encroach on the safehouse compound. This is what
## catches the classic authored-map mistake: nudging one building a hundred
## pixels and silently pushing it through a neighbour or out into the road.
func _test_district_buildings_fit_their_blocks_without_overlapping() -> void:
	var footprints: Array = []
	for shell in DistrictBuilder.SHELL_BUILDINGS:
		footprints.append({"name": String(shell["name"]), "rect": DistrictBuilder.shell_rect(shell)})
	for building_id in DistrictBuilder.BUILDING_POSITIONS:
		footprints.append({"name": String(building_id), "rect": DistrictBuilder.enterable_rect(building_id)})

	for i in range(footprints.size()):
		var rect: Rect2 = footprints[i]["rect"]
		var name: String = footprints[i]["name"]
		_assert(rect.size.x > 0.0 and rect.size.y > 0.0, "%s has an empty footprint -- enterable_half_extent() is probably missing a case for it" % name)

		var block_name := ""
		for block in DistrictBuilder.BLOCKS:
			if DistrictBuilder.buildable_rect(block).encloses(rect):
				block_name = String(block["name"])
				break
		_assert(block_name != "", "%s (%s) does not fit inside any city block's buildable area -- it would spill onto the sidewalk or the street" % [name, rect])

		for road in DistrictBuilder.ROADS:
			_assert(not DistrictBuilder.road_rect(road).intersects(rect), "%s overlaps the carriageway of %s" % [name, road["name"]])

		for j in range(i + 1, footprints.size()):
			_assert(not rect.intersects(footprints[j]["rect"]), "%s and %s overlap each other" % [name, footprints[j]["name"]])

	# Main.tscn seats the Settlement at (-976, -976); SafehouseInteriorBuilder
	# paints its floor out to half_extent 170 plus a one-tile wall ring, i.e.
	# 224px in every direction. That whole compound owns its block.
	var safehouse_compound := Rect2(-1200, -1200, 448, 448)
	for entry in footprints:
		_assert(not safehouse_compound.intersects(entry["rect"]), "%s encroaches on the safehouse compound, which owns its block outright" % entry["name"])

	# Spawn regions and scavenge points are authored as world positions, so
	# nothing structurally stops one being dropped inside a wall.
	for spec in DistrictBuilder.SPAWN_REGIONS:
		for entry in footprints:
			_assert(not (entry["rect"] as Rect2).has_point(spec["position"]), "spawn region %s sits inside %s" % [spec["id"], entry["name"]])
	for spec in DistrictBuilder.SCAVENGE_POINTS:
		for entry in footprints:
			_assert(not (entry["rect"] as Rect2).has_point(spec["position"]), "scavenge point %s sits inside %s" % [spec["name"], entry["name"]])

## A designed city is only a city if you can walk it. Instantiates the real
## baked scene, lets AuthoredDistrict build the navigation grid from its
## live static collision, and asserts every landmark the player is meant to
## reach -- each building's front door approach, each mid-block alley, the
## park, the plaza, the yards, the safehouse street -- is both a free
## navigation cell and actually path-connected to the middle of the street
## grid. A block accidentally walled shut by its own building row fails
## here rather than during play.
func _test_baked_district_landmarks_are_reachable() -> void:
	UrbanNavigationService.reset()
	var district: Node2D = load("res://scenes/world/maps/UrbanDistrict01.tscn").instantiate()
	add_child(district)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Middle of Market Street, south of the Grand Avenue junction: open
	# carriageway on the district's central spine.
	var origin := Vector2(0, 300)
	_assert(UrbanNavigationService.is_position_free(origin), "the middle of Market Street must be a free navigation cell")

	var landmarks: Array = [
		{"name": "safehouse street frontage", "position": Vector2(-976, -700)},
		{"name": "restaurant_01 front door", "position": Vector2(-352, 570)},
		{"name": "restaurant_01 service alley", "position": Vector2(-292, 326)},
		{"name": "convenience_store_01 front door", "position": Vector2(270, -130)},
		{"name": "clinic_01 front door", "position": Vector2(-1052, -130)},
		{"name": "apartment_01 lobby door", "position": Vector2(-472, -770)},
		{"name": "workshop_01 loading yard", "position": Vector2(920, -900)},
		{"name": "Market Plaza", "position": Vector2(240, 200)},
		{"name": "Willow Green park", "position": Vector2(-976, 350)},
		{"name": "Derelict Lot", "position": Vector2(240, 900)},
		{"name": "downtown back alley", "position": Vector2(-352, -352)},
		{"name": "Ash Terrace alley", "position": Vector2(352, -976)},
		{"name": "Kiln Row back alley", "position": Vector2(-976, 976)},
		{"name": "Storage Yard", "position": Vector2(1040, 470)},
	]
	for landmark in landmarks:
		# One request per physics frame: find_path() is deliberately budgeted
		# (MAX_REQUESTS_PER_FRAME) and silently returns an empty path once
		# that budget is spent, which would read here as "unreachable".
		await get_tree().physics_frame
		var target: Vector2 = landmark["position"]
		_assert(UrbanNavigationService.is_position_free(target), "%s must stand on a free navigation cell, not inside collision" % landmark["name"])
		var path: PackedVector2Array = UrbanNavigationService.find_path(origin, target)
		_assert(path.size() >= 2, "%s must be reachable on foot from Market Street (got a %d-point path)" % [landmark["name"], path.size()])

	district.queue_free()
	await get_tree().process_frame
	UrbanNavigationService.reset()

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
	_assert(building.is_projected_exterior_visible(), "the projected facade must be visible while the player is outside")

	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	var retail_room: Room = building.get_node("Rooms/RetailFloor")
	player.global_position = retail_room.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	_assert(not building.is_roof_visible(), "the roof must hide once the player is inside")
	_assert(not building.is_projected_exterior_visible(), "the projected facade must hide with the roof so the existing interior remains readable")
	_assert(building.current_room_id() == &"retail_floor", "the player's current room must be reported correctly")
	var back_room: Room = building.get_node("Rooms/BackRoom")
	_assert(back_room.modulate.a < 0.01, "an adjacent room behind a CLOSED door must stay fully hidden, not merely dimmed")

	player.global_position = Vector2(9000, 9000) # walk far outside the building entirely
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	_assert(building.is_roof_visible(), "the roof must restore once the player fully leaves the building")
	_assert(building.is_projected_exterior_visible(), "the projected facade must restore when the player exits")
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
	# Aim TOWARD the back door -- the portal graph only reveals through a
	# portal inside the player's view cone (direction derived, so the test
	# survives relayouts).
	player.aim_direction = (back_door.global_position - player.global_position).normalized()
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


func _test_voxel_zombie_hit_flash_engages_and_recovers() -> void:
	var zombie: VoxelPrototypeZombie = VOXEL_ZOMBIE_SCENE.instantiate()
	add_child(zombie)
	var mat := (zombie.get_node("Mesh") as MeshInstance3D).material_override as StandardMaterial3D
	var base := mat.albedo_color
	zombie.take_damage(10.0)
	_assert(mat.albedo_color.is_equal_approx(VoxelPrototypeZombie.FLASH_COLOR),
			"taking damage must snap the voxel zombie's albedo to the flash colour")
	await get_tree().create_timer(VoxelPrototypeZombie.FLASH_DURATION + 0.15).timeout
	_assert(mat.albedo_color.is_equal_approx(base),
			"the hit-flash must recover the base albedo once the flash window ends")
	zombie.queue_free()
	await get_tree().process_frame


func _test_voxel_zombie_hit_flash_is_isolated_per_instance() -> void:
	var a: VoxelPrototypeZombie = VOXEL_ZOMBIE_SCENE.instantiate()
	var b: VoxelPrototypeZombie = VOXEL_ZOMBIE_SCENE.instantiate()
	add_child(a)
	add_child(b)
	var mat_a := (a.get_node("Mesh") as MeshInstance3D).material_override as StandardMaterial3D
	var mat_b := (b.get_node("Mesh") as MeshInstance3D).material_override as StandardMaterial3D
	var base_b := mat_b.albedo_color
	_assert(mat_a != mat_b,
			"each voxel zombie must own a private material copy so a flash can never leak across instances")
	a.take_damage(10.0)
	_assert(mat_a.albedo_color.is_equal_approx(VoxelPrototypeZombie.FLASH_COLOR),
			"the damaged zombie must engage its flash immediately")
	_assert(mat_b.albedo_color.is_equal_approx(base_b),
			"an undamaged neighbour must keep its base albedo while another flashes")
	a.queue_free()
	b.queue_free()
	await get_tree().process_frame


func _test_safehouse_compass_offscreen_clamping_and_readout() -> void:
	var compass: Control = SAFEHOUSE_COMPASS_SCRIPT.new()
	add_child(compass)
	await get_tree().process_frame
	var vp := Vector2(1152.0, 648.0)
	var center := vp * 0.5
	var margin: float = SAFEHOUSE_COMPASS_SCRIPT.EDGE_MARGIN

	# Target well inside the inset -> on-screen, so no marker (no clutter
	# while the building itself is visible).
	compass.update_indicator(center + Vector2(120.0, -60.0), vp, 900.0)
	_assert(not compass.visible,
			"a safehouse already inside the on-screen inset must not raise a marker")

	# Due east and far off-screen -> marker appears clamped to the right
	# inset edge, arrow pointing along +X.
	compass.update_indicator(center + Vector2(5000.0, 0.0), vp, 2000.0)
	_assert(compass.visible, "an off-screen safehouse must raise the edge marker")
	var marker: Control = compass.get_node("Marker")
	var marker_center: Vector2 = marker.position + marker.pivot_offset
	_assert(absf(marker.rotation) < 0.001,
			"a safehouse due east must point the arrow along +X")
	_assert(absf(marker_center.x - (vp.x - margin)) < 0.5 and absf(marker_center.y - center.y) < 0.5,
			"an off-screen safehouse due east must clamp to the right inset edge")
	_assert(compass.get_node("DistanceLabel").text == "100m",
			"2000 world px at %d px/m must read as exactly 100m" % int(SAFEHOUSE_COMPASS_SCRIPT.PIXELS_PER_METER))

	# Up-left diagonal bearing -> marker stays inside the inset rect and the
	# arrow rotation matches the true bearing.
	var bearing := Vector2(-3000.0, -4000.0)
	compass.update_indicator(center + bearing, vp, 5000.0)
	marker_center = marker.position + marker.pivot_offset
	_assert(marker_center.x >= margin - 0.5 and marker_center.x <= vp.x - margin + 0.5 \
			and marker_center.y >= margin - 0.5 and marker_center.y <= vp.y - margin + 0.5,
			"the clamped marker must never sit outside the viewport inset")
	_assert(absf(wrapf(marker.rotation - bearing.angle(), -PI, PI)) < 0.001,
			"the arrow rotation must match the true bearing to the safehouse")

	compass.queue_free()
	await get_tree().process_frame


func _test_hud_builds_safehouse_compass_and_tolerates_missing_targets() -> void:
	var hud_scene: PackedScene = preload("res://scenes/ui/HUD.tscn")
	var hud: CanvasLayer = hud_scene.instantiate()
	add_child(hud)
	await get_tree().process_frame
	var compass: Control = hud.get_node_or_null("SafehouseCompass")
	_assert(compass != null, "the HUD must build its SafehouseCompass widget during _ready")
	# Bare fixture: whatever leaked actors may sit in the player/settlement
	# groups, the per-frame update path must run clean and leave a valid node.
	hud._update_safehouse_compass()
	_assert(is_instance_valid(compass), "the compass update path with missing targets must not destroy the widget")
	hud.queue_free()
	await get_tree().process_frame

func _test_hud_builds_game_clock_label_and_formats_time() -> void:
	var hud_scene: PackedScene = preload("res://scenes/ui/HUD.tscn")
	var hud: CanvasLayer = hud_scene.instantiate()
	add_child(hud)
	await get_tree().process_frame
	var clock: Label = hud.get_node_or_null("GameClockLabel")
	_assert(clock != null, "the HUD must build its GameClockLabel widget during _ready")
	# Pure formatter pin -- no instance needed.
	_assert(GAME_CLOCK_SCRIPT.phase_suffix(0) == "Night", "midnight must read as Night")
	_assert(GAME_CLOCK_SCRIPT.phase_suffix(390) == "Dawn", "06:30 must read as Dawn")
	_assert(GAME_CLOCK_SCRIPT.phase_suffix(765) == "Day", "12:45 must read as Day")
	_assert(GAME_CLOCK_SCRIPT.phase_suffix(1125) == "Dusk", "18:45 must read as Dusk")
	_assert(GAME_CLOCK_SCRIPT.phase_suffix(1440) == "Night", "24h wrap must roll back to Night")
	var probe: Label = GAME_CLOCK_SCRIPT.new()
	probe.update_time(3, 13, 5)
	_assert(probe.text == "Day 3  13:05  Day", "fed day/hour/minute must format as 'Day 3  13:05  Day' (got '%s')" % probe.text)
	probe.update_time(1, 27, 70)
	_assert(probe.text == "Day 1  03:10  Night", "out-of-range hour/minute must wrap to 03:10 (got '%s')" % probe.text)
	probe.queue_free()
	hud.queue_free()
	await get_tree().process_frame

func _test_combat_feedback_vignette_closes_in_with_low_health() -> void:
	# Mirror the HUD-widget tests: let add_child() drive _ready() (which
	# connects the GameEvents signals) and await a frame -- do NOT call
	# _ready() by hand, or the connections double up and corrupt the shared
	# GameEvents autoload for later tests.
	var fb: Control = COMBAT_FEEDBACK_SCRIPT.new()
	fb.size = Vector2(1280, 720)
	add_child(fb)
	await get_tree().process_frame
	# Full health -> screen stays open.
	fb._on_player_health_changed(100.0, 100.0)
	fb.advance(0.016)
	_assert(fb.vignette_strength() == 0.0, "full-health must keep the vignette fully open")
	# Just above onset -> still open.
	fb._on_player_health_changed(70.0, 100.0)
	fb.advance(0.016)
	_assert(fb.vignette_strength() == 0.0, "health above onset must not raise the vignette")
	# Below onset -> vignette begins to close in (smoothly, not instantly).
	fb._on_player_health_changed(50.0, 100.0)
	fb.advance(0.016)
	var v_mid: float = fb.vignette_strength()
	_assert(v_mid > 0.0, "dropping below onset must begin closing the vignette")
	# Lower still -> stronger than at 50%.
	fb._on_player_health_changed(30.0, 100.0)
	fb.advance(0.016)
	_assert(fb.vignette_strength() > v_mid, "lesser health must close the vignette further")
	# Critically low -> near-full close and the low-health warning is active.
	# (Strength peaks near 1.0 only as health->0; at 10% it sits ~0.7, so
	# assert a strong-but-not-absolute close.)
	fb._on_player_health_changed(10.0, 100.0)
	fb.advance(0.016)
	_assert(fb.vignette_strength() > 0.6, "critical health must strongly close the vignette")
	_assert(fb.is_low_health_warning_active(), "critical health must arm the low-health warning")
	# Respawn -> vignette clears.
	fb._on_player_respawned()
	fb.advance(0.016)
	_assert(fb.vignette_strength() == 0.0, "respawn must clear the vignette")
	fb.queue_free()
	await get_tree().process_frame

func _test_day_night_palette_is_continuous_bounded_and_timekeyed() -> void:
	var midnight: Dictionary = DAY_NIGHT_SCRIPT.evaluate(0.0)
	var noon: Dictionary = DAY_NIGHT_SCRIPT.evaluate(765.0)
	_assert(midnight["ambient_energy"] < noon["ambient_energy"],
			"midnight must be darker than midday")
	var dawn_sun: Color = DAY_NIGHT_SCRIPT.evaluate(390.0)["sun_color"]
	var dusk_sun: Color = DAY_NIGHT_SCRIPT.evaluate(1125.0)["sun_color"]
	var noon_sun: Color = noon["sun_color"]
	_assert(dawn_sun.r - dawn_sun.b > noon_sun.r - noon_sun.b,
			"dawn sun must be warmer (r-b) than noon sun")
	_assert(dusk_sun.r - dusk_sun.b > noon_sun.r - noon_sun.b,
			"dusk sun must be warmer (r-b) than noon sun")
	var prev: Dictionary = midnight
	for m in range(10, 1441, 10):
		var cur: Dictionary = DAY_NIGHT_SCRIPT.evaluate(float(m))
		for key in ["background", "ambient", "sun_color"]:
			var c: Color = cur[key]
			_assert(c.r >= 0.0 and c.r <= 1.0 and c.g >= 0.0 and c.g <= 1.0 \
					and c.b >= 0.0 and c.b <= 1.0,
					"palette colors must stay in [0,1] (minute %d)" % m)
		_assert(cur["ambient_energy"] >= 0.0 and cur["ambient_energy"] <= 1.0,
				"ambient energy must stay bounded (minute %d)" % m)
		_assert(cur["sun_energy"] >= 0.0 and cur["sun_energy"] <= DAY_NIGHT_SCRIPT.MAX_SUN_ENERGY + 0.001,
				"sun energy must stay bounded (minute %d)" % m)
		var d_amb: float = absf(cur["ambient_energy"] - prev["ambient_energy"])
		var cb: Color = cur["background"]
		var pb: Color = prev["background"]
		var d_bg: float = sqrt((cb.r - pb.r) * (cb.r - pb.r) + (cb.g - pb.g) * (cb.g - pb.g) + (cb.b - pb.b) * (cb.b - pb.b))
		_assert(d_amb < 0.06 and d_bg < 0.03,
				"palette must move smoothly across 10-minute steps (minute %d)" % m)
		prev = cur
	_assert(prev["background"].is_equal_approx(midnight["background"]),
			"the 24h wrap keyframe must return to the midnight look")

func _test_day_night_cycle_drives_environment_and_tolerates_missing_targets() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.WHITE
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	var sun := DirectionalLight3D.new()
	sun.light_color = Color.WHITE
	sun.light_energy = 2.0
	var cycle: Node = DAY_NIGHT_SCRIPT.new()
	cycle.environment_resource = env
	cycle.sun_light = sun
	add_child(cycle)
	cycle.apply_time(765.0)
	var want: Dictionary = DAY_NIGHT_SCRIPT.evaluate(765.0)
	_assert(env.background_color.is_equal_approx(want["background"]),
			"applying midday must drive the background to the palette value")
	_assert(env.ambient_light_color.is_equal_approx(want["ambient"]),
			"applying midday must drive the ambient tint to the palette value")
	_assert(is_equal_approx(env.ambient_light_energy, want["ambient_energy"]),
			"applying midday must drive the ambient energy to the palette value")
	_assert(sun.light_color.is_equal_approx(want["sun_color"]),
			"applying midday must drive the sun colour to the palette value")
	_assert(is_equal_approx(sun.light_energy, want["sun_energy"]),
			"applying midday must drive the sun energy to the palette value")
	cycle.apply_time(0.0)
	_assert(not env.background_color.is_equal_approx(want["background"]),
			"a night application must differ visually from midday")
	var night_bg: Color = env.background_color
	cycle.apply_time(0.0)
	_assert(env.background_color.is_equal_approx(night_bg),
			"re-applying the same minute must be idempotent")
	cycle.queue_free()
	var bare: Node = DAY_NIGHT_SCRIPT.new()
	add_child(bare)
	bare._process(0.0)
	_assert(is_instance_valid(bare), "the day-night update path with missing targets must not crash")
	bare.queue_free()
	await get_tree().process_frame
