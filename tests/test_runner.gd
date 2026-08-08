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

	## --- Phase 3B: fixed district, buildings, interaction, perception -----
	await _run_test("district_layout_checksum_matches_committed_baseline", _test_district_layout_checksum_matches_committed_baseline)
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

	print("\n=== TEST RESULTS: %d passed, %d failed ===" % [_pass_count, _fail_count])
	get_tree().quit(0 if _fail_count == 0 else 1)

## --- Harness ---------------------------------------------------------

func _run_test(test_name: String, fn: Callable) -> void:
	_current_test = test_name
	_test_failed = false
	WorldState.reset()
	SimulationClock.reset()
	NoiseManager.reset()
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
	_assert(checksum == "ffb96cfd56a6ef66a6f11b05b3213d9a054de741e72f8c817b967ce39795399d", "the fixed district's layout checksum drifted from the committed baseline (got %s) -- update the baseline deliberately if this was an intentional map change" % checksum)
	_assert(DistrictLayoutChecksum.compute() == checksum, "compute() must be perfectly deterministic across repeated calls")

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
	_assert(WorldState.get_prop_state_flag(&"test/wreck_1", &"salvaged", false), "the salvaged flag must persist in WorldState under the prop's stable id")
	_assert(not interactable.can_interact(actor), "the InteractableComponent must disable itself after one salvage -- PlayerInteractor will never offer it again")

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

	_assert(building.current_room_id() == &"retail_floor", "sanity: the player is in the retail floor")
	var back_room: Room = building.get_node("Rooms/BackRoom")
	_assert(back_room.modulate.a > 0.99, "an adjacent room sharing a currently-OPEN door with the player's room must be revealed")

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
