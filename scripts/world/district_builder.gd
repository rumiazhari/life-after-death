class_name DistrictBuilder
extends Node2D
## Builds the ONE fixed, authored urban district (Phase 3B). Every road,
## building, and prop position below is a literal authored coordinate --
## there is no chance-based skip, no random block grid, and the only RNG
## touched anywhere in this file is CosmeticRng for pure tile-variant noise
## (which asphalt/ground cell gets which of several equally-valid texture
## variants) that never affects position, collision, or which prop exists.
## Running this twice produces the identical world -- see
## scripts/world/district_layout_checksum.gd and
## tests/test_runner.gd's fixed-map tests, which assert exactly that.
##
## ArenaBuilder (scripts/world/arena_builder.gd) is preserved unused by
## Main.tscn as an optional random-layout test/performance scene -- see
## docs/urban_map_design.md "Why the main map is now fixed and authored."

const TS: int = PixelAtlasMap.TILE_SIZE
const WORLD_LAYER := 1

@export var arena_half_size: Vector2 = Vector2(1400, 1400)
@export var boundary_thickness: float = 40.0

var _ground_layer: TileMapLayer
var _roads_layer: TileMapLayer
var _sidewalks_layer: TileMapLayer
var _markings_layer: TileMapLayer
var _visual_rng := RandomNumberGenerator.new()

## Fixed road network: {center: Vector2, size: Vector2}. size.x > size.y
## means a horizontal road, otherwise vertical -- matches the existing
## world-space convention from ArenaBuilder's road strips.
const ROADS := [
	{"center": Vector2(0, 0), "size": Vector2(2800, 140)}, # main road (east-west)
	{"center": Vector2(-500, 0), "size": Vector2(100, 2800)}, # side street A
	{"center": Vector2(500, 0), "size": Vector2(100, 2800)}, # side street B
	{"center": Vector2(150, 115), "size": Vector2(48, 90)}, # service alley (main road -> Restaurant01)
]

const BUILDING_SCENES := {
	"restaurant_01": "res://scenes/world/buildings/Restaurant01.tscn",
	"convenience_store_01": "res://scenes/world/buildings/ConvenienceStore01.tscn",
	"clinic_01": "res://scenes/world/buildings/Clinic01.tscn",
}
## Fixed positions for the 3 fully-enterable authored buildings.
const BUILDING_POSITIONS := {
	"restaurant_01": Vector2(150, 250),
	"convenience_store_01": Vector2(850, -500),
	"clinic_01": Vector2(-850, 500),
}

## Fixed non-enterable "shell" background buildings for street density --
## {position, half_extent, roof_letter}.
const SHELL_BUILDINGS := [
	{"position": Vector2(950, 700), "half_extent": Vector2(90, 70), "roof": "D"},
	{"position": Vector2(-150, -700), "half_extent": Vector2(80, 65), "roof": "A"},
	{"position": Vector2(950, -950), "half_extent": Vector2(85, 90), "roof": "C"},
	{"position": Vector2(-950, -300), "half_extent": Vector2(80, 100), "roof": "B"},
]

## Fixed spawn regions -- {id, position, radius, category}. Never inside
## the safehouse, never overlapping a real building footprint.
const SPAWN_REGIONS := [
	{"id": &"edge_north", "position": Vector2(0, -1320), "radius": 220.0, "category": &"map_edge"},
	{"id": &"edge_south", "position": Vector2(0, 1320), "radius": 220.0, "category": &"map_edge"},
	{"id": &"edge_east", "position": Vector2(1320, 0), "radius": 220.0, "category": &"map_edge"},
	{"id": &"edge_west", "position": Vector2(-1320, 0), "radius": 220.0, "category": &"map_edge"},
	{"id": &"alley_service", "position": Vector2(150, 60), "radius": 50.0, "category": &"alley"},
	{"id": &"concealed_ne", "position": Vector2(1150, -750), "radius": 120.0, "category": &"concealed"},
	{"id": &"concealed_sw", "position": Vector2(-1150, 800), "radius": 120.0, "category": &"concealed"},
]

