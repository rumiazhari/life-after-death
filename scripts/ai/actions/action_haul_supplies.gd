class_name ActionHaulSupplies
extends UtilityAction
## Moves items into settlement storage in two ways:
##
## 1. "Bring my loot home" -- a survivor carrying scavenged stock it doesn't
##    urgently need itself (materials always qualify; food/water/medical
##    qualify once that particular need isn't currently urgent) walks to
##    general storage and deposits it. No reservation needed: the stack is
##    already exclusively in that survivor's own carried inventory.
## 2. Job-board HAUL jobs -- auto-created by SettlementJobBoard when general
##    storage ends up holding stock that belongs in food/water/medical
##    storage (which is exactly what path 1 produces), carried in two travel
##    legs (pickup, dropoff) and completed on drop-off.
##
## Together these are "Survivors collect nearby supplies and return them to
## storage" (ActionScavenge deposits into a survivor's own inventory;
## this action is what actually gets it into the settlement).
##
## Once a HAUL job's pickup leg succeeds, the cargo is physically in this
## survivor's own carried inventory and the job is marked IN_TRANSIT
## (Job.haul_phase) -- if interrupted before dropoff, enter() finds and
## resumes that same job via SettlementJobBoard.get_in_transit_haul_job()
## instead of re-scanning for new work, so the cargo is never abandoned or
## claimable by anyone else mid-delivery.
##
## If the dropoff destination stays full for longer than
## dropoff_retry_timeout (or is permanently missing), _redirect_stalled_cargo()
## gives up on it: the cargo goes to the settlement's general storage as a
## fallback, or -- if even that can't accept it -- becomes a recoverable
## WorldDrop at the survivor's current position. Either way the job
## resolves to FAILED exactly once; the cargo itself is never lost.

const SEARCH_RADIUS := 2000.0

var _job: Job = null
var _picked_up: bool = false
var _personal_item: StringName = &""
var _personal_container: StorageContainer = null

## How long (seconds) to keep retrying a full dropoff destination before
## redirecting the cargo to fallback (general) storage or a world drop. A
## var, not a const, so tests can shrink it instead of waiting out the
## default -- see _redirect_stalled_cargo().
var dropoff_retry_timeout: float = 8.0
var _dropoff_stall_timer: float = 0.0

func _init() -> void:
	action_name = &"haul_supplies"
	interrupt_cost = 0.15

func can_start(ai: SurvivorAI) -> bool:
	return ai.job_board != null or ai.settlement != null

func score(ai: SurvivorAI) -> float:
	if ai.job_board and ai.job_board.get_in_transit_haul_job(ai.data.id) != null:
		# Already physically carrying a job's cargo -- always finish
		# delivering it rather than picking a fresh haul/personal-carry
		# target and leaving that cargo stranded indefinitely.
		return 1.15
	return maxf(_best_job_score(ai), _personal_carry_score(ai))

func enter(ai: SurvivorAI) -> void:
	_job = null
	_personal_item = &""
	_personal_container = null
	_picked_up = false
	_dropoff_stall_timer = 0.0

	var resume_job: Job = ai.job_board.get_in_transit_haul_job(ai.data.id) if ai.job_board else null
	if resume_job:
		_job = resume_job
		ai.current_job = _job
		_picked_up = true
		return

	var prefer_job: bool = _best_job_score(ai) >= _personal_carry_score(ai)
	var committed: bool = false
	if prefer_job:
		committed = _claim_best_job(ai)
	if not committed:
		_start_personal_carry(ai)
		committed = _personal_item != &""
	# Whichever path scored higher failed to actually commit (race lost to
	# another survivor, container vanished) -- fall back to the other.
	if not committed and not prefer_job:
		_claim_best_job(ai)

func tick(ai: SurvivorAI, delta: float) -> bool:
	if _personal_item != &"":
		return _tick_personal_carry(ai, delta)
	return _tick_job(ai, delta)

