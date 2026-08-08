class_name SurvivorAI
extends Node
## Utility-AI brain for one Survivor. Owns need decay, a lightweight
## perception cache, and periodic reconsideration among the fixed action set
## in scripts/ai/actions/ -- there is no hard-coded behavior state machine
## here, only "ask every action for a score, run the winner."
##
## Reconsideration and perception both run on jittered per-survivor
## intervals (not every physics frame, not synchronized across survivors)
## so decision cost stays flat as survivor count grows, and a nearby threat
## or a stat crossing an emergency threshold can force early reconsideration
## between those normal ticks (see `_check_emergency`).

signal action_changed(action_name: StringName)

@export var base_decision_interval: float = 1.5
@export var decision_jitter: float = 0.4
@export var base_perception_interval: float = 0.5
@export var perception_radius: float = 420.0
@export var emergency_zombie_radius: float = 160.0
@export var offscreen_slowdown: float = 3.0

## --- Need decay, applied once per simulated game-minute (SimulationClock)
## so it scales with sim speed/pause instead of real wall-clock time. ---
@export var hunger_per_minute: float = 0.18
@export var thirst_per_minute: float = 0.26
@export var fatigue_per_minute: float = 0.12
@export var starvation_damage_per_minute: float = 1.0

var survivor: Survivor
var data: SurvivorData
var settlement: Settlement
var job_board: SettlementJobBoard

var current_action: UtilityAction = null
var current_job: Job = null
## Set by an action's enter()/tick() so the inspector panel can show what
## the survivor is actually walking toward / claiming.
var reserved_target_description: String = ""

var nearby_zombies: Array = []
var nearest_zombie: Node2D = null
var nearest_zombie_distance: float = INF

var last_scores: Dictionary = {} ## String action name -> float

var decisions_made: int = 0
var actions_evaluated: int = 0
var last_decision_time_usec: int = 0

var _actions: Array[UtilityAction] = []
var _decision_timer: float = 0.0
var _perception_timer: float = 0.0
var _stopped: bool = false

func _ready() -> void:
	survivor = get_parent()
	set_physics_process(false) ## enabled once Survivor.setup() supplies `data`

func begin(survivor_data: SurvivorData) -> void:
	data = survivor_data
	settlement = get_tree().get_first_node_in_group("settlement")
	job_board = get_tree().get_first_node_in_group("job_board")
	_actions = [
		ActionSeekSafety.new(), ActionFlee.new(), ActionFight.new(),
		ActionTreatSelf.new(), ActionHelpInjured.new(), ActionSleep.new(),
		ActionEat.new(), ActionDrink.new(),
		ActionHaulSupplies.new(), ActionRetrieveSupplies.new(), ActionScavenge.new(),
		ActionGuard.new(), ActionWander.new(), ActionIdle.new(),
	]
	_decision_timer = randf() * base_decision_interval
	_perception_timer = randf() * base_perception_interval
	SimulationClock.minute_changed.connect(_on_minute_changed)
	set_physics_process(true)

## Called once, on death -- permanent, unlike an emergency interruption
## (see UtilityAction.exit()). current_action.exit() first releases
## whatever a still-in-progress action would release on any interruption
## (a claimed-but-not-yet-picked-up job, a sleep spot, a helper claim, a
## personal retrieve-supplies reservation); release_survivor_permanently()
## then additionally fails any HAUL job this survivor was already
## physically carrying (its cargo dies with it) instead of leaving that
## job dangling or letting release_survivor() send someone else to an
## already-emptied pickup point.
func stop() -> void:
	_stopped = true
	set_physics_process(false)
	if current_action:
		current_action.exit(self)
		current_action = null
	if job_board and data:
		job_board.release_survivor_permanently(data.id)
	if SimulationClock.minute_changed.is_connected(_on_minute_changed):
		SimulationClock.minute_changed.disconnect(_on_minute_changed)

func _on_minute_changed(_minute: int) -> void:
	if _stopped or data == null or data.is_dead:
		return
	data.hunger = minf(data.hunger + hunger_per_minute, 100.0)
	data.thirst = minf(data.thirst + thirst_per_minute, 100.0)
	data.fatigue = minf(data.fatigue + fatigue_per_minute, 100.0)
	var is_safe: bool = settlement != null and settlement.is_position_safe(survivor.global_position)
	data.fear = maxf(data.fear - (3.0 if is_safe else 0.5), 0.0)
	var baseline_morale: float = 70.0
	data.morale = move_toward(data.morale, baseline_morale, 0.5)
	if data.hunger >= 100.0 or data.thirst >= 100.0:
		survivor.take_damage(starvation_damage_per_minute, null)

func _physics_process(delta: float) -> void:
	if _stopped or data == null:
		return
	if current_action:
		var finished: bool = current_action.tick(self, delta)
		if finished:
			_exit_current_action()
			_decision_timer = 0.0

	_perception_timer -= delta
	if _perception_timer <= 0.0:
		_refresh_perception()
		var slowdown: float = offscreen_slowdown if not survivor.is_on_screen else 1.0
		_perception_timer = base_perception_interval * slowdown + randf() * 0.1
		_check_emergency()

	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_reconsider()
		var slowdown: float = offscreen_slowdown if not survivor.is_on_screen else 1.0
		_decision_timer = base_decision_interval * slowdown + randf_range(-decision_jitter, decision_jitter)

## --- Perception -----------------------------------------------------------

func _refresh_perception() -> void:
	nearby_zombies.clear()
	nearest_zombie = null
	nearest_zombie_distance = INF
	var origin: Vector2 = survivor.global_position
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(zombie):
			continue
		var dist: float = origin.distance_to((zombie as Node2D).global_position)
		if dist <= perception_radius:
			nearby_zombies.append(zombie)
			if dist < nearest_zombie_distance:
				nearest_zombie_distance = dist
				nearest_zombie = zombie

func _check_emergency() -> void:
	var threatened: bool = nearest_zombie_distance <= emergency_zombie_radius
	var critical_health: bool = data.health <= data.max_health * 0.25
	var already_reacting: bool = current_action != null and current_action.is_emergency
	if (threatened or critical_health) and not already_reacting:
		_decision_timer = 0.0

## --- Decision loop ----------------------------------------------------

func _reconsider() -> void:
	var start_usec: int = Time.get_ticks_usec()
	var candidates: Array[UtilityAction] = []
	for action in _actions:
		if action.can_start(self):
			candidates.append(action)
	if candidates.is_empty():
		return
	last_scores.clear()
	var best_action: UtilityAction = null
	var best_score: float = -INF
	for action in candidates:
		var s: float = action.score(self)
		last_scores[String(action.action_name)] = s
		if s > best_score:
			best_score = s
			best_action = action
	actions_evaluated += candidates.size()
	decisions_made += 1
	last_decision_time_usec = Time.get_ticks_usec() - start_usec

	if current_action == null:
		_switch_to(best_action)
		return
	if best_action == current_action:
		return
	var current_score: float = last_scores.get(String(current_action.action_name), 0.0)
	if best_action.is_emergency and best_score > current_score:
		_switch_to(best_action)
	elif best_score > current_score + current_action.interrupt_cost:
		_switch_to(best_action)

func _switch_to(action: UtilityAction) -> void:
	_exit_current_action()
	current_action = action
	current_action.enter(self)
	data.current_action = String(action.action_name)
	action_changed.emit(action.action_name)

func _exit_current_action() -> void:
	if current_action:
		current_action.exit(self)
		current_action = null
	current_job = null
	reserved_target_description = ""

func average_decision_time_ms() -> float:
	return last_decision_time_usec / 1000.0
