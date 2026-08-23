class_name CrackOverlay
extends Node2D
## Deterministic crack lines drawn over a damaged single-block structure.
## Purely visual: three stages add more jagged fractures. Redrawn only when
## the damage stage changes.

var stage: int = 1
var size: Vector2 = Vector2(32, 32)
var seed_hash: int = 0

func _draw() -> void:
	if stage <= 0:
		return
	var cracks := stage * 2 + 1
	var dark := Color(0.08, 0.07, 0.06, 0.85)
	var mid := Color(0.18, 0.16, 0.14, 0.7)
	for i in range(cracks):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_hash ^ (i + 1) * 7919
		var start := Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4)) * size
		var direction := Vector2.RIGHT.rotated(rng.randf() * TAU)
		var segments := 3 + stage
		var point := start
		var previous := point
		for s in range(segments):
			previous = point
			point += direction.rotated(rng.randf_range(-0.8, 0.8)) * (size.length() * 0.16)
			point.x = clampf(point.x, -size.x * 0.5, size.x * 0.5)
			point.y = clampf(point.y, -size.y * 0.5, size.y * 0.5)
			draw_line(previous, point, mid if s % 2 == 0 else dark, 1.5 if stage > 2 else 1.0)
		# Chip pits at fracture ends for the heavier stages.
		if stage >= 2:
			draw_circle(point, 1.6 + float(stage), Color(0.05, 0.05, 0.04, 0.55))
