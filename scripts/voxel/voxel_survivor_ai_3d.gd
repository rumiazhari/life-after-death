class_name VoxelSurvivorAI3D
extends Node

const UTILITY := preload("res://scripts/ai/utility_math.gd")
const COORDINATES := preload("res://scripts/voxel/voxel_coordinates.gd")

@export var decision_interval := 0.75
@export var need_tick_seconds := 1.0
@export var scavenge_work_seconds := 0.5
@export var perception_radius := 8.0

var survivor
var data: SurvivorData
var world_data
var navigation_service
var job_board
var settlement_runtime
var current_action: StringName = &"idle"
var reserved_target_id: StringName = &""
var last_scores: Dictionary = {}
var _decision_remaining := 0.0
var _need_remaining := 0.0
var _work_remaining := 0.0
var _started := false
var _retrieve_item: StringName = &""
var _help_target: Node3D
var decisions_made := 0
var actions_evaluated := 0
var _decision_time_total_usec := 0


func _ready() -> void:
	survivor = get_parent()
	set_physics_process(false)


func configure(world, navigation, board, settlement_services = null) -> void:
	world_data = world
	navigation_service = navigation
	job_board = board
	settlement_runtime = settlement_services


func begin(survivor_data: SurvivorData) -> void:
	data = survivor_data
	_started = true
	set_physics_process(true)
	force_reconsider()


func stop() -> void:
	_release_reservation()
	current_action = &"idle"
	if data != null:
		data.current_action = "idle"
	_started = false
	set_physics_process(false)


func force_reconsider() -> void:
	_decision_remaining = 0.0
	_reconsider()


func _physics_process(delta: float) -> void:
	if not _started or data == null or data.is_dead:
		return
	_need_remaining -= delta
	if _need_remaining <= 0.0:
		_need_remaining = need_tick_seconds
		data.hunger = minf(data.hunger + 0.18, 100.0)
		data.thirst = minf(data.thirst + 0.26, 100.0)
		data.fatigue = minf(data.fatigue + 0.12, 100.0)
	_tick_action(delta)
	_decision_remaining -= delta
	if _decision_remaining <= 0.0:
		_decision_remaining = decision_interval
		_reconsider()


func _reconsider() -> void:
	var started_at := Time.get_ticks_usec()
	var scores := {
		&"idle": 0.05,
		&"eat": UTILITY.urgency(data.hunger, 15.0) * 1.3 if survivor.carried_inventory.get_count(&"food_ration") > 0 else 0.0,
		&"drink": UTILITY.urgency(data.thirst, 15.0) * 1.35 if survivor.carried_inventory.get_count(&"water_bottle") > 0 else 0.0,
		&"treat_self": _treat_self_score(),
		&"help_injured": _help_injured_score(),
		&"flee": _flee_score(),
		&"fight": _fight_score(),
		&"seek_safety": _seek_safety_score(),
		&"deposit": _deposit_score(),
		&"retrieve": _retrieve_score(),
		&"sleep": _sleep_score(),
		&"scavenge": _best_scavenge_score(),
		&"guard": _guard_score(),
	}
	last_scores = scores.duplicate()
	var best_action := &"idle"
	var best_score := -INF
	for action in scores:
		if float(scores[action]) > best_score:
			best_action = StringName(action)
			best_score = float(scores[action])
	decisions_made += 1
	actions_evaluated += scores.size()
	_decision_time_total_usec += Time.get_ticks_usec() - started_at
	if best_action == current_action:
		return
	_release_reservation()
	current_action = best_action
	data.current_action = String(best_action)
	if current_action == &"scavenge":
		_claim_best_scavenge()
	elif current_action == &"sleep":
		_claim_service(&"rest_point")
	elif current_action == &"guard":
		_claim_service(&"guard_post")
	elif current_action == &"retrieve":
		_claim_retrieve()
	elif current_action == &"help_injured":
		_claim_help_target()


func average_decision_time_ms() -> float:
	return float(_decision_time_total_usec) / maxf(float(decisions_made), 1.0) / 1000.0


func _tick_action(delta: float) -> void:
	match current_action:
		&"eat":
			_consume(&"food_ration", &"hunger")
			force_reconsider()
		&"drink":
			_consume(&"water_bottle", &"thirst")
			force_reconsider()
		&"treat_self":
			_treat_self()
			force_reconsider()
		&"help_injured":
			_tick_help_injured(delta)
		&"flee":
			_tick_flee(delta)
		&"fight":
			_tick_fight(delta)
		&"seek_safety":
			_tick_seek_safety(delta)
		&"scavenge":
			_tick_scavenge(delta)
		&"deposit":
			_tick_deposit(delta)
		&"retrieve":
			_tick_retrieve(delta)
		&"sleep":
			_tick_sleep(delta)
		&"guard":
			_tick_guard(delta)
		_:
			survivor.stop_moving()


