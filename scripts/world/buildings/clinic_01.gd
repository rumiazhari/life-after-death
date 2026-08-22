class_name Clinic01
extends BuildingVisibilityController
## Waiting area (entrance, full-width south strip) -> exam room -> medical
## storage (staff-only, reached through the exam room across the dividing
## partition). See docs/building_system.md for the shared authoring pattern.
##
## Geometry contract used throughout: the tile-snapped wall ring for
## HALF_EXTENT (100, 86) has its extreme row/column centers at +-80, the
## interior spans (-64..64) in both axes, every door bay is the runtime-
## standard 64px transverse aperture anchored half a cell west/north of its
## door node, and the window replaces its whole perimeter wall cell.

const HALF_EXTENT := Vector2(100, 86)
const WALL_TEXTURE := preload("res://assets/pixel/props/wall_plaster.png")
const INTERIOR_WALL_TEXTURE := preload("res://assets/pixel/props/wall_interior.png")
const FLOOR_TILE := &"floor_clinic"
const CHAIR_TEXTURE := preload("res://assets/pixel/props/chair.png")
const COUNTER_TEXTURE := preload("res://assets/pixel/props/counter.png")
const TABLE_TEXTURE := preload("res://assets/pixel/props/table.png")
const CABINET_TEXTURE := preload("res://assets/pixel/props/medical_cabinet.png")
const WINDOW_SCENE := preload("res://scenes/world/Window.tscn")

func _ready() -> void:
	if building_id == &"":
		building_id = &"clinic_01"
	roof_node_path = NodePath("Roof")
	rooms_container_path = NodePath("Rooms")
	_build_shell()
	_link_doors_to_rooms()
	super._ready()

func _build_shell() -> void:
	# Ring rows for this footprint snap to y = -80 / +80. The entrance bay
	# and the window cell both sit in the south wall run.
	var entrance_bay := Rect2(Vector2(-32, 64), Vector2(64, 32))
	var window_gap := Rect2(Vector2(32, 64), Vector2(32, 32))
	BuildingShellBuilder.build_perimeter_walls(self, HALF_EXTENT, WALL_TEXTURE, [entrance_bay, window_gap])
	# Waiting/exam divider straight through the middle of the interior; the
	# exam/storage divider runs from the north wall's inner face (y=-64 for
	# this footprint) down to the divider, so no partition cell duplicates a
	# perimeter wall body and the storage-door bay stays clear of the ring.
	BuildingShellBuilder.build_partition(self, Vector2(-HALF_EXTENT.x, 0), Vector2(HALF_EXTENT.x, 0), INTERIOR_WALL_TEXTURE, [Rect2(Vector2(-68, -16), Vector2(64, 32))])
	BuildingShellBuilder.build_partition(self, Vector2(0, -64), Vector2(0, 0), INTERIOR_WALL_TEXTURE, [Rect2(Vector2(-16, -64), Vector2(32, 64))])

	BuildingExteriorRenderer.build_authored(
		self, HALF_EXTENT, "C", &"painted_plaster", &"clinic", 3,
		[Vector2(0.0, 80.0)], [Vector2(48.0, 80.0)]
	)

	var waiting: Node2D = $Rooms/WaitingArea
	var exam: Node2D = $Rooms/ExamRoom
	var storage: Node2D = $Rooms/MedicalStorage
	BuildingShellBuilder.fill_floor(waiting, Vector2(64.0, 32.0), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(exam, Vector2(32.0, 32.0), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(storage, Vector2(32.0, 32.0), FLOOR_TILE)

	# All prop positions below are LOCAL to their own room node, and every
	# room node sits at the center of its actual walkable quadrant -- see
	# Clinic01.tscn. Positions were chosen so none of them intrudes into a
	# door bay or the approach corridor in front of one.
	BuildingShellBuilder.add_physical_prop(waiting, Vector2(-52.0, 16.0), CHAIR_TEXTURE, Vector2(14, 16))
	BuildingShellBuilder.add_physical_prop(waiting, Vector2(-36.0, 16.0), CHAIR_TEXTURE, Vector2(14, 16))
	BuildingShellBuilder.add_physical_prop(waiting, Vector2(40.0, 12.0), COUNTER_TEXTURE, Vector2(32, 20))
	# Tucked into the far NW corner so the doorway diagonal and the
	# storage-door approach both stay clear.
	BuildingShellBuilder.add_physical_prop(exam, Vector2(-44.0, -22.0), TABLE_TEXTURE, Vector2(24, 16))
	BuildingShellBuilder.add_loot_furniture(
		storage, Vector2(46.0, -20.0), CABINET_TEXTURE, Vector2(20, 24),
		&"clinic_01/cabinet_1", 60.0, {"medical_supplies": 4}
	)
	BuildingShellBuilder.add_loot_furniture(
		storage, Vector2(46.0, 8.0), CABINET_TEXTURE, Vector2(20, 24),
		&"clinic_01/cabinet_2", 60.0, {"medical_supplies": 3, "materials": 2}
	)

	var window: BuildingWindow = WINDOW_SCENE.instantiate()
	window.window_id = &"clinic_01/window_1"
	window.position = Vector2(48.0, 80.0)
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