## Fixed scavenge points -- deterministic identifiers, positions checked
## against every road/building/shell footprint above.
const SCAVENGE_POINTS := [
	{"name": "Food1", "position": Vector2(700, -950), "item_id": &"food_ration", "yield": 2, "stock": 8, "danger": 15.0},
	{"name": "Water1", "position": Vector2(-700, -800), "item_id": &"water_bottle", "yield": 2, "stock": 8, "danger": 15.0},
	{"name": "Materials1", "position": Vector2(1100, 950), "item_id": &"materials", "yield": 3, "stock": 12, "danger": 25.0},
	{"name": "Food2", "position": Vector2(-350, 950), "item_id": &"food_ration", "yield": 2, "stock": 6, "danger": 35.0},
	{"name": "Medical1", "position": Vector2(400, -300), "item_id": &"medical_supplies", "yield": 1, "stock": 4, "danger": 40.0},
]

func _ready() -> void:
	_visual_rng.seed = 0x0D157201
	_build_tile_layers()
	_paint_ground()
	_paint_roads()
	_paint_sidewalks()
	_paint_markings()
	_build_boundary()
	_build_shell_buildings()
	_build_real_buildings()
	_build_street_props()
	_build_scavenge_points()
	_build_spawn_regions()
	# Newly-added StaticBody2D collision shapes aren't queryable by the
	# physics server until at least one physics step has run -- wait one
	# before building the navigation grid's per-cell solidity from them.
	await get_tree().physics_frame
	UrbanNavigationService.build(arena_half_size)
	_register_doors_with_navigation()

func _register_doors_with_navigation() -> void:
	for door in get_tree().get_nodes_in_group("doors"):
		if door.door_id != &"":
			UrbanNavigationService.register_door(door.door_id, door.global_position)
			if door.is_open:
				UrbanNavigationService.mark_door_open(door.door_id)

func get_arena_size() -> Vector2:
	return arena_half_size * 2.0

# --- Tile layers (same technique as ArenaBuilder, fixed input instead of a loop grid) ---

func _build_tile_layers() -> void:
	var tileset := PixelTilesetBuilder.get_tileset()
	_ground_layer = _make_layer("Ground", -10, tileset)
	_roads_layer = _make_layer("Roads", -9, tileset)
	_sidewalks_layer = _make_layer("Sidewalks", -8, tileset)
	_markings_layer = _make_layer("RoadMarkings", -7, tileset)

