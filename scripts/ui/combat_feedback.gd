extends Control
## Full-screen combat feedback overlay: red damage flash, low-health warning
## pulse, and a kill-confirm hit marker. Purely presentational -- driven only
## by GameEvents signals, never reaching into gameplay nodes (the same
## read-only contract as the rest of the HUD). Lives inside HUD.tscn under
## Root, declared BEFORE SafeArea so panels and labels draw above the flash.

const FLASH_COLOR := Color(0.72, 0.09, 0.07, 1.0)
const VIGNETTE_COLOR := Color(0.42, 0.02, 0.02, 1.0)
const HIT_MARKER_COLOR := Color(1.0, 0.95, 0.78, 1.0)
## Tint applied to the screen-edge vignette that closes in as health drops.
const LOW_HEALTH_TINT := Color(0.55, 0.04, 0.04, 1.0)
## Below this health ratio the screen-edge vignette begins to close in.
const VIGNETTE_ONSET := 0.6

const LOW_HEALTH_THRESHOLD := 0.3
const MAX_FLASH_ALPHA := 0.42
const MAX_VIGNETTE_ALPHA := 0.3
const FLASH_DECAY_PER_SECOND := 2.2
const HIT_MARKER_DECAY_PER_SECOND := 3.0
const VIGNETTE_PULSE_SPEED := 4.5
const HIT_MARKER_GAP := 5.0
const HIT_MARKER_ARM := 11.0
const HIT_MARKER_WIDTH := 2.0

## Read-only strength of the screen-edge vignette (0 = open, 1 = max closed),
## derived from the current health ratio this frame.
var _vignette_strength: float = 0.0

var _flash_alpha: float = 0.0
var _hit_marker_alpha: float = 0.0
var _health_ratio: float = 1.0
var _pulse_time: float = 0.0
var _flash_rect: ColorRect
var _vignette_rect: ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette_rect = ColorRect.new()
	_vignette_rect.name = "LowHealthVignette"
	_vignette_rect.color = VIGNETTE_COLOR
	_vignette_rect.modulate.a = 0.0
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_vignette_rect)
	_flash_rect = ColorRect.new()
	_flash_rect.name = "DamageFlash"
	_flash_rect.color = FLASH_COLOR
	_flash_rect.modulate.a = 0.0
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash_rect)
	GameEvents.player_damaged.connect(_on_player_damaged)
	GameEvents.player_health_changed.connect(_on_player_health_changed)
	GameEvents.player_respawned.connect(_on_player_respawned)
	GameEvents.zombie_killed_by_player.connect(_on_zombie_killed_by_player)


func _process(delta: float) -> void:
	advance(delta)


## Time-step shared by _process and tests: advances every fade/pulse by an
## explicit delta so headless tests can drive decay deterministically.
func advance(delta: float) -> void:
	_flash_alpha = maxf(0.0, _flash_alpha - FLASH_DECAY_PER_SECOND * delta)
	_hit_marker_alpha = maxf(0.0, _hit_marker_alpha - HIT_MARKER_DECAY_PER_SECOND * delta)
	_flash_rect.modulate.a = MAX_FLASH_ALPHA * _flash_alpha
	# Screen-edge vignette closes in smoothly as health drops past onset,
	# peaking at the low-health threshold (where the pulsing low-health
	# vignette takes over). Above onset the screen stays clear.
	if _health_ratio > 0.0 and _health_ratio < VIGNETTE_ONSET:
		var t := clampf((VIGNETTE_ONSET - _health_ratio) / VIGNETTE_ONSET, 0.0, 1.0)
		_vignette_strength = t * t
	else:
		_vignette_strength = 0.0
	if is_low_health_warning_active():
		_pulse_time += delta
		var wave := 0.5 + 0.5 * sin(_pulse_time * VIGNETTE_PULSE_SPEED)
		_vignette_rect.modulate.a = MAX_VIGNETTE_ALPHA * (0.35 + 0.65 * wave)
	else:
		_pulse_time = 0.0
		_vignette_rect.modulate.a = 0.0
	queue_redraw()


## Read-only strength of the damage flash (0 = invisible, 1 = strongest).
func flash_strength() -> float:
	return _flash_alpha


## Read-only strength of the kill-confirm hit marker (0 = hidden).
func hit_marker_strength() -> float:
	return _hit_marker_alpha


## True while the player is alive and below the low-health threshold.
func is_low_health_warning_active() -> bool:
	return _health_ratio > 0.0 and _health_ratio < LOW_HEALTH_THRESHOLD


func _draw() -> void:
	if _hit_marker_alpha <= 0.0 and _vignette_strength <= 0.0:
		return
	# Screen-edge vignette: radial dark-red falloff that closes in as health
	# drops, painted with concentric translucent rings (no screen-grab shader
	# needed, so it works under the headless renderer too).
	if _vignette_strength > 0.0:
		var center := size * 0.5
		var max_r := center.length()
		var rings := 18
		for i in range(rings):
			var f := float(i) / float(rings)
			# Inner rings (near the edge) are the most opaque; closer to the
			# center the vignette fades to transparent so gameplay stays clear.
			var ring_alpha := _vignette_strength * (1.0 - f) * (1.0 - f) * 0.5
			if ring_alpha <= 0.002:
				continue
			var c := LOW_HEALTH_TINT
			c.a = ring_alpha
			draw_circle(center, max_r * (0.78 + 0.22 * f), c)
	if _hit_marker_alpha <= 0.0:
		return
	var center := size * 0.5
	var color := HIT_MARKER_COLOR
	color.a = 0.9 * _hit_marker_alpha
	for direction in [Vector2(1.0, 1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2(-1.0, -1.0)]:
		draw_line(
			center + direction * HIT_MARKER_GAP,
			center + direction * (HIT_MARKER_GAP + HIT_MARKER_ARM),
			color,
			HIT_MARKER_WIDTH
		)


func _on_player_damaged(amount: float) -> void:
	if amount <= 0.0:
		return
	_flash_alpha = minf(1.0, _flash_alpha + clampf(amount / 40.0, 0.35, 1.0))


func _on_player_health_changed(current: float, max_health: float) -> void:
	_health_ratio = current / maxf(max_health, 1.0)


## Read-only strength of the screen-edge vignette (0 = open, 1 = max closed).
func vignette_strength() -> float:
	return _vignette_strength


func _on_player_respawned() -> void:
	_flash_alpha = 0.0
	_hit_marker_alpha = 0.0
	_health_ratio = 1.0
	_pulse_time = 0.0
	_vignette_strength = 0.0


func _on_zombie_killed_by_player(_death_position: Vector2) -> void:
	_hit_marker_alpha = 1.0