func _consume(item_id: StringName, need: StringName) -> void:
	if not survivor.carried_inventory.remove_item(item_id, 1):
		return
	var item: ItemData = ItemDatabase.get_item(item_id)
	var restore := item.restore_amount if item != null else 30.0
	data.set(need, maxf(float(data.get(need)) - restore, 0.0))
	data.morale = minf(data.morale + 2.0, 100.0)


func _flee_score() -> float:
	var nearest: Node3D = _nearest_zombie()
	if nearest == null:
		return 0.0
	var distance: float = survivor.global_position.distance_to(nearest.global_position)
	var confidence: float = UTILITY.combat_confidence(data)
	return clampf((1.0 - distance / perception_radius) * (1.5 - confidence), 0.0, 1.5)


func _treat_self_score() -> float:
	if survivor.carried_inventory.get_count(&"medical_supplies") <= 0:
		return 0.0
	var missing_ratio := 1.0 - data.health / maxf(data.max_health, 1.0)
	if data.health >= data.max_health * 0.75 and data.infection_exposure < 20.0:
		return 0.0
	return clampf(missing_ratio * 1.5 + data.infection_exposure / 100.0, 0.0, 1.4)


func _treat_self() -> void:
	if not survivor.carried_inventory.remove_item(&"medical_supplies", 1):
		return
	var item: ItemData = ItemDatabase.get_item(&"medical_supplies")
	var restore := item.restore_amount if item != null else 25.0
	survivor.health_component.heal(restore)
	data.health = survivor.health_component.current_health
	data.infection_exposure = maxf(data.infection_exposure - restore, 0.0)


func _deposit_score() -> float:
	if settlement_runtime == null or settlement_runtime.first_service_id(&"settlement_storage") == &"":
		return 0.0
	return 0.9 if _surplus_deposit_item() != &"" else 0.0


func _retrieve_score() -> float:
	if settlement_runtime == null or settlement_runtime.storage_inventory() == null:
		return 0.0
	var best := 0.0
	if survivor.carried_inventory.get_count(&"food_ration") == 0 and settlement_runtime.inventory_for_item(&"food_ration").get_available(&"food_ration") > 0:
		best = maxf(best, UTILITY.urgency(data.hunger, 25.0) * 1.1)
	if survivor.carried_inventory.get_count(&"water_bottle") == 0 and settlement_runtime.inventory_for_item(&"water_bottle").get_available(&"water_bottle") > 0:
		best = maxf(best, UTILITY.urgency(data.thirst, 20.0) * 1.15)
	if survivor.carried_inventory.get_count(&"medical_supplies") == 0 and settlement_runtime.inventory_for_item(&"medical_supplies").get_available(&"medical_supplies") > 0:
		best = maxf(best, (1.0 - data.health / maxf(data.max_health, 1.0)) * 1.2)
	return best


func _claim_retrieve() -> void:
	var candidates: Array[StringName] = [&"food_ration", &"water_bottle", &"medical_supplies"]
	for item_id in candidates:
		var storage: Inventory = settlement_runtime.inventory_for_item(item_id)
		if storage != null and storage.get_available(item_id) > 0 and survivor.carried_inventory.get_count(item_id) == 0 and settlement_runtime.reserve_item(data.id, item_id, 1):
			_retrieve_item = item_id
			return


func _tick_retrieve(delta: float) -> void:
	if _retrieve_item == &"":
		force_reconsider()
		return
	var record: Dictionary = settlement_runtime.record_for_item(_retrieve_item)
	var target: Vector3 = COORDINATES.world_cell_to_world_position(record["cell"]) + Vector3(0.5, 1.0, 0.5)
	if not survivor.move_toward_world_point(target, delta):
		return
	settlement_runtime.confirm_reserved_item(data.id, survivor.carried_inventory)
	_retrieve_item = &""
	force_reconsider()


func _help_injured_score() -> float:
	if survivor.carried_inventory.get_count(&"medical_supplies") <= 0:
		return 0.0
	var target: Node3D = _find_injured_survivor()
	if target == null:
		return 0.0
	return clampf((1.0 - target.data.health / maxf(target.data.max_health, 1.0)) * (0.8 + data.medical_skill / 100.0), 0.0, 1.3)


