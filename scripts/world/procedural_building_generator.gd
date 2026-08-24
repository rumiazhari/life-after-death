class_name ProceduralBuildingGenerator
extends RefCounted
## Seeded, renderer-independent interior planner. The result contains every
## room, portal, partition, window, furniture footprint, and reserved aisle
## required to construct and validate an enterable building at runtime.

const TILE_SIZE := 32
const MODULE_SIZE := 64
const MIN_ROOM_SPAN := MODULE_SIZE * 2
const PORTAL_SIZE := Vector2(32, 32)
## A one-cell wall gap exactly matches the player diameter and can still
## collide at its edges.  The visible door remains 30px wide, while the
## semantic opening removes two wall cells across its transverse axis.
const DOOR_APERTURE_TRANSVERSE := 64.0
const DOOR_LANDING_DEPTH := 48.0
const AISLE_WIDTH := 40.0
const FURNITURE_CLEARANCE := 8.0

const ARCHETYPE_ROOMS := {
	&"apartment": [&"living_room", &"kitchen", &"bedroom", &"bathroom"],
	&"store": [&"retail_floor", &"stock_room"],
	&"restaurant": [&"dining_room", &"kitchen", &"pantry"],
	&"clinic": [&"waiting_area", &"exam_room", &"medical_storage"],
	&"workshop": [&"work_floor", &"loading_bay", &"storage", &"office"],
}

const ARCHETYPE_STYLE := {
	&"apartment": {
		"wall_texture": "res://assets/pixel/props/wall_concrete.png",
		"roof_material": "A",
	},
	&"store": {
		"wall_texture": "res://assets/pixel/props/wall_shopfront.png",
		"roof_material": "B",
	},
	&"restaurant": {
		"wall_texture": "res://assets/pixel/props/wall_brick.png",
		"roof_material": "A",
	},
	&"clinic": {
		"wall_texture": "res://assets/pixel/props/wall_plaster.png",
		"roof_material": "C",
	},
	&"workshop": {
		"wall_texture": "res://assets/pixel/props/wall_concrete.png",
		"roof_material": "D",
	},
}

const INTERIOR_WALL_TEXTURE := "res://assets/pixel/props/wall_interior.png"

var _rng := RandomNumberGenerator.new()

func generate(building_id: StringName, archetype: StringName, size: Vector2, seed_value: int, allow_annex: bool = true, apocalypse_level: int = 1) -> Dictionary:
	_rng.seed = seed_value
	_disturbance = _disturbance_level(building_id, apocalypse_level)
	var roles: Array = ARCHETYPE_ROOMS.get(archetype, [&"public_room", &"utility_room"])
	var orientation: StringName = _choose_orientation(archetype, roles.size(), size)
	var mirrored := orientation in [&"x", &"grid"] and _rng.randi_range(0, 1) == 1
	var rooms := _make_rooms(building_id, archetype, roles, size, orientation, mirrored)
	var compound: Dictionary = _make_compound_form(building_id, archetype, rooms, size, allow_annex)
	rooms = compound["rooms"]
	var doors := _make_doors(building_id, rooms, size, orientation)
	var partitions := _make_partitions(rooms, doors, size, orientation)
	var windows := _make_windows(building_id, rooms, doors, size, orientation)
	var clearance_rects := _make_clearance_rects(rooms, doors, orientation)
	var furniture := _make_furniture(building_id, rooms, doors, clearance_rects)
	_apply_apocalypse_disturbance(building_id, rooms, clearance_rects, furniture)
	var style: Dictionary = ARCHETYPE_STYLE.get(archetype, ARCHETYPE_STYLE[&"apartment"])
	return {
		"layout": &"grid_2x2" if orientation == &"grid" else StringName("strip_%s" % String(orientation)),
		"form": compound["form"],
		"mirrored": mirrored,
		"size": size,
		"half_extent": size * 0.5,
		"perimeter_rects": compound["perimeter_rects"],
		"footprint_bounds": compound["footprint_bounds"],
		"wall_texture": style["wall_texture"],
		"interior_wall_texture": INTERIOR_WALL_TEXTURE,
		"roof_material": style["roof_material"],
		"disturbance": _disturbance,
		"rooms": rooms,
		"doors": doors,
		"partitions": partitions,
		"windows": windows,
		"clearance_rects": clearance_rects,
		"furniture": furniture,
		"stairs_up": _stairs_up_position(rooms, clearance_rects, furniture),
	}

## Deterministic per-building collapse state: some interiors remain mostly
## intact while others are heavily disturbed. Derived from the stable
## building id plus the regional apocalypse level, never from wall-clock RNG.
var _disturbance := 0

func _disturbance_level(building_id: StringName, apocalypse_level: int) -> int:
	if apocalypse_level <= 0:
		return 0
	var roll := posmod(int(String(building_id).hash() ^ (apocalypse_level * 0x9E3779B9)), 100)
	if roll < 50:
		return clampi(apocalypse_level, 0, 2)
	if roll < 85:
		return clampi(apocalypse_level - 1, 0, 2)
	return clampi(apocalypse_level + 1, 0, 2)

## A building keeps its generated room graph, but may add one fully-enterable
## service wing onto the graph's terminal room.  The wing is deliberately
## never attached on the street-facing south edge: its door and approach stay
## readable, while the roof silhouette becomes L-shaped or rear-extended.
func _make_compound_form(building_id: StringName, archetype: StringName, base_rooms: Array[Dictionary], size: Vector2, allow_annex: bool) -> Dictionary:
	var base_rect := Rect2(-size * 0.5, size)
	var perimeter_rects: Array[Rect2] = []
	perimeter_rects.append(base_rect)
	var rooms: Array[Dictionary] = base_rooms.duplicate(true)
	var form: StringName = &"rectangle"
	if not allow_annex or rooms.is_empty() or not _should_add_annex(archetype):
		return {
			"form": form,
			"rooms": rooms,
			"perimeter_rects": perimeter_rects,
			"footprint_bounds": base_rect,
		}
	var terminal: Dictionary = rooms.back()
	var terminal_rect: Rect2 = terminal["rect"]
	var wing_rect := _annex_rect_for_terminal(terminal_rect, size)
	if wing_rect.size == Vector2.ZERO:
		return {
			"form": form,
			"rooms": rooms,
			"perimeter_rects": perimeter_rects,
			"footprint_bounds": base_rect,
		}
	var wing_id: StringName = &"service_annex"
	rooms.append({
		"id": wing_id,
		"stable_id": StringName("%s/room/%s" % [String(building_id), String(wing_id)]),
		"role": wing_id,
		"rect": wing_rect,
		"floor_tile": _floor_for(archetype, wing_id),
		"required": true,
	})
	perimeter_rects.append(wing_rect)
	form = &"rear_wing" if wing_rect.position.y < base_rect.position.y else &"side_wing"
	return {
		"form": form,
		"rooms": rooms,
		"perimeter_rects": perimeter_rects,
		"footprint_bounds": base_rect.merge(wing_rect),
	}

func _should_add_annex(archetype: StringName) -> bool:
	var chance := 0.0
	match archetype:
		&"workshop": chance = 0.85
		&"restaurant": chance = 0.72
		&"clinic": chance = 0.64
		&"store": chance = 0.58
		&"apartment": chance = 0.46
		_: chance = 0.5
	return _rng.randf() < chance

