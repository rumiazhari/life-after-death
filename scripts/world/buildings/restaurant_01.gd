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
	building_id = &"restaurant_01"
	roof_node_path = NodePath("Roof")
	rooms_container_path = NodePath("Rooms")
	_build_shell()
	_link_doors_to_rooms()
	super._ready()

func _build_shell() -> void:
	var entrance_gap := Rect2(Vector2(-16, HALF_EXTENT.y - 32), Vector2(32, 32))
	var service_gap := Rect2(Vector2(44, -HALF_EXTENT.y), Vector2(32, 32))
	BuildingShellBuilder.build_perimeter_walls(self, HALF_EXTENT, WALL_TEXTURE, [entrance_gap, service_gap])
	BuildingShellBuilder.build_partition(self, Vector2(-HALF_EXTENT.x, 20), Vector2(HALF_EXTENT.x, 20), INTERIOR_WALL_TEXTURE, [Rect2(Vector2(-76, 4), Vector2(32, 32))])
	BuildingShellBuilder.build_partition(self, Vector2(0, -HALF_EXTENT.y), Vector2(0, 20), INTERIOR_WALL_TEXTURE, [Rect2(Vector2(-16, -51), Vector2(32, 32))])

	var roof := TileMapLayer.new()
	roof.name = "Roof"
	roof.tile_set = PixelTilesetBuilder.get_tileset()
	roof.z_index = 5
	add_child(roof)
	BuildingShellBuilder.paint_roof(roof, HALF_EXTENT, "A")

	var dining: Node2D = $Rooms/DiningRoom
	var kitchen: Node2D = $Rooms/Kitchen
	var pantry: Node2D = $Rooms/Pantry
	BuildingShellBuilder.fill_floor(dining, Vector2(120.0, 35.0), FLOOR_DINING)
	BuildingShellBuilder.fill_floor(kitchen, Vector2(60.0, 55.0), FLOOR_KITCHEN)
	BuildingShellBuilder.fill_floor(pantry, Vector2(60.0, 55.0), FLOOR_KITCHEN)

	for tx in [-70.0, 0.0, 70.0]:
		BuildingShellBuilder.add_physical_prop(dining, Vector2(tx, 40.0), TABLE_TEXTURE, Vector2(32, 20))
		BuildingShellBuilder.add_physical_prop(dining, Vector2(tx - 10.0, 62.0), CHAIR_TEXTURE, Vector2(14, 16))
		BuildingShellBuilder.add_physical_prop(dining, Vector2(tx + 10.0, 62.0), CHAIR_TEXTURE, Vector2(14, 16))

	BuildingShellBuilder.add_physical_prop(kitchen, Vector2(-60.0, -60.0), COUNTER_TEXTURE, Vector2(48, 20))
	BuildingShellBuilder.add_loot_furniture(
		kitchen, Vector2(-90.0, -10.0), FRIDGE_TEXTURE, Vector2(20, 24),
		&"restaurant_01/kitchen_fridge", 60.0, {"food_ration": 4}
	)
	BuildingShellBuilder.add_loot_furniture(
		pantry, Vector2(90.0, -10.0), SHELF_TEXTURE, Vector2(28, 12),
		&"restaurant_01/pantry_shelf_1", 60.0, {"food_ration": 3, "water_bottle": 2}
	)
	BuildingShellBuilder.add_loot_furniture(
		pantry, Vector2(90.0, -60.0), SHELF_TEXTURE, Vector2(28, 12),
		&"restaurant_01/pantry_shelf_2", 60.0, {"materials": 4}
	)

	var window: BuildingWindow = WINDOW_SCENE.instantiate()
	window.window_id = &"restaurant_01/window_1"
	window.position = Vector2(-60.0, HALF_EXTENT.y)
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
