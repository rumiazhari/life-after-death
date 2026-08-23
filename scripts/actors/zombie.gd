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
## External physical pushes (explosions, heavy impacts) layered onto steering
## and decaying quickly -- the actor stays a CharacterBody2D; no ragdoll.
var _knockback := Vector2.ZERO
var _last_hit_source: Node = null

## Path-around-walls fallback (Phase 3B): only consulted when direct
## steering toward the current goal is actually blocked, and only
## re-evaluated on `_nav_recheck_interval`, not every physics frame -- see
## docs/perception_system.md "Navigation" for why this stays a fallback
## rather than every zombie pathfinding continuously.
const NAV_RECHECK_INTERVAL := 1.0
## How many consecutive NO_PATH results (not BUDGET_DEFERRED/NOT_READY,
## which retry for free) before giving up on this goal until it changes --
## a bounded retry, not an infinite one, per Phase 3B.2's route-invalidation
## requirements.
const NAV_MAX_NO_PATH_RETRIES := 3
const NAV_TARGET_RESAMPLE_DISTANCE := 24.0
var _nav_path: PackedVector2Array = PackedVector2Array()
var _nav_path_index: int = 0
var _nav_recheck_timer: float = 0.0
## The UrbanNavigationService.revision() this path was computed against --
## a mismatch means a door changed state or the grid rebuilt since, so the
## cached path may no longer be valid and must be discarded before use.
var _nav_path_revision: int = -1
var _nav_target: Vector2 = Vector2.ZERO
var _nav_path_target: Vector2 = Vector2.ZERO
var _nav_goal_identity: int = 0
var _nav_observed_revision: int = -1
var _nav_previous_state: ZombiePerceptionComponent.State = ZombiePerceptionComponent.State.IDLE
var _nav_no_path_retries: int = 0
var _nav_failure_revision: int = -1
var _nav_failure_goal: Vector2 = Vector2.ZERO
var _nav_failure_target_id: int = 0
var _nav_failure_valid: bool = false
## True once NAV_MAX_NO_PATH_RETRIES has been reached with no route found --
## _seek_point stops retrying pathfinding (but keeps re-checking direct line
## of sight, so a route that opens back up still gets noticed) until the
## goal itself changes.
var nav_stuck: bool = false
## Whether the last direct-line-of-sight recheck found the goal reachable
## in a straight line -- an empty _nav_path means EITHER "go direct" (this
## true) OR "blocked, no route yet" (this false); never conflate the two by
## defaulting to direct steering whenever the path happens to be empty.
var _nav_direct_clear: bool = true

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
	velocity += _consume_knockback(delta)
	move_and_slide()
	body_visual.update_from_velocity(velocity)

## Physical impulse state: added on top of steering this frame, then decays.
func apply_knockback(push: Vector2) -> void:
	_knockback = (_knockback + push).limit_length(420.0)

func _consume_knockback(delta: float) -> Vector2:
	var applied := _knockback
	_knockback = _knockback.lerp(Vector2.ZERO, minf(9.0 * delta, 1.0))
	return applied

func take_damage(amount: float, source: Node = null) -> void:
	_last_hit_source = source
	health_component.take_damage(amount, source)
	# A hit shoves the zombie along the impact direction even if it survives.
	if source is Node2D:
		var direction: Vector2 = global_position - (source as Node2D).global_position
		if direction.length_squared() > 1.0:
			apply_knockback(direction.normalized() * amount * 6.0)

## Off by default (ZombiePerceptionComponent.debug_draw_enabled) -- see
## docs/perception_system.md "Debug visualization".
func _draw() -> void:
	perception.draw_debug(self)

## What to move toward this frame, purely a function of the perception
## component's current state -- no separate retarget timer lives here.
## Falls back to UrbanNavigationService only when a straight line to the
## goal is actually obstructed (see _seek_point below).
func _seek_current_goal() -> Vector2:
	var active_navigation := perception.state == ZombiePerceptionComponent.State.CHASE or perception.state == ZombiePerceptionComponent.State.ATTACK or perception.state == ZombiePerceptionComponent.State.INVESTIGATE or perception.state == ZombiePerceptionComponent.State.SEARCH
	if perception.state != _nav_previous_state and not active_navigation:
		reset_navigation_goal()
	_nav_previous_state = perception.state
	match perception.state:
		ZombiePerceptionComponent.State.CHASE, ZombiePerceptionComponent.State.ATTACK:
			if perception.target == null or not is_instance_valid(perception.target):
				return Vector2.ZERO
			return _seek_point(perception.target.global_position)
		ZombiePerceptionComponent.State.INVESTIGATE, ZombiePerceptionComponent.State.SEARCH:
			return _seek_point(perception.last_known_position)
		_:
			_clear_nav_path()
			return Vector2.ZERO