func _annex_rect_for_terminal(terminal_rect: Rect2, size: Vector2) -> Rect2:
	var half := size * 0.5
	var directions: Array[StringName] = []
	if is_equal_approx(terminal_rect.position.y, -half.y):
		directions.append(&"north")
	if is_equal_approx(terminal_rect.end.x, half.x):
		directions.append(&"east")
	if is_equal_approx(terminal_rect.position.x, -half.x):
		directions.append(&"west")
	if directions.is_empty():
		return Rect2()
	var direction: StringName = directions[_rng.randi_range(0, directions.size() - 1)]
	var wing_size := Vector2(MIN_ROOM_SPAN, MIN_ROOM_SPAN)
	match direction:
		&"north":
			var wing_x := clampf(terminal_rect.get_center().x - wing_size.x * 0.5, terminal_rect.position.x, terminal_rect.end.x - wing_size.x)
			return Rect2(wing_x, -half.y - wing_size.y, wing_size.x, wing_size.y)
		&"east":
			var wing_y := clampf(terminal_rect.get_center().y - wing_size.y * 0.5, terminal_rect.position.y, terminal_rect.end.y - wing_size.y)
			return Rect2(half.x, wing_y, wing_size.x, wing_size.y)
		_:
			var west_y := clampf(terminal_rect.get_center().y - wing_size.y * 0.5, terminal_rect.position.y, terminal_rect.end.y - wing_size.y)
			return Rect2(-half.x - wing_size.x, west_y, wing_size.x, wing_size.y)

func _choose_orientation(_archetype: StringName, room_count: int, size: Vector2) -> StringName:
	# A room needs two 64 px modules across every partitioned axis: the two
	# wall cells otherwise consume the only navigation samples. Three- and
	# four-room archetypes therefore use a compact 2x2 plan, while a strip is
	# only selected on an axis that can give every room the full 128 px span.
	if room_count >= 3 and size.x >= MIN_ROOM_SPAN * 2 and size.y >= MIN_ROOM_SPAN * 2:
		return &"grid"
	var required_strip_span := float(room_count * MIN_ROOM_SPAN)
	var can_x := size.x >= required_strip_span
	var can_y := size.y >= required_strip_span
	if can_x and can_y:
		return &"x" if _rng.randi_range(0, 1) == 0 else &"y"
	if can_y:
		return &"y"
	return &"x"

func _make_rooms(building_id: StringName, archetype: StringName, roles: Array, size: Vector2, orientation: StringName, mirrored: bool) -> Array[Dictionary]:
	var rect_by_graph_index: Array[Rect2] = []
	for _i in range(roles.size()):
		rect_by_graph_index.append(Rect2())
	if orientation == &"grid":
		var half := size * 0.5
		var top_left := Rect2(-half, Vector2(half.x, half.y))
		var top_right := Rect2(Vector2(0.0, -half.y), Vector2(half.x, half.y))
		if roles.size() == 3:
			# The entrance room spans the south half; the two rear rooms complete
			# an L-shaped graph. Mirroring changes which rear room the graph enters
			# first without changing the public frontage.
			rect_by_graph_index[0] = Rect2(Vector2(-half.x, 0.0), Vector2(size.x, half.y))
			if mirrored:
				rect_by_graph_index[1] = top_left
				rect_by_graph_index[2] = top_right
			else:
				rect_by_graph_index[1] = top_right
				rect_by_graph_index[2] = top_left
		else:
			var bottom_left := Rect2(Vector2(-half.x, 0.0), Vector2(half.x, half.y))
			var bottom_right := Rect2(Vector2.ZERO, Vector2(half.x, half.y))
			# Four-room graph order remains entrance -> room 1 -> room 2 ->
			# service room. The U-shaped placement makes every consecutive pair
			# share one wall and keeps the terminal room on the rear wall.
			if mirrored:
				rect_by_graph_index[0] = bottom_right
				rect_by_graph_index[1] = bottom_left
				rect_by_graph_index[2] = top_left
				rect_by_graph_index[3] = top_right
			else:
				rect_by_graph_index[0] = bottom_left
				rect_by_graph_index[1] = bottom_right
				rect_by_graph_index[2] = top_right
				rect_by_graph_index[3] = top_left
	else:
		var along_size: float = size.x if orientation == &"x" else size.y
		var module_count := maxi(int(round(along_size / MODULE_SIZE)), roles.size())
		var allocations := _allocate_modules(module_count, roles.size())
		if orientation == &"x":
			var order: Array[int] = []
			for i in range(roles.size()):
				order.append(i)
			if mirrored:
				order.reverse()
			var cursor := -size.x * 0.5
			for graph_index in order:
				var width := float(allocations[graph_index] * MODULE_SIZE)
				rect_by_graph_index[graph_index] = Rect2(cursor, -size.y * 0.5, width, size.y)
				cursor += width
		else:
			# Graph room zero must touch the south frontage. Build northward so the
			# entrance always opens into the public/primary room.
			var cursor := size.y * 0.5
			for graph_index in range(roles.size()):
				var height := float(allocations[graph_index] * MODULE_SIZE)
				rect_by_graph_index[graph_index] = Rect2(-size.x * 0.5, cursor - height, size.x, height)
				cursor -= height
	var output: Array[Dictionary] = []
	for i in range(roles.size()):
		var role: StringName = roles[i]
		var room_id := StringName("%s_%02d" % [String(role), i])
		output.append({
			"id": room_id,
			"stable_id": StringName("%s/room/%s" % [String(building_id), String(room_id)]),
			"role": role,
			"rect": rect_by_graph_index[i],
			"floor_tile": _floor_for(archetype, role),
			"required": true,
		})
	return output

func _allocate_modules(total: int, count: int) -> Array[int]:
	var result: Array[int] = []
	var base_modules := 2 if total >= count * 2 else 1
	for _i in range(count):
		result.append(base_modules)
	var remaining := total - count * base_modules
	# Give the public/entrance room the first spare module; it contains the
	# most furniture and the exterior-to-interior circulation path.
	if remaining > 0:
		result[0] += 1
		remaining -= 1
	while remaining > 0:
		result[_rng.randi_range(0, count - 1)] += 1
		remaining -= 1
	return result

func _make_doors(building_id: StringName, rooms: Array[Dictionary], size: Vector2, _orientation: StringName) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var entrance_room: Dictionary = rooms[0]
	var entrance_rect: Rect2 = entrance_room["rect"]
	var entrance_x := _nearest_wall_slot(entrance_rect.get_center().x, -size.x * 0.5, size.x * 0.5)
	var entrance_position := Vector2(entrance_x, size.y * 0.5 - TILE_SIZE * 0.5)
	output.append({
		"id": StringName("%s/door/entrance" % String(building_id)),
		"position": entrance_position,
		"rotation": 0.0,
		"aperture_size": _aperture_size(0.0),
		"landing_depth": DOOR_LANDING_DEPTH,
		"room_a": entrance_room["id"],
		"room_b": &"",
		"exterior": true,
		"service": false,
	})
	for i in range(rooms.size() - 1):
		var room_a: Dictionary = rooms[i]
		var room_b: Dictionary = rooms[i + 1]
		var rect_a: Rect2 = room_a["rect"]
		var rect_b: Rect2 = room_b["rect"]
		var portal := _shared_portal(rect_a, rect_b, size)
		var position: Vector2 = portal["position"]
		var rotation: float = portal["rotation"]
		output.append({
			"id": StringName("%s/door/%s_to_%s" % [String(building_id), String(room_a["id"]), String(room_b["id"])]),
			"position": position,
			"rotation": rotation,
			"aperture_size": _aperture_size(rotation),
			"landing_depth": DOOR_LANDING_DEPTH,
			"room_a": room_a["id"],
			"room_b": room_b["id"],
			"exterior": false,
			"service": false,
		})
	# Restaurants and workshops also expose their terminal service room to
	# the rear alley. This remains a second exterior graph root, never a
	# disconnected decorative door.
	var terminal_role: StringName = rooms.back()["role"]
	if terminal_role in [&"pantry", &"office"]:
		var terminal_rect: Rect2 = rooms.back()["rect"]
		var service_x := _nearest_wall_slot(terminal_rect.get_center().x, -size.x * 0.5, size.x * 0.5)
		output.append({
			"id": StringName("%s/door/service" % String(building_id)),
			"position": Vector2(service_x, -size.y * 0.5 + TILE_SIZE * 0.5),
			"rotation": 0.0,
			"aperture_size": _aperture_size(0.0),
			"landing_depth": DOOR_LANDING_DEPTH,
			"room_a": rooms.back()["id"],
			"room_b": &"",
			"exterior": true,
			"service": true,
		})
	return output

