class_name ZombiePerceptionComponent
extends Node
## Bounded, staggered perception for one zombie -- replaces "nearest
## attackable in the whole scene, unlimited range" with actual sensing: a
## max vision distance, a facing-relative view cone, and a line-of-sight
## raycast, run on a low-frequency per-instance-jittered timer (never every
## physics frame). The "attackable" group is always small (player + up to
## 4 survivors in this slice), so the per-tick scan itself is cheap; the
## raycast is the expensive part and only ever runs for candidates that
## already passed the free distance/cone checks -- capped at one raycast
## per candidate per perception tick, never per physics frame.
##
## Hearing is independent of vision (see NoiseManager) but feeds the same
## state machine: a noise can promote IDLE straight to INVESTIGATE without
## ever seeing anything, but never grants a permanent exact target --
## losing sight/sound during SEARCH eventually returns to IDLE.

enum State { IDLE, SUSPICIOUS, INVESTIGATE, CHASE, ATTACK, SEARCH, RETURN_TO_IDLE }

@export var vision_distance: float = 260.0
@export var vision_cone_degrees: float = 100.0
@export var hearing_radius: float = 220.0
@export var update_interval: float = 0.35
@export var attack_range: float = 40.0
@export var suspicion_buildup: float = 1.5 ## per tick while a candidate is visible
@export var suspicion_threshold: float = 2.0 ## visible-time (in ticks-equivalent) before CHASE
@export var suspicion_decay: float = 0.6
@export var search_duration: float = 4.0
## -1 (default) auto-randomizes _gameplay_rng from OS entropy. A
## non-negative value seeds it explicitly -- used by tests to prove
## perception-timing output is unaffected by however much CosmeticRng is
## drawn from elsewhere (same RNG-isolation contract as SpawnManager/Zombie
## in Phase 3A.1 -- see docs/perception_system.md).
@export var rng_seed: int = -1

var state: State = State.IDLE
var target: Node2D = null
var last_known_position: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.DOWN

var _suspicion: float = 0.0
var _search_timer: float = 0.0
var _update_timer: float = 0.0
var _owner_actor: Node2D
## Private gameplay-only RNG stream (perception-tick stagger jitter) --
## deliberately separate from CosmeticRng.
var _gameplay_rng := RandomNumberGenerator.new()

func _ready() -> void:
	_owner_actor = get_parent()
	if rng_seed >= 0:
		_gameplay_rng.seed = rng_seed
	else:
		_gameplay_rng.randomize()
	_update_timer = _gameplay_rng.randf() * update_interval

## Called once per physics frame by Zombie -- cheap (just a timer
## countdown and a facing update) except on the ticks where
## `_update_timer` actually elapses.
func update(delta: float, current_velocity: Vector2) -> void:
	if current_velocity.length() > 4.0:
		facing = current_velocity.normalized()
	if debug_draw_enabled:
		_owner_actor.queue_redraw()
	if state == State.SEARCH:
		_search_timer -= delta
		if _search_timer <= 0.0:
			_enter_state(State.RETURN_TO_IDLE)
	_update_timer -= delta
	if _update_timer > 0.0:
		return
	_update_timer = update_interval + _gameplay_rng.randf() * 0.1
	_tick_perception()

func _tick_perception() -> void:
	var origin: Vector2 = _owner_actor.global_position
	var candidate: Node2D = _find_best_visible_candidate(origin)
	if candidate:
		_suspicion = minf(_suspicion + suspicion_buildup, suspicion_threshold * 2.0)
		target = candidate
		last_known_position = candidate.global_position
		if _suspicion >= suspicion_threshold or state == State.CHASE or state == State.ATTACK:
			var in_range: bool = origin.distance_to(candidate.global_position) <= attack_range
			_enter_state(State.ATTACK if in_range else State.CHASE)
		else:
			_enter_state(State.SUSPICIOUS)
		return

	_suspicion = maxf(_suspicion - suspicion_decay, 0.0)
	if state == State.CHASE or state == State.ATTACK:
		_enter_state(State.SEARCH)
	elif state == State.SUSPICIOUS and _suspicion <= 0.0:
		_enter_state(State.RETURN_TO_IDLE)
	elif state == State.IDLE or state == State.RETURN_TO_IDLE:
		_check_hearing(origin)

