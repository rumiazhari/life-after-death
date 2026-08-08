class_name SettlementJobBoard
extends Node
## Coordinates multi-survivor-exclusive work for one settlement: scavenging
## a resource point, hauling a reserved item stack between containers,
## guarding an entrance position, and treating a specific injured survivor.
##
## Every job a survivor can see through get_available_jobs() is already
## exclusive at the data level (reserved inventory stack, or a worker-slot
## count on the job itself), so two survivors evaluating the same tick never
## end up committing to the same single unit of work. Jobs also self-heal:
## release_survivor() (called from an action's exit() on interruption)
## frees a survivor's claim without losing the job, and periodic validation
## (staggered across sim ticks, not scanned every frame) cancels jobs whose
## node target disappeared out from under them. A HAUL job whose cargo is
## already physically in a survivor's carried inventory (haul_phase
## IN_TRANSIT) is the one exception: release_survivor() leaves it alone
## (only the same survivor resuming, or release_survivor_permanently() on
## death, can resolve it) so the cargo is never stranded or claimable twice.

signal job_created(job: Job)
signal job_status_changed(job: Job)

## How many jobs get target-validated per sim tick -- keeps validation cost
## flat regardless of job count instead of scanning the whole list.
@export var jobs_validated_per_tick: int = 3

var settlement: Settlement
var _jobs: Array[Job] = []
var _validate_cursor: int = 0

func _ready() -> void:
	add_to_group("job_board")
	SimulationClock.sim_tick.connect(_on_sim_tick)

func _on_sim_tick(_tick: int) -> void:
	# Lazily resolved: JobBoard is a child of Settlement, so its own _ready()
	# runs *before* Settlement's (Godot readies bottom-up) -- the group
	# lookup can't succeed there. By the first sim tick (fired on a timer,
	# strictly after the whole scene has finished readying) it always can.
	if settlement == null:
		settlement = get_tree().get_first_node_in_group("settlement")
	_validate_some_jobs()
	_refresh_haul_jobs()

## --- Job creation -------------------------------------------------------

func create_job(job_type: Job.Type, priority: float, required_capability: StringName = &"", max_workers: int = 1, target_node: Node = null, target_position: Vector2 = Vector2.ZERO) -> Job:
	var job := Job.new()
	job.id = WorldState.next_job_id()
	job.job_type = job_type
	job.priority = priority
	job.required_capability = required_capability
	job.max_workers = max_workers
	if target_node:
		job.set_target(target_node)
	else:
		job.target_position = target_position
	_jobs.append(job)
	WorldState.register_job(job)
	job_created.emit(job)
	return job

## Reserves `amount` of `item_id` at the source container immediately, so
## the stack is exclusive to this job before any survivor claims it. Returns
## null if the source doesn't have enough unreserved stock. The job's
## target (leg 1, travel-to-pickup) is the source container node; dest_position
## (leg 2, travel-to-dropoff) is cached from the destination container.
func create_haul_job(source_container: StorageContainer, dest_container: StorageContainer, item_id: StringName, amount: int, priority: float) -> Job:
	var source: Inventory = source_container.get_inventory()
	var reservation_id: int = source.reserve(item_id, amount)
	if reservation_id == 0:
		return null
	var job := create_job(Job.Type.HAUL, priority, &"", 1, source_container)
	job.source_container_id = source_container.container_id
	job.dest_container_id = dest_container.container_id
	job.dest_position = dest_container.global_position
	job.reserved_item_id = item_id
	job.reserved_amount = amount
	job.reservation_id = reservation_id
	job.haul_phase = Job.HaulPhase.AWAITING_PICKUP
	return job

## --- Query ---------------------------------------------------------------

func get_available_jobs(capability: StringName, from_position: Vector2, max_distance: float = -1.0) -> Array[Job]:
	var result: Array[Job] = []
	for job in _jobs:
		if job.status != Job.Status.AVAILABLE and job.status != Job.Status.RESERVED:
			continue
		if not job.has_room_for_worker():
			continue
		if job.required_capability != &"" and job.required_capability != capability:
			continue
		if max_distance > 0.0 and from_position.distance_to(job.target_position) > max_distance:
			continue
		result.append(job)
	return result

func jobs_available_count() -> int:
	return _count_status(Job.Status.AVAILABLE)

func jobs_reserved_count() -> int:
	return _count_status(Job.Status.RESERVED)

func jobs_active_count() -> int:
	return _count_status(Job.Status.ACTIVE)

func total_job_count() -> int:
	return _jobs.size()

## --- Lifecycle ------------------------------------------------------------

func claim_job(job: Job, survivor_id: int) -> bool:
	if job.status != Job.Status.AVAILABLE and job.status != Job.Status.RESERVED:
		return false
	if not job.has_room_for_worker() or job.assigned_survivor_ids.has(survivor_id):
		return false
	job.assigned_survivor_ids.append(survivor_id)
	job.status = Job.Status.RESERVED
	job_status_changed.emit(job)
	return true

func start_job(job: Job) -> void:
	if job.status == Job.Status.RESERVED:
		job.status = Job.Status.ACTIVE
		job_status_changed.emit(job)

func complete_job(job: Job) -> void:
	if job.job_type == Job.Type.HAUL:
		job.haul_phase = Job.HaulPhase.DELIVERED
	job.status = Job.Status.COMPLETED
	job_status_changed.emit(job)
	_remove_job(job)

