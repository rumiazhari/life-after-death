class_name Job
extends RefCounted
## One unit of settlement work coordinated by SettlementJobBoard: scavenging
## a resource point, hauling a specific reserved item stack between
## containers, guarding an entrance position, or treating a specific
## injured survivor. Plain data plus a couple of validity helpers -- the
## job board owns lifecycle transitions, actions own execution.

enum Type { SCAVENGE, HAUL, GUARD, HELP_INJURED }
enum Status { AVAILABLE, RESERVED, ACTIVE, COMPLETED, FAILED, CANCELLED }
## HAUL-specific sub-state, tracked independently of Status because Status
## alone can't distinguish "claimed and traveling to pick up" from "cargo
## physically in the carrier's own inventory" -- Status flips to ACTIVE on
## the very first tick (see SettlementJobBoard.start_job callers), well
## before pickup actually happens. NONE for non-HAUL job types.
enum HaulPhase { NONE, AWAITING_PICKUP, IN_TRANSIT, DELIVERED }

var id: int = 0
var job_type: Type = Type.SCAVENGE
var status: Status = Status.AVAILABLE
var priority: float = 0.0
## "" = any survivor can take this job; otherwise a SurvivorData skill field
## name ("combat_skill", "medical_skill", "scavenging_skill", ...).
var required_capability: StringName = &""
var max_workers: int = 1
var assigned_survivor_ids: Array[int] = []

var target_position: Vector2 = Vector2.ZERO
var _target_ref: WeakRef = null

## HAUL-specific: the item stack this job already claimed at creation time
## (see SettlementJobBoard.create_haul_job), so the stack is exclusive to
## this job the moment it exists, before any survivor has even claimed it.
## target_position (set via set_target(source_container)) is leg 1 of the
## haul; dest_position is leg 2.
var source_container_id: int = 0
var dest_container_id: int = 0
var dest_position: Vector2 = Vector2.ZERO
var reserved_item_id: StringName = &""
var reserved_amount: int = 0
var reservation_id: int = 0
var haul_phase: HaulPhase = HaulPhase.NONE
## Survivor id physically carrying the cargo once haul_phase is IN_TRANSIT.
## 0 = nobody (not a HAUL job, or not picked up yet).
var carrier_survivor_id: int = 0

func set_target(node: Node) -> void:
	_target_ref = weakref(node) if node else null
	if node:
		target_position = node.global_position

func get_target() -> Node:
	return _target_ref.get_ref() if _target_ref else null

## True when the job's target is still meaningful and it should keep
## existing; false means periodic validation should cancel it.
##
## Phase-aware for HAUL jobs, since Status alone can't tell "claimed and
## traveling to pick up" from "cargo already in the carrier's own
## inventory" (Status flips to ACTIVE on the very first tick, well before
## pickup actually happens):
## - AWAITING_PICKUP validates the source container (this job's
##   _target_ref, i.e. leg 1) is still registered and its reservation
##   still live -- both must hold for a pickup to ever succeed.
## - IN_TRANSIT deliberately does NOT revalidate the source: the cargo
##   already left it, physically carried by carrier_survivor_id, so the
##   source disappearing after pickup must never cancel a job whose cargo
##   is safe in a survivor's inventory. ActionHaulSupplies' own dropoff
##   retry/fallback logic (not this method) is what resolves a stuck
##   delivery. The only thing checked here is that the carrier itself
##   still exists -- if not (freed without going through the normal death
##   path, which would have already failed this job), the cargo can never
##   be delivered and the job should be cleaned up.
func is_target_valid() -> bool:
	if job_type == Type.HAUL:
		if haul_phase == HaulPhase.IN_TRANSIT:
			return WorldState.is_survivor_alive(carrier_survivor_id)
		if haul_phase == HaulPhase.AWAITING_PICKUP:
			var source: Inventory = WorldState.get_container(source_container_id)
			if source == null or not source.has_reservation(reservation_id):
				return false
			# Fall through to also confirm the source container node
			# itself (this job's _target_ref) still exists.
	if _target_ref == null:
		return true
	return is_instance_valid(_target_ref.get_ref())

func has_room_for_worker() -> bool:
	return assigned_survivor_ids.size() < max_workers

func to_dict() -> Dictionary:
	return {
		"id": id,
		"job_type": job_type,
		"status": status,
		"priority": priority,
		"required_capability": String(required_capability),
		"max_workers": max_workers,
		"assigned_survivor_ids": assigned_survivor_ids.duplicate(),
		"reserved_item_id": String(reserved_item_id),
		"reserved_amount": reserved_amount,
		"haul_phase": haul_phase,
		"carrier_survivor_id": carrier_survivor_id,
	}