func _aperture_size(rotation: float) -> Vector2:
	if is_equal_approx(rotation, PI * 0.5):
		return Vector2(PORTAL_SIZE.y, DOOR_APERTURE_TRANSVERSE)
	return Vector2(DOOR_APERTURE_TRANSVERSE, PORTAL_SIZE.y)

## The wall-cell bay a door occupies. Wall cells are removed when their
## CENTER falls inside this rect, and Rect2.has_point() includes the left
## edge but excludes the right edge, so a naive centered rect carves an
## asymmetric hole (own cell plus the WEST/NORTH neighbor). Offsetting by
## half a cell along the transverse axis selects the own cell plus the
## EAST/SOUTH neighbor instead, producing the deterministic bay
## [center-16, center+48] whose center is exactly where Door and the
## painted facade place their leaf. Must stay in sync with
## ProceduralBuilding._build_shell and Door._setup_aperture.
static func door_bay_rect(position: Vector2, aperture: Vector2) -> Rect2:
	var shift := (aperture - Vector2(TILE_SIZE, TILE_SIZE)) * 0.5
	return Rect2(position - aperture * 0.5 + shift, aperture)

func _bay_center(position: Vector2, aperture: Vector2) -> Vector2:
	return position + (aperture - Vector2(TILE_SIZE, TILE_SIZE)) * 0.5

func _shared_portal(rect_a: Rect2, rect_b: Rect2, size: Vector2) -> Dictionary:
	var boundary_x := 0.0
	var shares_vertical := false
	if is_equal_approx(rect_a.end.x, rect_b.position.x):
		boundary_x = rect_a.end.x
		shares_vertical = true
	elif is_equal_approx(rect_b.end.x, rect_a.position.x):
		boundary_x = rect_b.end.x
		shares_vertical = true
	if shares_vertical:
		var overlap_top := maxf(rect_a.position.y, rect_b.position.y)
		var overlap_bottom := minf(rect_a.end.y, rect_b.end.y)
		var door_y := _nearest_wall_slot((overlap_top + overlap_bottom) * 0.5, -size.y * 0.5, size.y * 0.5)
		return {"position": Vector2(boundary_x, door_y), "rotation": PI * 0.5}
	var boundary_y := rect_a.end.y if is_equal_approx(rect_a.end.y, rect_b.position.y) else rect_b.end.y
	var overlap_left := maxf(rect_a.position.x, rect_b.position.x)
	var overlap_right := minf(rect_a.end.x, rect_b.end.x)
	var door_x := _nearest_wall_slot((overlap_left + overlap_right) * 0.5, -size.x * 0.5, size.x * 0.5)
	return {"position": Vector2(door_x, boundary_y), "rotation": 0.0}

func _make_partitions(rooms: Array[Dictionary], doors: Array[Dictionary], size: Vector2, orientation: StringName) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if orientation == &"grid":
		var vertical_gaps: Array[Rect2] = []
		var horizontal_gaps: Array[Rect2] = []
		for door in doors:
			if bool(door["exterior"]):
				continue
			var aperture: Vector2 = door.get("aperture_size", PORTAL_SIZE)
			var gap := door_bay_rect(door["position"], aperture)
			if is_equal_approx(float(door["rotation"]), PI * 0.5):
				vertical_gaps.append(gap)
			else:
				horizontal_gaps.append(gap)
		output.append({
			"from": Vector2(0.0, -size.y * 0.5 + TILE_SIZE),
			"to": Vector2(0.0, 0.0 if _core_room_count(rooms) == 3 else size.y * 0.5 - TILE_SIZE),
			"gaps": vertical_gaps,
		})
		output.append({
			"from": Vector2(-size.x * 0.5 + TILE_SIZE, 0.0),
			"to": Vector2(size.x * 0.5 - TILE_SIZE, 0.0),
			"gaps": horizontal_gaps,
		})
		_append_annex_partition(output, rooms, doors)
		return output
	for i in range(rooms.size() - 1):
		var room_a: Dictionary = rooms[i]
		var room_b: Dictionary = rooms[i + 1]
		var connecting_door: Dictionary = {}
		for door in doors:
			if not bool(door["exterior"]) and door["room_a"] == room_a["id"] and door["room_b"] == room_b["id"]:
				connecting_door = door
				break
		if connecting_door.is_empty():
			continue
		if room_b["role"] == &"service_annex":
			_append_partition_between(output, room_a, room_b, connecting_door)
			continue
		var position: Vector2 = connecting_door["position"]
		if orientation == &"x":
			var aperture: Vector2 = connecting_door.get("aperture_size", PORTAL_SIZE)
			output.append({
				"from": Vector2(position.x, -size.y * 0.5 + TILE_SIZE),
				"to": Vector2(position.x, size.y * 0.5 - TILE_SIZE),
				# Anchor at (-16,-16) like door_bay_rect: has_point includes
				# the left/top edge, so this carves exactly the own cell plus
				# the SOUTH neighbor -- the same pair Door's slab seals.
				"gaps": [Rect2(position - Vector2(TILE_SIZE, TILE_SIZE) * 0.5, aperture)],
			})
		else:
			var aperture: Vector2 = connecting_door.get("aperture_size", PORTAL_SIZE)
			output.append({
				"from": Vector2(-size.x * 0.5 + TILE_SIZE, position.y),
				"to": Vector2(size.x * 0.5 - TILE_SIZE, position.y),
				"gaps": [Rect2(position - Vector2(TILE_SIZE, TILE_SIZE) * 0.5, aperture)],
			})
	return output

func _core_room_count(rooms: Array[Dictionary]) -> int:
	if not rooms.is_empty() and rooms.back()["role"] == &"service_annex":
		return rooms.size() - 1
	return rooms.size()

func _append_annex_partition(output: Array[Dictionary], rooms: Array[Dictionary], doors: Array[Dictionary]) -> void:
	if rooms.size() < 2 or rooms.back()["role"] != &"service_annex":
		return
	var room_a: Dictionary = rooms[rooms.size() - 2]
	var room_b: Dictionary = rooms.back()
	for door in doors:
		if not bool(door["exterior"]) and door["room_a"] == room_a["id"] and door["room_b"] == room_b["id"]:
			_append_partition_between(output, room_a, room_b, door)
			return

func _append_partition_between(output: Array[Dictionary], room_a: Dictionary, room_b: Dictionary, door: Dictionary) -> void:
	var rect_a: Rect2 = room_a["rect"]
	var rect_b: Rect2 = room_b["rect"]
	var aperture: Vector2 = door.get("aperture_size", PORTAL_SIZE)
	var position: Vector2 = door["position"]
	if is_equal_approx(float(door["rotation"]), PI * 0.5):
		var top := maxf(rect_a.position.y, rect_b.position.y)
		var bottom := minf(rect_a.end.y, rect_b.end.y)
		output.append({
			"from": Vector2(position.x, top),
			"to": Vector2(position.x, bottom),
			"gaps": [Rect2(position - Vector2(TILE_SIZE, TILE_SIZE) * 0.5, aperture)],
		})
		return
	var left := maxf(rect_a.position.x, rect_b.position.x)
	var right := minf(rect_a.end.x, rect_b.end.x)
	output.append({
		"from": Vector2(left, position.y),
		"to": Vector2(right, position.y),
		"gaps": [Rect2(position - Vector2(TILE_SIZE, TILE_SIZE) * 0.5, aperture)],
	})

