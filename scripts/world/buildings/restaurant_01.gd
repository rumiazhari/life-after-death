class_name Restaurant01
extends BuildingVisibilityController
## Dining room (entrance) -> kitchen -> pantry (also reachable from
## outside via a north service door). See docs/building_system.md for the
## shared authoring pattern.

const HALF_EXTENT := Vector2(120, 90)
const WALL_TEXTURE := preload("res://assets/pixel/props/wall_brick.png")
const INTERIOR_WALL_TEXTURE := preload("res://assets/pixel/props/wall_interior.png")
const FLOOR_DINING := &"floor_restaurant"
const FLOOR_KITCHEN := &"floor_kitchen"
const TABLE_TEXTURE := preload("res://assets/pixel/props/table.png")
const CHAIR_TEXTURE := preload("res://assets/pixel/props/chair.png")
const COUNTER_TEXTURE := preload("res://assets/pixel/props/counter.png")
const FRIDGE_TEXTURE := preload("res://assets/pixel/props/fridge.png")
const SHELF_TEXTURE := preload("res://assets/pixel/props/shelf.png")
const WINDOW_SCENE := preload("res://scenes/world/Window.tscn")

func _ready() -> void:
	if building_id == &"":
		building_id = &"restaurant_01"
	roof_node_path = NodePath("Roof")
	rooms_container_path = NodePath("Rooms")
	_build_shell()
	_link_doors_to_rooms()
	super._ready()

func _build_shell() -> void:
	# 64px door bays anchored half a cell west/north of each door node so the
	# carved cell pair is exactly what the closed slab seals. Ring rows for
	# this footprint snap to y = -80 / +80; the dining-room south window
	# replaces its whole perimeter wall cell.
	var entrance_bay := Rect2(Vector2(-32, 64), Vector2(64, 32))
	var service_bay := Rect2(Vector2(32, -96), Vector2(64, 32))
	var window_gap := Rect2(Vector2(-64, 64), Vector2(32, 32))
	BuildingShellBuilder.build_perimeter_walls(self, HALF_EXTENT, WALL_TEXTURE, [entrance_bay, service_bay, window_gap])
	BuildingShellBuilder.build_partition(self, Vector2(-HALF_EXTENT.x, 20), Vector2(HALF_EXTENT.x, 20), INTERIOR_WALL_TEXTURE, [Rect2(Vector2(-88, 4), Vector2(64, 32))])
	BuildingShellBuilder.build_partition(self, Vector2(0, -HALF_EXTENT.y), Vector2(0, 20), INTERIOR_WALL_TEXTURE, [Rect2(Vector2(-16, -58), Vector2(32, 64))])

	BuildingExteriorRenderer.build_authored(
		self, HALF_EXTENT, "A", &"active_shopfront", &"restaurant", 3,
		[Vector2(0.0, 80.0)]
	)

	var dining: Node2D = $Rooms/DiningRoom
	var kitchen: Node2D = $Rooms/Kitchen
	var pantry: Node2D = $Rooms/Pantry
	BuildingShellBuilder.fill_floor(dining, Vector2(120.0, 35.0), FLOOR_DINING)
	BuildingShellBuilder.fill_floor(kitchen, Vector2(60.0, 55.0), FLOOR_KITCHEN)
	BuildingShellBuilder.fill_floor(pantry, Vector2(60.0, 55.0), FLOOR_KITCHEN)

	# Every position below is LOCAL TO ITS ROOM NODE, and each of the three
	# room nodes carries its own offset inside the building (DiningRoom
	# (0,55), Kitchen (-60,-35), Pantry (60,-35) -- see Restaurant01.tscn).
	# These were previously written as if they were building-local, which
	# put the whole dining set, the fridge and both pantry shelves OUTSIDE
	# the restaurant's own walls -- the chairs landed on the street directly
	# in front of the entrance and made the front door impassable. The
	# district's landmark-reachability test now asserts that doorway stays
	# walkable.
	#
	# One table set flanking the east wall: the dining strip between the
	# partition (inner face y=36) and the south wall band is shallow, and a
	# second set on the west side used to sit squarely inside the
	# kitchen-door approach corridor, blocking that doorway entirely. The
	# whole west half now stays clear for entrance <-> kitchen circulation.
	var tx := 70.0
	BuildingShellBuilder.add_physical_prop(dining, Vector2(tx, -15.0), TABLE_TEXTURE, Vector2(32, 20))
	BuildingShellBuilder.add_physical_prop(dining, Vector2(tx - 14.0, 0.0), CHAIR_TEXTURE, Vector2(14, 16))
	BuildingShellBuilder.add_physical_prop(dining, Vector2(tx + 14.0, 0.0), CHAIR_TEXTURE, Vector2(14, 16))

	# Shifted east of its old spot so it no longer pokes into the west-wall
	# band or the kitchen doorway's approach cone.
	# Counter hugs the kitchen's north wall and the fridge its west wall --
	# both moved off the room's center node so neither sits inside the
	# kitchen<->dining or kitchen<->pantry circulation lanes.
	BuildingShellBuilder.add_physical_prop(kitchen, Vector2(4.0, -17.0), COUNTER_TEXTURE, Vector2(48, 20))
	BuildingShellBuilder.add_loot_furniture(
		kitchen, Vector2(-26.0, 25.0), FRIDGE_TEXTURE, Vector2(20, 24),
		&"restaurant_01/kitchen_fridge", 60.0, {"food_ration": 4}
	)
	BuildingShellBuilder.add_loot_furniture(
		pantry, Vector2(20.0, 29.0), SHELF_TEXTURE, Vector2(28, 12),
		&"restaurant_01/pantry_shelf_1", 60.0, {"food_ration": 3, "water_bottle": 2}
	)
	BuildingShellBuilder.add_loot_furniture(
		pantry, Vector2(20.0, -21.0), SHELF_TEXTURE, Vector2(28, 12),
		&"restaurant_01/pantry_shelf_2", 60.0, {"materials": 4}
	)

	var window: BuildingWindow = WINDOW_SCENE.instantiate()
	window.window_id = &"restaurant_01/window_1"
	window.position = Vector2(-48.0, 80.0)
	add_child(window)

	_build_patio()

## Fixed outdoor tables/chairs just south of the entrance -- physical
## obstacles only, not inside any Room (no interior visibility to manage
## for outdoor furniture).
func _build_patio() -> void:
	for i in range(2):
		var tx: float = -50.0 + i * 100.0
		var ty: float = HALF_EXTENT.y + 40.0
		BuildingShellBuilder.add_physical_prop(self, Vector2(tx, ty), TABLE_TEXTURE, Vector2(32, 20))
		BuildingShellBuilder.add_physical_prop(self, Vector2(tx - 10.0, ty + 18.0), CHAIR_TEXTURE, Vector2(14, 16))
		BuildingShellBuilder.add_physical_prop(self, Vector2(tx + 10.0, ty + 18.0), CHAIR_TEXTURE, Vector2(14, 16))

func _link_doors_to_rooms() -> void:
	var entrance: Door = $Doors/EntranceDoor
	var kitchen_door: Door = $Doors/KitchenDoor
	var pantry_door: Door = $Doors/PantryDoor
	var service_door: Door = $Doors/ServiceDoor
	var dining: Room = $Rooms/DiningRoom
	var kitchen: Room = $Rooms/Kitchen
	var pantry: Room = $Rooms/Pantry
	dining.doors = [entrance, kitchen_door]
	kitchen.doors = [kitchen_door, pantry_door]
	pantry.doors = [pantry_door, service_door]
