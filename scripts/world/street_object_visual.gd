class_name StreetObjectVisual
extends Node2D
## Procedural visual for street objects whose tiny atlas sprite cannot read
## as a full urban object (trees, street lamps). Draws upward from the node
## origin, which MUST sit at the object's ground/base point so shared
## y_sort_enabled containers order actors correctly against the base while
## the tall visual may freely overlap roofs, roads or facades behind it.
## Everything above the physical footprint is strictly visual-only.

var kind: StringName = &"tree"
var variant: int = 0
var damaged: bool = false
var visual_size: Vector2 = Vector2(96, 112)
## Flicker mode drives a cheap low-frequency energy cut on the attached
## light; steady/dead lamps never run per-frame logic at all.
var light_mode: StringName = &"steady"
var light_node: PointLight2D

static func make(spec: Dictionary) -> StreetObjectVisual:
	var visual := StreetObjectVisual.new()
	visual.kind = spec.get("procedural_kind", &"tree")
	visual.variant = int(spec.get("variant", 0))
	visual.damaged = bool(spec.get("damaged", false))
	visual.visual_size = spec.get("visual_size", Vector2(96, 112))
	visual.light_mode = spec.get("light_mode", &"steady")
	return visual

func _ready() -> void:
	if kind == &"lamp":
		_attach_light()
	if light_mode != &"flicker":
		set_process(false)

func _attach_light() -> void:
	if light_mode == &"dead":
		return
	light_node = PointLight2D.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.93, 0.74, 0.85))
	gradient.set_color(1, Color(1.0, 0.9, 0.65, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 256
	texture.height = 256
	light_node.texture = texture
	light_node.color = Color(1.0, 0.92, 0.7)
	light_node.energy = 0.55 if light_mode == &"flicker" else 0.8
	light_node.texture_scale = maxf(visual_size.x, 96.0) / 128.0
	# Lamp head sits near the top of the pole visual.
	light_node.position = Vector2(0.0, -visual_size.y * 0.86)
	add_child(light_node)

func _process(_delta: float) -> void:
	if light_node == null or light_mode != &"flicker":
		set_process(false)
		return
	# Cheap mains flicker: only flickering lamps ever run this, and it
	# touches one enabled flag -- no searches, no allocations.
	var t := Time.get_ticks_msec() / 1000.0
	light_node.enabled = fmod(t * 7.3 + float(variant), 1.0) > 0.12

func _draw() -> void:
	match kind:
		&"tree":
			_draw_tree()
		&"lamp":
			_draw_lamp()

func _draw_tree() -> void:
	var height := visual_size.y
	var trunk_top := -height * 0.42
	if damaged:
		# Dead tree: bare trunk plus two broken branch stubs, no canopy.
		draw_rect(Rect2(-4.0, trunk_top, 8.0, -trunk_top), Color8(74, 58, 46))
		draw_line(Vector2(-2.0, trunk_top + 14.0), Vector2(-20.0, trunk_top - 6.0), Color8(74, 58, 46), 5.0)
		draw_line(Vector2(2.0, trunk_top + 26.0), Vector2(18.0, trunk_top + 8.0), Color8(66, 52, 41), 4.0)
		return
	var greens: Array[Color] = [Color8(64, 96, 52), Color8(78, 112, 58), Color8(92, 126, 66)]
	if variant % 3 == 1:
		greens = [Color8(58, 88, 62), Color8(70, 104, 70), Color8(86, 120, 78)]
	elif variant % 3 == 2:
		greens = [Color8(84, 108, 48), Color8(100, 124, 56), Color8(116, 138, 66)]
	var radius_x := visual_size.x * 0.46
	var crown_center := Vector2(0.0, trunk_top - height * 0.16)
	# Layered canopy blobs: three overlapping crowns read as one mature
	# urban tree while staying cheap (a handful of draw calls).
	var spread := radius_x * 0.55
	draw_circle(crown_center + Vector2(-spread, height * 0.05), radius_x * 0.72, greens[0])
	draw_circle(crown_center + Vector2(spread, height * 0.07), radius_x * 0.66, greens[0])
	draw_circle(crown_center + Vector2(0.0, -height * 0.06), radius_x * 0.8, greens[1])
	draw_circle(crown_center + Vector2(-radius_x * 0.2, -height * 0.12), radius_x * 0.5, greens[2])
	draw_circle(crown_center + Vector2(radius_x * 0.24, height * 0.02), radius_x * 0.42, greens[2])
	# Trunk drawn after the canopy so it visibly meets the crown shadowline.
	draw_rect(Rect2(-4.0, trunk_top, 8.0, -trunk_top), Color8(84, 66, 50))
	draw_rect(Rect2(-1.5, trunk_top, 3.0, -trunk_top), Color8(104, 82, 60))

func _draw_lamp() -> void:
	var height := visual_size.y
	var tilt := 1.0 if not damaged else 0.35
	draw_rect(Rect2(-3.0, -height * 0.82 * tilt, 6.0, height * 0.82 * tilt), Color8(84, 88, 90))
	draw_rect(Rect2(-1.0, -height * 0.82 * tilt, 2.0, height * 0.82 * tilt), Color8(112, 118, 120))
	# Base flange.
	draw_rect(Rect2(-6.0, -9.0, 12.0, 9.0), Color8(64, 68, 70))
	var head_y := -height * 0.82 * tilt
	if damaged:
		# Bent/broken lamp: arm snapped sideways, dead head hanging.
		draw_line(Vector2.ZERO, Vector2(18.0, head_y + 26.0), Color8(84, 88, 90), 4.0)
		draw_rect(Rect2(12.0, head_y + 18.0, 18.0, 8.0), Color8(48, 52, 54))
	else:
		draw_rect(Rect2(-10.0, head_y - 9.0, 20.0, 9.0), Color8(64, 68, 70))
		draw_rect(Rect2(-8.0, head_y - 7.0, 16.0, 5.0), Color8(168, 158, 116))