func _make_windows(building_id: StringName, rooms: Array[Dictionary], doors: Array[Dictionary], size: Vector2, _orientation: StringName) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for i in range(rooms.size()):
		# Keep the public room's entrance frontage visually legible. Every other
		# required room gets a real exterior window on a wall it borders.
		if i == 0 and rooms.size() > 1:
			continue
		var room: Dictionary = rooms[i]
		var rect: Rect2 = room["rect"]
		var candidate := _window_candidate(rect, size, doors)
		if candidate.is_empty():
			continue
		var position: Vector2 = candidate["position"]
		var rotation: float = candidate["rotation"]
		output.append({
			"id": StringName("%s/window/%s" % [String(building_id), String(room["id"])]),
			"position": position,
			"rotation": rotation,
			"room_id": room["id"],
			"boarded": room["role"] in [&"storage", &"medical_storage"] and _rng.randf() < 0.35,
		})
	return output

func _window_candidate(rect: Rect2, size: Vector2, doors: Array[Dictionary]) -> Dictionary:
	var half := size * 0.5
	var candidates: Array[Dictionary] = []
	var center := rect.get_center()
	# Rear wall first, then side walls, then frontage. This keeps storefront
	# entrances legible and gives a service door on the rear wall priority.
	if is_equal_approx(rect.position.y, -half.y):
		candidates.append({"position": Vector2(_nearest_wall_slot(center.x, -half.x, half.x), -half.y + TILE_SIZE * 0.5), "rotation": 0.0})
	if is_equal_approx(rect.position.x, -half.x):
		candidates.append({"position": Vector2(-half.x + TILE_SIZE * 0.5, _nearest_wall_slot(center.y, -half.y, half.y)), "rotation": PI * 0.5})
	if is_equal_approx(rect.end.x, half.x):
		candidates.append({"position": Vector2(half.x - TILE_SIZE * 0.5, _nearest_wall_slot(center.y, -half.y, half.y)), "rotation": PI * 0.5})
	if is_equal_approx(rect.end.y, half.y):
		candidates.append({"position": Vector2(_nearest_wall_slot(center.x, -half.x, half.x), half.y - TILE_SIZE * 0.5), "rotation": 0.0})
	for candidate in candidates:
		var blocked := false
		for door in doors:
			if (candidate["position"] as Vector2).distance_squared_to(door["position"]) < TILE_SIZE * TILE_SIZE:
				blocked = true
				break
		if not blocked:
			return candidate
	return {}

func _make_clearance_rects(rooms: Array[Dictionary], doors: Array[Dictionary], orientation: StringName) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var room_by_id: Dictionary = {}
	for room in rooms:
		room_by_id[room["id"]] = room
	for room in rooms:
		var room_rect: Rect2 = room["rect"]
		var center := room_rect.get_center()
		for door in doors:
			if door["room_a"] != room["id"] and door["room_b"] != room["id"]:
				continue
			var portal: Vector2 = door["position"]
			var horizontal := Rect2(
				Vector2(minf(center.x, portal.x), center.y - AISLE_WIDTH * 0.5),
				Vector2(maxf(absf(center.x - portal.x), AISLE_WIDTH), AISLE_WIDTH)
			)
			var vertical := Rect2(
				Vector2(portal.x - AISLE_WIDTH * 0.5, minf(center.y, portal.y)),
				Vector2(AISLE_WIDTH, maxf(absf(center.y - portal.y), AISLE_WIDTH))
			)
			output.append({"room_id": room["id"], "rect": horizontal.intersection(room_rect)})
			output.append({"room_id": room["id"], "rect": vertical.intersection(room_rect)})
			# The carved doorway itself is sacred ground on BOTH sides: no
			# furniture may ever overlap the wall bay or its immediate
			# landing, whatever else the aisle geometry allows.
			var bay := door_bay_rect(door["position"], door.get("aperture_size", PORTAL_SIZE)).grow(6.0)
			output.append({"room_id": room["id"], "rect": bay.intersection(room_rect)})
		# A continuous strip through the graph makes door-to-door passage
		# explicit even when two randomized portal slots do not share a line.
		if orientation != &"grid":
			var aisle: Rect2
			if orientation == &"x":
				aisle = Rect2(room_rect.position.x, center.y - AISLE_WIDTH * 0.5, room_rect.size.x, AISLE_WIDTH)
			else:
				aisle = Rect2(center.x - AISLE_WIDTH * 0.5, room_rect.position.y, AISLE_WIDTH, room_rect.size.y)
			output.append({"room_id": room["id"], "rect": aisle})
		# Room centers host semantic anchors (spawn sampling, AI goals); keep
		# a small standing square clear of furniture at every room's heart.
		output.append({"room_id": room["id"], "rect": Rect2(center - Vector2(16, 16), Vector2(32, 32))})
	return output

func _make_furniture(building_id: StringName, rooms: Array[Dictionary], _doors: Array[Dictionary], clearance_rects: Array[Dictionary]) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for room in rooms:
		var accepted: Array[Rect2] = []
		var accepted_by_kind: Dictionary = {}
		var room_reserves: Array[Rect2] = []
		for reserve in clearance_rects:
			if reserve["room_id"] == room["id"]:
				room_reserves.append(reserve["rect"])
		for rule in _rules_for_role(room["role"]):
			var placed := _place_furniture_rule(building_id, room, rule, room_reserves, accepted, accepted_by_kind, output.size())
			if not placed.is_empty():
				accepted.append(placed["clearance_rect"])
				if not accepted_by_kind.has(rule["kind"]):
					accepted_by_kind[rule["kind"]] = []
				(accepted_by_kind[rule["kind"]] as Array).append(placed["collision_rect"])
				output.append(placed)
		if accepted.is_empty():
			var fallback := _furniture_rule(&"crate", &"salvage", {}, 2)
			var placed := _place_furniture_rule(building_id, room, fallback, room_reserves, accepted, {}, output.size())
			if not placed.is_empty():
				accepted.append(placed["clearance_rect"])
				output.append(placed)
	return output

func _place_furniture_rule(building_id: StringName, room: Dictionary, rule: Dictionary, reserves: Array[Rect2], accepted: Array[Rect2], accepted_by_kind: Dictionary, serial: int) -> Dictionary:
	var room_rect: Rect2 = room["rect"]
	var size: Vector2 = rule["size"]
	var candidates := _candidate_positions(room_rect, size)
	# Multi-segment runs (kitchen counters, shelf rows) first try to continue
	# directly adjacent to an already-accepted piece of the same kind so
	# composed rooms read as continuous furniture runs rather than scattered
	# single items.
	for run_anchor_variant in accepted_by_kind.get(rule["kind"], []):
		var anchor: Rect2 = run_anchor_variant
		candidates.push_front(anchor.get_center() + Vector2(anchor.size.x * 0.5 + size.x * 0.5 + FURNITURE_CLEARANCE * 2.0, 0.0))
		candidates.push_front(anchor.get_center() - Vector2(anchor.size.x * 0.5 + size.x * 0.5 + FURNITURE_CLEARANCE * 2.0, 0.0))
	for position in candidates:
		var collision_rect := Rect2(position - size * 0.5, size)
		var clearance := collision_rect.grow(FURNITURE_CLEARANCE)
		if not room_rect.encloses(clearance):
			continue
		var blocked := false
		for reserve in reserves:
			if clearance.intersects(reserve):
				blocked = true
				break
		if blocked:
			continue
		for other in accepted:
			if clearance.intersects(other):
				blocked = true
				break
		if blocked:
			continue
		var role_text := String(room["role"])
		var kind_text := String(rule["kind"])
		return {
			"id": StringName("%s/prop/%s_%s_%02d" % [String(building_id), role_text, kind_text, serial]),
			"room_id": room["id"],
			"role": room["role"],
			"kind": rule["kind"],
			"mode": rule["mode"],
			"position": position,
			"size": size,
			"visual_size": rule.get("visual_size", size),
			"collision_rect": collision_rect,
			"clearance_rect": clearance,
			"texture": rule["texture"],
			"capacity": rule.get("capacity", 60.0),
			"items": (rule.get("items", {}) as Dictionary).duplicate(),
			"yield": int(rule.get("yield", 1)),
			"minimum_damage_class": int(rule.get("minimum_damage_class", EnvironmentDamage.DamageClass.SMALL_ARMS)),
		}
	return {}

