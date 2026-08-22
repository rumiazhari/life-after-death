class_name ConvenienceStore01
extends BuildingVisibilityController
## Retail floor + back room. Walls/floor/roof/furniture are built once,
## deterministically, in _build_shell() -- Rooms and Doors are hand-authored
## in the .tscn (they need stable identity/positions a script shouldn't
## silently redecide). See docs/building_system.md for the authoring
## pattern every building in scenes/world/buildings/ follows.

const HALF_EXTENT := Vector2(110, 86)
const WALL_TEXTURE := preload("res://assets/pixel/props/wall_shopfront.png")
const INTERIOR_WALL_TEXTURE := preload("res://assets/pixel/props/wall_interior.png")
const FLOOR_TILE := &"floor_store"
const SHELF_TEXTURE := preload("res://assets/pixel/props/shelf.png")
const COUNTER_TEXTURE := preload("res://assets/pixel/props/counter.png")
const FRIDGE_TEXTURE := preload("res://assets/pixel/props/fridge.png")
const WINDOW_SCENE := preload("res://scenes/world/Window.tscn")

func _ready() -> void:
	if building_id == &"":
		building_id = &"convenience_store_01"
	roof_node_path = NodePath("Roof")
	rooms_container_path = NodePath("Rooms")
	_build_shell()
	_link_doors_to_rooms()
	super._ready()

func _build_shell() -> void:
	# 64px door bays anchored half a cell west/north of each door node so the
	# carved cell pair is exactly what the closed slab seals. This footprint's
	# tile-snapped ring rows sit at y = -80 / +80 (86 is not a multiple of 32,
	# so the ring overhangs symmetrically). The entrance bay and both
	# shopfront window cells sit in the south wall run.
	var entrance_bay := Rect2(Vector2(-32, 64), Vector2(64, 32))
	var window_gaps: Array[Rect2] = [
		Rect2(Vector2(-64, 64), Vector2(32, 32)),
		Rect2(Vector2(32, 64), Vector2(32, 32)),
	]
	var perimeter_gaps: Array[Rect2] = [entrance_bay]
	perimeter_gaps.append_array(window_gaps)
	BuildingShellBuilder.build_perimeter_walls(self, HALF_EXTENT, WALL_TEXTURE, perimeter_gaps)
	# Retail/back divider straight through the middle of the 128px-tall
	# interior: each strip ends up a walkable 48px tall.
	BuildingShellBuilder.build_partition(self, Vector2(-HALF_EXTENT.x, 0), Vector2(HALF_EXTENT.x, 0), INTERIOR_WALL_TEXTURE, [Rect2(Vector2(-46, -16), Vector2(64, 32))])

	BuildingExteriorRenderer.build_authored(
		self, HALF_EXTENT, "B", &"active_shopfront", &"store", 3,
		[Vector2(0.0, 80.0)], [Vector2(-48.0, 80.0), Vector2(48.0, 80.0)]
	)

	var retail: Node2D = $Rooms/RetailFloor
	var back_room: Node2D = $Rooms/BackRoom
	BuildingShellBuilder.fill_floor(retail, Vector2(80.0, 24.0), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(back_room, Vector2(80.0, 24.0), FLOOR_TILE)

	# Room-local: $Rooms/RetailFloor sits at (16, 40) inside the building
	# (the tile-snapped ring for this footprint is asymmetric -- inner faces
	# at x=-64/+96 -- so the walkable strip's center is x=+16). Prop ids are
	# kept verbatim for WorldState persistence; positions keep the entrance
	# forecourt clear of fixtures so a player-sized body can always step
	# inside and turn.
	for shelf in [
		{"local": Vector2(-64.0, -12.0), "id": &"convenience_store_01/shelf_0"},
		{"local": Vector2(28.0, -12.0), "id": &"convenience_store_01/shelf_64"},
		{"local": Vector2(64.0, 12.0), "id": &"convenience_store_01/shelf_128"},
	]:
		BuildingShellBuilder.add_loot_furniture(
			retail, shelf["local"], SHELF_TEXTURE, Vector2(28, 12),
			shelf["id"], 60.0,
			{"food_ration": 3, "materials": 2}
		)
	BuildingShellBuilder.add_physical_prop(retail, Vector2(64.0, -12.0), COUNTER_TEXTURE, Vector2(32, 20))
	BuildingShellBuilder.add_loot_furniture(
		back_room, Vector2(56.0, 24.0), FRIDGE_TEXTURE, Vector2(20, 24),
		&"convenience_store_01/fridge", 60.0, {"water_bottle": 3, "food_ration": 2}
	)

	for wx in [-48.0, 48.0]:
		var window: BuildingWindow = WINDOW_SCENE.instantiate()
		window.window_id = StringName("convenience_store_01/window_%d" % int(wx))
		window.position = Vector2(wx, 80.0)
		add_child(window)

func _link_doors_to_rooms() -> void:
	var entrance: Door = $Doors/EntranceDoor
	var back_door: Door = $Doors/BackRoomDoor
	var retail: Room = $Rooms/RetailFloor
	var back_room: Room = $Rooms/BackRoom
	retail.doors = [entrance, back_door]
	back_room.doors = [back_door]
