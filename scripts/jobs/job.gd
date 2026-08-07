class_name Job
extends RefCounted
## One unit of settlement work coordinated by SettlementJobBoard: scavenging
## a resource point, hauling a specific reserved item stack between
## containers, guarding an entrance position, or treating a specific
## injured survivor. Plain data plus a couple of validity helpers -- the
## job board owns lifecycle transitions, actions own execution.

enum Type { SCAVENGE, HAUL, GUARD, HELP_INJURED }
enum Status { AVAILABLE, RESERVED, ACTIVE, COMPLETED, FAILED, CANCELLED }

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

func set_target(node: Node) -> void:
	_target_ref = weakref(node) if node else null
	if node:
		target_position = node.global_position

func get_target() -> Node:
	return _target_ref.get_ref() if _target_ref else null

## True when the job has no node target (pure-position jobs like guard) or
## its node target still exists. False means the job should be cancelled.
func is_target_valid() -> bool:
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
	}
