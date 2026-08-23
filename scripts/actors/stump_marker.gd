class_name StumpMarker
extends Node2D
## Draws a dark red stump where a zombie limb was severed. Purely visual.

func _draw() -> void:
	draw_circle(Vector2.ZERO, 4.0, Color8(96, 12, 12))
	draw_circle(Vector2.ZERO, 2.0, Color8(40, 8, 8))