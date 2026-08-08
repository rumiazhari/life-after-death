class_name ConvenienceStore01
extends BuildingVisibilityController
## Retail floor + back room. Walls/floor/roof/furniture are built once,
## deterministically, in _build_shell() -- Rooms and Doors are hand-authored
## in the .tscn (they need stable identity/positions a script shouldn't
## silently redecide). See docs/building_system.md for the authoring
## pattern every building in scenes/world/buildings/ follows.

const HALF_EXTENT := Vector2(110, 75)
const WALL_TEXTURE := preload("res://assets/pixel/props/wall_shopfront.png")
const INTERIOR_WALL_TEXTURE := preload("res://assets/pixel/props/wall_interior.png")
const FLOOR_TILE := &"floor_store"
const SHELF_TEXTURE := preload("res://assets/pixel/props/shelf.png")
const COUNTER_TEXTURE := preload("res://assets/pixel/props/counter.png")
const FRIDGE_TEXTURE := preload("res://assets/pixel/props/fridge.png")
const WINDOW_SCENE := preload("res://scenes/world/Window.tscn")

func _ready() -> void:
	building_id = &"convenience_store_01"
	roof_node_path = NodePath("Roof")
	rooms_container_path = NodePath("Rooms")
	_build_shell()
	_link_doors_to_rooms()
	super._ready()

func _build_shell() -> void:
	var entrance_gap := Rect2(Vector2(-16, HALF_EXTENT.y - 32), Vector2(32, 32))
	BuildingShellBuilder.build_perimeter_walls(self, HALF_EXTENT, WALL_TEXTURE, [entrance_gap])
	BuildingShellBuilder.build_partition(self, Vector2(-HALF_EXTENT.x, 20), Vector2(HALF_EXTENT.x, 20), INTERIOR_WALL_TEXTURE, [Rect2(Vector2(-16, 4), Vector2(32, 32))])

	var roof := TileMapLayer.new()
	roof.name = "Roof"
	roof.tile_set = PixelTilesetBuilder.get_tileset()
	roof.z_index = 5
	add_child(roof)
	BuildingShellBuilder.paint_roof(roof, HALF_EXTENT, "B")

	var retail: Node2D = $Rooms/RetailFloor
	var back_room: Node2D = $Rooms/BackRoom
	BuildingShellBuilder.fill_floor(retail, Vector2(HALF_EXTENT.x, 47.5), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(back_room, Vector2(HALF_EXTENT.x, 27.5), FLOOR_TILE)

	for wx in [-64.0, 0.0, 64.0]:
		BuildingShellBuilder.add_loot_furniture(
			retail, Vector2(wx, -50.0), SHELF_TEXTURE, Vector2(28, 12),
			StringName("convenience_store_01/shelf_%d" % int(wx + 64)), 60.0,
			{"food_ration": 3, "materials": 2}
		)
	BuildingShellBuilder.add_physical_prop(retail, Vector2(60.0, 10.0), COUNTER_TEXTURE, Vector2(48, 20))
	BuildingShellBuilder.add_loot_furniture(
		back_room, Vector2(0.0, 20.0), FRIDGE_TEXTURE, Vector2(20, 24),
		&"convenience_store_01/fridge", 60.0, {"water_bottle": 3, "food_ration": 2}
	)

	for wx in [-55.0, 55.0]:
		var window: BuildingWindow = WINDOW_SCENE.instantiate()
		window.window_id = StringName("convenience_store_01/window_%d" % int(wx))
		window.position = Vector2(wx, HALF_EXTENT.y)
		add_child(window)

func _link_doors_to_rooms() -> void:
	var entrance: Door = $Doors/EntranceDoor
	var back_door: Door = $Doors/BackRoomDoor
	var retail: Room = $Rooms/RetailFloor
	var back_room: Room = $Rooms/BackRoom
	retail.doors = [entrance, back_door]
	back_room.doors = [back_door]