func _claim_help_target() -> void:
	var target: Node3D = _find_injured_survivor()
	if target != null and target.try_claim_helper(data.id):
		_help_target = target


func _tick_help_injured(delta: float) -> void:
	if not is_instance_valid(_help_target) or _help_target.is_dead:
		force_reconsider()
		return
	if not survivor.move_toward_world_point(_help_target.global_position, delta):
		return
	if survivor.carried_inventory.remove_item(&"medical_supplies", 1):
		var item: ItemData = ItemDatabase.get_item(&"medical_supplies")
		var restore := item.restore_amount if item != null else 25.0
		_help_target.health_component.heal(restore)
		_help_target.data.health = _help_target.health_component.current_health
	_help_target.release_helper(data.id)
	_help_target = null
	force_reconsider()


func _find_injured_survivor() -> Node3D:
	var best: Node3D = null
	var missing := 0.0
	for node in get_tree().get_nodes_in_group(&"survivors"):
		if node == survivor or not node is Node3D or not "data" in node or node.data == null or node.data.is_dead or node.is_claimed_for_help():
			continue
		var candidate_missing: float = node.data.max_health - node.data.health
		if candidate_missing > missing:
			missing = candidate_missing
			best = node
	return best


func _sleep_score() -> float:
	if settlement_runtime == null or settlement_runtime.first_service_id(&"rest_point") == &"":
		return 0.0
	return UTILITY.urgency(data.fatigue, 35.0) * 1.2


func _guard_score() -> float:
	if settlement_runtime == null or settlement_runtime.first_service_id(&"guard_post") == &"":
		return 0.0
	return clampf(0.2 * UTILITY.combat_confidence(data), 0.0, 0.3)


func _tick_flee(delta: float) -> void:
	var nearest: Node3D = _nearest_zombie()
	if nearest == null:
		force_reconsider()
		return
	var away: Vector3 = survivor.global_position - nearest.global_position
	away.y = 0.0
	if away.length() <= 0.01:
		away = Vector3.RIGHT
	var goal: Vector3 = survivor.global_position + away.normalized() * 5.0
	if not navigation_service.is_walkable(Vector3i(floori(goal.x), 0, floori(goal.z))):
		goal = survivor.global_position + away.normalized() * 2.0
	survivor.move_toward_world_point(goal, delta)


func _fight_score() -> float:
	var nearest: Node3D = _nearest_zombie()
	if nearest == null:
		return 0.0
	var distance: float = survivor.global_position.distance_to(nearest.global_position)
	return clampf(UTILITY.combat_confidence(data) * (1.0 - distance / perception_radius) * 1.4, 0.0, 1.4)


func _tick_fight(delta: float) -> void:
	var nearest: Node3D = _nearest_zombie()
	if nearest == null:
		force_reconsider()
		return
	var distance: float = survivor.global_position.distance_to(nearest.global_position)
	if distance > 5.5:
		survivor.move_toward_world_point(nearest.global_position, delta)
	else:
		survivor.stop_moving()
		survivor.face_and_fire(nearest.global_position)


func _seek_safety_score() -> float:
	if settlement_runtime == null:
		return 0.0
	var safe: Dictionary = settlement_runtime.storage_record(&"general")
	if safe.is_empty():
		return 0.0
	var position: Vector3 = COORDINATES.world_cell_to_world_position(safe["cell"]) + Vector3(0.5, 1.0, 0.5)
	if survivor.global_position.distance_to(position) <= 8.0:
		return 0.0
	return clampf(data.fear / 100.0 * 0.9, 0.0, 0.9)


func _tick_seek_safety(delta: float) -> void:
	var safe: Dictionary = settlement_runtime.storage_record(&"general")
	if safe.is_empty():
		force_reconsider()
		return
	var target: Vector3 = COORDINATES.world_cell_to_world_position(safe["cell"]) + Vector3(0.5, 1.0, 0.5)
	if survivor.move_toward_world_point(target, delta):
		data.fear = maxf(data.fear - 10.0, 0.0)
		force_reconsider()


func _best_scavenge_score() -> float:
	if job_board == null:
		return 0.0
	var best := 0.0
	for stable_id in job_board.available_scavenge_ids():
		var record: Dictionary = world_data.get_stable_object(stable_id)
		var distance: float = survivor.global_position.distance_to(COORDINATES.world_cell_to_world_position(record["cell"]))
		var risk := UTILITY.risk_from_danger(float(record.get("state", {}).get("danger", 0.0)), float(data.personality.get("brave", 0.0)))
		var benefit := 0.5 + data.scavenging_skill / 200.0
		best = maxf(best, clampf(benefit - risk * 0.5 - UTILITY.distance_cost(distance, 28.0) * 0.4, 0.0, 1.2))
	return best


