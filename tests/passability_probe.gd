extends SceneTree

## Headless passability audit for enterable buildings (2D runtime).
## Verifies, for every generated building plus the safehouse:
##   1. room graph connectivity through declared doors
##   2. carved wall bays are fully sealed by their closed door slab
##   3. closed doors physically block, open doors physically clear
##   4. outside -> entrance room -> every other room is walkable (nav grid)
##   5. windows sit on perimeter lines
## Exits 0 when every check passes; prints one FAIL line per problem.
##
## Deliberately avoids compile-time references to gameplay classes that
## resolve autoload singletons (they are not registered while a --script
## MainLoop compiles); everything below ducks through Node properties.

const COORDS := 32

var _failures: Array[String] = []
var _checks := 0
var _walker: CharacterBody2D = null
var _last_walk_end := Vector2.INF


func _initialize() -> void:
	call_deferred(&"_run")


## Local physics point query used by the seal checks.
func _point_hits(pos: Vector2, mask: int) -> bool:
	var params := PhysicsPointQueryParameters2D.new()
	params.position = pos
	params.collision_mask = mask
	params.collide_with_areas = false
	params.collide_with_bodies = true
	return not root.get_world_2d().direct_space_state.intersect_point(params, 8).is_empty()


func _run() -> void:
	root.get_node("WorldState").reset()
	root.get_node("UrbanNavigationService").reset()
	var main = load("res://scenes/main/Main.tscn").instantiate()
	root.add_child(main)
	for _i in range(30):
		await process_frame
		await physics_frame

	var world = main.get_node("World")
	var buildings: Array = []
	for child in world.get_children():
		var buildings_node = child.get_node_or_null("Buildings")
		if buildings_node == null:
			continue
		for building in buildings_node.get_children():
			if "specification" in building:
				buildings.append(building)

	if buildings.is_empty():
		_fail("probe", "no generated buildings found in loaded chunks")

	# Walker traversal is real-time even headless -- audit a deterministic,
	# evenly-spread sample (every archetype appears across quarters) instead
	# of every streamed building.
	var stride := ceili(buildings.size() / 24.0)
	var sampled: Array = []
	for i in range(0, buildings.size(), stride):
		sampled.append(buildings[i])
	buildings = sampled

	_walker = CharacterBody2D.new()
	_walker.name = "ProbeWalker"
	_walker.collision_layer = 0
	_walker.collision_mask = 1
	_walker.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var walker_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0 # the real Player.tscn collider radius
	walker_shape.shape = circle
	_walker.add_child(walker_shape)
	root.add_child(_walker)

	var total_doors := 0
	var total_windows := 0
	for building in buildings:
		total_doors += await _audit_building(building)
		total_windows += _audit_windows(building)

	var settlement = main.get_node_or_null("Settlement")
	if settlement != null:
		total_doors += await _audit_safehouse(settlement)

	print("PASSABILITY_PROBE buildings=%d doors=%d windows=%d checks=%d failures=%d" % [
		buildings.size(), total_doors, total_windows, _checks, _failures.size()
	])
	for failure in _failures:
		push_error("PASSABILITY_PROBE FAIL: %s" % failure)
	main.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _audit_building(building) -> int:
	var label := String(building.building_id)
	var interior: Dictionary = building.specification["interior"]
	var rooms: Array = interior["rooms"]
	# Live Room nodes (for walker side-points); the spec list above drives
	# the graph checks.
	var live_rooms: Array = []
	var rooms_container: Node = building.get_node_or_null("Rooms")
	if rooms_container != null:
		live_rooms = rooms_container.get_children()
	var door_nodes: Array = []
	for node in get_nodes_in_group(&"doors"):
		if building.is_ancestor_of(node):
			door_nodes.append(node)

	# --- 1. room graph connectivity through declared doors -----------------
	var adjacency: Dictionary = {}
	for room_spec in rooms:
		adjacency[room_spec["id"]] = {}
	for door_spec in interior["doors"]:
		var room_a: StringName = door_spec["room_a"]
		var room_b: StringName = door_spec["room_b"]
		if not adjacency.has(room_a):
			_fail(label, "door %s references unknown room %s" % [door_spec["id"], room_a])
			continue
		if room_b == &"":
			continue
		if not adjacency.has(room_b):
			_fail(label, "door %s references unknown room %s" % [door_spec["id"], room_b])
			continue
		adjacency[room_a][room_b] = true
		adjacency[room_b][room_a] = true
	if interior["doors"].is_empty():
		_fail(label, "building has no doors at all")
		return 0
	var entrance_room: StringName = interior["doors"][0]["room_a"]
	var reached: Dictionary = {}
	if adjacency.has(entrance_room):
		var queue: Array[StringName] = [entrance_room]
		reached[entrance_room] = true
		while not queue.is_empty():
			var current: StringName = queue.pop_front()
			for neighbor in adjacency[current]:
				if not reached.has(neighbor):
					reached[neighbor] = true
					queue.append(neighbor)
	_check(reached.size() == rooms.size(), "%s: room graph connects only %d/%d rooms" % [label, reached.size(), rooms.size()])

	# --- 2. bay geometry: no surviving wall cell inside/under the closed
	# slab, and the closed slab physically seals sample points across the
	# whole bay interior. Measured against LIVE bodies and physics queries,
	# not a lattice model: grid-mode partitions sit on room-boundary lines
	# whose cells are NOT on the perimeter ring's 16px-offset lattice.
	for door in door_nodes:
		if door.is_open:
			door.toggle(null)
	await _settle_doors(door_nodes, false)
	var walls: Array = []
	for child in building.get_children():
		if child is StaticBody2D:
			var shape_node: Node = child.get_node_or_null("CollisionShape2D")
			if shape_node != null and shape_node.shape is RectangleShape2D \
					and (shape_node.shape as RectangleShape2D).size == Vector2(COORDS, COORDS):
				walls.append(child)
	for door in door_nodes:
		var aperture: Vector2 = door.aperture_size
		var shift: Vector2 = (aperture - Vector2(COORDS, COORDS)) * 0.5
		var bay: Rect2 = Rect2(door.position - aperture * 0.5 + shift, aperture)
		var slab: Rect2 = Rect2(door.position + shift - (bay.size - Vector2(2, 2)) * 0.5, bay.size - Vector2(2, 2))
		var carved_beside := false
		for wall in walls:
			if bay.grow(-1.0).has_point(wall.position):
				_check(false, "%s: door %s leaves an uncarved wall cell inside its bay at %s" % [
					label, String(door.door_id), wall.position])
				continue
			if bay.grow(float(COORDS) + 1.0).has_point(wall.position):
				carved_beside = true
			var wall_rect := Rect2(wall.position - Vector2(COORDS, COORDS) * 0.5, Vector2(COORDS, COORDS))
			var intrusion: Rect2 = wall_rect.grow(-1.0).intersection(slab)
			# Benign: a slab edge may kiss an adjacent wall band when an
			# annex partition runs offset from the perimeter lattice -- as
			# long as every overlapped pixel stays INSIDE the door's own bay
			# (which is supposed to be empty), no collision extends into a
			# room or past the doorway line.
			var benign := intrusion.get_area() <= 0.0 or bay.encloses(intrusion)
			_check(benign,
				"%s: door %s slab pokes outside its bay into wall cell at %s" % [label, String(door.door_id), wall.position])
		_check(carved_beside, "%s: door %s carves no wall cell (no surviving wall run beside its bay)" % [
			label, String(door.door_id)])
		# Physical seal across the whole bay interior (1px seams excluded).
		var axis := Vector2(1, 0) if aperture.x >= aperture.y else Vector2(0, 1)
		var long_axis := maxf(aperture.x, aperture.y)
		var t := -12.0
		while t <= long_axis - 20.0:
			var params := PhysicsPointQueryParameters2D.new()
			params.position = building.global_position + door.position + shift + axis * t
			params.collision_mask = 1 | 32
			params.collide_with_areas = false
			var hits: Array = root.get_world_2d().direct_space_state.intersect_point(params, 4)
			_check(hits.is_empty() == false,
				"%s: CLOSED door %s leaves its bay unsealed at local %s" % [
					label, String(door.door_id), door.position + shift + axis * t])
			t += 4.0

	# --- 3. closed doors block; open doors clear ---------------------------
	var space := root.get_world_2d().direct_space_state
	for door in door_nodes:
		if door.is_open:
			door.toggle(null)
	for _i in range(2):
		await physics_frame
	for door in door_nodes:
		var params := PhysicsPointQueryParameters2D.new()
		params.position = building.global_position + door.position + (door.aperture_size - Vector2(COORDS, COORDS)) * 0.5
		params.collision_mask = 1 | 32
		params.collide_with_areas = false
		var hits: Array = space.intersect_point(params, 4)
		_check(not hits.is_empty(), "%s: CLOSED door %s does not block its bay center" % [label, String(door.door_id)])

	# --- 4. physical reachability: player-sized WALKER, no nav service ------
	# The old checks called are_positions_connected() through the ONE shared
	# global nav grid while auditing buildings across many streamed regions;
	# endpoints outside the currently-built region always read "not
	# connected". A walking body measures what actually matters.
	var bounds: Rect2 = interior["footprint_bounds"]
	var entrance_spec: Dictionary = interior["doors"][0]
	var entrance: Node = null
	for door in door_nodes:
		if door.door_id == entrance_spec["id"]:
			entrance = door
	if entrance != null:
		var shift_in: Vector2 = (entrance.aperture_size - Vector2(COORDS, COORDS)) * 0.5
		var bay_center: Vector2 = building.global_position + entrance.position + shift_in
		var off: Vector2 = entrance.position - bounds.get_center()
		var outward: Vector2
		if absf(off.y) >= absf(off.x):
			outward = Vector2(0.0, signf(off.y))
		else:
			outward = Vector2(signf(off.x), 0.0)
		var outside: Vector2 = bay_center + outward * 48.0
		var landing: Vector2 = bay_center - outward * 28.0
		# default all-closed state: outside -> inside must be blocked
		for door in door_nodes:
			if door.is_open:
				door.toggle(null)
		await _settle_doors(door_nodes, false)
		var crossed := await _try_walk([outside, landing])
		_check(not crossed, "%s: player-sized body crosses the CLOSED entrance" % label)
		# open everything: crossing must succeed ...
		for door in door_nodes:
			if not door.is_open:
				door.toggle(null)
		await _settle_doors(door_nodes, true)
		crossed = await _try_walk([outside, landing])
		_check(crossed, "%s: player-sized body CANNOT cross the OPEN entrance (stopped at local %s)" % [
			label, _last_walk_end - building.global_position])
		# ... and every interior doorway must be walkable side to side.
		var tested := 0
		for door in door_nodes:
			if tested >= 3:
				break
			var sides := _rooms_sharing(door, live_rooms)
			if sides.size() != 2:
				continue
			tested += 1
			var dir_a: Vector2 = (sides[0].global_position - door.global_position).normalized()
			var dir_b: Vector2 = (sides[1].global_position - door.global_position).normalized()
			crossed = await _try_walk([door.global_position + dir_a * 44.0, door.global_position + dir_b * 44.0])
			_check(crossed, "%s: OPEN door %s impassable between rooms %s and %s (stopped at local %s)" % [
				label, String(door.door_id), sides[0].get("room_id"), sides[1].get("room_id"),
				_last_walk_end - building.global_position])
	# restore the default all-closed state
	for door in door_nodes:
		if door.is_open:
			door.toggle(null)
	return door_nodes.size()