func _candidate_positions(rect: Rect2, size: Vector2) -> Array[Vector2]:
	var pad := FURNITURE_CLEARANCE
	var left := rect.position.x + pad + size.x * 0.5
	var right := rect.end.x - pad - size.x * 0.5
	var top := rect.position.y + pad + size.y * 0.5
	var bottom := rect.end.y - pad - size.y * 0.5
	var cx := rect.get_center().x
	var cy := rect.get_center().y
	var qx_left := rect.position.x + pad + (rect.size.x - pad * 2.0) * 0.25
	var qx_right := rect.position.x + pad + (rect.size.x - pad * 2.0) * 0.75
	var qy_top := rect.position.y + pad + (rect.size.y - pad * 2.0) * 0.25
	var qy_bottom := rect.position.y + pad + (rect.size.y - pad * 2.0) * 0.75
	var candidates: Array[Vector2] = [
		Vector2(left, top), Vector2(right, top), Vector2(cx, top),
		Vector2(left, bottom), Vector2(right, bottom), Vector2(cx, bottom),
		Vector2(left, cy), Vector2(right, cy),
		Vector2(qx_left, top), Vector2(qx_right, top),
		Vector2(qx_left, bottom), Vector2(qx_right, bottom),
		Vector2(left, qy_top), Vector2(left, qy_bottom),
		Vector2(right, qy_top), Vector2(right, qy_bottom),
	]
	if _rng.randi_range(0, 1) == 1:
		candidates.reverse()
	return candidates

## Role-driven furniture compositions. Rules are tried in order; each piece
## is placed only where it keeps door aisles and earlier pieces clear, so a
## composition degrades gracefully in small rooms instead of blocking paths.
## Variant picks are deterministic per building seed so identical archetypes
## still furnish differently across a street.
func _rules_for_role(role: StringName) -> Array[Dictionary]:
	match role:
		&"living_room":
			return [
				_furniture_rule(_pick([&"sofa", &"sofa_b", &"armchair"]), &"physical"),
				_furniture_rule(_pick([&"coffee_table", &"dining_table"]), &"physical"),
				_furniture_rule(&"chair", &"physical"),
				_furniture_rule(&"armchair", &"physical"),
				_furniture_rule(_pick([&"bookshelf", &"tv_stand"]), &"loot", {"materials": 2, "water_bottle": 1}),
				_furniture_rule(&"cabinet", &"loot", {"materials": 1}),
			]
		&"kitchen":
			return [
				_furniture_rule(&"counter", &"physical"),
				_furniture_rule(&"counter_corner", &"physical"),
				_furniture_rule(&"sink_counter", &"physical"),
				_furniture_rule(&"stove", &"physical"),
				_furniture_rule(&"fridge", &"loot", {"food_ration": 3, "water_bottle": 2}),
				_furniture_rule(_pick([&"pantry_shelf", &"shelf_row"]), &"loot", {"materials": 2, "food_ration": 2}),
				_furniture_rule(&"dining_table", &"physical"),
				_furniture_rule(&"chair", &"physical"),
			]
		&"bedroom":
			var bedroom: Array[Dictionary] = [_furniture_rule(_pick([&"bed_single", &"bed_double"]), &"physical")]
			bedroom.append_array([
				_furniture_rule(_pick([&"wardrobe", &"dresser"]), &"loot", {"materials": 2, "medical_supplies": 1}),
				_furniture_rule(&"nightstand", &"loot", {"food_ration": 1}),
				_furniture_rule(&"desk", &"physical"),
				_furniture_rule(_pick([&"office_chair", &"chair"]), &"physical"),
				_furniture_rule(_pick([&"bookshelf", &"mattress"]), &"physical"),
			])
			return bedroom
		&"bathroom":
			return [
				_furniture_rule(&"cabinet", &"loot", {"medical_supplies": 1, "water_bottle": 1}),
				_furniture_rule(&"sink_counter", &"physical"),
			]
		&"retail_floor":
			return [
				_furniture_rule(_pick([&"grocery_shelf_short", &"grocery_shelf_long"]), &"loot", {"food_ration": 3, "materials": 2}),
				_furniture_rule(_pick([&"grocery_shelf_long", &"aisle_shelf"]), &"loot", {"water_bottle": 3}),
				_furniture_rule(_pick([&"aisle_shelf", &"wall_shelving"]), &"loot", {}),
				_furniture_rule(&"grocery_shelf_short", &"loot", {"materials": 4}),
				_furniture_rule(&"checkout_counter", &"physical"),
				_furniture_rule(&"display_rack", &"loot", {"medical_supplies": 1, "materials": 1}),
				_furniture_rule(&"fridge_display", &"loot", {"water_bottle": 4, "food_ration": 2}),
				_furniture_rule(&"freezer_chest", &"loot", {"food_ration": 4}),
				_furniture_rule(&"crate", &"salvage", {}, 2),
			]
		&"stock_room":
			return [
				_furniture_rule(_pick([&"pallet_rack", &"industrial_shelf"]), &"loot", {"food_ration": 2, "water_bottle": 3, "materials": 2}),
				_furniture_rule(_pick([&"wall_shelving", &"industrial_shelf"]), &"loot", {"materials": 5}),
				_furniture_rule(&"freezer_chest", &"loot", {"food_ration": 3}),
				_furniture_rule(&"barrel", &"salvage", {}, 2),
				_furniture_rule(&"crate", &"salvage", {}, 3),
				_furniture_rule(&"pallet", &"physical"),
			]
		&"dining_room":
			return [
				_furniture_rule(_pick([&"dining_table", &"round_table"]), &"physical"),
				_furniture_rule(&"chair", &"physical"),
				_furniture_rule(&"chair", &"physical"),
				_furniture_rule(_pick([&"round_table", &"dining_table"]), &"physical"),
				_furniture_rule(&"booth", &"physical"),
				_furniture_rule(&"chair", &"physical"),
				_furniture_rule(&"dining_table", &"physical"),
				_furniture_rule(&"chair", &"physical"),
				_furniture_rule(&"cabinet", &"loot", {"food_ration": 2, "water_bottle": 2}),
			]
		&"pantry":
			return [
				_furniture_rule(&"pantry_shelf", &"loot", {"food_ration": 4, "water_bottle": 2}),
				_furniture_rule(&"pantry_shelf", &"loot", {"food_ration": 3}),
				_furniture_rule(&"wall_shelving", &"loot", {"materials": 2}),
				_furniture_rule(&"barrel", &"salvage", {}, 2),
				_furniture_rule(&"counter", &"physical"),
			]
		&"waiting_area":
			return [
				_furniture_rule(&"waiting_bench", &"physical"),
				_furniture_rule(&"chair", &"physical"),
				_furniture_rule(&"chair", &"physical"),
				_furniture_rule(&"reception_desk", &"physical"),
				_furniture_rule(&"medicine_shelf", &"loot", {"medical_supplies": 2}),
			]
		&"exam_room":
			return [
				_furniture_rule(&"exam_bed", &"physical"),
				_furniture_rule(&"bedside_trolley", &"physical"),
				_furniture_rule(&"equipment_trolley", &"loot", {"medical_supplies": 2}),
				_furniture_rule(&"cabinet", &"loot", {"medical_supplies": 2}),
				_furniture_rule(&"medicine_shelf", &"loot", {"medical_supplies": 3}),
			]
		&"medical_storage":
			return [
				_furniture_rule(&"medicine_shelf", &"loot", {"medical_supplies": 5}),
				_furniture_rule(&"locker", &"loot", {"medical_supplies": 3, "materials": 2}),
				_furniture_rule(&"shelf_row", &"loot", {"medical_supplies": 2, "materials": 2}),
				_furniture_rule(&"crate", &"salvage", {}, 2),
			]
		&"work_floor":
			return [
				_furniture_rule(&"workbench", &"physical"),
				_furniture_rule(&"machinery", &"physical"),
				_furniture_rule(&"tool_cabinet", &"loot", {"materials": 4, "ammunition": 2}),
				_furniture_rule(&"industrial_shelf", &"loot", {"materials": 3}),
				_furniture_rule(&"desk", &"physical"),
				_furniture_rule(&"office_chair", &"physical"),
			]
		&"loading_bay":
			return [
				_furniture_rule(&"pallet_rack", &"physical"),
				_furniture_rule(&"pallet", &"physical"),
				_furniture_rule(&"pallet", &"physical"),
				_furniture_rule(&"barrel", &"salvage", {}, 3),
				_furniture_rule(&"crate", &"salvage", {}, 3),
			]
		&"storage":
			return [
				_furniture_rule(_pick([&"industrial_shelf", &"pallet_rack"]), &"loot", {"materials": 5, "ammunition": 3}),
				_furniture_rule(_pick([&"locker", &"tool_cabinet"]), &"loot", {"materials": 4}),
				_furniture_rule(&"crate", &"salvage", {}, 4),
				_furniture_rule(&"pallet", &"physical"),
			]
		&"office":
			return [
				_furniture_rule(&"desk", &"physical"),
				_furniture_rule(&"office_chair", &"physical"),
				_furniture_rule(&"bookshelf", &"loot", {"materials": 2, "ammunition": 2}),
				_furniture_rule(_pick([&"dresser", &"nightstand"]), &"loot", {"food_ration": 1}),
				_furniture_rule(&"cabinet", &"loot", {"materials": 1}),
			]
		&"service_annex":
			return [
				_furniture_rule(&"workbench", &"physical"),
				_furniture_rule(&"crate", &"salvage", {}, 2),
				_furniture_rule(_pick([&"pantry_shelf", &"wall_shelving"]), &"loot", {"materials": 2}),
			]
	return [_furniture_rule(&"crate", &"salvage", {}, 2)]