func _claim_best_scavenge() -> void:
	var best_id := &""
	var best_distance := INF
	for stable_id in job_board.available_scavenge_ids():
		var record: Dictionary = world_data.get_stable_object(stable_id)
		var distance: float = survivor.global_position.distance_to(COORDINATES.world_cell_to_world_position(record["cell"]))
		if distance < best_distance:
			best_distance = distance
			best_id = stable_id
	if best_id != &"" and job_board.claim(best_id, data.id):
		reserved_target_id = best_id
		_work_remaining = scavenge_work_seconds


func _tick_scavenge(delta: float) -> void:
	if reserved_target_id == &"":
		force_reconsider()
		return
	var record: Dictionary = world_data.get_stable_object(reserved_target_id)
	var target: Vector3 = COORDINATES.world_cell_to_world_position(record["cell"]) + Vector3(0.5, 1.0, 0.5)
	if not survivor.move_toward_world_point(target, delta):
		return
	_work_remaining -= delta
	if _work_remaining > 0.0:
		return
	job_board.harvest(reserved_target_id, data.id, survivor.carried_inventory)
	reserved_target_id = &""
	force_reconsider()


func _tick_deposit(delta: float) -> void:
	var item_id := _surplus_deposit_item()
	if item_id == &"":
		force_reconsider()
		return
	var record: Dictionary = settlement_runtime.record_for_item(item_id)
	if record.is_empty():
		force_reconsider()
		return
	var target: Vector3 = COORDINATES.world_cell_to_world_position(record["cell"]) + Vector3(0.5, 1.0, 0.5)
	if not survivor.move_toward_world_point(target, delta):
		return
	var keep := 0 if item_id == &"materials" else 1
	settlement_runtime.deposit_item(survivor.carried_inventory, item_id, survivor.carried_inventory.get_available(item_id) - keep)
	force_reconsider()


func _surplus_deposit_item() -> StringName:
	for item_id in [&"materials", &"food_ration", &"water_bottle", &"medical_supplies"]:
		var keep := 0 if item_id == &"materials" else 1
		if survivor.carried_inventory.get_available(item_id) > keep:
			return item_id
	return &""


func _tick_sleep(delta: float) -> void:
	if reserved_target_id == &"":
		force_reconsider()
		return
	var record: Dictionary = world_data.get_stable_object(reserved_target_id)
	var target: Vector3 = COORDINATES.world_cell_to_world_position(record["cell"]) + Vector3(0.5, 1.0, 0.5)
	if not survivor.move_toward_world_point(target, delta):
		return
	data.fatigue = maxf(data.fatigue - 9.0 * delta, 0.0)
	data.morale = minf(data.morale + 1.5 * delta, 100.0)
	if data.fatigue <= 5.0:
		force_reconsider()


func _tick_guard(delta: float) -> void:
	if reserved_target_id == &"":
		force_reconsider()
		return
	var record: Dictionary = world_data.get_stable_object(reserved_target_id)
	var target: Vector3 = COORDINATES.world_cell_to_world_position(record["cell"]) + Vector3(0.5, 1.0, 0.5)
	if survivor.move_toward_world_point(target, delta):
		survivor.stop_moving()


func _claim_service(kind: StringName) -> void:
	var stable_id: StringName = settlement_runtime.first_service_id(kind)
	if settlement_runtime.claim_service(stable_id, data.id):
		reserved_target_id = stable_id


func _nearest_zombie() -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := perception_radius
	for node in get_tree().get_nodes_in_group(&"voxel_zombies"):
		if not node is Node3D:
			continue
		var distance: float = survivor.global_position.distance_to(node.global_position)
		if distance < nearest_distance and navigation_service.is_direct_path_clear(survivor.global_position, node.global_position):
			nearest = node
			nearest_distance = distance
	return nearest


func _release_reservation() -> void:
	if is_instance_valid(_help_target):
		_help_target.release_helper(data.id)
	_help_target = null
	_retrieve_item = &""
	if job_board != null and data != null:
		job_board.release_survivor(data.id)
	if settlement_runtime != null and data != null:
		settlement_runtime.release_survivor(data.id)
	reserved_target_id = &""
	_work_remaining = 0.0
