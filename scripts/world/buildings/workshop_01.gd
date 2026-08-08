class_name Workshop01
extends BuildingVisibilityController
## Loading Bay (west service entrance) -> Work Floor (main public entrance,
## south) -> Storage -> Office, in a row, divided by simple vertical
## partitions -- same authoring pattern as every other building, see
## docs/building_system.md.

const HALF_EXTENT := Vector2(150, 90)
const WALL_TEXTURE := preload("res://assets/pixel/props/wall_concrete.png")
const INTERIOR_WALL_TEXTURE := preload("res://assets/pixel/props/wall_interior.png")
const FLOOR_TILE := &"floor_interior_plain"
const COUNTER_TEXTURE := preload("res://assets/pixel/props/counter.png")
const TABLE_TEXTURE := preload("res://assets/pixel/props/table.png")
const CHAIR_TEXTURE := preload("res://assets/pixel/props/chair.png")
const SHELF_TEXTURE := preload("res://assets/pixel/props/shelf.png")
const CRATE_TEXTURE := preload("res://assets/pixel/props/crate.png")
const PALLET_TEXTURE := preload("res://assets/pixel/props/pallet.png")
const CABINET_TEXTURE := preload("res://assets/pixel/props/medical_cabinet.png")
const WINDOW_SCENE := preload("res://scenes/world/Window.tscn")

## Vertical partition x-positions (building-local), in room order:
## LoadingBay|WorkFloor, WorkFloor|Storage, Storage|Office.
const PARTITION_X := [-100.0, 40.0, 110.0]
const ROOM_HALF_X := {"loading": 25.0, "work": 70.0, "storage": 35.0, "office": 20.0}

func _ready() -> void:
	building_id = &"workshop_01"
	roof_node_path = NodePath("Roof")
	rooms_container_path = NodePath("Rooms")
	_build_shell()
	_link_doors_to_rooms()
	super._ready()

func _build_shell() -> void:
	var entrance_gap := Rect2(Vector2(-46.0, HALF_EXTENT.y - 32.0), Vector2(32, 32)) # WorkFloor's own south wall (center x = -30)
	var service_gap := Rect2(Vector2(-HALF_EXTENT.x, -16.0), Vector2(32, 32)) # LoadingBay's west wall
	BuildingShellBuilder.build_perimeter_walls(self, HALF_EXTENT, WALL_TEXTURE, [entrance_gap, service_gap])
	for x in PARTITION_X:
		var door_gap := Rect2(Vector2(x - 16.0, -16.0), Vector2(32, 32))
		BuildingShellBuilder.build_partition(self, Vector2(x, -HALF_EXTENT.y), Vector2(x, HALF_EXTENT.y), INTERIOR_WALL_TEXTURE, [door_gap])

	var roof := TileMapLayer.new()
	roof.name = "Roof"
	roof.tile_set = PixelTilesetBuilder.get_tileset()
	roof.z_index = 5
	add_child(roof)
	BuildingShellBuilder.paint_roof(roof, HALF_EXTENT, "D")

	var loading: Node2D = $Rooms/LoadingBay
	var work: Node2D = $Rooms/WorkFloor
	var storage: Node2D = $Rooms/Storage
	var office: Node2D = $Rooms/Office
	BuildingShellBuilder.fill_floor(loading, Vector2(ROOM_HALF_X["loading"], HALF_EXTENT.y), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(work, Vector2(ROOM_HALF_X["work"], HALF_EXTENT.y), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(storage, Vector2(ROOM_HALF_X["storage"], HALF_EXTENT.y), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(office, Vector2(ROOM_HALF_X["office"], HALF_EXTENT.y), FLOOR_TILE)

	# All prop positions below are LOCAL to their own room node.
	BuildingShellBuilder.add_physical_prop(loading, Vector2(0.0, -50.0), PALLET_TEXTURE, Vector2(28, 20))
	BuildingShellBuilder.add_salvage_prop(loading, Vector2(0.0, 40.0), CRATE_TEXTURE, Vector2(24, 20), &"workshop_01/loading_crate", 3)

	BuildingShellBuilder.add_physical_prop(work, Vector2(-30.0, -55.0), COUNTER_TEXTURE, Vector2(56, 20))
	BuildingShellBuilder.add_physical_prop(work, Vector2(20.0, 0.0), TABLE_TEXTURE, Vector2(32, 20))
	BuildingShellBuilder.add_physical_prop(work, Vector2(20.0, 20.0), CHAIR_TEXTURE, Vector2(14, 16))

	BuildingShellBuilder.add_loot_furniture(
		storage, Vector2(0.0, -55.0), SHELF_TEXTURE, Vector2(28, 12),
		&"workshop_01/storage_shelf_1", 80.0, {"materials": 5}
	)
	BuildingShellBuilder.add_loot_furniture(
		storage, Vector2(0.0, -20.0), SHELF_TEXTURE, Vector2(28, 12),
		&"workshop_01/storage_shelf_2", 80.0, {"materials": 3, "ammunition": 4}
	)
	BuildingShellBuilder.add_salvage_prop(storage, Vector2(0.0, 40.0), CRATE_TEXTURE, Vector2(24, 20), &"workshop_01/storage_crate", 4)

	BuildingShellBuilder.add_physical_prop(office, Vector2(0.0, -55.0), TABLE_TEXTURE, Vector2(32, 20))
	BuildingShellBuilder.add_loot_furniture(
		office, Vector2(0.0, 40.0), CABINET_TEXTURE, Vector2(20, 24),
		&"workshop_01/office_cabinet", 40.0, {"materials": 2, "ammunition": 2}
	)

	var window: BuildingWindow = WINDOW_SCENE.instantiate()
	window.window_id = &"workshop_01/window_office"
	window.position = Vector2(130.0, -HALF_EXTENT.y)
	add_child(window)

func _link_doors_to_rooms() -> void:
	var entrance: Door = $Doors/EntranceDoor
	var service: Door = $Doors/ServiceDoor
	var loading_work: Door = $Doors/LoadingWorkDoor
	var work_storage: Door = $Doors/WorkStorageDoor
	var storage_office: Door = $Doors/StorageOfficeDoor
	var loading: Room = $Rooms/LoadingBay
	var work: Room = $Rooms/WorkFloor
	var storage: Room = $Rooms/Storage
	var office: Room = $Rooms/Office
	loading.doors = [service, loading_work]
	work.doors = [entrance, loading_work, work_storage]
	storage.doors = [work_storage, storage_office]
	office.doors = [storage_office]
