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
## release_survivor() (called by SurvivorAI on death/interruption) frees a
## survivor's claim without losing the job, and periodic validation
## (staggered across sim ticks, not scanned every frame) cancels jobs whose
## node target disappeared out from under them.

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
	job.status = Job.Status.COMPLETED
	job_status_changed.emit(job)
	_remove_job(job)

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
## job itself -- called when a survivor dies or an emergency interrupts it,
## so the work (and any inventory reservation backing it) is still there
## for another survivor to pick up.
func release_survivor(survivor_id: int) -> void:
	for job in _jobs:
		if job.assigned_survivor_ids.has(survivor_id):
			job.assigned_survivor_ids.erase(survivor_id)
			if job.assigned_survivor_ids.is_empty() and job.status != Job.Status.AVAILABLE:
				job.status = Job.Status.AVAILABLE
				job_status_changed.emit(job)

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
