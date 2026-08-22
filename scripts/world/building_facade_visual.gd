class_name BuildingFacadeVisual
extends Node2D
## One deterministic, non-colliding Prague street elevation. The node's
## origin is the southern ground-contact baseline so a shared y-sort parent
## can order actors against the complete facade as one architectural object.

const TILE_SIZE := 32.0
## Semantic entrance positions sit on a wall-cell center, but the carved
## door bay spans [center-16, center+48] (see
## ProceduralBuildingGenerator.door_bay_rect), so the painted leaf centers
## half a cell east of the semantic point to line up exactly with the
## interior Door leaves and their collision.
const DOOR_BAY_SHIFT := 16.0
const DOOR_BAY_WIDTH := 58.0

var facade_spans: Array[Rect2] = []
var facade_style: StringName = &"painted_plaster"
var archetype: StringName = &"apartment"
var storeys: int = 3
var entrance_positions: Array[Vector2] = []
var window_positions: Array[Vector2] = []
var decoration_seed: int = 0
var projection_height: float = 96.0
var anchor_y: float = 0.0

func configure(spec: Dictionary) -> void:
	facade_spans.assign(spec.get("facade_spans", []))
	facade_style = spec.get("facade_style", &"painted_plaster")
	archetype = spec.get("archetype", &"apartment")
	storeys = clampi(int(spec.get("visual_storeys", 3)), 2, 4)
	entrance_positions.assign(spec.get("entrance_positions", []))
	window_positions.assign(spec.get("window_positions", []))
	decoration_seed = int(spec.get("decoration_seed", 0))
	projection_height = float(spec.get("projection_height", storeys * TILE_SIZE))
	anchor_y = float(spec.get("anchor_y", 0.0))
	position.y = anchor_y
	queue_redraw()

func _draw() -> void:
	for span_index in range(facade_spans.size()):
		_draw_span(facade_spans[span_index], span_index)

func _draw_span(world_local_span: Rect2, span_index: int) -> void:
	var baseline := world_local_span.end.y - anchor_y
	var rect := Rect2(
		Vector2(world_local_span.position.x, baseline - projection_height),
		Vector2(world_local_span.size.x, projection_height)
	)
	var palette := _palette()
	# Ground-contact shadow and a dark return on both exposed party-wall ends.
	draw_rect(Rect2(rect.position + Vector2(4.0, rect.size.y), Vector2(rect.size.x, 9.0)), Color(0.08, 0.075, 0.07, 0.34))
	draw_rect(rect, palette["wall"])
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4.0)), palette["trim_dark"])
	draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - 6.0), Vector2(rect.size.x, 6.0)), palette["trim_dark"])
	draw_rect(Rect2(rect.position, Vector2(5.0, rect.size.y)), palette["side_dark"])
	draw_rect(Rect2(Vector2(rect.end.x - 5.0, rect.position.y), Vector2(5.0, rect.size.y)), palette["side_dark"])

	_draw_masonry(rect, palette, span_index)
	_draw_floor_bands(rect, palette)
	_draw_upper_windows(rect, palette, span_index)
	_draw_ground_frontage(rect, world_local_span, palette, span_index)
	_draw_prague_details(rect, palette, span_index)

func _draw_masonry(rect: Rect2, palette: Dictionary, span_index: int) -> void:
	if facade_style not in [&"masonry_industrial", &"exposed_brick_infill"]:
		# Restrained plaster wear: deterministic short cracks and faded patches.
		var patch_count := clampi(int(rect.size.x / 96.0), 1, 5)
		for i in range(patch_count):
			var x := rect.position.x + 18.0 + float(_hash(span_index, i, 11) % maxi(int(rect.size.x - 36.0), 1))
			var y := rect.position.y + 14.0 + float(_hash(span_index, i, 17) % maxi(int(rect.size.y - 38.0), 1))
			draw_rect(Rect2(Vector2(x, y), Vector2(9.0, 5.0)), palette["wear"])
			draw_line(Vector2(x + 4.0, y + 5.0), Vector2(x + 1.0, y + 11.0), palette["crack"], 1.0)
		return
	var row_height := 8.0
	var rows := int(rect.size.y / row_height)
	for row in range(rows):
		var y := rect.position.y + float(row) * row_height
		draw_line(Vector2(rect.position.x + 5.0, y), Vector2(rect.end.x - 5.0, y), palette["mortar"], 1.0)
		var offset := 12.0 if row % 2 == 0 else 0.0
		var x := rect.position.x + 5.0 + offset
		while x < rect.end.x - 5.0:
			draw_line(Vector2(x, y), Vector2(x, minf(y + row_height, rect.end.y)), palette["mortar"], 1.0)
			x += 24.0