func _seek_point(goal: Vector2) -> Vector2:
	var direct: Vector2 = goal - global_position
	if direct.length() <= arrive_threshold:
		_clear_nav_path()
		return Vector2.ZERO

	var target_id: int = perception.target.get_instance_id() if perception.target != null and is_instance_valid(perception.target) else 0
	var revision := UrbanNavigationService.revision()
	if _nav_observed_revision != revision:
		_nav_observed_revision = revision
		clear_cached_path()
		clear_navigation_failure()
		_nav_recheck_timer = 0.0
	if target_id != _nav_goal_identity or (target_id == 0 and not goal.is_equal_approx(_nav_target)):
		begin_navigation_goal(goal, target_id)
	elif target_id != 0 and goal.distance_to(_nav_target) >= NAV_TARGET_RESAMPLE_DISTANCE:
		_nav_target = goal
		clear_cached_path()
		clear_navigation_failure()
		_nav_recheck_timer = 0.0
	var sampled_goal: Vector2 = _nav_target
	if _nav_failure_valid and (_nav_failure_revision != revision or not _nav_failure_goal.is_equal_approx(sampled_goal) or _nav_failure_target_id != target_id):
		clear_navigation_failure()
		_nav_recheck_timer = 0.0
	if not _nav_path.is_empty() and _nav_path_revision != revision:
		_clear_nav_path() # a door changed state (or the grid rebuilt) since this route was computed
		clear_navigation_failure()
		_nav_recheck_timer = 0.0

	_nav_recheck_timer -= get_physics_process_delta_time()
	if _nav_recheck_timer <= 0.0:
		_nav_recheck_timer = NAV_RECHECK_INTERVAL
		if UrbanNavigationService.is_direct_path_clear(global_position, sampled_goal):
			_clear_nav_path()
			_nav_direct_clear = true
			clear_navigation_failure()
		else:
			_nav_direct_clear = false
			if _nav_path.is_empty() and not (_nav_failure_valid and _nav_failure_goal.is_equal_approx(sampled_goal) and _nav_failure_revision == revision and _nav_failure_target_id == target_id and nav_stuck):
				var result: Dictionary = UrbanNavigationService.find_path_ex(global_position, sampled_goal)
				match result["status"]:
					UrbanNavigationService.PathResult.SUCCESS:
						_nav_path = result["path"]
						_nav_path_index = 0
						_nav_path_revision = result["revision"]
						_nav_path_target = sampled_goal
						_nav_no_path_retries = 0
						nav_stuck = false
					UrbanNavigationService.PathResult.NO_PATH:
						_nav_no_path_retries += 1
						if _nav_no_path_retries >= NAV_MAX_NO_PATH_RETRIES:
							nav_stuck = true
							_nav_failure_valid = true
							_nav_failure_goal = sampled_goal
							_nav_failure_revision = revision
							_nav_failure_target_id = target_id
					_: # BUDGET_DEFERRED / NOT_READY -- retry next recheck, doesn't count as a real no-path failure
						pass

	if _nav_path.is_empty():
		# Blocked with no known route (yet, or permanently) -- never steer
		# straight at a goal we just confirmed isn't directly reachable.
		if nav_stuck:
			if perception.state == ZombiePerceptionComponent.State.CHASE or perception.state == ZombiePerceptionComponent.State.ATTACK:
				perception.on_navigation_failed()
			elif perception.state == ZombiePerceptionComponent.State.INVESTIGATE:
				perception.on_navigation_failed()
		return direct.normalized() if _nav_direct_clear else Vector2.ZERO

	while _nav_path_index < _nav_path.size() - 1 and global_position.distance_to(_nav_path[_nav_path_index]) <= arrive_threshold:
		_nav_path_index += 1
	var waypoint: Vector2 = _nav_path[_nav_path_index]
	if global_position.distance_to(waypoint) <= arrive_threshold and _nav_path_index >= _nav_path.size() - 1:
		if UrbanNavigationService.is_direct_path_clear(global_position, goal):
			_clear_nav_path()
			return direct.normalized()
		_clear_nav_path()
		_nav_direct_clear = false
	return (waypoint - global_position).normalized()

func _clear_nav_path() -> void:
	_nav_path.clear()
	_nav_path_index = 0
	_nav_path_revision = -1
	_nav_path_target = Vector2.ZERO

func reset_navigation_goal() -> void:
	_clear_nav_path()
	_nav_recheck_timer = 0.0
	clear_navigation_failure()
	_nav_goal_identity = 0
	_nav_observed_revision = UrbanNavigationService.revision()

func clear_cached_path() -> void:
	_clear_nav_path()

func clear_navigation_failure() -> void:
	_nav_no_path_retries = 0
	nav_stuck = false
	_nav_failure_valid = false
	_nav_failure_revision = -1
	_nav_failure_goal = Vector2.ZERO
	_nav_failure_target_id = 0

func begin_navigation_goal(goal: Vector2, target_id: int = 0) -> void:
	clear_cached_path()
	clear_navigation_failure()
	_nav_target = goal
	_nav_goal_identity = target_id
	_nav_recheck_timer = 0.0

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
	# The zombie stops being an actor and leaves a physical corpse behind
	# that receives the killing blow's impulse; later blasts can move it.
	var death_direction := Vector2.RIGHT
	if _last_hit_source is Node2D:
		var direction: Vector2 = global_position - (_last_hit_source as Node2D).global_position
		if direction.length_squared() > 1.0:
			death_direction = direction.normalized()
	var container := get_tree().get_first_node_in_group("entity_container")
	if container == null:
		container = get_parent()
	Corpse.spawn(container, body_visual, global_position, death_direction * 140.0 + Vector2(0, 0))
	queue_free()
