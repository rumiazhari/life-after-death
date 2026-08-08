class_name Room
extends Area2D
## One room within a building -- an Area2D whose bounds define "the player
## (or a survivor) is in this room." `room_id`/`building_id` are stable
## authored identifiers (see docs/building_system.md for the naming
## convention). Monitors Player AND Survivor layers: visual roof/room
## reveal (BuildingVisibilityController) is still player-only, but a
## Survivor entering/leaving is also used to keep its DetectableComponent's
## indoor context current -- see building_visibility_controller.gd
## "_update_detectable_context."

const LAYER_PLAYER := 2
const LAYER_SURVIVOR := 16

@export var room_id: StringName = &""
@export var building_id: StringName = &""
## Doors bordering this room (assigned by the owning building script/scene).
## Two rooms are considered visually connected exactly when they share one
## of these AND it's currently open -- see BuildingVisibilityController.
var doors: Array[Door] = []
## Windows bordering this room, same authored-assignment convention as
## doors -- a window shared by two rooms (both list it) is a portal too,
## open whenever the window is intact (not boarded). None of the current
## buildings author an interior-facing window (every BuildingWindow so far
## only borders the exterior), so this stays empty for them in practice;
## the portal-graph code path is generic and ready for one that does.
var windows: Array[BuildingWindow] = []

func _ready() -> void:
	add_to_group("rooms")
	collision_layer = 0
	collision_mask = LAYER_PLAYER | LAYER_SURVIVOR
	monitoring = true

## Global-space bounding rectangle, read directly from this Room's own
## RectangleShape2D (every authored Room uses one) -- a cheap point-in-room
## test (`get_bounds_rect().has_point(p)`) for callers that need "is this
## position inside this room" without waiting on an actual physics overlap
## (e.g. SpawnManager rejecting a candidate that falls inside the player's
## current room, or a portal-visibility check).
func get_bounds_rect() -> Rect2:
	var shape_node: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if shape_node == null or not (shape_node.shape is RectangleShape2D):
		return Rect2(global_position, Vector2.ZERO)
	var size: Vector2 = (shape_node.shape as RectangleShape2D).size
	return Rect2(global_position - size * 0.5, size)

## The Room currently containing `body` (typically the player), or null.
## Iterates the "rooms" group rather than requiring a caller to know which
## building it's in -- with only a handful of rooms per building this
## stays cheap.
static func room_containing(body: Node) -> Room:
	for room in Engine.get_main_loop().get_nodes_in_group("rooms"):
		if room.get_overlapping_bodies().has(body):
			return room
	return null
