extends SceneTree

## Headless PASSABILITY AUDIT for the five AUTHORED building fixtures
## (scenes/world/buildings/*.tscn) -- complements tests/passability_probe.gd,
## which only covers runtime-generated buildings plus the safehouse.
##
## Per building it verifies, with REAL physics queries and a player-sized
## walker body (radius 16 -- the actual Player.tscn collider):
##   1. every door's carved wall bay contains zero surviving wall cells
##   2. the CLOSED door physically seals its entire bay (no walk-around
##      slivers beside the slab), and the OPEN door leaves the whole bay clear
##   3. outside -> entrance room is blocked while closed, walkable once open
##   4. every interior doorway is walkable room-to-room when open and
##      sealed against a player-sized body when that one door closes
##   5. every window blocks movement, does NOT block the Vision layer while
##      intact, and does not overlap a solid wall cell (an intact window
##      buried inside a solid wall run can never let reveal see through)
## Exits 0 when every check passes; prints one FAIL line per problem.
##
## Like passability_probe.gd, deliberately avoids compile-time references to
## gameplay classes so it stays loadable as a bare --script MainLoop.

const WALKER_RADIUS := 16.0
const MASK_WORLD := 1
const MASK_VISION := 32
const WALK_SPEED := 220.0
## Arrival tolerance: generous enough that a room's exact center node may sit
## flush against authored furniture (the body still has to be genuinely
## inside the room), tight enough that a closed slab 15px thick can never be
## mistaken for "crossed".
const WALK_REACH := 18.0

## Entrance door id + outward (away-from-building) normal for each fixture.
const FIXTURES := [
	{"path": "res://scenes/world/buildings/Apartment01.tscn", "id": &"apartment_01/door_entrance", "out": Vector2(0, 1)},
	{"path": "res://scenes/world/buildings/Restaurant01.tscn", "id": &"restaurant_01/door_entrance", "out": Vector2(0, 1)},
	{"path": "res://scenes/world/buildings/Clinic01.tscn", "id": &"clinic_01/door_entrance", "out": Vector2(0, 1)},
	{"path": "res://scenes/world/buildings/ConvenienceStore01.tscn", "id": &"convenience_store_01/door_entrance", "out": Vector2(0, 1)},
	{"path": "res://scenes/world/buildings/Workshop01.tscn", "id": &"workshop_01/door_entrance", "out": Vector2(0, 1)},
]

var _failures: Array[String] = []
var _checks := 0
var _walker: CharacterBody2D = null
var _last_walk_end := Vector2.INF


