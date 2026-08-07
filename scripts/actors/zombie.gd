class_name Zombie
extends CharacterBody2D
## Prototype swarm zombie. Deliberately cheap per-instance: no
## NavigationAgent2D, no per-frame pathfinding -- just seek-the-nearest-
## target steering plus grid-based separation from SwarmManager, tolerant
## of getting stuck on obstacles since it relies on move_and_slide only.
##
## Targets the nearest node in the "attackable" group (Player and Survivor
## both add themselves to it) rather than always the player, so zombies can
## threaten autonomous survivors too. Re-picked on a periodic timer, not
## every frame, to keep this as cheap as the original player-only version.

@export var move_speed: float = 55.0
@export var contact_damage: float = 8.0
@export var contact_damage_interval: float = 0.6
@export var separation_radius: float = 24.0
@export var separation_strength: float = 120.0
@export var retarget_interval: float = 3.0

@onready var health_component: HealthComponent = $HealthComponent
@onready var body_visual: Polygon2D = $BodyVisual
@onready var attack_area: Area2D = $AttackArea

var _target: Node2D = null
var _contact_targets: Array[Node] = []
var _damage_tick_remaining: float = 0.0
var _swarm_manager: Node = null
var _retarget_remaining: float = 0.0

func _ready() -> void:
	add_to_group("zombies")
	health_component.died.connect(_on_died)
	health_component.damaged.connect(_on_damaged)
	attack_area.body_entered.connect(_on_attack_area_body_entered)
	attack_area.body_exited.connect(_on_attack_area_body_exited)
	_swarm_manager = get_tree().get_first_node_in_group("swarm_manager")
	if _swarm_manager:
		_swarm_manager.call("register_zombie", self)
	_retarget_remaining = randf() * retarget_interval
	_target = _find_nearest_attackable()

func _physics_process(delta: float) -> void:
	if health_component.is_dead:
		return
	_tick_contact_damage(delta)
	_retarget_remaining -= delta
	if _retarget_remaining <= 0.0 or _target == null or not is_instance_valid(_target):
		_retarget_remaining = retarget_interval + randf_range(-0.5, 0.5)
		var found: Node2D = _find_nearest_attackable()
		if found:
			_target = found
	var steering: Vector2 = _seek_target() + _separation()
	if steering.length() > 0.0:
		velocity = steering.normalized() * move_speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()

func take_damage(amount: float, source: Node = null) -> void:
	health_component.take_damage(amount, source)

func _seek_target() -> Vector2:
	if _target == null or not is_instance_valid(_target):
		return Vector2.ZERO
	return (_target.global_position - global_position).normalized()

func _find_nearest_attackable() -> Node2D:
	var best: Node2D = null
	var best_dist_sq: float = INF
	for node in get_tree().get_nodes_in_group("attackable"):
		if not is_instance_valid(node):
			continue
		var dist_sq: float = global_position.distance_squared_to((node as Node2D).global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = node
	return best

func _separation() -> Vector2:
	if _swarm_manager == null:
		return Vector2.ZERO
	var neighbors: Array = _swarm_manager.call("get_nearby", self, separation_radius)
	var push := Vector2.ZERO
	for neighbor in neighbors:
		if neighbor == self or not is_instance_valid(neighbor):
			continue
		var offset: Vector2 = global_position - neighbor.global_position
		var dist: float = offset.length()
		if dist > 0.0 and dist < separation_radius:
			push += offset.normalized() * (1.0 - dist / separation_radius)
	return push * (separation_strength / move_speed)

func _tick_contact_damage(delta: float) -> void:
	if _damage_tick_remaining > 0.0:
		_damage_tick_remaining -= delta
		return
	if _contact_targets.is_empty():
		return
	for target in _contact_targets:
		if is_instance_valid(target) and target.has_method("take_damage"):
			target.call("take_damage", contact_damage, self)
	_damage_tick_remaining = contact_damage_interval

func _on_attack_area_body_entered(body: Node) -> void:
	if body != self and body.has_method("take_damage"):
		_contact_targets.append(body)

func _on_attack_area_body_exited(body: Node) -> void:
	_contact_targets.erase(body)

func _on_damaged(_amount: float) -> void:
	body_visual.modulate = Color(2.2, 2.2, 2.2)
	var tween := create_tween()
	tween.tween_property(body_visual, "modulate", Color(1, 1, 1), 0.15)

func _on_died() -> void:
	GameEvents.zombie_died.emit(self, global_position)
	GameEvents.zombie_killed_by_player.emit(global_position)
	if _swarm_manager:
		_swarm_manager.call("unregister_zombie", self)
	queue_free()
