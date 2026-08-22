class_name VoxelInteractor3D
extends Area3D

const FACING_DOT_THRESHOLD := 0.3
const FACING_BONUS := 1.25

var _candidate_areas: Array[Area3D] = []
var _player: Node3D
var _last_prompt := ""


func _ready() -> void:
	collision_layer = 0
	collision_mask = 64
	_player = get_parent()
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	InputRouter.interact_requested.connect(_on_interact_requested)


func _physics_process(_delta: float) -> void:
	_prune_invalid()
	var best = _best_candidate()
	var label: String = best.interact_label if best != null else ""
	if label != _last_prompt:
		_last_prompt = label
		GameEvents.interact_prompt_changed.emit(label)


func _on_area_entered(area: Area3D) -> void:
	if _get_component(area) != null and area not in _candidate_areas:
		_candidate_areas.append(area)


func _on_area_exited(area: Area3D) -> void:
	_candidate_areas.erase(area)


func _prune_invalid() -> void:
	for index in range(_candidate_areas.size() - 1, -1, -1):
		if not is_instance_valid(_candidate_areas[index]):
			_candidate_areas.remove_at(index)


func _get_component(area: Area3D):
	return area.get_node_or_null("InteractableComponent")


func _best_candidate():
	var best = null
	var best_score := INF
	var aim: Vector3 = _player.get("aim_direction") if "aim_direction" in _player else Vector3.FORWARD
	for area in _candidate_areas:
		if not is_instance_valid(area):
			continue
		var component = _get_component(area)
		if component == null or not component.can_interact(_player):
			continue
		var offset: Vector3 = area.global_position - _player.global_position
		offset.y = 0.0
		var distance := offset.length()
		var score := distance
		if distance > 0.001 and aim.dot(offset / distance) >= FACING_DOT_THRESHOLD:
			score -= FACING_BONUS
		if score < best_score:
			best_score = score
			best = component
	return best


func _on_interact_requested() -> void:
	interact_best()


func interact_best() -> bool:
	var best = _best_candidate()
	if best == null:
		return false
	best.interact(_player)
	return true