func exit(ai: SurvivorAI) -> void:
	# Only release the claim if pickup hasn't happened yet -- the source
	# reservation is still intact then, so another survivor can safely pick
	# this job up. Once cargo is physically in this survivor's own carried
	# inventory (_picked_up), releasing the claim would let someone else
	# walk to an already-emptied pickup point while the real cargo sits
	# untracked with this survivor; leaving the job assigned lets
	# get_in_transit_haul_job() find it again on resume instead.
	if _job and not _picked_up:
		ai.job_board.release_survivor(ai.data.id)
	_job = null
	_picked_up = false
	_personal_item = &""
	_personal_container = null

## --- Path 1: personal carry-home --------------------------------------

func _personal_carry_score(ai: SurvivorAI) -> float:
	if ai.settlement == null or ai.settlement.storage_containers.get("general") == null:
		return 0.0
	var item: StringName = _find_surplus_item(ai)
	if item == &"":
		return 0.0
	var diligent: float = ai.data.personality.get("diligent", 0.0)
	return 0.45 + diligent * 0.25

func _start_personal_carry(ai: SurvivorAI) -> void:
	var item: StringName = _find_surplus_item(ai)
	if item == &"":
		return
	var container: StorageContainer = ai.settlement.storage_containers.get("general")
	if container == null:
		return
	_personal_item = item
	_personal_container = container

func _tick_personal_carry(ai: SurvivorAI, delta: float) -> bool:
	if _personal_container == null or not is_instance_valid(_personal_container):
		return true
	var carried: Inventory = ai.survivor.carried_inventory
	var amount: int = carried.get_count(_personal_item)
	if amount <= 0:
		return true
	ai.reserved_target_description = "hauling %s home" % _personal_item
	var arrived: bool = ai.survivor.move_toward_point(_personal_container.global_position, delta)
	if not arrived:
		return false
	Inventory.transfer_item(carried, _personal_container.get_inventory(), _personal_item, amount)
	return true

## Materials always count as surplus (nothing consumes them personally);
## food/water/medical only count once that need isn't currently urgent, so
## a hungry survivor eats what it just scavenged instead of dutifully
## walking it past its own mouth to storage first.
func _find_surplus_item(ai: SurvivorAI) -> StringName:
	var carried: Inventory = ai.survivor.carried_inventory
	if carried.get_count(&"materials") > 0:
		return &"materials"
	if carried.get_count(&"food_ration") > 0 and UtilityMath.urgency(ai.data.hunger, 15.0) <= 0.0:
		return &"food_ration"
	if carried.get_count(&"water_bottle") > 0 and UtilityMath.urgency(ai.data.thirst, 15.0) <= 0.0:
		return &"water_bottle"
	if carried.get_count(&"medical_supplies") > 0:
		var missing_ratio: float = 1.0 - ai.data.health / maxf(ai.data.max_health, 1.0)
		if missing_ratio < 0.15 and ai.data.infection_exposure < 15.0:
			return &"medical_supplies"
	return &""

## --- Path 2: job-board general -> role-storage sorting -----------------

func _best_job_score(ai: SurvivorAI) -> float:
	if ai.job_board == null:
		return 0.0
	var best: float = 0.0
	for job in ai.job_board.get_available_jobs(&"", ai.survivor.global_position, SEARCH_RADIUS):
		if job.job_type != Job.Type.HAUL:
			continue
		best = maxf(best, _score_job(ai, job))
	return best

func _claim_best_job(ai: SurvivorAI) -> bool:
	if ai.job_board == null:
		return false
	var best_job: Job = null
	var best_score: float = -1.0
	for job in ai.job_board.get_available_jobs(&"", ai.survivor.global_position, SEARCH_RADIUS):
		if job.job_type != Job.Type.HAUL:
			continue
		var s: float = _score_job(ai, job)
		if s > best_score:
			best_score = s
			best_job = job
	if best_job and ai.job_board.claim_job(best_job, ai.data.id):
		_job = best_job
		ai.current_job = _job
		_picked_up = false
		return true
	return false

