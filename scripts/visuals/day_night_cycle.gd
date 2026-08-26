extends Node
## Day-night ambient tint cycle -- presentation-only lighting mood driver.
##
## Reads SimulationClock's game time-of-day and blends a keyframed palette
## onto the scene Environment (background colour + ambient tint/energy) and
## the sun DirectionalLight3D (colour + energy). Purely cosmetic: it only
## READS SimulationClock (like HUD does) and writes render properties; it
## never touches simulation state. Re-applies only when the integer game-
## minute changes, so a paused clock freezes the mood for free.
##
## The midday keyframe intentionally equals VoxelMain.tscn's shipped static
## look, so noon is a zero-regression anchor and every other hour is a blend
## away from it (cold dim nights, warm dawn/dusk, bright neutral days).

const MINUTES_PER_DAY := 1440

## Upper bound for sun energy across the whole palette (test guard rail).
const MAX_SUN_ENERGY := 1.2

## Keyframes over one in-game day: [minute_of_day, background, ambient,
## ambient_energy, sun_colour, sun_energy]. Minute 1440 duplicates minute 0
## so the wrap interpolates cleanly instead of snapping.
const KEYFRAMES: Array = [
	[0.0, Color(0.020, 0.028, 0.055), Color(0.16, 0.22, 0.38), 0.20, Color(0.50, 0.62, 0.92), 0.10],
	[270.0, Color(0.035, 0.042, 0.075), Color(0.24, 0.28, 0.44), 0.26, Color(0.60, 0.66, 0.90), 0.18],
	[390.0, Color(0.16, 0.11, 0.105), Color(0.82, 0.55, 0.42), 0.45, Color(1.00, 0.62, 0.36), 0.70],
	[540.0, Color(0.095, 0.12, 0.165), Color(0.70, 0.78, 0.90), 0.62, Color(1.00, 0.93, 0.85), 1.00],
	[765.0, Color(0.105, 0.13, 0.17), Color(0.72, 0.80, 0.92), 0.68, Color(1.00, 0.97, 0.92), 1.15],
	[1005.0, Color(0.115, 0.125, 0.155), Color(0.72, 0.76, 0.86), 0.58, Color(1.00, 0.90, 0.78), 0.95],
	[1125.0, Color(0.19, 0.10, 0.085), Color(0.88, 0.52, 0.36), 0.42, Color(1.00, 0.55, 0.30), 0.65],
	[1245.0, Color(0.045, 0.05, 0.085), Color(0.28, 0.32, 0.48), 0.28, Color(0.55, 0.63, 0.90), 0.20],
	[1440.0, Color(0.020, 0.028, 0.055), Color(0.16, 0.22, 0.38), 0.20, Color(0.50, 0.62, 0.92), 0.10],
]

## Render targets -- normally auto-resolved from the parent (VoxelMain's
## WorldEnvironment / Sun siblings); tests may inject them directly.
var environment_resource: Environment = null
var sun_light: DirectionalLight3D = null

var _last_applied_minutes: float = -1.0


func _ready() -> void:
	_resolve_targets()
	var now: float = float(SimulationClock.total_game_minutes())
	apply_time(now)
	_last_applied_minutes = now


func _process(_delta: float) -> void:
	var now: float = float(SimulationClock.total_game_minutes())
	if now != _last_applied_minutes:
		apply_time(now)
		_last_applied_minutes = now


## Resolves missing render targets from sibling nodes under the same parent
## (VoxelMain layout). Anything already injected stays untouched.
func _resolve_targets() -> void:
	if environment_resource == null:
		var world_env: Node = get_parent().get_node_or_null("WorldEnvironment") if get_parent() != null else null
		if world_env is WorldEnvironment and world_env.environment != null:
			environment_resource = world_env.environment
	if sun_light == null:
		var sun_node: Node = get_parent().get_node_or_null("Sun") if get_parent() != null else null
		if sun_node is DirectionalLight3D:
			sun_light = sun_node


## Blends the palette at an absolute game-minute count onto the targets.
## Safe to call repeatedly; missing targets are skipped silently so the
## widget also works in bare fixtures.
func apply_time(total_game_minutes: float) -> void:
	var look: Dictionary = evaluate(total_game_minutes)
	if environment_resource != null:
		environment_resource.background_color = look["background"]
		environment_resource.ambient_light_color = look["ambient"]
		environment_resource.ambient_light_energy = look["ambient_energy"]
	if sun_light != null:
		sun_light.light_color = look["sun_color"]
		sun_light.light_energy = look["sun_energy"]


## Pure palette evaluation at an absolute game-minute count (wraps over
## 24 h). Returns {background, ambient, ambient_energy, sun_color,
## sun_energy}. Deterministic: same input, same output, no clock access --
## which is what makes the headless tests able to pin it exactly.
static func evaluate(total_game_minutes: float) -> Dictionary:
	var t: float = fposmod(total_game_minutes, float(MINUTES_PER_DAY))
	var lo: Array = KEYFRAMES[0]
	var hi: Array = KEYFRAMES[KEYFRAMES.size() - 1]
	for i in range(KEYFRAMES.size() - 1):
		if t >= KEYFRAMES[i][0] and t <= KEYFRAMES[i + 1][0]:
			lo = KEYFRAMES[i]
			hi = KEYFRAMES[i + 1]
			break
	var span: float = maxf(hi[0] - lo[0], 0.0001)
	var u: float = clampf((t - lo[0]) / span, 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)  # smoothstep for soft handoffs
	return {
		"background": (lo[1] as Color).lerp(hi[1], u),
		"ambient": (lo[2] as Color).lerp(hi[2], u),
		"ambient_energy": lerpf(lo[3], hi[3], u),
		"sun_color": (lo[4] as Color).lerp(hi[4], u),
		"sun_energy": lerpf(lo[5], hi[5], u),
	}
