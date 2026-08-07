class_name Settlement
extends Node2D
## Prototype safehouse. Collects its own storage containers, sleep spots,
## and guard posts from its child tree (ownership, not a cross-cutting
## lookup, so direct tree traversal is appropriate here per
## docs/architecture.md), registers a SettlementData with WorldState, and
## tracks a danger level from nearby zombie presence.

@export var settlement_name: String = "Safehouse"
## A survivor/player inside this radius of the settlement origin is
## considered "safe" for utility-scoring purposes (SeekSafety/Sleep/Flee).
@export var safe_radius: float = 260.0
@export var danger_check_radius: float = 520.0
@export var danger_check_interval_ticks: int = 8

var data: SettlementData
var storage_containers: Dictionary = {} ## role String -> StorageContainer
var sleep_spots: Array[SleepSpot] = []
var guard_posts: Array[GuardPost] = []
var entrance: Node2D = null

func _ready() -> void:
	add_to_group("settlement")
	data = SettlementData.new()
	data.settlement_name = settlement_name
	WorldState.register_settlement(data)
	_collect_children(self)
	for role in storage_containers:
		data.storage_container_ids[role] = (storage_containers[role] as StorageContainer).container_id
	SimulationClock.sim_tick.connect(_on_sim_tick)

func setup_jobs(job_board: SettlementJobBoard) -> void:
	for post in guard_posts:
		job_board.create_job(Job.Type.GUARD, 2.0, &"", 1, post)

func get_container_id(role: String) -> int:
	var container: StorageContainer = storage_containers.get(role)
	return container.container_id if container else 0

func get_inventory(role: String) -> Inventory:
	var container: StorageContainer = storage_containers.get(role)
	return container.get_inventory() if container else null

func add_member(survivor_id: int) -> void:
	if not data.member_ids.has(survivor_id):
		data.member_ids.append(survivor_id)

func remove_member(survivor_id: int) -> void:
	data.member_ids.erase(survivor_id)

func is_position_safe(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= safe_radius

func get_free_sleep_spot(survivor_id: int) -> SleepSpot:
	for spot in sleep_spots:
		if spot.is_free() or spot.occupant_id() == survivor_id:
			return spot
	return null

func danger_level() -> float:
	return data.danger_level if data else 0.0

func _on_sim_tick(tick: int) -> void:
	if tick % danger_check_interval_ticks != 0:
		return
	_recompute_danger()

func _recompute_danger() -> void:
	var nearby: int = 0
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(zombie):
			continue
		if global_position.distance_to((zombie as Node2D).global_position) <= danger_check_radius:
			nearby += 1
	data.danger_level = clampf(float(nearby) * 6.0, 0.0, 100.0)

func _collect_children(node: Node) -> void:
	for child in node.get_children():
		if child is StorageContainer:
			storage_containers[(child as StorageContainer).storage_role] = child
		elif child is SleepSpot:
			sleep_spots.append(child)
		elif child is GuardPost:
			guard_posts.append(child)
		elif child.name == "Entrance":
			entrance = child
		_collect_children(child)
