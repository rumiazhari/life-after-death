class_name Apartment01
extends BuildingVisibilityController
## Shotgun-style apartment: Lobby -> Living Room -> Kitchen -> Bedroom ->
## Bathroom, each room the building's full height, divided by simple
## vertical partitions (same authoring pattern as every other building --
## see docs/building_system.md).

const HALF_EXTENT := Vector2(150, 70)
const WALL_TEXTURE := preload("res://assets/pixel/props/wall_concrete.png")
const INTERIOR_WALL_TEXTURE := preload("res://assets/pixel/props/wall_interior.png")
const FLOOR_TILE := &"floor_interior_plain"
const BENCH_TEXTURE := preload("res://assets/pixel/props/bench.png")
const TABLE_TEXTURE := preload("res://assets/pixel/props/table.png")
const CHAIR_TEXTURE := preload("res://assets/pixel/props/chair.png")
const COUNTER_TEXTURE := preload("res://assets/pixel/props/counter.png")
const FRIDGE_TEXTURE := preload("res://assets/pixel/props/fridge.png")
const BED_TEXTURE := preload("res://assets/pixel/props/bed.png")
const CABINET_TEXTURE := preload("res://assets/pixel/props/medical_cabinet.png")
const WINDOW_SCENE := preload("res://scenes/world/Window.tscn")

## Vertical partition x-positions (building-local), in room order:
## Lobby|LivingRoom, LivingRoom|Kitchen, Kitchen|Bedroom, Bedroom|Bathroom.
const PARTITION_X := [-90.0, -20.0, 40.0, 100.0]
## Each room's building-local half-extent (x, y) -- y is the same full
## HALF_EXTENT.y for every room since none of them are vertically split.
const ROOM_HALF_X := {"lobby": 30.0, "living": 35.0, "kitchen": 30.0, "bedroom": 30.0, "bathroom": 25.0}

func _ready() -> void:
	building_id = &"apartment_01"
	roof_node_path = NodePath("Roof")
	rooms_container_path = NodePath("Rooms")
	_build_shell()
	_link_doors_to_rooms()
	super._ready()

func _build_shell() -> void:
	var entrance_gap := Rect2(Vector2(-136, HALF_EXTENT.y - 16), Vector2(32, 32))
	BuildingShellBuilder.build_perimeter_walls(self, HALF_EXTENT, WALL_TEXTURE, [entrance_gap])
	for x in PARTITION_X:
		var door_gap := Rect2(Vector2(x - 16, -16), Vector2(32, 32))
		BuildingShellBuilder.build_partition(self, Vector2(x, -HALF_EXTENT.y), Vector2(x, HALF_EXTENT.y), INTERIOR_WALL_TEXTURE, [door_gap])

	var roof := TileMapLayer.new()
	roof.name = "Roof"
	roof.tile_set = PixelTilesetBuilder.get_tileset()
	roof.z_index = 5
	add_child(roof)
	BuildingShellBuilder.paint_roof(roof, HALF_EXTENT, "A")

	var lobby: Node2D = $Rooms/Lobby
	var living: Node2D = $Rooms/LivingRoom
	var kitchen: Node2D = $Rooms/Kitchen
	var bedroom: Node2D = $Rooms/Bedroom
	var bathroom: Node2D = $Rooms/Bathroom
	BuildingShellBuilder.fill_floor(lobby, Vector2(ROOM_HALF_X["lobby"], HALF_EXTENT.y), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(living, Vector2(ROOM_HALF_X["living"], HALF_EXTENT.y), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(kitchen, Vector2(ROOM_HALF_X["kitchen"], HALF_EXTENT.y), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(bedroom, Vector2(ROOM_HALF_X["bedroom"], HALF_EXTENT.y), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(bathroom, Vector2(ROOM_HALF_X["bathroom"], HALF_EXTENT.y), FLOOR_TILE)

	# All prop positions below are LOCAL to their own room node (each
	# room's own origin is its building-space center) -- see
	# docs/building_system.md's authoring pattern.
	BuildingShellBuilder.add_physical_prop(lobby, Vector2(0.0, -40.0), BENCH_TEXTURE, Vector2(32, 12))
	BuildingShellBuilder.add_physical_prop(living, Vector2(0.0, -40.0), TABLE_TEXTURE, Vector2(32, 20))
	BuildingShellBuilder.add_physical_prop(living, Vector2(-12.0, -20.0), CHAIR_TEXTURE, Vector2(14, 16))
	BuildingShellBuilder.add_physical_prop(living, Vector2(12.0, -20.0), CHAIR_TEXTURE, Vector2(14, 16))
	BuildingShellBuilder.add_physical_prop(kitchen, Vector2(0.0, -45.0), COUNTER_TEXTURE, Vector2(48, 20))
	BuildingShellBuilder.add_loot_furniture(
		kitchen, Vector2(0.0, 40.0), FRIDGE_TEXTURE, Vector2(20, 24),
		&"apartment_01/kitchen_fridge", 50.0, {"food_ration": 2, "water_bottle": 2}
	)
	BuildingShellBuilder.add_physical_prop(bedroom, Vector2(0.0, -20.0), BED_TEXTURE, Vector2(28, 40))
	BuildingShellBuilder.add_loot_furniture(
		bedroom, Vector2(15.0, 40.0), CABINET_TEXTURE, Vector2(20, 24),
		&"apartment_01/dresser", 40.0, {"materials": 2, "medical_supplies": 1}
	)
	BuildingShellBuilder.add_physical_prop(bathroom, Vector2(0.0, -45.0), COUNTER_TEXTURE, Vector2(30, 16))

	var window_living: BuildingWindow = WINDOW_SCENE.instantiate()
	window_living.window_id = &"apartment_01/window_living"
	window_living.position = Vector2(-55.0, -HALF_EXTENT.y)
	add_child(window_living)
	var window_bedroom: BuildingWindow = WINDOW_SCENE.instantiate()
	window_bedroom.window_id = &"apartment_01/window_bedroom"
	window_bedroom.position = Vector2(70.0, -HALF_EXTENT.y)
	add_child(window_bedroom)

func _link_doors_to_rooms() -> void:
	var entrance: Door = $Doors/EntranceDoor
	var lobby_living: Door = $Doors/LobbyLivingDoor
	var living_kitchen: Door = $Doors/LivingKitchenDoor
	var kitchen_bedroom: Door = $Doors/KitchenBedroomDoor
	var bedroom_bathroom: Door = $Doors/BedroomBathroomDoor
	var lobby: Room = $Rooms/Lobby
	var living: Room = $Rooms/LivingRoom
	var kitchen: Room = $Rooms/Kitchen
	var bedroom: Room = $Rooms/Bedroom
	var bathroom: Room = $Rooms/Bathroom
	lobby.doors = [entrance, lobby_living]
	living.doors = [lobby_living, living_kitchen]
	kitchen.doors = [living_kitchen, kitchen_bedroom]
	bedroom.doors = [kitchen_bedroom, bedroom_bathroom]
	bathroom.doors = [bedroom_bathroom]
