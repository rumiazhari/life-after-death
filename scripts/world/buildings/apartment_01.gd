class_name Apartment01
extends BuildingVisibilityController
## Shotgun-style apartment: Lobby -> Living Room / Kitchen -> Bedroom ->
## Bathroom, each room the building's full height, divided by simple
## vertical partitions -- same authoring pattern as every other building,
## see docs/building_system.md. The living room and kitchen share one open
## plan lane (matching the runtime archetype's four-room plan), and a north
## service door opens the kitchen lane onto the Ash Row backyard.
##
## Geometry contract: HALF_EXTENT (192, 86) snaps its wall ring to columns
## +-176 and rows +-80, so the interior spans (-160..160) x (-64..64). The
## three partitions split it into four walkable lanes -- every lane is at
## least 48px clear, comfortably wider than the player's 32px collider
## (the original 300px-wide footprint left lanes of only 12-38px and was
## physically impassable end to end).

const HALF_EXTENT := Vector2(192, 86)
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
## Lobby|LivingRoom, LivingRoom|Bedroom, Bedroom|Bathroom.
const PARTITION_X := [-88.0, 8.0, 96.0]

func _ready() -> void:
	if building_id == &"":
		building_id = &"apartment_01"
	roof_node_path = NodePath("Roof")
	rooms_container_path = NodePath("Rooms")
	_build_shell()
	_link_doors_to_rooms()
	super._ready()

func _build_shell() -> void:
	# Door bays are two wall cells wide (the runtime-standard 64px transverse
	# aperture -- a one-cell gap exactly matches the player diameter and can
	# still collide at its edges). Bay rects anchor half a cell west/north of
	# the door node so the carved pair is exactly what the slab seals.
	# Ring rows snap to y = -80 / +80; the entrance pair sits in the lobby
	# lane of the south wall, the service pair in the living/kitchen lane of
	# the north wall.
	var entrance_bay := Rect2(Vector2(-160, 64), Vector2(64, 32))
	var service_bay := Rect2(Vector2(-64, -96), Vector2(64, 32))
	var window_gaps: Array[Rect2] = [
		Rect2(Vector2(-64, 64), Vector2(32, 32)), # living-room south window cell
		Rect2(Vector2(32, -96), Vector2(32, 32)), # bedroom north window cell
		Rect2(Vector2(128, -96), Vector2(32, 32)), # bathroom north window cell
	]
	var perimeter_gaps: Array[Rect2] = [entrance_bay, service_bay]
	perimeter_gaps.append_array(window_gaps)
	BuildingShellBuilder.build_perimeter_walls(self, HALF_EXTENT, WALL_TEXTURE, perimeter_gaps)
	# Partitions span only the interior (inner wall faces at y = +-64); each
	# door bay carves their middle two of four cells, leaving real wall
	# stubs above and below every doorway.
	for x in PARTITION_X:
		var door_gap := Rect2(Vector2(x - 16, -32), Vector2(32, 64))
		BuildingShellBuilder.build_partition(self, Vector2(x, -64), Vector2(x, 64), INTERIOR_WALL_TEXTURE, [door_gap])

	BuildingExteriorRenderer.build_authored(
		self, HALF_EXTENT, "A", &"painted_plaster", &"apartment", 4,
		[Vector2(-128.0, 80.0)], [Vector2(-48.0, 80.0)]
	)

	var lobby: Node2D = $Rooms/Lobby
	var living: Node2D = $Rooms/LivingRoom
	var bedroom: Node2D = $Rooms/Bedroom
	var bathroom: Node2D = $Rooms/Bathroom
	BuildingShellBuilder.fill_floor(lobby, Vector2(24.0, 86.0), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(living, Vector2(36.0, 86.0), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(bedroom, Vector2(28.0, 86.0), FLOOR_TILE)
	BuildingShellBuilder.fill_floor(bathroom, Vector2(24.0, 86.0), FLOOR_TILE)

	# All prop positions below are LOCAL to their own room node (each room's
	# origin is its lane center -- see Apartment01.tscn) and sized/placed to
	# stay inside their 48-80px-wide lanes without pinching a doorway or a
	# doorway approach cone.
	BuildingShellBuilder.add_physical_prop(lobby, Vector2(0.0, -40.0), BENCH_TEXTURE, Vector2(32, 12))
	BuildingShellBuilder.add_physical_prop(living, Vector2(-6.0, -54.0), COUNTER_TEXTURE, Vector2(48, 20))
	BuildingShellBuilder.add_physical_prop(living, Vector2(-20.0, 38.0), TABLE_TEXTURE, Vector2(32, 20))
	BuildingShellBuilder.add_loot_furniture(
		living, Vector2(18.0, 32.0), FRIDGE_TEXTURE, Vector2(20, 24),
		&"apartment_01/kitchen_fridge", 50.0, {"food_ration": 2, "water_bottle": 2}
	)
	BuildingShellBuilder.add_physical_prop(bedroom, Vector2(0.0, -44.0), BED_TEXTURE, Vector2(24, 36))
	BuildingShellBuilder.add_loot_furniture(
		bedroom, Vector2(10.0, 34.0), CABINET_TEXTURE, Vector2(20, 24),
		&"apartment_01/dresser", 40.0, {"materials": 2, "medical_supplies": 1}
	)
	BuildingShellBuilder.add_physical_prop(bathroom, Vector2(0.0, -40.0), COUNTER_TEXTURE, Vector2(30, 16))

	# Windows replace their whole perimeter wall cell (the cell is carved via
	# window_gaps above), so they sit flush inside the wall run: solid to
	# movement, transparent to the Vision layer while intact.
	var window_living: BuildingWindow = WINDOW_SCENE.instantiate()
	window_living.window_id = &"apartment_01/window_living"
	window_living.position = Vector2(-48.0, 80.0)
	add_child(window_living)
	var window_bedroom: BuildingWindow = WINDOW_SCENE.instantiate()
	window_bedroom.window_id = &"apartment_01/window_bedroom"
	window_bedroom.position = Vector2(48.0, -80.0)
	add_child(window_bedroom)
	var window_bathroom: BuildingWindow = WINDOW_SCENE.instantiate()
	window_bathroom.window_id = &"apartment_01/window_bathroom"
	window_bathroom.position = Vector2(144.0, -80.0)
	add_child(window_bathroom)

func _link_doors_to_rooms() -> void:
	var entrance: Door = $Doors/EntranceDoor
	var service: Door = $Doors/ServiceDoor
	var lobby_living: Door = $Doors/LobbyLivingDoor
	var living_bedroom: Door = $Doors/LivingBedroomDoor
	var bedroom_bathroom: Door = $Doors/BedroomBathroomDoor
	var lobby: Room = $Rooms/Lobby
	var living: Room = $Rooms/LivingRoom
	var bedroom: Room = $Rooms/Bedroom
	var bathroom: Room = $Rooms/Bathroom
	lobby.doors = [entrance, lobby_living]
	living.doors = [service, lobby_living, living_bedroom]
	bedroom.doors = [living_bedroom, bedroom_bathroom]
	bathroom.doors = [bedroom_bathroom]