func _tick_job(ai: SurvivorAI, delta: float) -> bool:
	if _job == null or not _job.is_target_valid():
		return true
	if _job.status == Job.Status.RESERVED:
		ai.job_board.start_job(_job)
	if not _picked_up:
		ai.reserved_target_description = "hauling: pickup %s" % _job.reserved_item_id
		var arrived: bool = ai.survivor.move_toward_point(_job.target_position, delta)
		if not arrived:
			return false
		var source: Inventory = WorldState.get_container(_job.source_container_id)
		if source == null or not source.confirm_reserved_transfer(_job.reservation_id, ai.survivor.carried_inventory):
			ai.job_board.fail_job(_job)
			_job = null
			return true
		ai.job_board.mark_picked_up(_job, ai.data.id)
		_picked_up = true
		return false
	ai.reserved_target_description = "hauling: dropoff %s" % _job.reserved_item_id
	var arrived_dest: bool = ai.survivor.move_toward_point(_job.dest_position, delta)
	if not arrived_dest:
		return false
	var dest: Inventory = WorldState.get_container(_job.dest_container_id)
	if dest != null and Inventory.transfer_item(ai.survivor.carried_inventory, dest, _job.reserved_item_id, _job.reserved_amount):
		ai.job_board.complete_job(_job)
		_job = null
		_dropoff_stall_timer = 0.0
		return true
	if dest == null:
		# Permanently invalid destination (container no longer registered) --
		# no amount of waiting will fix this, so redirect immediately
		# instead of accumulating toward the retry timeout for nothing.
		return _redirect_stalled_cargo(ai)
	# Destination exists but is (still) full -- a transient, potentially-
	# recoverable condition, so retry up to dropoff_retry_timeout before
	# giving up on it and redirecting the cargo elsewhere. The cargo stays
	# safely in the survivor's own carried inventory the whole time either
	# way; nothing is ever lost, duplicated, or looped on forever.
	_dropoff_stall_timer += delta
	if _dropoff_stall_timer < dropoff_retry_timeout:
		return false
	return _redirect_stalled_cargo(ai)

## Called once the dropoff destination has proven unusable (permanently
## missing, or full for longer than dropoff_retry_timeout). Tries the
## settlement's general storage as a fallback; if that can't take it
## either, the cargo becomes a recoverable WorldDrop at the survivor's
## current position. Either way the job resolves to FAILED here -- exactly
## once -- since it was never delivered to its originally intended
## destination even though the cargo itself is safe.
func _redirect_stalled_cargo(ai: SurvivorAI) -> bool:
	_dropoff_stall_timer = 0.0
	var item_id: StringName = _job.reserved_item_id
	var carried: Inventory = ai.survivor.carried_inventory
	# Only ever redirect what's actually still physically carried -- never
	# fabricates cargo, and if something else already consumed/moved part
	# of it in the meantime, redirects exactly the remainder.
	var to_redirect: int = mini(_job.reserved_amount, carried.get_count(item_id))
	if to_redirect <= 0:
		ai.job_board.fail_job(_job)
		_job = null
		return true

	var fallback: StorageContainer = ai.settlement.storage_containers.get("general") if ai.settlement else null
	if fallback and fallback.container_id != _job.dest_container_id and Inventory.transfer_item(carried, fallback.get_inventory(), item_id, to_redirect):
		ai.job_board.fail_job(_job)
		_job = null
		return true

	var drop := WorldDrop.new()
	drop.position = ai.survivor.global_position
	drop.source_survivor_id = ai.data.id
	drop.created_tick = SimulationClock.tick_count
	drop.reason = &"haul_stalled"
	drop.inventory = Inventory.new(0.0)
	Inventory.transfer_item(carried, drop.inventory, item_id, to_redirect)
	WorldState.register_drop(drop)
	ai.job_board.fail_job(_job)
	_job = null
	return true

func _score_job(ai: SurvivorAI, job: Job) -> float:
	var distance: float = ai.survivor.global_position.distance_to(job.target_position)
	var diligent: float = ai.data.personality.get("diligent", 0.0)
	var benefit: float = 0.35 + diligent * 0.3
	var cost: float = UtilityMath.distance_cost(distance, SEARCH_RADIUS)
	return clampf(benefit - cost * 0.3, 0.0, 1.0)
