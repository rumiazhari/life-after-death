extends Control
## Off-screen safehouse indicator -- presentation-only widget.
##
## The HUD feeds this node the settlement's screen position and the world-space
## distance every frame (`update_indicator`); here we decide visibility, clamp
## a rotated arrow marker to the viewport edge along the bearing to the target,
## and show remaining distance in metres. It never reaches into gameplay
## systems itself, matching HUD's read-only display contract.

## Inset from the viewport edges the marker is clamped into.
const EDGE_MARGIN := 56.0
## Presentation approximation for the metre readout (~1 human height per ~34px;
## chosen so building footprints read as plausible real-world sizes).
const PIXELS_PER_METER := 20.0

const _ARROW_COLOR := Color(0.55, 0.92, 0.6, 0.9)
const _MARKER_SIZE := 64.0

var _marker: Control
var _distance_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker = Control.new()
	_marker.name = "Marker"
	_marker.size = Vector2(_MARKER_SIZE, _MARKER_SIZE)
	_marker.pivot_offset = Vector2(_MARKER_SIZE, _MARKER_SIZE) * 0.5
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_on_marker_draw)
	add_child(_marker)
	_distance_label = Label.new()
	_distance_label.name = "DistanceLabel"
	_distance_label.size = Vector2(80, 20)
	_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_distance_label.add_theme_font_size_override("font_size", 14)
	_distance_label.add_theme_color_override("font_color", Color(0.7, 0.95, 0.72))
	_distance_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_distance_label.add_theme_constant_override("outline_size", 4)
	add_child(_distance_label)
	visible = false


func update_indicator(target_screen_pos: Vector2, viewport_size: Vector2, world_distance_px: float) -> void:
	if viewport_size.x <= EDGE_MARGIN * 2.0 or viewport_size.y <= EDGE_MARGIN * 2.0:
		visible = false
		return
	var center := viewport_size * 0.5
	var offset := target_screen_pos - center
	if offset.length_squared() < 1.0:
		visible = false
		return
	var half := center - Vector2(EDGE_MARGIN, EDGE_MARGIN)
	var scale_x: float = INF if offset.x == 0.0 else half.x / absf(offset.x)
	var scale_y: float = INF if offset.y == 0.0 else half.y / absf(offset.y)
	# t is how far along the bearing the inset boundary sits, relative to the
	# target distance: t < 1 means the boundary comes first (target is
	# off-screen); t >= 1 means the target itself is inside the safe inset.
	var t := minf(scale_x, scale_y)
	if t >= 1.0:
		# Target already inside the safe inset -> it is on-screen; the player
		# can see the building itself, so the marker would only add clutter.
		visible = false
		return
	var edge_point := center + offset * t
	visible = true
	_marker.rotation = offset.angle()
	_marker.position = edge_point - _marker.pivot_offset
	var metres := int(round(world_distance_px / PIXELS_PER_METER))
	_distance_label.text = "%dm" % metres
	# Nudge the readout inward from the edge so it never clips off-screen.
	var inward := -offset.normalized() * (_MARKER_SIZE * 0.5 + 6.0)
	_distance_label.position = edge_point + inward - _distance_label.size * 0.5


func _on_marker_draw() -> void:
	# Chunky arrow pointing along local +X (rotation carries the bearing):
	# shaft rectangle plus an arrowhead triangle.
	_marker.draw_rect(Rect2(Vector2(10.0, 27.0), Vector2(18.0, 10.0)), _ARROW_COLOR)
	var head := PackedVector2Array([
		Vector2(48.0, 32.0),
		Vector2(26.0, 16.0),
		Vector2(26.0, 48.0),
	])
	_marker.draw_colored_polygon(head, _ARROW_COLOR)