func _draw_floor_bands(rect: Rect2, palette: Dictionary) -> void:
	var floor_height := projection_height / float(storeys)
	for floor_index in range(1, storeys):
		var y := rect.end.y - floor_height * float(floor_index)
		draw_rect(Rect2(Vector2(rect.position.x + 4.0, y - 2.0), Vector2(rect.size.x - 8.0, 4.0)), palette["trim"])

func _draw_upper_windows(rect: Rect2, palette: Dictionary, span_index: int) -> void:
	var floor_height := projection_height / float(storeys)
	var bay_count := maxi(int(floor(rect.size.x / 48.0)), 1)
	var bay_width := rect.size.x / float(bay_count)
	for floor_index in range(1, storeys):
		var center_y := rect.end.y - floor_height * (float(floor_index) + 0.48)
		for bay in range(bay_count):
			if _hash(span_index, floor_index, bay) % 13 == 0:
				continue
			var center_x := rect.position.x + bay_width * (float(bay) + 0.5)
			_draw_window(Vector2(center_x, center_y), palette, _hash(span_index, floor_index, bay + 31) % 4 == 0)

func _draw_window(center: Vector2, palette: Dictionary, flower_box: bool) -> void:
	var frame := Rect2(center - Vector2(10.0, 10.0), Vector2(20.0, 20.0))
	draw_rect(frame.grow(3.0), palette["trim_dark"])
	draw_rect(frame, palette["glass"])
	draw_line(Vector2(center.x, frame.position.y), Vector2(center.x, frame.end.y), palette["frame"], 2.0)
	draw_line(Vector2(frame.position.x, center.y), Vector2(frame.end.x, center.y), palette["frame"], 2.0)
	draw_line(frame.position + Vector2(3.0, 2.0), frame.position + Vector2(8.0, 7.0), palette["glass_light"], 2.0)
	if flower_box:
		draw_rect(Rect2(Vector2(center.x - 13.0, frame.end.y + 2.0), Vector2(26.0, 5.0)), palette["wood"])
		for dx in [-8.0, 0.0, 8.0]:
			draw_circle(Vector2(center.x + dx, frame.end.y + 1.0), 3.0, palette["flower"])

func _draw_ground_frontage(rect: Rect2, world_local_span: Rect2, palette: Dictionary, span_index: int) -> void:
	var floor_height := projection_height / float(storeys)
	var ground_top := rect.end.y - floor_height + 3.0
	var doors_here: Array[Vector2] = []
	for door_position in entrance_positions:
		if door_position.x >= world_local_span.position.x and door_position.x <= world_local_span.end.x and absf(door_position.y + 16.0 - world_local_span.end.y) <= 1.0:
			doors_here.append(door_position)

	if facade_style == &"active_shopfront":
		var bay_count := maxi(int(floor(rect.size.x / 64.0)), 1)
		var bay_width := rect.size.x / float(bay_count)
		for bay in range(bay_count):
			var bay_rect := Rect2(
				Vector2(rect.position.x + bay_width * bay + 7.0, ground_top + 7.0),
				Vector2(bay_width - 14.0, rect.end.y - ground_top - 16.0)
			)
			var contains_door := false
			for door_position in doors_here:
				if door_position.x >= bay_rect.position.x and door_position.x <= bay_rect.end.x:
					contains_door = true
					break
			if not contains_door:
				draw_rect(bay_rect.grow(3.0), palette["trim_dark"])
				draw_rect(bay_rect, palette["glass"])
				draw_line(bay_rect.position + Vector2(5.0, 3.0), bay_rect.position + Vector2(15.0, 12.0), palette["glass_light"], 3.0)
		_draw_awning(Rect2(Vector2(rect.position.x + 6.0, ground_top - 5.0), Vector2(rect.size.x - 12.0, 14.0)), palette)
	else:
		# Ground windows follow real semantic window openings when possible.
		for window_position in window_positions:
			if window_position.x >= world_local_span.position.x and window_position.x <= world_local_span.end.x and absf(window_position.y + 16.0 - world_local_span.end.y) <= 1.0:
				_draw_window(Vector2(window_position.x, rect.end.y - floor_height * 0.48), palette, false)

	for door_position in doors_here:
		_draw_door(Vector2(door_position.x + DOOR_BAY_SHIFT, rect.end.y), palette)

	if archetype == &"workshop" and doors_here.is_empty():
		var shutter := Rect2(Vector2(rect.get_center().x - 26.0, ground_top + 5.0), Vector2(52.0, rect.end.y - ground_top - 9.0))
		draw_rect(shutter.grow(3.0), palette["trim_dark"])
		draw_rect(shutter, palette["metal"])
		for y in range(int(shutter.position.y + 5.0), int(shutter.end.y), 6):
			draw_line(Vector2(shutter.position.x, y), Vector2(shutter.end.x, y), palette["metal_dark"], 1.0)

