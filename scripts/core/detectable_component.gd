class_name DetectableComponent
extends Node
## Reusable per-actor "how detectable am I right now" component (Player,
## Survivor). ZombiePerceptionComponent consumes it when the candidate has
## one; a candidate WITHOUT it (any actor type that doesn't add this
## component) falls back to neutral defaults (full visibility, no indoor
## context) rather than special-casing "component missing" as an error
## anywhere that reads it -- see `_visibility_multiplier_for()` and
## `_concealment_for()` in zombie_perception_component.gd.
##
## Movement noise state (stationary/walking/running) is driven by the
## owning actor calling `report_movement_speed(speed)` once per physics
## tick from its own _physics_process -- this component never reads
## CharacterBody2D.velocity itself, keeping it decoupled from any one
## actor's own movement implementation. No crouch input exists yet, but
## `visibility_multiplier` and `concealment_modifier` are already the
## exact two knobs a future crouch action would set.

signal noise_reported(loudness: float, category: StringName)

## Multiplies effective vision-detection distance/suspicion buildup for
## zombies looking at this actor -- < 1.0 reads as harder to see (e.g. a
## future crouch/concealment action), > 1.0 easier. 1.0 is the neutral
## default; see effective_visibility_multiplier() for how a stationary
## actor further reduces this without needing a separate flag.
@export var visibility_multiplier: float = 1.0
## Extra multiplicative reduction applied while NOT currently moving
## (report_movement_speed() was last called with a near-zero speed) --
## "a stationary actor is harder to notice than one moving in the open."
@export var stationary_visibility_factor: float = 0.7
## Loudness while walking (see NoiseManager's loudness-as-radius model --
## docs/perception_system.md).
@export var walking_noise: float = 2.0
## Loudness while running/sprinting -- deliberately louder than walking,
## so it reaches farther through NoiseManager's loudness*20 radius rule.
@export var running_noise: float = 6.0
## Speed threshold (world units/sec) above which movement counts as
## "running" rather than "walking" for noise purposes.
@export var running_speed_threshold: float = 90.0
## Below this speed (world units/sec), an actor counts as stationary --
## no movement noise, no footstep events.
@export var minimum_speed: float = 1.0
## Seconds between footstep noise events while walking.
@export var walking_step_interval: float = 0.6
## Seconds between footstep noise events while running -- shorter than
## walking_step_interval, so running is both louder AND more frequent.
@export var running_step_interval: float = 0.3
## Extra flat reduction to how loud any noise this actor makes reads to
## NoiseManager (e.g. a future crouch/hide mechanic) -- subtracted before
## loudness is converted to an effective hearing radius.
@export var concealment_modifier: float = 0.0

var current_building_id: StringName = &""
var current_room_id: StringName = &""
var is_indoors: bool = false
var last_noise_category: StringName = &""
var last_noise_time_ticks: int = -1

var _movement_noise: float = 0.0
var _owner_actor: Node2D
var _step_timer: float = 0.0

func _ready() -> void:
	_owner_actor = get_parent()

## Called once per physics tick by the owning actor with its current
## speed (world units/sec). Drives movement_noise() and, through
## effective_visibility_multiplier(), how visually noticeable standing
## still vs. moving reads to a zombie's perception. Does NOT emit noise
## itself -- see _physics_process(), which emits at most one bounded
## footstep event per walking_step_interval/running_step_interval rather
## than every physics tick this is called from.
func report_movement_speed(speed: float) -> void:
	if speed < minimum_speed:
		_movement_noise = 0.0
	elif speed < running_speed_threshold:
		_movement_noise = walking_noise
	else:
		_movement_noise = running_noise

## Bounded footstep emission -- gated by a countdown timer, never once per
## frame, so a long walk doesn't flood NoiseManager's fixed-size ring
## buffer with near-duplicate events. Resets to zero (fires immediately on
## the next step) whenever the actor is stationary, so starting to move
## always produces an audible first footstep rather than waiting out a
## leftover countdown from a previous walk.
func _physics_process(delta: float) -> void:
	if not is_moving():
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = running_step_interval if _movement_noise >= running_noise else walking_step_interval
		_emit_noise(movement_noise(), &"footstep")

func movement_noise() -> float:
	return _movement_noise

func is_moving() -> bool:
	return _movement_noise > 0.0

## visibility_multiplier, further reduced while stationary -- the single
## value ZombiePerceptionComponent scales its vision_distance/suspicion
## buildup by for this actor.
func effective_visibility_multiplier() -> float:
	return visibility_multiplier * (1.0 if is_moving() else stationary_visibility_factor)

## A momentary noise (search/salvage/door/gunshot/footstep/...). Routes
## through the same NoiseManager every other noise source uses (never a
## parallel hearing system), and records last_noise_category/
## last_noise_time_ticks locally so a caller (a future UI/debug readout,
## or a test) can read "what did this actor just do" without re-deriving
## it from NoiseManager's own ring buffer.
func report_activity_noise(loudness: float, category: StringName) -> void:
	_emit_noise(loudness, category)

func _emit_noise(loudness: float, category: StringName) -> void:
	last_noise_category = category
	last_noise_time_ticks = SimulationClock.tick_count
	var effective: float = maxf(loudness - concealment_modifier, 0.0)
	NoiseManager.emit_noise(_owner_actor.global_position, effective, category, _owner_actor)
	noise_reported.emit(effective, category)

## Effective loudness of this actor's current continuous movement (not
## one-shot activities, which go through report_activity_noise directly).
func effective_movement_loudness() -> float:
	return maxf(_movement_noise - concealment_modifier, 0.0)

## Set by BuildingVisibilityController when this actor's owning body
## enters/exits a Room it monitors (see building_visibility_controller.gd
## "_update_detectable_context"). Indoor status alone never makes an
## actor undetectable -- ZombiePerceptionComponent's raycast-based line of
## sight is still the only thing that decides visibility; this is purely
## descriptive state for callers that want to know "is this actor
## indoors right now" (e.g. a future UI, or SurvivorAI's own decisions).
func set_indoor_context(building_id: StringName, room_id: StringName) -> void:
	current_building_id = building_id
	current_room_id = room_id
	is_indoors = building_id != &""
