class_name BuildingVisibilityController
extends Node2D
## Toggles a building's roof visibility and interior room reveal as the
## player enters/exits, using a bounded room-portal graph (Phase 3B.1) --
## replaces the earlier "current room + any room sharing an open door"
## rule. Collision is never touched by any of this -- only `modulate` on
## each room's own Area2D and `.visible` on the roof TileMapLayer.
##
## Portal graph: a Door (open) or BuildingWindow (intact, not boarded)
## connects two Rooms (see Room.doors/Room.windows). Starting from the
## player's current room (always revealed), a neighboring room reveals
## only if: its connecting portal is currently open/intact, that portal
## is within the player's current view cone on the FIRST hop (aim
## direction preferred, recent movement direction as fallback -- see
## `_player_view_direction()`), and a raycast from the player to the
## portal is unobstructed (so a portal on the far side of another wall
## never counts -- "walls block reveal"). From each depth-1 revealed
## room, ONE further hop is allowed (`MAX_PORTAL_DEPTH = 2`) through
## another open/intact, line-of-sight-clear portal -- "look through one
## room into the next," not an unbounded chain; the second hop only
## re-checks line of sight, not the cone, since the player is already
## looking "through" the first portal.
##
## Scope: reveal is only computed while the player is inside the building
## -- the roof is a single building-wide TileMapLayer, not segmented per
## room, so "peek into a room through an exterior window from outside"
## would need per-room roof cutouts, out of scope this pass (see
## docs/building_system.md "Known limitations"). Every BuildingWindow in
## the current 5 buildings only borders the exterior (none connect two
## rooms), so the window-portal path never actually fires for them today
## -- it's exercised directly by a synthetic test fixture instead, ready
## for a future building authored with a real interior-facing window.
##
## Updates on room enter/exit (event-driven) and any door in the scene
## changing state (Door.state_changed, event-driven -- "opening or
## closing a door immediately recalculates visibility even when the
## player is stationary"), plus a low-frequency timer
## (`view_recheck_interval`, only running while the player is actually
## inside this building) to pick up aim/movement direction changes
## without raycasting every physics frame.

@export var building_id: StringName = &""
@export var roof_node_path: NodePath
@export var rooms_container_path: NodePath = NodePath("Rooms")
@export var view_cone_degrees: float = 120.0
## Purely how often a stationary player's aim/movement direction is
## re-sampled -- room-enter/exit and door-toggle triggers are immediate
## regardless of this value.
@export var view_recheck_interval: float = 0.2

const REVEALED := Color(1, 1, 1, 1)
const HIDDEN := Color(1, 1, 1, 0.0)
const MAX_PORTAL_DEPTH := 2
## Vision-layer ONLY, deliberately not World too -- real walls and closed
## doors always carry the Vision bit alongside World, and a boarded
## window adds it too, so all three still correctly block a reveal
## raycast. An INTACT window carries World (it's still physically solid,
## blocking movement) but never Vision, so it deliberately does NOT block
## this raycast -- "intact windows allow visual reveal but not movement."
## A raycast against `World | Vision` (the mask every other LOS check in
## this codebase uses, e.g. ZombiePerceptionComponent/SpawnManager) would
## incorrectly treat every intact window as opaque, since it's still
## World-solid.
const VISION_MASK := 32

var _roof: CanvasItem
var _rooms: Array[Room] = []
var _player_inside: bool = false
var _current_room: Room = null
var _player: Node2D = null
var _view_recheck_timer: float = 0.0

func _ready() -> void:
	_roof = get_node_or_null(roof_node_path)
	var rooms_container: Node = get_node_or_null(rooms_container_path)
	if rooms_container:
		for child in rooms_container.get_children():
			if child is Room:
				_rooms.append(child)
				child.body_entered.connect(_on_room_body_entered.bind(child))
				child.body_exited.connect(_on_room_body_exited.bind(child))
	for door in get_tree().get_nodes_in_group("doors"):
		if door.has_signal("state_changed") and not door.state_changed.is_connected(_on_any_door_state_changed):
			door.state_changed.connect(_on_any_door_state_changed)
	set_physics_process(false) # only while the player is actually inside -- see _on_room_body_entered/exited
	_apply_states()

func _physics_process(delta: float) -> void:
	_view_recheck_timer -= delta
	if _view_recheck_timer <= 0.0:
		_view_recheck_timer = view_recheck_interval
		_apply_states()

## Cheap even for a door in a different building: `_apply_states()`
## no-ops instantly whenever `_player_inside` is false, and the district
## only has a handful of doors total.
func _on_any_door_state_changed(_is_open: bool) -> void:
	if _player_inside:
		_apply_states()

func _on_room_body_entered(body: Node, room: Room) -> void:
	_update_detectable_context(body)
	if not body.is_in_group("player"):
		return
	_player = body
	_player_inside = true
	_current_room = room
	set_physics_process(true)
	_apply_states()

func _on_room_body_exited(body: Node, room: Room) -> void:
	_update_detectable_context(body)
	if not body.is_in_group("player"):
		return
	if _current_room != room:
		return
	_current_room = _find_room_still_containing_player()
	_player_inside = _current_room != null
	if not _player_inside:
		set_physics_process(false)
	_apply_states()

