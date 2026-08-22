class_name Workshop01
extends BuildingVisibilityController
## Loading Bay (west service entrance) -> Work Floor (main public entrance,
## south) -> Storage -> Office, in a row, divided by simple vertical
## partitions -- same authoring pattern as every other building, see
## docs/building_system.md.

const HALF_EXTENT := Vector2(176, 90)
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
## LoadingBay|WorkFloor, WorkFloor|Storage, Storage|Office. The 384px-wide
## interior (inner faces at +-160 for this footprint) splits into four
## walkable lanes -- every lane is at least 48px clear, comfortably wider
## than the player's 32px collider (the old 300px-wide footprint left the
## loading bay a 12px and the office a 2px sliver).
const PARTITION_X := [-96.0, 16.0, 96.0]
const ROOM_HALF_X := {"loading": 24.0, "work": 40.0, "storage": 24.0, "office": 24.0}

func _ready() -> void:
	if building_id == &"":
		building_id = &"workshop_01"
	roof_node_path = NodePath("Roof")
	rooms_container_path = NodePath("Rooms")
	_build_shell()
	_link_doors_to_rooms()
	super._ready()

func _build_shell() -> void:
	# 64px door bays anchored half a cell west/north of each door node, so the
	# carved cell pair is exactly what the closed slab seals. Ring rows snap
	# to y = -80 / +80; ring columns sit at +-176 (inner faces +-160). The
	# office window replaces its whole north-wall cell.
	var entrance_bay := Rect2(Vector2(-64, 64), Vector2(64, 32)) # WorkFloor's own south wall (bay center x = -32)
	var service_bay := Rect2(Vector2(-192, -32), Vector2(32, 64)) # LoadingBay's west wall
	var office_window_gap := Rect2(Vector2(128, -96), Vector2(32, 32))
	var perimeter_gaps: Array[Rect2] = [entrance_bay, service_bay, office_window_gap]
	BuildingShellBuilder.build_perimeter_walls(self, HALF_EXTENT, WALL_TEXTURE, perimeter_gaps)
	# Partitions span only the interior (inner wall faces at y = +-64); each
	# door bay carves their middle two of four cells, leaving real wall
	# stubs above and below every doorway.
	for x in PARTITION_X:
		var door_gap := Rect2(Vector2(x - 16, -32), Vector2(32, 64))
		BuildingShellBuilder.build_partition(self, Vector2(x, -64), Vector2(x, 64), INTERIOR_WALL_TEXTURE, [door_gap])

	BuildingExteriorRenderer.build_authored(
		self, HALF_EXTENT, "D", &"masonry_industrial", &"workshop", 2,
		[Vector2(-32.0, 80.0)]
	)

	var loading: Node2D = $Rooms/LoadingBay
	var work: Node2D = $Rooms/WorkFloor
	var storage: Node2D = $Rooms/Storage
	var office: Node2D = $Rooms/Office
	BuildingShellBuilder.fill_floor(loading, Vector2(ROOM_HALF_X["loading"], HALF_EXTENT.y), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(work, Vector2(ROOM_HALF_X["work"], HALF_EXTENT.y), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(storage, Vector2(ROOM_HALF_X["storage"], HALF_EXTENT.y), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(office, Vector2(ROOM_HALF_X["office"], HALF_EXTENT.y), FLOOR_TILE)

	# All prop positions below are LOCAL to their own room node, kept off the
	# room-origin clearance zones and out of every widened door-bay approach.
	BuildingShellBuilder.add_physical_prop(loading, Vector2(0.0, -50.0), PALLET_TEXTURE, Vector2(28, 20))
	BuildingShellBuilder.add_salvage_prop(loading, Vector2(0.0, 40.0), CRATE_TEXTURE, Vector2(24, 20), &"workshop_01/loading_crate", 3)

	BuildingShellBuilder.add_physical_prop(work, Vector2(-12.0, -54.0), COUNTER_TEXTURE, Vector2(56, 20))
	BuildingShellBuilder.add_physical_prop(work, Vector2(20.0, 28.0), TABLE_TEXTURE, Vector2(32, 20))
	BuildingShellBuilder.add_physical_prop(work, Vector2(26.0, 46.0), CHAIR_TEXTURE, Vector2(14, 16))

	BuildingShellBuilder.add_loot_furniture(
		storage, Vector2(0.0, -55.0), SHELF_TEXTURE, Vector2(28, 12),
		&"workshop_01/storage_shelf_1", 80.0, {"materials": 5}
	)
	BuildingShellBuilder.add_loot_furniture(
		storage, Vector2(0.0, -26.0), SHELF_TEXTURE, Vector2(28, 12),
		&"workshop_01/storage_shelf_2", 80.0, {"materials": 3, "ammunition": 4}
	)
	BuildingShellBuilder.add_salvage_prop(storage, Vector2(0.0, 40.0), CRATE_TEXTURE, Vector2(24, 20), &"workshop_01/storage_crate", 4)

	BuildingShellBuilder.add_physical_prop(office, Vector2(0.0, -54.0), TABLE_TEXTURE, Vector2(32, 20))
	BuildingShellBuilder.add_loot_furniture(
		office, Vector2(0.0, 40.0), CABINET_TEXTURE, Vector2(20, 24),
		&"workshop_01/office_cabinet", 40.0, {"materials": 2, "ammunition": 2}
	)

	# The office window replaces its whole perimeter wall cell (carved via
	# office_window_gap above): solid to movement, Vision-transparent while
	# intact, flush inside the wall run.
	var window: BuildingWindow = WINDOW_SCENE.instantiate()
	window.window_id = &"workshop_01/window_office"
	window.position = Vector2(144.0, -80.0)
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