func _check_hearing(origin: Vector2) -> void:
	var noises: Array[Dictionary] = NoiseManager.recent_noises_near(origin, hearing_radius)
	if noises.is_empty():
		return
	last_known_position = noises[-1]["position"]
	_enter_state(State.INVESTIGATE)

## Free (squared-distance + cone dot-product) filtering happens for every
## candidate; the raycast -- the only per-candidate cost that scales with
## actual physics-server work -- only runs for whatever survives that.
func _find_best_visible_candidate(origin: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist_sq: float = vision_distance * vision_distance
	var half_cone_cos: float = cos(deg_to_rad(vision_cone_degrees * 0.5))
	for node in _owner_actor.get_tree().get_nodes_in_group("attackable"):
		if not is_instance_valid(node):
			continue
		var n2d: Node2D = node as Node2D
		var offset: Vector2 = n2d.global_position - origin
		var dist_sq: float = offset.length_squared()
		if dist_sq > best_dist_sq:
			continue
		if dist_sq > 1.0:
			var dot: float = facing.dot(offset / sqrt(dist_sq))
			if dot < half_cone_cos:
				continue
		if not _has_line_of_sight(origin, n2d.global_position):
			continue
		best_dist_sq = dist_sq
		best = n2d
	return best

func _has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var space_state := _owner_actor.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, 1 | 32) # World | Vision
	query.exclude = [_owner_actor.get_rid()]
	var result: Dictionary = space_state.intersect_ray(query)
	return result.is_empty()

func _enter_state(new_state: State) -> void:
	if new_state == State.SEARCH and state != State.SEARCH:
		_search_timer = search_duration
	if new_state == State.RETURN_TO_IDLE:
		target = null
		_suspicion = 0.0
	state = new_state

func has_target() -> bool:
	return state == State.CHASE or state == State.ATTACK

## Off by default (see docs/perception_system.md "Debug visualization").
## Per-instance, not a shared flag -- set `zombie.perception.debug_draw_enabled
## = true` on the one zombie you're inspecting (e.g. from game_eval or a
## future debug-select tool) so a 250-zombie swarm never draws 250
## overlapping cones. Draws this zombie's vision cone, last-known target
## position, and current state as text.
var debug_draw_enabled: bool = false

func draw_debug(canvas: CanvasItem) -> void:
	if not debug_draw_enabled:
		return
	var half_angle: float = deg_to_rad(vision_cone_degrees * 0.5)
	var left: Vector2 = facing.rotated(-half_angle) * vision_distance
	var right: Vector2 = facing.rotated(half_angle) * vision_distance
	var cone_color: Color = Color(0.2, 1.0, 0.3, 0.5) if has_target() else Color(1.0, 0.85, 0.2, 0.35)
	canvas.draw_line(Vector2.ZERO, left, cone_color, 1.5)
	canvas.draw_line(Vector2.ZERO, right, cone_color, 1.5)
	canvas.draw_arc(Vector2.ZERO, vision_distance, facing.angle() - half_angle, facing.angle() + half_angle, 16, cone_color, 1.5)
	if state != State.IDLE:
		var to_last_known: Vector2 = last_known_position - _owner_actor.global_position
		canvas.draw_line(Vector2.ZERO, to_last_known, Color(1.0, 0.2, 0.2, 0.7), 1.5)
		canvas.draw_circle(to_last_known, 6.0, Color(1.0, 0.2, 0.2, 0.8))
	canvas.draw_string(ThemeDB.fallback_font, Vector2(-20, -30), State.keys()[state], HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color.WHITE)
