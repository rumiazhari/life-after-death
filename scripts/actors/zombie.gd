class_name Zombie
extends CharacterBody2D
## Prototype swarm zombie. Deliberately cheap per-instance: no
## NavigationAgent2D, no per-frame pathfinding -- just seek-the-current-
## perception-target steering plus grid-based separation from
## SwarmManager, tolerant of getting stuck on obstacles since it relies on
## move_and_slide only.
##
## Targeting is entirely owned by ZombiePerceptionComponent (Phase 3B) --
## this script never itself scans the "attackable" group or decides who to
## chase. See docs/perception_system.md: a zombie only moves toward
## `perception.target` (CHASE/ATTACK) or `perception.last_known_position`
## (INVESTIGATE/SEARCH after losing sight/hearing), and stands still
## (aside from separation jitter) while IDLE/SUSPICIOUS/RETURN_TO_IDLE --
## there is no more "nearest attackable in the whole scene, unlimited
## range" fallback.

@export var move_speed: float = 55.0
@export var contact_damage: float = 8.0
@export var contact_damage_interval: float = 0.6
@export var separation_radius: float = 24.0
@export var separation_strength: float = 120.0
@export var arrive_threshold: float = 12.0

@onready var health_component: HealthComponent = $HealthComponent
@onready var body_visual: ActorVisual = $BodyVisual
@onready var attack_area: Area2D = $AttackArea
@onready var perception: ZombiePerceptionComponent = $Perception

var _contact_targets: Array[Node] = []
var _damage_tick_remaining: float = 0.0
var _swarm_manager: Node = null

## Path-around-walls fallback (Phase 3B): only consulted when direct
## steering toward the current goal is actually blocked, and only
## re-evaluated on `_nav_recheck_interval`, not every physics frame -- see
## docs/perception_system.md "Navigation" for why this stays a fallback
## rather than every zombie pathfinding continuously.
const NAV_RECHECK_INTERVAL := 1.0
var _nav_path: PackedVector2Array = PackedVector2Array()
var _nav_path_index: int = 0
var _nav_recheck_timer: float = 0.0

func _ready() -> void:
	add_to_group("zombies")
	body_visual.variant = CosmeticRng.randi_range(0, ActorSpriteLibrary.get_variant_count(&"zombie") - 1)
	health_component.died.connect(_on_died)
	health_component.damaged.connect(_on_damaged)
	attack_area.body_entered.connect(_on_attack_area_body_entered)
	attack_area.body_exited.connect(_on_attack_area_body_exited)
	_swarm_manager = get_tree().get_first_node_in_group("swarm_manager")
	if _swarm_manager:
		_swarm_manager.call("register_zombie", self)

func _physics_process(delta: float) -> void:
	if health_component.is_dead:
		return
	_tick_contact_damage(delta)
	perception.update(delta, velocity)
	var steering: Vector2 = _seek_current_goal() + _separation()
	if steering.length() > 0.0:
		velocity = steering.normalized() * move_speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	body_visual.update_from_velocity(velocity)

func take_damage(amount: float, source: Node = null) -> void:
	health_component.take_damage(amount, source)

## Off by default (ZombiePerceptionComponent.debug_draw_enabled) -- see
## docs/perception_system.md "Debug visualization".
func _draw() -> void:
	perception.draw_debug(self)

## What to move toward this frame, purely a function of the perception
## component's current state -- no separate retarget timer lives here.
## Falls back to UrbanNavigationService only when a straight line to the
## goal is actually obstructed (see _seek_point below).
func _seek_current_goal() -> Vector2:
	match perception.state:
		ZombiePerceptionComponent.State.CHASE, ZombiePerceptionComponent.State.ATTACK:
			if perception.target == null or not is_instance_valid(perception.target):
				return Vector2.ZERO
			return _seek_point(perception.target.global_position)
		ZombiePerceptionComponent.State.INVESTIGATE, ZombiePerceptionComponent.State.SEARCH:
			return _seek_point(perception.last_known_position)
		_:
			_nav_path.clear()
			return Vector2.ZERO

func _seek_point(goal: Vector2) -> Vector2:
	var direct: Vector2 = goal - global_position
	if direct.length() <= arrive_threshold:
		_nav_path.clear()
		return Vector2.ZERO

	_nav_recheck_timer -= get_physics_process_delta_time()
	if _nav_recheck_timer <= 0.0:
		_nav_recheck_timer = NAV_RECHECK_INTERVAL
		if UrbanNavigationService.is_direct_path_clear(global_position, goal):
			_nav_path.clear()
		elif _nav_path.is_empty():
			_nav_path = UrbanNavigationService.find_path(global_position, goal)
			_nav_path_index = 0

	if _nav_path.is_empty():
		return direct.normalized()

	while _nav_path_index < _nav_path.size() - 1 and global_position.distance_to(_nav_path[_nav_path_index]) <= arrive_threshold:
		_nav_path_index += 1
	var waypoint: Vector2 = _nav_path[_nav_path_index]
	if global_position.distance_to(waypoint) <= arrive_threshold and _nav_path_index >= _nav_path.size() - 1:
		_nav_path.clear()
		return direct.normalized()
	return (waypoint - global_position).normalized()

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

func _on_damaged(amount: float) -> void:
	body_visual.modulate = Color(2.2, 2.2, 2.2)
	var tween := create_tween()
	tween.tween_property(body_visual, "modulate", Color(1, 1, 1), 0.15)
	GameEvents.zombie_damaged.emit(self, amount)

func _on_died() -> void:
	GameEvents.zombie_died.emit(self, global_position)
	GameEvents.zombie_killed_by_player.emit(global_position)
	if _swarm_manager:
		_swarm_manager.call("unregister_zombie", self)
	queue_free()
