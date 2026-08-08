extends Node
## Deterministic simulation time source (autoload "SimulationClock").
##
## Everything that needs "how much game time passed" reads from here instead
## of `_process(delta)` directly, so simulation speed (pause/normal/fast) is
## one shared knob rather than something every system has to re-implement.
## Ticks at a fixed real-time interval independent of rendering FPS -- a
## slow frame does not skip simulation steps, it just processes more of them
## in one `_process` call (bounded, see `_MAX_TICKS_PER_FRAME`).

signal minute_changed(minute: int)
signal hour_changed(hour: int)
signal day_changed(day: int)
## Fires on every fixed simulation tick (independent of game-minute
## granularity). AI systems stagger decision work off `tick_count` instead
## of every rendered frame.
signal sim_tick(tick_count: int)

enum SimSpeed { PAUSED = 0, NORMAL = 1, FAST = 4 }

## How many real seconds correspond to one in-game minute at NORMAL speed.
@export var real_seconds_per_game_minute: float = 1.0
## Fixed simulation step, in real seconds, at 1x speed. Ticks are what
## `sim_tick` fires on; `real_seconds_per_game_minute` is expressed as a
## count of these ticks so minute changes stay aligned to tick boundaries.
@export var tick_interval_seconds: float = 0.25
const _MAX_TICKS_PER_FRAME := 40

var speed: SimSpeed = SimSpeed.NORMAL

var game_minute: int = 0
var game_hour: int = 0
var game_day: int = 1
var tick_count: int = 0

var _tick_accumulator: float = 0.0
var _minute_accumulator: float = 0.0

func _process(delta: float) -> void:
	if speed == SimSpeed.PAUSED:
		return
	_tick_accumulator += delta * float(speed)
	var ticks_this_frame: int = 0
	while _tick_accumulator >= tick_interval_seconds and ticks_this_frame < _MAX_TICKS_PER_FRAME:
		_tick_accumulator -= tick_interval_seconds
		ticks_this_frame += 1
		_advance_tick()

func set_speed(new_speed: SimSpeed) -> void:
	speed = new_speed

func pause() -> void:
	speed = SimSpeed.PAUSED

func resume_normal() -> void:
	speed = SimSpeed.NORMAL

## Total simulated minutes elapsed since day 1, 00:00 (which evaluates to
## exactly zero -- game_day is 1-based, so it's (game_day - 1) here, not
## game_day).
func total_game_minutes() -> int:
	return (game_day - 1) * 24 * 60 + game_hour * 60 + game_minute

## Resets every mutable field to its initial state -- called on restart so
## a reloaded scene doesn't inherit the previous run's time-of-day, speed,
## or tick accumulators (SimulationClock is an autoload and survives
## SceneTree.reload_current_scene() otherwise).
func reset() -> void:
	speed = SimSpeed.NORMAL
	game_minute = 0
	game_hour = 0
	game_day = 1
	tick_count = 0
	_tick_accumulator = 0.0
	_minute_accumulator = 0.0

func _advance_tick() -> void:
	tick_count += 1
	sim_tick.emit(tick_count)
	_minute_accumulator += tick_interval_seconds
	while _minute_accumulator >= real_seconds_per_game_minute:
		_minute_accumulator -= real_seconds_per_game_minute
		_advance_minute()

func _advance_minute() -> void:
	game_minute += 1
	if game_minute >= 60:
		game_minute = 0
		game_hour += 1
		if game_hour >= 24:
			game_hour = 0
			game_day += 1
			day_changed.emit(game_day)
		hour_changed.emit(game_hour)
	minute_changed.emit(game_minute)