func _make_layer(layer_name: String, z: int, tileset: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tileset
	layer.z_index = z
	$GroundLayers.add_child(layer)
	return layer

func _tile_min() -> Vector2i:
	return Vector2i(floori(-arena_half_size.x / TS), floori(-arena_half_size.y / TS))

func _tile_max() -> Vector2i:
	return Vector2i(floori((arena_half_size.x - 1.0) / TS), floori((arena_half_size.y - 1.0) / TS))

func _paint_ground() -> void:
	var lo := _tile_min()
	var hi := _tile_max()
	for gx in range(lo.x, hi.x + 1):
		for gy in range(lo.y, hi.y + 1):
			var roll := _visual_rng.randf()
			var tile_name: StringName = &"concrete"
			if roll < 0.05:
				tile_name = &"grass"
			elif roll < 0.08:
				tile_name = &"dirt"
			elif roll < 0.10:
				tile_name = &"cracked_ground"
			PixelTilesetBuilder.paint(_ground_layer, Vector2i(gx, gy), tile_name)

func _paint_roads() -> void:
	var names: Array[StringName] = [&"asphalt_0", &"asphalt_1", &"asphalt_2", &"asphalt_3"]
	for road in ROADS:
		var center: Vector2 = road["center"]
		var half: Vector2 = road["size"] * 0.5
		var col_lo := floori((center.x - half.x) / TS)
		var col_hi := floori((center.x + half.x - 1.0) / TS)
		var row_lo := floori((center.y - half.y) / TS)
		var row_hi := floori((center.y + half.y - 1.0) / TS)
		for gx in range(col_lo, col_hi + 1):
			for gy in range(row_lo, row_hi + 1):
				var pick: StringName = names[_visual_rng.randi_range(0, names.size() - 1)]
				PixelTilesetBuilder.paint(_roads_layer, Vector2i(gx, gy), pick)

func _paint_sidewalks() -> void:
	for road in ROADS:
		var center: Vector2 = road["center"]
		var size: Vector2 = road["size"]
		if size.x > size.y:
			_paint_horizontal_sidewalk(center, size)
		else:
			_paint_vertical_sidewalk(center, size)

func _paint_vertical_sidewalk(center: Vector2, size: Vector2) -> void:
	var half: float = size.x * 0.5
	var left_col := floori((center.x - half) / TS)
	var right_col := floori((center.x + half - 1.0) / TS)
	var row_lo := floori((center.y - size.y * 0.5) / TS)
	var row_hi := floori((center.y + size.y * 0.5 - 1.0) / TS)
	for row in range(row_lo, row_hi + 1):
		PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(left_col - 1, row), &"curb_right")
		PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(left_col - 2, row), _sidewalk_variant())
		PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(right_col + 1, row), &"curb_left")
		PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(right_col + 2, row), _sidewalk_variant())

func _paint_horizontal_sidewalk(center: Vector2, size: Vector2) -> void:
	var half: float = size.y * 0.5
	var top_row := floori((center.y - half) / TS)
	var bottom_row := floori((center.y + half - 1.0) / TS)
	var col_lo := floori((center.x - size.x * 0.5) / TS)
	var col_hi := floori((center.x + size.x * 0.5 - 1.0) / TS)
	for col in range(col_lo, col_hi + 1):
		PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(col, top_row - 1), &"curb_bottom")
		PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(col, top_row - 2), _sidewalk_variant())
		PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(col, bottom_row + 1), &"curb_top")
		PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(col, bottom_row + 2), _sidewalk_variant())

func _sidewalk_variant() -> StringName:
	return &"sidewalk_0" if _visual_rng.randf() < 0.5 else &"sidewalk_1"

func _paint_markings() -> void:
	for road in ROADS:
		var center: Vector2 = road["center"]
		var size: Vector2 = road["size"]
		var vertical: bool = size.x < size.y
		var col_lo := floori((center.x - size.x * 0.5) / TS)
		var col_hi := floori((center.x + size.x * 0.5 - 1.0) / TS)
		var row_lo := floori((center.y - size.y * 0.5) / TS)
		var row_hi := floori((center.y + size.y * 0.5 - 1.0) / TS)
		if vertical:
			var col := floori(center.x / TS)
			for row in range(row_lo, row_hi + 1):
				PixelTilesetBuilder.paint(_markings_layer, Vector2i(col, row), &"road_dash_v")
		else:
			var row := floori(center.y / TS)
			for col in range(col_lo, col_hi + 1):
				PixelTilesetBuilder.paint(_markings_layer, Vector2i(col, row), &"road_dash_h")
	# Crosswalks at the one real intersection (main road x each side street).
	_paint_crosswalk(Vector2(-500, 0))
	_paint_crosswalk(Vector2(500, 0))

func _paint_crosswalk(center: Vector2) -> void:
	var half := 70.0
	var col_lo := floori((center.x - half) / TS)
	var col_hi := floori((center.x + half - 1.0) / TS)
	var row_lo := floori((center.y - half) / TS)
	var row_hi := floori((center.y + half - 1.0) / TS)
	for gx in range(col_lo, col_hi + 1):
		for gy in range(row_lo, row_hi + 1):
			PixelTilesetBuilder.paint(_markings_layer, Vector2i(gx, gy), &"crosswalk")