## Keeps ANY entering/exiting body's DetectableComponent (Player or
## Survivor -- Room monitors both layers) current on which building/room
## it's in, independent of the player-only visual reveal above.
##
## Re-scans which room the body is ACTUALLY overlapping right now rather
## than trusting the individual signal's own room argument: a body crossing
## directly from Room A to Room B can have body_entered(B) and
## body_exited(A) fire in EITHER order within the same physics step, but
## Godot's Area2D signals are only emitted once the physics server has
## fully updated every monitored Area2D's overlap list for that step --
## so by the time ANY entered/exited handler runs, get_overlapping_bodies()
## already reflects the true final state, regardless of which particular
## signal is being handled or the order the two arrived in. Trusting that
## live state (instead of applying "entered room" / "cleared" from
## whichever signal fired) is what makes a same-frame "exited A" unable to
## clobber a same-frame "entered B".
func _update_detectable_context(body: Node) -> void:
	var detectable: DetectableComponent = body.get_node_or_null("DetectableComponent") if body is Node else null
	if detectable == null:
		return
	var actual_room: Room = null
	for room in _rooms:
		if is_instance_valid(room) and room.get_overlapping_bodies().has(body):
			actual_room = room
			break
	if actual_room != null:
		detectable.set_indoor_context(building_id, actual_room.room_id)
	elif detectable.current_building_id == building_id:
		# Only clear if THIS building most recently claimed the context --
		# if the body walked straight into a different building this same
		# frame, that building's own handler already (or will) claim it,
		# and this one clearing it out from under that would reintroduce
		# the exact ordering bug this re-scan exists to avoid.
		detectable.set_indoor_context(&"", &"")

func _find_room_still_containing_player() -> Room:
	for room in _rooms:
		for body in room.get_overlapping_bodies():
			if body.is_in_group("player"):
				return room
	return null

## Rooms hold their own floor/furniture as direct children and ARE
## themselves the CanvasItem being dimmed (Area2D is a CanvasItem) -- no
## extra "Visual" wrapper node needed.
func _apply_states() -> void:
	if _roof:
		_roof.visible = not _player_inside
	var revealed: Dictionary = {} # Room -> true
	if _player_inside and _current_room:
		revealed[_current_room] = true
		var view_dir: Vector2 = _player_view_direction()
		var half_cone_cos: float = cos(deg_to_rad(view_cone_degrees * 0.5))
		_reveal_through_portals(_current_room, _player.global_position, view_dir, half_cone_cos, 1, revealed)
	for room in _rooms:
		room.modulate = REVEALED if revealed.has(room) else HIDDEN

## Aim direction preferred; recent movement direction as the fallback
## (only actually exercised by an actor whose aim_direction reads as
## near-zero -- Player's own aim_direction never truly goes to zero since
## it retains the last nonzero InputRouter.aim_vector, so this fallback
## is mainly here for any future/test actor that doesn't maintain one).
func _player_view_direction() -> Vector2:
	if _player == null:
		return Vector2.DOWN
	if "aim_direction" in _player and (_player.aim_direction as Vector2).length() > 0.01:
		return (_player.aim_direction as Vector2).normalized()
	if "velocity" in _player and (_player.velocity as Vector2).length() > 1.0:
		return (_player.velocity as Vector2).normalized()
	return Vector2.DOWN

func _reveal_through_portals(from_room: Room, player_pos: Vector2, view_dir: Vector2, half_cone_cos: float, depth: int, revealed: Dictionary) -> void:
	if depth > MAX_PORTAL_DEPTH:
		return
	for door in from_room.doors:
		if is_instance_valid(door) and door.is_open:
			_maybe_reveal_through_portal(from_room, door.global_position, _other_room_for_door(from_room, door), player_pos, view_dir, half_cone_cos, depth, revealed)
	for window in from_room.windows:
		if is_instance_valid(window) and not window.is_boarded:
			_maybe_reveal_through_portal(from_room, window.global_position, _other_room_for_window(from_room, window), player_pos, view_dir, half_cone_cos, depth, revealed)

func _maybe_reveal_through_portal(_from_room: Room, portal_pos: Vector2, other_room: Room, player_pos: Vector2, view_dir: Vector2, half_cone_cos: float, depth: int, revealed: Dictionary) -> void:
	if other_room == null or revealed.has(other_room):
		return
	if depth == 1:
		var offset: Vector2 = portal_pos - player_pos
		if offset.length() > 1.0 and view_dir.dot(offset.normalized()) < half_cone_cos:
			return # outside the player's view cone -- first hop only, see class doc
	if not _has_line_of_sight(player_pos, portal_pos):
		return # a wall (or another closed door) stands between the player and this portal
	revealed[other_room] = true
	_reveal_through_portals(other_room, player_pos, view_dir, half_cone_cos, depth + 1, revealed)

func _other_room_for_door(room: Room, door: Door) -> Room:
	for candidate in _rooms:
		if candidate != room and candidate.doors.has(door):
			return candidate
	return null

func _other_room_for_window(room: Room, window: BuildingWindow) -> Room:
	for candidate in _rooms:
		if candidate != room and candidate.windows.has(window):
			return candidate
	return null

func _has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var space_state := get_tree().root.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, VISION_MASK)
	if _player:
		query.exclude = [_player.get_rid()]
	return space_state.intersect_ray(query).is_empty()

## For tests/debug: current exterior/interior presentation state.
func is_roof_visible() -> bool:
	return _roof == null or _roof.visible

func current_room_id() -> StringName:
	return _current_room.room_id if _current_room else &""
