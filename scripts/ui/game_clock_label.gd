extends Label
## Game-clock readout widget -- presentation-only display of SimulationClock
## time-of-day.
##
## The HUD feeds this node the current day/hour/minute every frame via
## `update_time`; here we just format "Day N  HH:MM" with a phase suffix
## (Dawn / Day / Dusk / Night) so the player gets at-a-glance temporal
## context for the day-night mood. It never reads SimulationClock itself,
## matching HUD's read-only display contract and keeping the widget unit-
## testable from a bare fixture.

const _SUFFIXES: Array = [
	["Night", 0, 330],
	["Dawn", 330, 450],
	["Day", 450, 1050],
	["Dusk", 1050, 1170],
	["Night", 1170, 1440],
]


## Pure phase suffix for a minute-of-day (wraps via fposmod). Exposed as a
## static so the headless test can pin it without an instance or the clock.
static func phase_suffix(minute_of_day: int) -> String:
	var m: int = int(fposmod(float(minute_of_day), 1440.0))
	for entry in _SUFFIXES:
		if m >= entry[1] and m < entry[2]:
			return entry[0]
	return "Night"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 16)
	add_theme_color_override("font_color", Color(0.86, 0.92, 1.0, 0.92))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_theme_constant_override("outline_size", 3)
	text = "Day 1  00:00"
	visible = true


## Formats the fed game time into "Day N  HH:MM" with a phase suffix.
func update_time(day: int, hour: int, minute: int) -> void:
	var h := int(fposmod(float(hour), 24.0))
	var m := int(fposmod(float(minute), 60.0))
	var pad := func(n: int) -> String: return "%02d" % n
	var suffix := phase_suffix(h * 60 + m)
	text = "Day %d  %s:%s  %s" % [maxi(day, 1), pad.call(h), pad.call(m), suffix]