# --- Boundary (unchanged pattern from ArenaBuilder) ---

func _build_boundary() -> void:
	var t: float = boundary_thickness
	var s: Vector2 = arena_half_size
	var walls: Array[Dictionary] = [
		{"center": Vector2(0, -s.y - t * 0.5), "size": Vector2(s.x * 2.0 + t * 2.0, t)},
		{"center": Vector2(0, s.y + t * 0.5), "size": Vector2(s.x * 2.0 + t * 2.0, t)},
		{"center": Vector2(-s.x - t * 0.5, 0), "size": Vector2(t, s.y * 2.0 + t * 2.0)},
		{"center": Vector2(s.x + t * 0.5, 0), "size": Vector2(t, s.y * 2.0 + t * 2.0)},
	]
	for wall_data in walls:
		$Boundaries.add_child(_make_wall(wall_data["center"], wall_data["size"]))

func _make_wall(center: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "BoundaryWall"
	body.position = center
	body.collision_layer = WORLD_LAYER | 32 # World + Vision
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	var visual := ColorRect.new()
	visual.color = Color(0.14, 0.05, 0.05)
	visual.size = size
	visual.position = -size * 0.5
	body.add_child(visual)
	return body

# --- Shell (non-enterable) background buildings, fixed positions ---

func _build_shell_buildings() -> void:
	for spec in SHELL_BUILDINGS:
		$Buildings.add_child(_make_shell_building(spec["position"], spec["half_extent"], spec["roof"]))

func _make_shell_building(position: Vector2, half: Vector2, roof_letter: String) -> Node2D:
	var root := Node2D.new()
	root.position = position
	var body := StaticBody2D.new()
	body.name = "Building"
	body.collision_layer = WORLD_LAYER | 32
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = half * 2.0
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	root.add_child(body)
	var roof := TileMapLayer.new()
	roof.name = "Roof"
	roof.tile_set = PixelTilesetBuilder.get_tileset()
	roof.z_index = 5
	root.add_child(roof)
	BuildingShellBuilder.paint_roof(roof, half, roof_letter)
	return root

# --- Real enterable buildings, fixed positions ---

func _build_real_buildings() -> void:
	for building_id in BUILDING_POSITIONS:
		var scene: PackedScene = load(BUILDING_SCENES[building_id])
		var instance: Node2D = scene.instantiate()
		instance.position = BUILDING_POSITIONS[building_id]
		$Buildings.add_child(instance)

# --- Fixed street dressing ---

func _build_street_props() -> void:
	var dynamic_world: Node = get_tree().get_first_node_in_group("entity_container")
	var props := $StreetProps

	# Parking lot (SE corner) -- asphalt patch with painted stall lines.
	_paint_parking_lot(Vector2(950, 950), Vector2(200, 160))

	# Plaza (south-center) -- benches, a tree, planters, on plain concrete
	# ground already painted by _paint_ground(); just add furniture.
	BuildingShellBuilder.add_physical_prop(props, Vector2(-200, 950), preload("res://assets/pixel/props/bench.png"), Vector2(32, 12))
	BuildingShellBuilder.add_physical_prop(props, Vector2(-100, 950), preload("res://assets/pixel/props/tree.png"), Vector2(20, 20))
	BuildingShellBuilder.add_physical_prop(props, Vector2(-150, 1000), preload("res://assets/pixel/props/planter.png"), Vector2(24, 16))

	# Abandoned cars along the side streets (lootable trunk/cabin).
	BuildingShellBuilder.add_loot_furniture(dynamic_world, Vector2(-560, -200), preload("res://assets/pixel/props/car_sedan.png"), Vector2(24, 44), &"street/car_1", 80.0, {"materials": 2})
	BuildingShellBuilder.add_salvage_prop(dynamic_world, Vector2(560, 300), preload("res://assets/pixel/props/car_wreck.png"), Vector2(24, 44), &"street/car_wreck_1", 4)

	# Trees, utility box, street sign, hydrant along the main road frontage.
	BuildingShellBuilder.add_physical_prop(props, Vector2(-300, -110), preload("res://assets/pixel/props/tree.png"), Vector2(20, 20))
	BuildingShellBuilder.add_physical_prop(props, Vector2(300, 110), preload("res://assets/pixel/props/tree.png"), Vector2(20, 20))
	BuildingShellBuilder.add_physical_prop(props, Vector2(-450, -110), preload("res://assets/pixel/props/utility_box.png"), Vector2(14, 18))
	BuildingShellBuilder.add_physical_prop(props, Vector2(-500, -450), preload("res://assets/pixel/props/street_sign.png"), Vector2(6, 6))
	BuildingShellBuilder.add_physical_prop(props, Vector2(500, -450), preload("res://assets/pixel/props/street_lamp.png"), Vector2(8, 8))
	BuildingShellBuilder.add_physical_prop(props, Vector2(80, -30), preload("res://assets/pixel/props/hydrant.png"), Vector2(10, 10))

	# Dumpsters/trash near the restaurant's service alley.
	BuildingShellBuilder.add_loot_furniture(dynamic_world, Vector2(210, 100), preload("res://assets/pixel/props/dumpster.png"), Vector2(36, 24), &"street/dumpster_alley", 60.0, {"materials": 3})
	BuildingShellBuilder.add_physical_prop(props, Vector2(90, 100), preload("res://assets/pixel/props/trash_bag.png"), Vector2(12, 10))

	# Road barriers/cones near the parking entrance.
	BuildingShellBuilder.add_physical_prop(props, Vector2(850, 870), preload("res://assets/pixel/props/road_barrier.png"), Vector2(36, 16))
	BuildingShellBuilder.add_physical_prop(props, Vector2(1050, 870), preload("res://assets/pixel/props/cone.png"), Vector2(10, 10))

func _paint_parking_lot(center: Vector2, size: Vector2) -> void:
	var half := size * 0.5
	var col_lo := floori((center.x - half.x) / TS)
	var col_hi := floori((center.x + half.x - 1.0) / TS)
	var row_lo := floori((center.y - half.y) / TS)
	var row_hi := floori((center.y + half.y - 1.0) / TS)
	for gx in range(col_lo, col_hi + 1):
		for gy in range(row_lo, row_hi + 1):
			PixelTilesetBuilder.paint(_roads_layer, Vector2i(gx, gy), &"asphalt_2")
	for gx in range(col_lo + 1, col_hi, 3):
		for gy in range(row_lo + 1, row_hi - 1):
			PixelTilesetBuilder.paint(_markings_layer, Vector2i(gx, gy), &"road_solid_v")

# --- Scavenge points ---

func _build_scavenge_points() -> void:
	var dynamic_world: Node = get_tree().get_first_node_in_group("entity_container")
	if dynamic_world == null:
		return
	var scene: PackedScene = load("res://scenes/world/ScavengePoint.tscn")
	for spec in SCAVENGE_POINTS:
		var instance: Node2D = scene.instantiate()
		instance.name = spec["name"]
		instance.item_id = spec["item_id"]
		instance.yield_per_scavenge = spec["yield"]
		instance.remaining_stock = spec["stock"]
		instance.danger = spec["danger"]
		dynamic_world.add_child(instance)
		instance.global_position = spec["position"]

# --- Spawn regions ---

func _build_spawn_regions() -> void:
	for spec in SPAWN_REGIONS:
		var marker := SpawnRegion.new()
		marker.region_id = spec["id"]
		marker.radius = spec["radius"]
		marker.category = spec["category"]
		marker.position = spec["position"]
		$SpawnRegions.add_child(marker)