## Deterministic variant pick consumed from the seeded stream in rule order.
func _pick(options: Array) -> StringName:
	return options[_rng.randi_range(0, options.size() - 1)]

func _furniture_rule(kind: StringName, mode: StringName, items: Dictionary = {}, material_yield: int = 1) -> Dictionary:
	var data := _furniture_data(kind)
	return {
		"kind": kind,
		"mode": mode,
		"texture": data["texture"],
		"size": data["size"],
		"visual_size": data["visual_size"],
		"items": items,
		"yield": material_yield,
		"capacity": 80.0 if kind in [&"shelf_row", &"industrial_shelf", &"cabinet", &"wardrobe"] else 60.0,
		"minimum_damage_class": EnvironmentDamage.DamageClass.SMALL_ARMS,
	}

func _furniture_data(kind: StringName) -> Dictionary:
	const FURNITURE := {
		&"bed_single": {"texture": "res://assets/pixel/props/furniture_bed_single.png", "size": Vector2(32, 64), "visual_size": Vector2(34, 64)},
		&"bed_double": {"texture": "res://assets/pixel/props/furniture_bed_double.png", "size": Vector2(44, 64), "visual_size": Vector2(46, 64)},
		&"mattress": {"texture": "res://assets/pixel/props/furniture_mattress.png", "size": Vector2(30, 62), "visual_size": Vector2(32, 64)},
		&"exam_bed": {"texture": "res://assets/pixel/props/furniture_bed_single.png", "size": Vector2(32, 64), "visual_size": Vector2(34, 64)},
		&"sofa": {"texture": "res://assets/pixel/props/furniture_sofa_a.png", "size": Vector2(64, 28), "visual_size": Vector2(66, 30)},
		&"sofa_b": {"texture": "res://assets/pixel/props/furniture_sofa_b.png", "size": Vector2(64, 28), "visual_size": Vector2(66, 30)},
		&"armchair": {"texture": "res://assets/pixel/props/furniture_armchair.png", "size": Vector2(26, 26), "visual_size": Vector2(28, 28)},
		&"dining_table": {"texture": "res://assets/pixel/props/table.png", "size": Vector2(64, 40), "visual_size": Vector2(68, 44)},
		&"round_table": {"texture": "res://assets/pixel/props/furniture_table_round.png", "size": Vector2(40, 40), "visual_size": Vector2(42, 42)},
		&"coffee_table": {"texture": "res://assets/pixel/props/furniture_coffee_table.png", "size": Vector2(44, 22), "visual_size": Vector2(46, 24)},
		&"desk": {"texture": "res://assets/pixel/props/table.png", "size": Vector2(48, 24), "visual_size": Vector2(52, 28)},
		&"chair": {"texture": "res://assets/pixel/props/chair.png", "size": Vector2(16, 18), "visual_size": Vector2(18, 20)},
		&"office_chair": {"texture": "res://assets/pixel/props/furniture_office_chair.png", "size": Vector2(20, 20), "visual_size": Vector2(22, 22)},
		&"wardrobe": {"texture": "res://assets/pixel/props/furniture_wardrobe.png", "size": Vector2(32, 46), "visual_size": Vector2(34, 48)},
		&"dresser": {"texture": "res://assets/pixel/props/furniture_dresser.png", "size": Vector2(36, 24), "visual_size": Vector2(38, 26)},
		&"nightstand": {"texture": "res://assets/pixel/props/furniture_nightstand.png", "size": Vector2(18, 18), "visual_size": Vector2(20, 20)},
		&"tv_stand": {"texture": "res://assets/pixel/props/furniture_tv_stand.png", "size": Vector2(48, 18), "visual_size": Vector2(50, 20)},
		&"bookshelf": {"texture": "res://assets/pixel/props/furniture_bookshelf.png", "size": Vector2(30, 38), "visual_size": Vector2(32, 40)},
		&"counter": {"texture": "res://assets/pixel/props/counter.png", "size": Vector2(48, 24), "visual_size": Vector2(52, 26)},
		&"counter_corner": {"texture": "res://assets/pixel/props/furniture_counter_corner.png", "size": Vector2(46, 46), "visual_size": Vector2(48, 48)},
		&"sink_counter": {"texture": "res://assets/pixel/props/furniture_sink_counter.png", "size": Vector2(48, 24), "visual_size": Vector2(50, 26)},
		&"stove": {"texture": "res://assets/pixel/props/furniture_stove.png", "size": Vector2(40, 26), "visual_size": Vector2(42, 28)},
		&"pantry_shelf": {"texture": "res://assets/pixel/props/furniture_pantry_shelf.png", "size": Vector2(26, 34), "visual_size": Vector2(28, 36)},
		&"grocery_shelf_short": {"texture": "res://assets/pixel/props/furniture_grocery_shelf_short.png", "size": Vector2(56, 22), "visual_size": Vector2(58, 24)},
		&"grocery_shelf_long": {"texture": "res://assets/pixel/props/furniture_grocery_shelf_long.png", "size": Vector2(96, 22), "visual_size": Vector2(98, 24)},
		&"aisle_shelf": {"texture": "res://assets/pixel/props/furniture_aisle_shelf.png", "size": Vector2(84, 26), "visual_size": Vector2(86, 28)},
		&"wall_shelving": {"texture": "res://assets/pixel/props/furniture_wall_shelving.png", "size": Vector2(72, 16), "visual_size": Vector2(74, 18)},
		&"shelf_row": {"texture": "res://assets/pixel/props/shelf.png", "size": Vector2(80, 20), "visual_size": Vector2(84, 22)},
		&"industrial_shelf": {"texture": "res://assets/pixel/props/shelf.png", "size": Vector2(96, 24), "visual_size": Vector2(100, 26)},
		&"checkout_counter": {"texture": "res://assets/pixel/props/furniture_checkout_counter.png", "size": Vector2(56, 24), "visual_size": Vector2(58, 26)},
		&"display_rack": {"texture": "res://assets/pixel/props/furniture_display_rack.png", "size": Vector2(34, 30), "visual_size": Vector2(36, 32)},
		&"fridge_display": {"texture": "res://assets/pixel/props/furniture_fridge_display.png", "size": Vector2(34, 40), "visual_size": Vector2(36, 42)},
		&"freezer_chest": {"texture": "res://assets/pixel/props/furniture_freezer_chest.png", "size": Vector2(44, 26), "visual_size": Vector2(46, 28)},
		&"booth": {"texture": "res://assets/pixel/props/furniture_booth.png", "size": Vector2(56, 26), "visual_size": Vector2(58, 28)},
		&"bar_counter": {"texture": "res://assets/pixel/props/furniture_bar_counter.png", "size": Vector2(80, 24), "visual_size": Vector2(82, 26)},
		&"bedside_trolley": {"texture": "res://assets/pixel/props/furniture_bedside_trolley.png", "size": Vector2(26, 32), "visual_size": Vector2(28, 34)},
		&"equipment_trolley": {"texture": "res://assets/pixel/props/furniture_equipment_trolley.png", "size": Vector2(26, 32), "visual_size": Vector2(28, 34)},
		&"medicine_shelf": {"texture": "res://assets/pixel/props/furniture_medicine_shelf.png", "size": Vector2(28, 36), "visual_size": Vector2(30, 38)},
		&"waiting_bench": {"texture": "res://assets/pixel/props/furniture_waiting_bench.png", "size": Vector2(64, 20), "visual_size": Vector2(66, 22)},
		&"reception_desk": {"texture": "res://assets/pixel/props/furniture_reception_desk.png", "size": Vector2(64, 26), "visual_size": Vector2(66, 28)},
		&"tool_cabinet": {"texture": "res://assets/pixel/props/furniture_tool_cabinet.png", "size": Vector2(30, 30), "visual_size": Vector2(32, 32)},
		&"pallet_rack": {"texture": "res://assets/pixel/props/furniture_pallet_rack.png", "size": Vector2(96, 28), "visual_size": Vector2(98, 30)},
		&"locker": {"texture": "res://assets/pixel/props/furniture_locker.png", "size": Vector2(22, 32), "visual_size": Vector2(24, 34)},
		&"barrel": {"texture": "res://assets/pixel/props/furniture_barrel.png", "size": Vector2(22, 22), "visual_size": Vector2(24, 24)},
		&"machinery": {"texture": "res://assets/pixel/props/furniture_machinery.png", "size": Vector2(56, 38), "visual_size": Vector2(58, 40)},
		&"cabinet": {"texture": "res://assets/pixel/props/medical_cabinet.png", "size": Vector2(22, 30), "visual_size": Vector2(26, 34)},
		&"fridge": {"texture": "res://assets/pixel/props/fridge.png", "size": Vector2(28, 32), "visual_size": Vector2(30, 34)},
		&"workbench": {"texture": "res://assets/pixel/props/table.png", "size": Vector2(80, 28), "visual_size": Vector2(84, 30)},
		&"pallet": {"texture": "res://assets/pixel/props/pallet.png", "size": Vector2(28, 20), "visual_size": Vector2(32, 22)},
		&"crate": {"texture": "res://assets/pixel/props/crate.png", "size": Vector2(26, 22), "visual_size": Vector2(28, 24)},
	}
	if FURNITURE.has(kind):
		return FURNITURE[kind]
	return {"texture": "res://assets/pixel/props/crate.png", "size": Vector2(26, 22), "visual_size": Vector2(28, 24)}

