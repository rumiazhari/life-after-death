class_name Clinic01
extends BuildingVisibilityController
## Waiting area (entrance) -> exam room -> medical storage (staff-only,
## reachable only through the exam room). See docs/building_system.md for
## the shared authoring pattern.

const HALF_EXTENT := Vector2(100, 70)
const WALL_TEXTURE := preload("res://assets/pixel/props/wall_plaster.png")
const INTERIOR_WALL_TEXTURE := preload("res://assets/pixel/props/wall_interior.png")
const FLOOR_TILE := &"floor_clinic"
const CHAIR_TEXTURE := preload("res://assets/pixel/props/chair.png")
const COUNTER_TEXTURE := preload("res://assets/pixel/props/counter.png")
const TABLE_TEXTURE := preload("res://assets/pixel/props/table.png")
const CABINET_TEXTURE := preload("res://assets/pixel/props/medical_cabinet.png")
const WINDOW_SCENE := preload("res://scenes/world/Window.tscn")

func _ready() -> void:
	building_id = &"clinic_01"
	roof_node_path = NodePath("Roof")
	rooms_container_path = NodePath("Rooms")
	_build_shell()
	_link_doors_to_rooms()
	super._ready()

func _build_shell() -> void:
	var entrance_gap := Rect2(Vector2(-16, HALF_EXTENT.y - 32), Vector2(32, 32))
	BuildingShellBuilder.build_perimeter_walls(self, HALF_EXTENT, WALL_TEXTURE, [entrance_gap])
	BuildingShellBuilder.build_partition(self, Vector2(-HALF_EXTENT.x, 15), Vector2(HALF_EXTENT.x, 15), INTERIOR_WALL_TEXTURE, [Rect2(Vector2(-46, 4), Vector2(32, 32))])
	BuildingShellBuilder.build_partition(self, Vector2(0, -HALF_EXTENT.y), Vector2(0, 15), INTERIOR_WALL_TEXTURE, [Rect2(Vector2(-16, -36), Vector2(32, 32))])

	var roof := TileMapLayer.new()
	roof.name = "Roof"
	roof.tile_set = PixelTilesetBuilder.get_tileset()
	roof.z_index = 5
	add_child(roof)
	BuildingShellBuilder.paint_roof(roof, HALF_EXTENT, "C")

	var waiting: Node2D = $Rooms/WaitingArea
	var exam: Node2D = $Rooms/ExamRoom
	var storage: Node2D = $Rooms/MedicalStorage
	BuildingShellBuilder.fill_floor(waiting, Vector2(HALF_EXTENT.x, 27.5), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(exam, Vector2(50.0, 42.5), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(storage, Vector2(50.0, 42.5), FLOOR_TILE)

	BuildingShellBuilder.add_physical_prop(waiting, Vector2(-70.0, 20.0), CHAIR_TEXTURE, Vector2(14, 16))
	BuildingShellBuilder.add_physical_prop(waiting, Vector2(-50.0, 20.0), CHAIR_TEXTURE, Vector2(14, 16))
	BuildingShellBuilder.add_physical_prop(waiting, Vector2(0.0, -10.0), COUNTER_TEXTURE, Vector2(48, 20))
	BuildingShellBuilder.add_physical_prop(exam, Vector2(-50.0, -35.0), TABLE_TEXTURE, Vector2(32, 20))
	BuildingShellBuilder.add_loot_furniture(
		storage, Vector2(50.0, -50.0), CABINET_TEXTURE, Vector2(20, 24),
		&"clinic_01/cabinet_1", 60.0, {"medical_supplies": 4}
	)
	BuildingShellBuilder.add_loot_furniture(
		storage, Vector2(80.0, -50.0), CABINET_TEXTURE, Vector2(20, 24),
		&"clinic_01/cabinet_2", 60.0, {"medical_supplies": 3, "materials": 2}
	)

	var window: BuildingWindow = WINDOW_SCENE.instantiate()
	window.window_id = &"clinic_01/window_1"
	window.position = Vector2(60.0, HALF_EXTENT.y)
	add_child(window)

func _link_doors_to_rooms() -> void:
	var entrance: Door = $Doors/EntranceDoor
	var exam_door: Door = $Doors/ExamDoor
	var storage_door: Door = $Doors/StorageDoor
	var waiting: Room = $Rooms/WaitingArea
	var exam: Room = $Rooms/ExamRoom
	var storage: Room = $Rooms/MedicalStorage
	waiting.doors = [entrance, exam_door]
	exam.doors = [exam_door, storage_door]
	storage.doors = [storage_door]
