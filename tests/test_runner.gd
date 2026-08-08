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
## runs) so tests can't leak state into each other, and exercises the real
## production code (Inventory, ScavengePoint, Job, SettlementJobBoard,
## WorldState, SimulationClock) directly rather than reimplementing it --
## StorageContainer/SettlementJobBoard instances are constructed with
## `.new()` and have `_ready()` called on them explicitly (a plain virtual
## method, safe to call directly) instead of waiting on scene-tree
## add_child() timing, which keeps every test fully synchronous and
## deterministic.

var _pass_count: int = 0
var _fail_count: int = 0
var _current_test: String = ""
var _test_failed: bool = false

func _ready() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	_run_test("reserved_transfer_success", _test_reserved_transfer_success)
	_run_test("reserved_transfer_failure_full_destination", _test_reserved_transfer_failure)
	_run_test("reservation_release_after_interruption", _test_reservation_release_after_interruption)
	_run_test("partial_scavenge_capacity", _test_partial_scavenge_capacity)
	_run_test("zero_capacity_scavenge", _test_zero_capacity_scavenge)
	_run_test("haul_interrupt_before_pickup", _test_haul_interrupt_before_pickup)
	_run_test("haul_interrupt_after_pickup", _test_haul_interrupt_after_pickup)
	_run_test("survivor_death_retains_data", _test_survivor_death_retains_data)
	_run_test("restart_resets_ids_and_time", _test_restart_resets_ids_and_time)
	_run_test("reservation_create_release_cycle", _test_reservation_cycle)

	print("\n=== TEST RESULTS: %d passed, %d failed ===" % [_pass_count, _fail_count])
	get_tree().quit(0 if _fail_count == 0 else 1)

## --- Harness ---------------------------------------------------------

func _run_test(test_name: String, fn: Callable) -> void:
	_current_test = test_name
	_test_failed = false
	WorldState.reset()
	SimulationClock.reset()
	fn.call()
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
