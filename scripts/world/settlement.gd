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
	child_exiting_tree.connect(_on_child_exiting_tree)

## Direct children only (child_exiting_tree doesn't fire for grandchildren),
## which matches how storage containers are actually parented -- keeps
## storage_containers/data.storage_container_ids from ever holding a
## reference to a container that's leaving the tree, instead of relying on
## every reader to separately notice and clean up a stale entry.
func _on_child_exiting_tree(node: Node) -> void:
	if node is StorageContainer:
		var container := node as StorageContainer
		if storage_containers.get(container.storage_role) == container:
			storage_containers.erase(container.storage_role)
			if data:
				data.storage_container_ids.erase(container.storage_role)

## Registers (or re-registers) a StorageContainer as belonging to this
## settlement -- called by StorageContainer._enter_tree() when a container
## is reparented in after this settlement's own initial
## _collect_children() scan already ran. Deterministic on a role
## collision: whichever container already holds that role keeps it, and
## the newcomer is rejected (false) rather than silently overwriting a
## live container's slot.
func register_storage_container(container: StorageContainer) -> bool:
	var existing: StorageContainer = storage_containers.get(container.storage_role)
	if existing != null and is_instance_valid(existing) and existing != container:
		return false
	storage_containers[container.storage_role] = container
	if data:
		data.storage_container_ids[container.storage_role] = container.container_id
	return true

func setup_jobs(job_board: SettlementJobBoard) -> void:
	for post in guard_posts:
		job_board.create_job(Job.Type.GUARD, 2.0, &"", 1, post)

func get_container_id(role: String) -> int:
	var container: StorageContainer = storage_containers.get(role)
	if container == null or not is_instance_valid(container):
		return 0
	return container.container_id

func get_inventory(role: String) -> Inventory:
	var container: StorageContainer = storage_containers.get(role)
	if container == null or not is_instance_valid(container):
		return null
	return container.get_inventory()

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