func _initialize() -> void:
	call_deferred(&"_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		print("AUDIT FAIL: ", message)


func _run() -> void:
	root.get_node("WorldState").reset()
	root.get_node("UrbanNavigationService").reset()
	var buildings: Array = []
	for i in range(FIXTURES.size()):
		var building: Node2D = (load(FIXTURES[i]["path"]) as PackedScene).instantiate()
		building.position = Vector2(20000.0 + float(i) * 4000.0, 20000.0)
		root.add_child(building)
		buildings.append(building)
	_walker = _spawn_walker()
	for _i in range(10):
		await process_frame
		await physics_frame

	for i in range(FIXTURES.size()):
		await _audit_building(buildings[i], FIXTURES[i]["id"], FIXTURES[i]["out"])

	_walker.queue_free()
	print("AUTHORED_PASSABILITY_AUDIT checks=%d failures=%d" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _audit_building(building: Node2D, entrance_id: StringName, out_normal: Vector2) -> void:
	var label := String(building.get("building_id"))
	var building_half_extent: Vector2 = building.HALF_EXTENT
	var doors: Array = []
	for node in get_nodes_in_group(&"doors"):
		if building.is_ancestor_of(node):
			doors.append(node)
	var windows: Array = []
	for node in get_nodes_in_group(&"windows"):
		if building.is_ancestor_of(node):
			windows.append(node)
	var rooms: Array = []
	var rooms_node := building.get_node_or_null("Rooms")
	if rooms_node != null:
		rooms = rooms_node.get_children()
	var walls := _wall_cells(building)

	# --- 1. carved bays contain no surviving wall cells ---------------------
	# Bay rects anchor half a cell west/north of the door node (matching
	# Door._setup_aperture / door_bay_rect); shrink by 1px so a wall cell
	# merely TOUCHING a bay corner is not flagged.
	for door in doors:
		var bay := Rect2(door.position - Vector2(16, 16), door.aperture_size).grow(-1.0)
		for wall in walls:
			if bay.has_point(wall.position):
				_check(false, "%s: door %s bay still contains a wall cell at %s" % [
					label, String(door.door_id), wall.position])

	# --- 2. closed door seals its bay / open door clears it ------------------
	for door in doors:
		var long_axis: float = maxf(door.aperture_size.x, door.aperture_size.y)
		var axis := _transverse_axis(door)
		# The bay anchors at local (-16,-16) and extends along +axis by the
		# aperture, so interior samples run from -12 to long_axis - 20.
		var offset := -12.0
		var sealed := true
		_set_all_doors(doors, false)
		await physics_frame
		while offset <= long_axis - 20.0:
			if not _point_hits(door.global_position + axis * offset, MASK_WORLD | MASK_VISION):
				sealed = false
			offset += 4.0
		_check(sealed, "%s: CLOSED door %s leaves its bay unsealed (see-through gap)" % [
			label, String(door.door_id)])

		door.toggle(null)
		await physics_frame
		var cleared := true
		var blocked_at := Vector2.INF
		# Only the central 32px lane of the open bay must be clear -- that is
		# the lane a player-sized body needs. Bay ends may legitimately touch
		# crossing partition junctions.
		var lane_center := long_axis * 0.5 - 16.0
		offset = lane_center - 14.0
		while offset <= lane_center + 14.0:
			if _point_hits(door.global_position + axis * offset, MASK_WORLD):
				cleared = false
				blocked_at = door.global_position + axis * offset
			offset += 4.0
		_check(cleared, "%s: OPEN door %s still has an obstruction in its bay (at local %s)" % [
			label, String(door.door_id), blocked_at - building.global_position])
		door.toggle(null)
	_set_all_doors(doors, false)
	await physics_frame

	# --- 3. entrance: blocked closed, walkable open --------------------------
	var entrance: Node = null
	for door in doors:
		if door.door_id == entrance_id:
			entrance = door
	if entrance != null:
		# Cross through the BAY CENTER (the door node anchors at the west/
		# north carved cell for non-square apertures), and scan outward for
		# genuinely free standing spots -- authored offsets can land inside
		# wall bands or furniture.
		var shift: Vector2 = (entrance.aperture_size - Vector2(32, 32)) * 0.5
		var bay_center: Vector2 = entrance.global_position + shift
		var outside := _first_free(bay_center + out_normal * 40.0, out_normal)
		var landing := _first_free(bay_center - out_normal * 40.0, -out_normal)
		_set_all_doors(doors, false)
		await physics_frame
		var crossed := await _try_walk([outside, landing])
		_check(not crossed, "%s: player-sized body crosses the CLOSED entrance %s" % [
			label, String(entrance_id)])
		_set_all_doors(doors, true)
		await physics_frame
		crossed = await _try_walk([outside, landing])
		_check(crossed, "%s: player-sized body CANNOT cross the OPEN entrance %s (stopped at local %s)" % [
			label, String(entrance_id), _last_walk_end - building.global_position])

	# --- 4. interior doorways -------------------------------------------------
	for door in doors:
		var sides := _rooms_sharing(door, rooms)
		if sides.size() != 2:
			continue
		var room_a: Node2D = sides[0]
		var room_b: Node2D = sides[1]
		# Standpoints 44px out from the door along each room's direction --
		# far enough that the closed slab (bay + 1px seams) separates them,
		# so a successful "cross" can only mean a real traversal of the
		# doorway. Room origins can sit closer than 24px to their door,
		# which would collapse every waypoint onto one side.
		var dir_a: Vector2 = (room_a.global_position - door.global_position).normalized()
		var dir_b: Vector2 = (room_b.global_position - door.global_position).normalized()
		var side_a: Vector2 = door.global_position + dir_a * 44.0
		var side_b: Vector2 = door.global_position + dir_b * 44.0
		_set_all_doors(doors, true)
		await physics_frame
		var crossed := await _try_walk([side_a, side_b])
		_check(crossed, "%s: OPEN door %s impassable between rooms %s and %s (stopped at %s)" % [
			label, String(door.door_id), room_a.get("room_id"), room_b.get("room_id"), _last_walk_end - building.global_position])
		# Park the walker well clear of the doorway, then close ONLY this
		# door -- toggle() refuses to close onto a standing body, and a
		# refused close would masquerade as a sealed-door leak.
		_walker.global_position = room_a.global_position
		_walker.velocity = Vector2.ZERO
		await physics_frame
		# Park the walker well clear of the doorway, then close ONLY this
		# door -- toggle() refuses to close onto a standing body, and a
		# refused close would masquerade as a sealed-door leak.
		_walker.global_position = room_a.global_position
		_walker.velocity = Vector2.ZERO
		await physics_frame
		door.toggle(null)
		var actually_closed: bool = not door.is_open
		_check(actually_closed, "%s: door %s could not re-close after the walk-through (body overlap?)" % [
			label, String(door.door_id)])
		if actually_closed:
			await physics_frame
			crossed = await _try_walk([side_a, side_b])
			_check(not crossed, "%s: CLOSED door %s leaks between rooms %s and %s (player fits past the slab)" % [
				label, String(door.door_id), room_a.get("room_id"), room_b.get("room_id")])

	_set_all_doors(doors, false)

	# --- 5. windows ------------------------------------------------------------
	for window in windows:
		var local: Vector2 = window.position
		var wpos: Vector2 = window.global_position
		_check(_point_hits(wpos, MASK_WORLD),
			"%s: window %s does not block movement at its own position" % [label, String(window.window_id)])
		var axis := _ring_axis(local, building_half_extent)
		if axis == Vector2.ZERO:
			_check(false, "%s: window %s sits off every perimeter wall line" % [
				label, String(window.window_id)])
			continue
		if not window.is_boarded:
			var from: Vector2 = wpos + axis * 26.0
			var to: Vector2 = wpos - axis * 26.0
			_check(not _segment_blocked(from, to, MASK_VISION),
				"%s: INTACT window %s blocks the Vision-layer sightline through itself" % [
					label, String(window.window_id)])
		for wall in walls:
			var wall_rect := Rect2(wall.global_position - Vector2(16, 16), Vector2(32, 32))
			var window_rect := Rect2(wpos - Vector2(15, 6), Vector2(30, 12))
			_check(not wall_rect.intersects(window_rect),
				"%s: window %s overlaps a solid wall cell at %s (decorative, can never reveal)" % [
					label, String(window.window_id), wall.global_position])


## Replicates BuildingShellBuilder's ring snapping: returns the sightline
## axis (normal to the wall run) when the local position sits on a perimeter
## row/column center band, else ZERO.
func _ring_axis(local: Vector2, half_extent: Vector2) -> Vector2:
	var row_top := float(roundi(-half_extent.y / 32.0) * 32 + 16)
	var row_bottom := float((roundi(half_extent.y / 32.0) - 1) * 32 + 16)
	var col_left := float(roundi(-half_extent.x / 32.0) * 32 + 16)
	var col_right := float((roundi(half_extent.x / 32.0) - 1) * 32 + 16)
	var on_row := (absf(local.y - row_top) <= 15.9 or absf(local.y - row_bottom) <= 15.9) \
		and local.x >= col_left - 16.0 and local.x <= col_right + 16.0
	var on_col := (absf(local.x - col_left) <= 15.9 or absf(local.x - col_right) <= 15.9) \
		and local.y >= row_top - 16.0 and local.y <= row_bottom + 16.0
	if on_row:
		return Vector2(0, 1)
	if on_col:
		return Vector2(1, 0)
	return Vector2.ZERO


func _rooms_sharing(door: Node, rooms: Array) -> Array:
	var sides: Array = []
	for room in rooms:
		if room.doors.has(door):
			sides.append(room)
	return sides


func _set_all_doors(doors: Array, open_state: bool) -> void:
	for door in doors:
		if door.is_open != open_state:
			door.toggle(null)


func _wall_cells(building: Node2D) -> Array:
	var result: Array = []
	for child in building.get_children():
		if child is StaticBody2D:
			var shape_node := _shape_of(child)
			if shape_node != null and shape_node.shape is RectangleShape2D \
					and (shape_node.shape as RectangleShape2D).size == Vector2(32, 32):
				result.append(child)
	return result


func _shape_of(body: Node) -> CollisionShape2D:
	var named := body.get_node_or_null("CollisionShape2D")
	if named is CollisionShape2D:
		return named
	for child in body.get_children():
		if child is CollisionShape2D:
			return child
	return null


func _transverse_axis(door: Node) -> Vector2:
	# Authored door slabs are squares, so rotation only re-orients visuals;
	# the bay runs across whichever wall the door sits in. Infer from the
	# aperture aspect once apertures go non-square (64px convention).
	if absf(door.aperture_size.x - door.aperture_size.y) < 0.01:
		return Vector2(1, 0) if absf(door.rotation_degrees) < 45.0 else Vector2(0, 1)
	return Vector2(1, 0) if door.aperture_size.x >= door.aperture_size.y else Vector2(0, 1)


func _point_hits(pos: Vector2, mask: int) -> bool:
	var params := PhysicsPointQueryParameters2D.new()
	params.position = pos
	params.collision_mask = mask
	params.collide_with_areas = false
	params.collide_with_bodies = true
	return not root.get_world_2d().direct_space_state.intersect_point(params, 8).is_empty()


## Steps along `dir` until the point query comes up empty (a standing spot a
## walker can be aimed at), bounded to 20 steps.
func _first_free(from: Vector2, dir: Vector2) -> Vector2:
	var p := from
	for _i in range(20):
		if not _point_hits(p, MASK_WORLD | MASK_VISION):
			return p
		p += dir * 8.0
	return p


func _segment_blocked(from: Vector2, to: Vector2, mask: int) -> bool:
	var params := PhysicsRayQueryParameters2D.create(from, to, mask)
	var hit := root.get_world_2d().direct_space_state.intersect_ray(params)
	return not hit.is_empty()


func _spawn_walker() -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.name = "AuditWalker"
	body.collision_layer = 0
	body.collision_mask = MASK_WORLD
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = WALKER_RADIUS
	shape.shape = circle
	body.add_child(shape)
	root.add_child(body)
	return body


func _try_walk(waypoints: Array) -> bool:
	_walker.global_position = waypoints[0]
	_walker.velocity = Vector2.ZERO
	await physics_frame
	const REACH := WALK_REACH
	var stuck_frames := 0
	var frames := 0
	for waypoint_index in range(waypoints.size()):
		var target: Vector2 = waypoints[waypoint_index]
		stuck_frames = 0
		while frames < 900:
			frames += 1
			var to_target := target - _walker.global_position
			if to_target.length() <= REACH:
				break
			var previous := _walker.global_position
			_walker.velocity = to_target.limit_length(WALK_SPEED)
			_walker.move_and_slide()
			await physics_frame
			if _walker.global_position.distance_to(previous) < 0.05:
				stuck_frames += 1
				if stuck_frames > 40:
					_last_walk_end = _walker.global_position
					return false
			else:
				stuck_frames = 0
		if _walker.global_position.distance_to(target) > REACH:
			_last_walk_end = _walker.global_position
			return false
	_last_walk_end = _walker.global_position
	return true