## Deterministic stairwell spot for multistory buildings: inside the
## entrance room, against its north wall band, clear of reserved aisles and
## already-placed furniture. Empty when no free cell exists (single-storey
## play only for that building).
func _stairs_up_position(rooms: Array[Dictionary], clearance_rects: Array[Dictionary], furniture: Array[Dictionary]) -> Dictionary:
	if rooms.is_empty():
		return {}
	var entrance_room: Dictionary = rooms[0]
	var room_rect: Rect2 = entrance_room["rect"]
	var reserves: Array[Rect2] = []
	for reserve in clearance_rects:
		if reserve["room_id"] == entrance_room["id"]:
			reserves.append(reserve["rect"])
	var occupied: Array[Rect2] = []
	for furn in furniture:
		if furn["room_id"] == entrance_room["id"]:
			occupied.append(furn["clearance_rect"])
	var size := Vector2(32, 32)
	var candidates: Array[Vector2] = [
		Vector2(room_rect.get_center().x, room_rect.position.y + 24.0),
		Vector2(room_rect.position.x + 28.0, room_rect.position.y + 24.0),
		Vector2(room_rect.end.x - 28.0, room_rect.position.y + 24.0),
		room_rect.get_center(),
	]
	for candidate in candidates:
		var collision := Rect2(candidate - size * 0.5, size)
		var clear := collision.grow(FURNITURE_CLEARANCE)
		if not room_rect.encloses(clear):
			continue
		var blocked := false
		for reserve in reserves:
			if clear.intersects(reserve):
				blocked = true
				break
		if blocked:
			continue
		for other in occupied:
			if clear.intersects(other):
				blocked = true
				break
		if blocked:
			continue
		return {
			"position": candidate,
			"room_id": entrance_room["id"],
			"size": size,
		}
	return {}

func _floor_for(archetype: StringName, role: StringName) -> StringName:
	if archetype == &"clinic":
		return &"floor_clinic"
	if archetype == &"store":
		return &"floor_store"
	if archetype == &"restaurant":
		return &"floor_kitchen" if role in [&"kitchen", &"pantry"] else &"floor_restaurant"
	return &"floor_interior_plain"