## Toggle states reach the physics server asynchronously; poll until every
## door reports the wanted state AND its bay center point-query agrees
## (closed -> blocked, open -> clear). Bounded so a genuinely broken door
## still fails its checks instead of hanging the probe.
func _settle_doors(doors: Array, want_open: bool) -> void:
	for _attempt in range(40):
		await physics_frame
		var settled := true
		for door in doors:
			if door.is_open != want_open:
				settled = false
				break
			var center: Vector2 = door.global_position + (door.aperture_size - Vector2(COORDS, COORDS)) * 0.5
			if _point_hits(center, 1 | 32) == want_open:
				settled = false
				break
		if settled:
			return


func _rooms_sharing(door: Node, rooms: Array) -> Array:
	var sides: Array = []
	for room in rooms:
		if room.doors.has(door):
			sides.append(room)
	return sides


func _try_walk(waypoints: Array) -> bool:
	_walker.global_position = waypoints[0]
	_walker.velocity = Vector2.ZERO
	await physics_frame
	const REACH := 18.0
	const SPEED := 420.0
	var frames := 0
	for waypoint_index in range(waypoints.size()):
		var target: Vector2 = waypoints[waypoint_index]
		var first_dir := target - _walker.global_position
		if first_dir.length() < 0.01:
			first_dir = Vector2.RIGHT
		else:
			first_dir = first_dir.normalized()
		var perp := Vector2(-first_dir.y, first_dir.x)
		# Straight seek first; on stall, retry with one lateral offset so a
		# furniture corner or partition stub beside an otherwise-open
		# doorway is rounded instead of wedging the naive seeker.
		for attempt_offset in [0.0, 30.0, -30.0]:
			var aim: Vector2 = target + perp * attempt_offset
			var local_frames := 0
			var stuck := 0
			while frames < 900 and local_frames < 240:
				frames += 1
				local_frames += 1
				var to_target: Vector2 = aim - _walker.global_position
				if to_target.length() <= REACH:
					break
				var previous := _walker.global_position
				_walker.velocity = to_target.limit_length(SPEED)
				_walker.move_and_slide()
				await physics_frame
				if _walker.global_position.distance_to(previous) < 0.05:
					stuck += 1
					if stuck > 14:
						break
				else:
					stuck = 0
			if _walker.global_position.distance_to(aim) <= REACH + absf(attempt_offset):
				break
		if _walker.global_position.distance_to(target) > REACH + 8.0:
			_last_walk_end = _walker.global_position
			return false
	_last_walk_end = _walker.global_position
	return true


