class_name VoxelZombiePerception3D
extends Node

enum State { IDLE, SUSPICIOUS, INVESTIGATE, CHASE, ATTACK, SEARCH }

@export var vision_distance := 10.0
@export var vision_cone_degrees := 100.0
@export var hearing_radius := 8.0
@export var attack_range := 1.4
@export var update_interval := 0.25
@export var suspicion_threshold := 2.0
@export var search_duration := 3.0

var state := State.IDLE
var target: Node3D
var last_known_position := Vector3.ZERO
var facing := Vector3.FORWARD
var navigation_service
var _owner_actor: Node3D
var _suspicion := 0.0
var _timer := 0.0
var _search_remaining := 0.0
var _last_noise_sequence := 0


func _ready() -> void:
	_owner_actor = get_parent()
	facing = -_owner_actor.global_transform.basis.z


func configure(service) -> void:
	navigation_service = service


func update(delta: float, current_velocity: Vector3) -> void:
	var flat_velocity := Vector3(current_velocity.x, 0.0, current_velocity.z)
	if flat_velocity.length() > 0.05:
		facing = flat_velocity.normalized()
	if state == State.SEARCH:
		_search_remaining -= delta
		if _search_remaining <= 0.0:
			state = State.IDLE
			target = null
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = update_interval
	_tick()


func _tick() -> void:
	var candidate: Node3D = _best_visible_target()
	if candidate != null:
		target = candidate
		last_known_position = candidate.global_position
		_suspicion = minf(_suspicion + 1.0, suspicion_threshold)
		if _suspicion >= suspicion_threshold:
			state = State.ATTACK if _owner_actor.global_position.distance_to(candidate.global_position) <= attack_range else State.CHASE
		else:
			state = State.SUSPICIOUS
		return
	_suspicion = maxf(0.0, _suspicion - 0.5)
	if state in [State.CHASE, State.ATTACK, State.SUSPICIOUS]:
		state = State.SEARCH
		_search_remaining = search_duration
		return
	_check_hearing()


func _best_visible_target():
	if navigation_service == null:
		return null
	var best: Node3D
	var best_distance := INF
	var cone_cos := cos(deg_to_rad(vision_cone_degrees * 0.5))
	for node in _owner_actor.get_tree().get_nodes_in_group(&"attackable"):
		if node == _owner_actor or not node is Node3D:
			continue
		var candidate := node as Node3D
		var offset := candidate.global_position - _owner_actor.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > vision_distance or distance >= best_distance:
			continue
		if distance > 0.01 and facing.dot(offset / distance) < cone_cos:
			continue
		if not navigation_service.is_direct_path_clear(_owner_actor.global_position, candidate.global_position):
			continue
		best = candidate
		best_distance = distance
	return best


func _check_hearing() -> void:
	var origin := Vector2(_owner_actor.global_position.x, _owner_actor.global_position.z)
	for noise in NoiseManager.recent_noises_near(origin, hearing_radius):
		var sequence := int(noise.get("sequence", 0))
		if sequence <= _last_noise_sequence:
			continue
		_last_noise_sequence = sequence
		var point: Vector2 = noise["position"]
		last_known_position = Vector3(point.x, _owner_actor.global_position.y, point.y)
		state = State.INVESTIGATE


func movement_goal() -> Vector3:
	if state in [State.CHASE, State.ATTACK] and is_instance_valid(target):
		return target.global_position
	if state in [State.INVESTIGATE, State.SEARCH]:
		return last_known_position
	return Vector3.INF


func on_navigation_failed() -> void:
	state = State.SEARCH if state in [State.CHASE, State.ATTACK] else State.IDLE
	_search_remaining = search_duration if state == State.SEARCH else 0.0
