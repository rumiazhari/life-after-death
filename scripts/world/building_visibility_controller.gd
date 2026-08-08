class_name BuildingVisibilityController
extends Node2D
## Toggles a building's roof visibility and interior room reveal as the
## player enters/exits. Collision is never touched by any of this -- only
## `modulate` on each room's own "Visual" child -- so fading never changes
## what blocks movement.
##
## Simplified subset of a full room-portal-graph system (see
## docs/building_system.md "Known limitations" for what a later pass would
## add): the room currently containing the player is fully revealed, a
## room sharing an OPEN door with it is also revealed, every other room in
## the SAME building stays hidden (not raycast/view-cone-checked against
## the player's aim), and the roof hides for the whole building while the
## player is anywhere inside it.

@export var building_id: StringName = &""
@export var roof_node_path: NodePath
@export var rooms_container_path: NodePath = NodePath("Rooms")

const REVEALED := Color(1, 1, 1, 1)
const HIDDEN := Color(1, 1, 1, 0.0)

var _roof: CanvasItem
var _rooms: Array[Room] = []
var _player_inside: bool = false
var _current_room: Room = null

func _ready() -> void:
	_roof = get_node_or_null(roof_node_path)
	var rooms_container: Node = get_node_or_null(rooms_container_path)
	if rooms_container:
		for child in rooms_container.get_children():
			if child is Room:
				_rooms.append(child)
				child.body_entered.connect(_on_room_body_entered.bind(child))
				child.body_exited.connect(_on_room_body_exited.bind(child))
	_apply_states()

func _on_room_body_entered(body: Node, room: Room) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = true
	_current_room = room
	_apply_states()

func _on_room_body_exited(body: Node, room: Room) -> void:
	if not body.is_in_group("player"):
		return
	if _current_room != room:
		return
	_current_room = _find_room_still_containing_player()
	_player_inside = _current_room != null
	_apply_states()

func _find_room_still_containing_player() -> Room:
	for room in _rooms:
		for body in room.get_overlapping_bodies():
			if body.is_in_group("player"):
				return room
	return null

## Rooms hold their own floor/furniture as direct children and ARE
## themselves the CanvasItem being dimmed (Area2D is a CanvasItem) --
## no extra "Visual" wrapper node needed. A non-current room reveals only
## if it shares an OPEN door with the current room; a closed door (or no
## shared door at all) keeps it hidden, never merely dimmed, matching
## "rooms behind closed opaque doors remain hidden."
func _apply_states() -> void:
	if _roof:
		_roof.visible = not _player_inside
	for room in _rooms:
		if room == _current_room:
			room.modulate = REVEALED
		elif _player_inside and _current_room != null and _shares_open_door(_current_room, room):
			room.modulate = REVEALED
		else:
			room.modulate = HIDDEN

func _shares_open_door(a: Room, b: Room) -> bool:
	for door in a.doors:
		if door in b.doors and is_instance_valid(door) and door.is_open:
			return true
	return false

## For tests/debug: current exterior/interior presentation state.
func is_roof_visible() -> bool:
	return _roof == null or _roof.visible

func current_room_id() -> StringName:
	return _current_room.room_id if _current_room else &""