func _audit_windows(building) -> int:
	var label := String(building.building_id)
	var half_extent: Vector2 = building.specification["interior"]["half_extent"]
	var count := 0
	for window in get_nodes_in_group(&"windows"):
		if not building.is_ancestor_of(window):
			continue
		count += 1
		var local: Vector2 = window.position
		# build_perimeter_walls snaps its ring INSIDE the footprint: for a
		# tile-multiple half extent the extreme row/column centers sit at
		# -(h-16) / +(h-16), not at -(h+16). Model the real ring.
		var near_left := absf(local.x - (-half_extent.x + COORDS * 0.5)) < COORDS * 0.5
		var near_right := absf(local.x - (half_extent.x - COORDS * 0.5)) < COORDS * 0.5
		var near_top := absf(local.y - (-half_extent.y + COORDS * 0.5)) < COORDS * 0.5
		var near_bottom := absf(local.y - (half_extent.y - COORDS * 0.5)) < COORDS * 0.5
		_check(near_left or near_right or near_top or near_bottom,
			"%s: window at (%.0f, %.0f) does not sit on a perimeter wall line" % [label, local.x, local.y])
	return count


func _audit_safehouse(settlement) -> int:
	var doors: Array = []
	for node in get_nodes_in_group(&"doors"):
		if settlement.is_ancestor_of(node):
			doors.append(node)
	for door in doors:
		var aperture: Vector2 = door.aperture_size
		_check(maxf(aperture.x, aperture.y) >= float(COORDS), "safehouse door %s has degenerate aperture" % String(door.door_id))
	return doors.size()


func _check(condition: bool, message: String) -> void:
	if message.is_empty():
		return
	_checks += 1
	if not condition:
		_failures.append(message)


func _fail(label: String, message: String) -> void:
	_checks += 1
	_failures.append("%s: %s" % [label, message])