func _draw_door(ground_center: Vector2, palette: Dictionary, width := DOOR_BAY_WIDTH) -> void:
	var height := 38.0
	var door_rect := Rect2(Vector2(ground_center.x - width * 0.5, ground_center.y - height), Vector2(width, height))
	draw_rect(door_rect.grow(4.0), palette["trim_dark"])
	draw_rect(door_rect, palette["door"])
	# One recessed panel per 32px leaf so a two-cell bay reads as a double door.
	var panels := maxi(1, roundi(width / TILE_SIZE))
	var panel_width := (width - 8.0 - float(panels - 1) * 6.0) / float(panels)
	for index in range(panels):
		var panel_x := door_rect.position.x + 4.0 + float(index) * (panel_width + 6.0)
		draw_rect(Rect2(Vector2(panel_x, door_rect.position.y + 5.0), Vector2(panel_width, 10.0)), palette["door_dark"])
	draw_circle(Vector2(door_rect.end.x - 5.0, door_rect.position.y + 23.0), 2.0, palette["metal"])
	draw_rect(Rect2(Vector2(door_rect.position.x - 5.0, door_rect.position.y - 5.0), Vector2(width + 10.0, 5.0)), palette["trim"])

func _draw_awning(rect: Rect2, palette: Dictionary) -> void:
	draw_rect(rect, palette["awning_light"])
	var stripe_width := 12.0
	var x := rect.position.x
	while x < rect.end.x:
		draw_rect(Rect2(Vector2(x, rect.position.y), Vector2(minf(stripe_width, rect.end.x - x), rect.size.y)), palette["awning_dark"])
		x += stripe_width * 2.0
	draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), palette["trim_dark"], 2.0)

func _draw_prague_details(rect: Rect2, palette: Dictionary, span_index: int) -> void:
	# Cornice, drainpipe and restrained seed-driven frontage dressing.
	draw_rect(Rect2(rect.position + Vector2(2.0, 4.0), Vector2(rect.size.x - 4.0, 5.0)), palette["trim"])
	var pipe_x := rect.end.x - 10.0 if _hash(span_index, 71, 3) % 2 == 0 else rect.position.x + 10.0
	draw_rect(Rect2(Vector2(pipe_x, rect.position.y + 8.0), Vector2(3.0, rect.size.y - 12.0)), palette["metal_dark"])
	if facade_style == &"active_shopfront" and rect.size.x >= 96.0:
		var sign_rect := Rect2(Vector2(rect.end.x - 14.0, rect.end.y - 82.0), Vector2(12.0, 46.0))
		draw_rect(sign_rect.grow(2.0), palette["trim_dark"])
		draw_rect(sign_rect, palette["sign"])
		for y in range(int(sign_rect.position.y + 6.0), int(sign_rect.end.y - 2.0), 8):
			draw_rect(Rect2(Vector2(sign_rect.position.x + 3.0, y), Vector2(6.0, 3.0)), palette["sign_text"])

func _hash(a: int, b: int, c: int) -> int:
	return abs(int((decoration_seed ^ (a + 1) * 73856093 ^ (b + 1) * 19349663 ^ (c + 1) * 83492791) & 0x7fffffff))

func _palette() -> Dictionary:
	var result := {
		"wall": Color8(199, 178, 139), "side_dark": Color8(121, 94, 75),
		"trim": Color8(224, 207, 170), "trim_dark": Color8(72, 58, 51),
		"wear": Color8(171, 145, 111), "crack": Color8(105, 86, 72),
		"mortar": Color8(111, 88, 72), "glass": Color8(63, 91, 103),
		"glass_light": Color8(141, 181, 184), "frame": Color8(42, 45, 45),
		"door": Color8(91, 56, 39), "door_dark": Color8(56, 40, 33),
		"wood": Color8(101, 67, 44), "flower": Color8(190, 57, 68),
		"metal": Color8(132, 139, 137), "metal_dark": Color8(72, 78, 78),
		"awning_light": Color8(226, 207, 163), "awning_dark": Color8(152, 60, 53),
		"sign": Color8(47, 91, 82), "sign_text": Color8(226, 214, 166),
	}
	match facade_style:
		&"active_shopfront":
			result["wall"] = Color8(178, 151, 112)
			result["trim"] = Color8(218, 196, 148)
		&"masonry_industrial":
			result["wall"] = Color8(128, 68, 55)
			result["side_dark"] = Color8(80, 43, 39)
			result["trim"] = Color8(157, 123, 93)
		&"exposed_brick_infill":
			result["wall"] = Color8(151, 78, 61)
			result["side_dark"] = Color8(91, 48, 43)
			result["trim"] = Color8(192, 164, 126)
		_:
			pass
	return result