## Marks a HAUL job's cargo as now physically inside `survivor_id`'s own
## carried inventory. From this point the job is no longer "available
## work" for anyone else -- only this survivor can complete it (by
## resuming via get_in_transit_haul_job()) or, on death, forfeit it (see
## release_survivor_permanently()). Called by ActionHaulSupplies right
## after a successful pickup transfer.
func mark_picked_up(job: Job, survivor_id: int) -> void:
	job.haul_phase = Job.HaulPhase.IN_TRANSIT
	job.carrier_survivor_id = survivor_id
	## The source-side reservation was already consumed by the pickup
	## transfer; clearing this makes that permanent and unambiguous rather
	## than leaving a stale id an interruption path might try to re-release.
	job.reservation_id = 0

## The HAUL job (if any) whose cargo `survivor_id` is already physically
## carrying. ActionHaulSupplies checks this first on every reconsideration
## so an interrupted-after-pickup survivor resumes delivering what it's
## already holding instead of the job being lost track of.
func get_in_transit_haul_job(survivor_id: int) -> Job:
	for job in _jobs:
		if job.job_type == Job.Type.HAUL and job.haul_phase == Job.HaulPhase.IN_TRANSIT and job.carrier_survivor_id == survivor_id:
			return job
	return null

func fail_job(job: Job) -> void:
	_release_job_reservation(job)
	job.status = Job.Status.FAILED
	job_status_changed.emit(job)
	_remove_job(job)

func cancel_job(job: Job) -> void:
	_release_job_reservation(job)
	job.status = Job.Status.CANCELLED
	job_status_changed.emit(job)
	_remove_job(job)

## Drops one survivor's claim on every job it holds without cancelling the
## job itself -- called when an emergency interrupts a survivor (not when
## it dies; see release_survivor_permanently() for that), so the work (and
## any inventory reservation backing it) is still there for another
## survivor to pick up.
##
## Deliberately a no-op for a HAUL job the survivor has already physically
## picked up (haul_phase == IN_TRANSIT): the cargo is sitting in that
## survivor's own carried inventory, not claimable by anyone else, so
## reopening the job here would send a different survivor to walk to an
## already-emptied pickup point. Only the same survivor resuming (see
## get_in_transit_haul_job()) or dying (see release_survivor_permanently())
## can resolve it. This is enforced here, not just by callers remembering
## not to call this for that case, so the invariant holds regardless of caller.
func release_survivor(survivor_id: int) -> void:
	for job in _jobs:
		if not job.assigned_survivor_ids.has(survivor_id):
			continue
		if job.job_type == Job.Type.HAUL and job.haul_phase == Job.HaulPhase.IN_TRANSIT and job.carrier_survivor_id == survivor_id:
			continue
		job.assigned_survivor_ids.erase(survivor_id)
		if job.assigned_survivor_ids.is_empty() and job.status != Job.Status.AVAILABLE:
			job.status = Job.Status.AVAILABLE
			job_status_changed.emit(job)

## Permanent counterpart to release_survivor(), for when the survivor has
## died rather than merely being interrupted. Any HAUL job whose cargo it
## was physically carrying can never be completed -- the cargo was in its
## carried inventory, which is gone -- so that job fails outright instead
## of being reopened for a different survivor to walk to a dead end. Every
## other job the dead survivor held (including an AWAITING_PICKUP haul,
## whose source reservation is still intact) is released normally.
func release_survivor_permanently(survivor_id: int) -> void:
	var stranded_with_survivor: Array[Job] = []
	for job in _jobs:
		if job.job_type == Job.Type.HAUL and job.haul_phase == Job.HaulPhase.IN_TRANSIT and job.carrier_survivor_id == survivor_id:
			stranded_with_survivor.append(job)
	for job in stranded_with_survivor:
		fail_job(job)
	release_survivor(survivor_id)

## --- Internal --------------------------------------------------------------

func _count_status(status: Job.Status) -> int:
	var count: int = 0
	for job in _jobs:
		if job.status == status:
			count += 1
	return count

func _release_job_reservation(job: Job) -> void:
	if job.reservation_id != 0:
		var source: Inventory = WorldState.get_container(job.source_container_id)
		if source:
			source.release_reservation(job.reservation_id)
		job.reservation_id = 0

func _remove_job(job: Job) -> void:
	_jobs.erase(job)
	WorldState.unregister_job(job.id)

func _validate_some_jobs() -> void:
	if _jobs.is_empty():
		return
	var checked: int = 0
	var count: int = _jobs.size()
	while checked < jobs_validated_per_tick and checked < count:
		if _validate_cursor >= _jobs.size():
			_validate_cursor = 0
		var job: Job = _jobs[_validate_cursor]
		if not job.is_target_valid():
			cancel_job(job)
		else:
			_validate_cursor += 1
		checked += 1

## Keeps settlement storage sorted by creating HAUL jobs for any
## category-mismatched stock sitting in general storage (e.g. food that
## arrived via scavenging and hasn't been moved to food storage yet).
func _refresh_haul_jobs() -> void:
	if settlement == null:
		return
	var general_container: StorageContainer = settlement.storage_containers.get("general")
	if general_container == null:
		return
	var general: Inventory = general_container.get_inventory()
	var role_by_category := {
		ItemData.Category.FOOD: "food",
		ItemData.Category.WATER: "water",
		ItemData.Category.MEDICAL: "medical",
	}
	for category in role_by_category:
		for item_id in ItemDatabase.item_ids_in_category(category):
			var available: int = general.get_available(item_id)
			if available <= 0:
				continue
			if _has_pending_haul(general_container.container_id, item_id):
				continue
			var dest_container: StorageContainer = settlement.storage_containers.get(role_by_category[category])
			if dest_container == null:
				continue
			create_haul_job(general_container, dest_container, item_id, available, 3.0)

func _has_pending_haul(source_container_id: int, item_id: StringName) -> bool:
	for job in _jobs:
		if job.job_type == Job.Type.HAUL and job.source_container_id == source_container_id and job.reserved_item_id == item_id:
			return true
	return false