## Deterministic post-collapse dressing of an interior: overturned seating,
## emptied/damaged storage, scattered debris and occasional old stains.
## Intensity comes from the building's own disturbance level, so a street can
## mix untouched apartments with gutted ones instead of trashing everything.
func _apply_apocalypse_disturbance(building_id: StringName, rooms: Array[Dictionary], clearance_rects: Array[Dictionary], furniture: Array[Dictionary]) -> void:
	if _disturbance <= 0:
		return
	var overturn_chance := 20 + _disturbance * 20
	var empty_chance := 12 * _disturbance
	var damage_chance := 10 * _disturbance
	for furn in furniture:
		var roll := posmod(int(String(furn["id"]).hash()), 100)
		match String(furn["mode"]):
			"physical":
				if furn["kind"] in [&"chair", &"dining_table", &"desk"] and roll < overturn_chance:
					furn["overturned"] = true
			"loot":
				if roll < empty_chance and not (furn["items"] as Dictionary).is_empty():
					furn["items"] = {}
					furn["overturned"] = roll % 2 == 0
				elif roll % 100 < damage_chance:
					furn["damaged"] = true
			_:
				pass
	# Scattered debris decals: cheap non-collision ground detail. They still
	# respect door aisles and existing furniture like everything else.
	var reserves_by_room: Dictionary = {}
	for reserve in clearance_rects:
		if not reserves_by_room.has(reserve["room_id"]):
			reserves_by_room[reserve["room_id"]] = []
		(reserves_by_room[reserve["room_id"]] as Array).append(reserve["rect"])
	var occupied_by_room: Dictionary = {}
	for furn in furniture:
		if not occupied_by_room.has(furn["room_id"]):
			occupied_by_room[furn["room_id"]] = []
		(occupied_by_room[furn["room_id"]] as Array).append(furn["clearance_rect"])
	var debris_per_room := _disturbance
	for room_variant in rooms:
		var room: Dictionary = room_variant
		var room_rect: Rect2 = room["rect"]
		var room_reserves: Array = reserves_by_room.get(room["id"], [])
		var occupied: Array = occupied_by_room.get(room["id"], [])
		for debris_index in range(debris_per_room):
			var seed_hash := posmod(int((String(building_id) + String(room["id"]) + str(debris_index)).hash()), 1000)
			var kind: StringName = &"rubble" if seed_hash % 3 != 2 else &"stain"
			var size := Vector2(14, 10)
			var spot := _find_free_debris_spot(room_rect, room_reserves, occupied, size, seed_hash)
			if spot == Vector2.INF:
				continue
			var collision := Rect2(spot - size * 0.5, size)
			furniture.append({
				"id": StringName("%s/prop/%s_debris_%02d_%02d" % [String(building_id), String(room["id"]), debris_index, seed_hash % 100]),
				"room_id": room["id"],
				"role": room["role"],
				"kind": kind,
				"mode": &"decal",
				"position": spot,
				"size": size,
				"visual_size": size * 1.4,
				"collision_rect": collision,
				"clearance_rect": collision.grow(1.0),
				"texture": "res://assets/pixel/props/debris_small.png",
				"capacity": 60.0,
				"items": {},
				"yield": 1,
				"minimum_damage_class": EnvironmentDamage.DamageClass.SMALL_ARMS,
				"tint": Color(0.35, 0.08, 0.08) if kind == &"stain" else Color.WHITE,
			})
			occupied.append(collision.grow(1.0))

func _find_free_debris_spot(room_rect: Rect2, reserves: Array, occupied: Array, size: Vector2, seed_hash: int) -> Vector2:
	var candidates: Array[Vector2] = [
		room_rect.get_center() + Vector2(-40.0 + float(seed_hash % 80), -40.0 + float((seed_hash / 7) % 80)),
		Vector2(room_rect.position.x + 28.0, room_rect.end.y - 28.0),
		Vector2(room_rect.end.x - 28.0, room_rect.position.y + 28.0),
		room_rect.get_center() + Vector2(float(seed_hash % 40) - 20.0, 24.0),
		room_rect.get_center() + Vector2(24.0, float(seed_hash % 40) - 20.0),
	]
	for candidate in candidates:
		# Test the exact footprint the record will store (grown by the same
		# 1px margin) so validator arithmetic matches placement arithmetic.
		var collision := Rect2(candidate - size * 0.5, size)
		var clearance := collision.grow(1.0)
		if not room_rect.encloses(clearance):
			continue
		var blocked := false
		for reserve in reserves:
			if clearance.intersects(reserve):
				blocked = true
				break
		if blocked:
			continue
		for other in occupied:
			if clearance.intersects(other):
				blocked = true
				break
		if blocked:
			continue
		return candidate
	return Vector2.INF

func _nearest_wall_slot(value: float, minimum: float, maximum: float) -> float:
	var first_center := minimum + TILE_SIZE * 0.5
	var last_center := maximum - TILE_SIZE * 0.5
	var index := roundi((value - first_center) / TILE_SIZE)
	return clampf(first_center + float(index * TILE_SIZE), first_center, last_center)

func validate(interior: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var size: Vector2 = interior.get("size", Vector2.ZERO)
	var bounds: Rect2 = interior.get("footprint_bounds", Rect2(-size * 0.5, size))
	var perimeter_rects: Array = interior.get("perimeter_rects", [Rect2(-size * 0.5, size)])
	var room_by_id: Dictionary = {}
	var ids: Dictionary = {}
	for room in interior.get("rooms", []):
		var room_id: StringName = room["id"]
		if room_by_id.has(room_id):
			errors.append("duplicate room id %s" % String(room_id))
		room_by_id[room_id] = room
		var room_rect: Rect2 = room["rect"]
		if not bounds.encloses(room_rect):
			errors.append("room %s leaves building bounds" % String(room_id))
		var in_footprint := false
		for perimeter_rect in perimeter_rects:
			if (perimeter_rect as Rect2).encloses(room_rect):
				in_footprint = true
				break
		if not in_footprint:
			errors.append("room %s leaves compound footprint" % String(room_id))
		if room_rect.size.x < MIN_ROOM_SPAN or room_rect.size.y < MIN_ROOM_SPAN:
			errors.append("room %s is too narrow for wall and actor clearance" % String(room_id))
		_register_unique_id(room["stable_id"], ids, errors)
	var adjacency: Dictionary = {}
	var roots: Array[StringName] = []
	for room_id in room_by_id:
		adjacency[room_id] = []
	for door in interior.get("doors", []):
		_register_unique_id(door["id"], ids, errors)
		var room_a: StringName = door["room_a"]
		var room_b: StringName = door["room_b"]
		if not room_by_id.has(room_a):
			errors.append("door %s references missing room_a" % String(door["id"]))
			continue
		if bool(door["exterior"]):
			roots.append(room_a)
		elif room_b == &"" or not room_by_id.has(room_b):
			errors.append("interior door %s references missing room_b" % String(door["id"]))
		else:
			adjacency[room_a].append(room_b)
			adjacency[room_b].append(room_a)
	if roots.is_empty():
		errors.append("building has no exterior entrance")
	var visited: Dictionary = {}
	var queue: Array[StringName] = roots.duplicate()
	while not queue.is_empty():
		var current: StringName = queue.pop_front()
		if visited.has(current):
			continue
		visited[current] = true
		for neighbor in adjacency.get(current, []):
			if not visited.has(neighbor):
				queue.append(neighbor)
	for room in interior.get("rooms", []):
		if bool(room.get("required", true)) and not visited.has(room["id"]):
			errors.append("required room %s is unreachable from exterior" % String(room["id"]))
	var furniture_by_room: Dictionary = {}
	for furniture in interior.get("furniture", []):
		_register_unique_id(furniture["id"], ids, errors)
		var room_id: StringName = furniture["room_id"]
		if not room_by_id.has(room_id):
			errors.append("furniture %s references missing room" % String(furniture["id"]))
			continue
		if not (room_by_id[room_id]["rect"] as Rect2).encloses(furniture["clearance_rect"]):
			errors.append("furniture %s violates room clearance" % String(furniture["id"]))
		if not furniture_by_room.has(room_id):
			furniture_by_room[room_id] = []
		for other_rect in furniture_by_room[room_id]:
			if (furniture["clearance_rect"] as Rect2).intersects(other_rect):
				errors.append("furniture %s overlaps another clearance" % String(furniture["id"]))
		furniture_by_room[room_id].append(furniture["clearance_rect"])
		for reserve in interior.get("clearance_rects", []):
			if reserve["room_id"] == room_id and (furniture["clearance_rect"] as Rect2).intersects(reserve["rect"]):
				errors.append("furniture %s blocks a reserved aisle" % String(furniture["id"]))
	for room in interior.get("rooms", []):
		if not furniture_by_room.has(room["id"]):
			errors.append("required room %s has no functional furniture" % String(room["id"]))
	for window in interior.get("windows", []):
		_register_unique_id(window["id"], ids, errors)
		if not room_by_id.has(window["room_id"]):
			errors.append("window %s references missing room" % String(window["id"]))
	return errors

func _register_unique_id(id: StringName, ids: Dictionary, errors: Array[String]) -> void:
	if id == &"":
		errors.append("generated stable id is empty")
	elif ids.has(id):
		errors.append("duplicate generated stable id %s" % String(id))
	else:
		ids[id] = true
