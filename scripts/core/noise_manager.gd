extends Node
## Autoload "NoiseManager". Central bounded noise system -- one signal, one
## small ring buffer of recent noise events, no per-sound Area2D. Zombie
## perception polls `recent_noises_since()` on its own low-frequency
## timer rather than this manager pushing to every zombie individually, so
## emitting a noise stays O(1) regardless of zombie count.

signal noise_emitted(position: Vector2, loudness: float, category: StringName, source: Node)

const MAX_RECENT := 32

## Array of {position, loudness, category, tick} dictionaries, newest last,
## capped at MAX_RECENT (oldest dropped) -- a bounded log, not a growing one.
var _recent: Array[Dictionary] = []
var _next_sequence: int = 1

## Prefers `actor`'s own DetectableComponent (duck-typed via its `detectable`
## property, the same convention Player/Survivor already expose) so
## concealment_modifier applies and last_noise_category/last_noise_time_ticks
## get recorded on that actor; falls back to a direct emit_noise() when
## `actor` is null or has no such component -- e.g. a programmatic/
## environmental toggle with no interacting actor, or an actor type that
## never added the component. Never requires an actor to make noise.
func emit_actor_noise(actor: Node, position: Vector2, loudness: float, category: StringName) -> void:
	if actor != null and "detectable" in actor and actor.detectable != null:
		actor.detectable.report_activity_noise(loudness, category, position)
	else:
		emit_noise(position, loudness, category, actor)

func emit_noise(position: Vector2, loudness: float, category: StringName, source: Node = null) -> void:
	if loudness <= 0.0:
		return
	_recent.append({
		"sequence": _next_sequence,
		"position": position,
		"loudness": loudness,
		"category": category,
		"source": source,
		"tick": SimulationClock.tick_count,
	})
	_next_sequence += 1
	if _recent.size() > MAX_RECENT:
		_recent.remove_at(0)
	noise_emitted.emit(position, loudness, category, source)

## Noises emitted within the last `within_ticks` sim ticks, for a listener
## at `listener_position` whose effective hearing radius is `hearing_radius`
## (the loudness itself already IS the radius -- see docs/perception_system.md
## for why hearing uses loudness-as-radius rather than a falloff curve).
func recent_noises_near(listener_position: Vector2, hearing_radius: float, within_ticks: int = 12) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var min_tick: int = SimulationClock.tick_count - within_ticks
	for entry in _recent:
		if entry["tick"] < min_tick:
			continue
		var effective_radius: float = minf(entry["loudness"] * 20.0, hearing_radius)
		if listener_position.distance_to(entry["position"]) <= effective_radius:
			result.append(entry)
	return result

func reset() -> void:
	_recent.clear()
	_next_sequence = 1
