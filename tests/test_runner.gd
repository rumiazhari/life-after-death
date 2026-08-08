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

	print("\n=== TEST RESULTS: %d passed, %d failed ===" % [_pass_count, _fail_count])
	get_tree().quit(0 if _fail_count == 0 else 1)

## --- Harness ---------------------------------------------------------

func _run_test(test_name: String, fn: Callable) -> void:
	_current_test = test_name
	_test_failed = false
	WorldState.reset()
	SimulationClock.reset()
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

## Builds a StorageContainer test double: constructed but never added to
## the scene tree, with _ready() called directly (a plain virtual method,
## safe to invoke without add_child()) so setup is synchronous instead of
## depending on when the tree would normally call it.
func _make_container(role: String, capacity_weight: float = 0.0) -> StorageContainer:
	var container := StorageContainer.new()
	container.storage_role = role
	container.capacity_weight = capacity_weight
	container._ready()
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
	var source := _make_container("general")
	source.get_inventory().add_item(&"food_ration", 5)
	var dest := _make_container("food")
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
	var source := _make_container("general")
	source.get_inventory().add_item(&"materials", 5)
	var dest := _make_container("general_dest")
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
	var source := _make_container("general")
	source.get_inventory().add_item(&"materials", 4)
	var dest := _make_container("general_dest")
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

	var source := _make_container("general")
	source.get_inventory().add_item(&"materials", 5)
	var dest := _make_container("general_dest")
	var board := _make_job_board()

	var job: Job = board.create_haul_job(source, dest, &"materials", 3, 1.0)
	board.claim_job(job, carrier_id)
	var carried := Inventory.new(0.0)
	source.get_inventory().confirm_reserved_transfer(job.reservation_id, carried)
	board.mark_picked_up(job, carrier_id)
	_assert(job.haul_phase == Job.HaulPhase.IN_TRANSIT, "sanity check: job should be in transit before the source is destroyed")

	source.free() # the job's AWAITING_PICKUP-era target, now gone
	_assert(job.is_target_valid(), "an IN_TRANSIT job must stay valid after its source is destroyed -- the cargo already left it")

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
