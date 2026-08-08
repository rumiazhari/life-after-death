class_name ArenaBuilder
extends Node2D
## Builds a procedural urban test arena at runtime: a tile-painted road
## grid over a ground base, block-shaped building obstacles with rooftop
## art, and a solid perimeter boundary. Visuals are TileMapLayers painted
## from the generated pixel atlas (see docs/art_direction.md); collision
## geometry (StaticBody2D + RectangleShape2D) and the world-space layout
## math are byte-for-byte unchanged from the original primitive-drawn
## build.
##
## Two independent RNG streams, deliberately: `_rng` drives every choice
## that affects collision/gameplay (building position, size, empty-lot
## skip chance) and consumes calls in EXACTLY the same order as before
## this visual rewrite, so a given random_seed still produces the same
## building footprints. `_visual_rng` drives every purely cosmetic choice
## (ground/asphalt/roof tile variant, roof-detail placement, prop
## scatter) on a separate stream, so adding or tuning cosmetic randomness
## can never shift which tile a gameplay-relevant roll lands on.

const WORLD_COLLISION_LAYER := 1
const TS: int = PixelAtlasMap.TILE_SIZE

@export var arena_half_size: Vector2 = Vector2(1400, 1400)
@export var block_size: float = 420.0
@export var road_width: float = 100.0
@export var building_margin: float = 28.0 ## pavement gap between a building and the road
@export var boundary_thickness: float = 40.0
@export var random_seed: int = 20260807

var _rng := RandomNumberGenerator.new()
var _visual_rng := RandomNumberGenerator.new()

var _ground_layer: TileMapLayer
var _roads_layer: TileMapLayer
var _sidewalks_layer: TileMapLayer
var _markings_layer: TileMapLayer
var _roofs_layer: TileMapLayer

## Vector2i block coord -> true, populated by _build_buildings() as it
## places each building. _scatter_props() consults this so decorative
## clutter only ever lands in a genuinely empty lot, never underneath a
## building's roof.
var _building_blocks: Dictionary = {}

func _ready() -> void:
	_rng.seed = random_seed
	_visual_rng.seed = random_seed ^ 0x5A5AF00D
	_build_tile_layers()
	_paint_ground()
	_paint_roads()
	_paint_sidewalks()
	_paint_markings()
	_build_buildings()
	_build_boundary()
	_scatter_props()

func get_arena_size() -> Vector2:
	return arena_half_size * 2.0

# ---------------------------------------------------------------------------
# Tile layers
# ---------------------------------------------------------------------------

func _build_tile_layers() -> void:
	var tileset := PixelTilesetBuilder.get_tileset()
	_ground_layer = _make_layer("Ground", -10, tileset)
	_roads_layer = _make_layer("Roads", -9, tileset)
	_sidewalks_layer = _make_layer("Sidewalks", -8, tileset)
	_markings_layer = _make_layer("RoadMarkings", -7, tileset)
	_roofs_layer = _make_layer("BuildingRoofs", 5, tileset)

func _make_layer(layer_name: String, z: int, tileset: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tileset
	layer.z_index = z
	add_child(layer)
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
	var x: float = -arena_half_size.x
	while x <= arena_half_size.x:
		_paint_road_strip(Vector2(x, 0.0), Vector2(road_width, arena_half_size.y * 2.0))
		x += block_size
	var y: float = -arena_half_size.y
	while y <= arena_half_size.y:
		_paint_road_strip(Vector2(0.0, y), Vector2(arena_half_size.x * 2.0, road_width))
		y += block_size

func _paint_road_strip(center: Vector2, size: Vector2) -> void:
	var half: Vector2 = size * 0.5
	var col_lo := floori((center.x - half.x) / TS)
	var col_hi := floori((center.x + half.x - 1.0) / TS)
	var row_lo := floori((center.y - half.y) / TS)
	var row_hi := floori((center.y + half.y - 1.0) / TS)
	var names: Array[StringName] = [&"asphalt_0", &"asphalt_1", &"asphalt_2", &"asphalt_3"]
	for gx in range(col_lo, col_hi + 1):
		for gy in range(row_lo, row_hi + 1):
			var pick: StringName = names[_visual_rng.randi_range(0, names.size() - 1)]
			PixelTilesetBuilder.paint(_roads_layer, Vector2i(gx, gy), pick)

func _paint_sidewalks() -> void:
	var h_ranges := _horizontal_road_row_ranges()
	var v_ranges := _vertical_road_col_ranges()
	var x: float = -arena_half_size.x
	while x <= arena_half_size.x:
		_paint_vertical_sidewalk(x, h_ranges)
		x += block_size
	var y: float = -arena_half_size.y
	while y <= arena_half_size.y:
		_paint_horizontal_sidewalk(y, v_ranges)
		y += block_size
	_paint_intersection_corners()

## [row_lo, row_hi] (as a Vector2i) for every horizontal road strip --
## used so a vertical sidewalk never paints a curb/sidewalk tile across a
## crossing road's own drivable lane.
func _horizontal_road_row_ranges() -> Array:
	var ranges: Array = []
	var half: float = road_width * 0.5
	var y: float = -arena_half_size.y
	while y <= arena_half_size.y:
		ranges.append(Vector2i(floori((y - half) / TS), floori((y + half - 1.0) / TS)))
		y += block_size
	return ranges

## Column equivalent of _horizontal_road_row_ranges(), for horizontal
## sidewalks crossing vertical roads.
func _vertical_road_col_ranges() -> Array:
	var ranges: Array = []
	var half: float = road_width * 0.5
	var x: float = -arena_half_size.x
	while x <= arena_half_size.x:
		ranges.append(Vector2i(floori((x - half) / TS), floori((x + half - 1.0) / TS)))
		x += block_size
	return ranges

func _in_any_range(value: int, ranges: Array) -> bool:
	for r in ranges:
		if value >= r.x and value <= r.y:
			return true
	return false

func _paint_vertical_sidewalk(center_x: float, h_ranges: Array) -> void:
	var half: float = road_width * 0.5
	var left_road_col := floori((center_x - half) / TS)
	var right_road_col := floori((center_x + half - 1.0) / TS)
	var lo := _tile_min()
	var hi := _tile_max()
	for row in range(lo.y, hi.y + 1):
		if _in_any_range(row, h_ranges):
			continue # inside a crossing road's own lane -- leave it asphalt
		PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(left_road_col - 1, row), &"curb_right")
		PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(left_road_col - 2, row), _sidewalk_variant())
		PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(right_road_col + 1, row), &"curb_left")
		PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(right_road_col + 2, row), _sidewalk_variant())

func _paint_horizontal_sidewalk(center_y: float, v_ranges: Array) -> void:
	var half: float = road_width * 0.5
	var top_road_row := floori((center_y - half) / TS)
	var bottom_road_row := floori((center_y + half - 1.0) / TS)
	var lo := _tile_min()
	var hi := _tile_max()
	for col in range(lo.x, hi.x + 1):
		if _in_any_range(col, v_ranges):
			continue # inside a crossing road's own lane -- leave it asphalt
		PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(col, top_road_row - 1), &"curb_bottom")
		PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(col, top_road_row - 2), _sidewalk_variant())
		PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(col, bottom_road_row + 1), &"curb_top")
		PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(col, bottom_road_row + 2), _sidewalk_variant())

## Closes off each intersection's four sidewalk corners with a proper
## curb-corner tile (curve facing into the intersection) instead of
## leaving a blunt gap where the vertical/horizontal skip logic above
## stopped painting straight curb strips.
func _paint_intersection_corners() -> void:
	var half: float = road_width * 0.5
	var x: float = -arena_half_size.x
	while x <= arena_half_size.x:
		var left_col := floori((x - half) / TS)
		var right_col := floori((x + half - 1.0) / TS)
		var y: float = -arena_half_size.y
		while y <= arena_half_size.y:
			var top_row := floori((y - half) / TS)
			var bottom_row := floori((y + half - 1.0) / TS)
			PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(left_col - 1, top_row - 1), &"curb_corner_br")
			PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(right_col + 1, top_row - 1), &"curb_corner_bl")
			PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(left_col - 1, bottom_row + 1), &"curb_corner_tr")
			PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(right_col + 1, bottom_row + 1), &"curb_corner_tl")
			y += block_size
		x += block_size

func _sidewalk_variant() -> StringName:
	return &"sidewalk_0" if _visual_rng.randf() < 0.5 else &"sidewalk_1"

func _paint_markings() -> void:
	var xs: Array[float] = []
	var x: float = -arena_half_size.x
	while x <= arena_half_size.x:
		xs.append(x)
		x += block_size
	var ys: Array[float] = []
	var y: float = -arena_half_size.y
	while y <= arena_half_size.y:
		ys.append(y)
		y += block_size

	var lo := _tile_min()
	var hi := _tile_max()
	for road_x in xs:
		var col := floori(road_x / TS)
		for row in range(lo.y, hi.y + 1):
			PixelTilesetBuilder.paint(_markings_layer, Vector2i(col, row), &"road_dash_v")
	for road_y in ys:
		var row := floori(road_y / TS)
		for col in range(lo.x, hi.x + 1):
			PixelTilesetBuilder.paint(_markings_layer, Vector2i(col, row), &"road_dash_h")

	for road_x in xs:
		for road_y in ys:
			_paint_crosswalk(road_x, road_y)

func _paint_crosswalk(center_x: float, center_y: float) -> void:
	var half: float = road_width * 0.5
	var col_lo := floori((center_x - half) / TS)
	var col_hi := floori((center_x + half - 1.0) / TS)
	var row_lo := floori((center_y - half) / TS)
	var row_hi := floori((center_y + half - 1.0) / TS)
	for gx in range(col_lo, col_hi + 1):
		for gy in range(row_lo, row_hi + 1):
			PixelTilesetBuilder.paint(_markings_layer, Vector2i(gx, gy), &"crosswalk")

# ---------------------------------------------------------------------------
# Buildings (collision unchanged; visuals repainted onto BuildingRoofs)
# ---------------------------------------------------------------------------

func _build_buildings() -> void:
	var buildings := Node2D.new()
	buildings.name = "Buildings"
	add_child(buildings)
	var half_blocks_x: int = int(arena_half_size.x / block_size)
	var half_blocks_y: int = int(arena_half_size.y / block_size)
	for bx in range(-half_blocks_x, half_blocks_x + 1):
		for by in range(-half_blocks_y, half_blocks_y + 1):
			var block_center := Vector2(bx * block_size, by * block_size)
			if block_center.length() < block_size * 0.75:
				continue # keep the player's spawn block clear
			if _rng.randf() < 0.18:
				continue # occasional empty lot
			_building_blocks[Vector2i(bx, by)] = true
			buildings.add_child(_make_building(block_center))

func _make_building(block_center: Vector2) -> StaticBody2D:
	var footprint: float = block_size - road_width - building_margin * 2.0
	var w: float = footprint * _rng.randf_range(0.55, 0.9)
	var h: float = footprint * _rng.randf_range(0.55, 0.9)
	var jitter := Vector2(
		_rng.randf_range(-footprint, footprint) * 0.15,
		_rng.randf_range(-footprint, footprint) * 0.15
	)
	var center: Vector2 = block_center + jitter
	var half: Vector2 = Vector2(w, h) * 0.5

	var body := StaticBody2D.new()
	body.name = "Building"
	body.position = center
	body.collision_layer = WORLD_COLLISION_LAYER
	body.collision_mask = 0

	var shape := RectangleShape2D.new()
	shape.size = Vector2(w, h)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)

	_paint_building_roof(center, half)
	_add_roof_details(body, half)

	return body

func _paint_building_roof(center: Vector2, half: Vector2) -> void:
	var letter: String = ["A", "B", "C", "D"][_visual_rng.randi_range(0, 3)]
	var col_lo := floori((center.x - half.x) / TS)
	var col_hi := floori((center.x + half.x - 1.0) / TS)
	var row_lo := floori((center.y - half.y) / TS)
	var row_hi := floori((center.y + half.y - 1.0) / TS)
	for gx in range(col_lo, col_hi + 1):
		for gy in range(row_lo, row_hi + 1):
			var is_left: bool = gx == col_lo
			var is_right: bool = gx == col_hi
			var is_top: bool = gy == row_lo
			var is_bottom: bool = gy == row_hi
			var part: String
			if is_top and is_left:
				part = "corner_tl"
			elif is_top and is_right:
				part = "corner_tr"
			elif is_bottom and is_left:
				part = "corner_bl"
			elif is_bottom and is_right:
				part = "corner_br"
			elif is_top:
				part = "edge_top"
			elif is_bottom:
				part = "edge_bottom"
			elif is_left:
				part = "edge_left"
			elif is_right:
				part = "edge_right"
			else:
				part = "center"
			PixelTilesetBuilder.paint(_roofs_layer, Vector2i(gx, gy), StringName("roof%s_%s" % [letter, part]))

func _add_roof_details(body: StaticBody2D, half: Vector2) -> void:
	if half.x < TS * 2.0 or half.y < TS * 2.0:
		return
	var detail_names: Array[StringName] = [&"roof_vent", &"roof_pipe", &"roof_sign", &"roof_duct", &"roof_tank"]
	var texture: Texture2D = load(PixelAtlasMap.ENV_ATLAS_PATH)
	var count: int = _visual_rng.randi_range(0, 2)
	for i in range(count):
		var detail_name: StringName = detail_names[_visual_rng.randi_range(0, detail_names.size() - 1)]
		var sprite := Sprite2D.new()
		var atlas_tex := AtlasTexture.new()
		atlas_tex.atlas = texture
		var cell: Vector2i = PixelAtlasMap.env_cell(detail_name)
		atlas_tex.region = Rect2(cell * TS, Vector2(TS, TS))
		sprite.texture = atlas_tex
		sprite.position = Vector2(
			_visual_rng.randf_range(-half.x + TS, half.x - TS),
			_visual_rng.randf_range(-half.y + TS, half.y - TS)
		)
		sprite.z_index = 6
		body.add_child(sprite)

# ---------------------------------------------------------------------------
# Boundary
# ---------------------------------------------------------------------------

func _build_boundary() -> void:
	var boundary := Node2D.new()
	boundary.name = "Boundary"
	add_child(boundary)
	var t: float = boundary_thickness
	var s: Vector2 = arena_half_size
	var walls: Array[Dictionary] = [
		{"center": Vector2(0, -s.y - t * 0.5), "size": Vector2(s.x * 2.0 + t * 2.0, t)},
		{"center": Vector2(0, s.y + t * 0.5), "size": Vector2(s.x * 2.0 + t * 2.0, t)},
		{"center": Vector2(-s.x - t * 0.5, 0), "size": Vector2(t, s.y * 2.0 + t * 2.0)},
		{"center": Vector2(s.x + t * 0.5, 0), "size": Vector2(t, s.y * 2.0 + t * 2.0)},
	]
	for wall_data in walls:
		boundary.add_child(_make_wall(wall_data["center"], wall_data["size"]))

func _make_wall(center: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "BoundaryWall"
	body.position = center
	body.collision_layer = WORLD_COLLISION_LAYER
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

# ---------------------------------------------------------------------------
# Decorative (non-colliding) prop scatter -- empty lots only
# ---------------------------------------------------------------------------

## "Volumetric" props (a crate/bag/pile an actor can walk in front of or
## behind) are added directly to the shared y-sort dynamic-world container
## (the "entity_container" group node -- same one Player/Survivor/Zombie/
## ScavengePoints live in) with no z_index override, so Godot's native
## y-sort orders them against actors by feet position. "Flush" ground-level
## decorations (loose debris, drain covers) stay in this builder's own
## GroundProps container at a fixed low z-index, always beneath actors --
## they read as part of the ground, not an obstacle to sort against.
func _scatter_props() -> void:
	var dynamic_world: Node = get_tree().get_first_node_in_group("entity_container")
	var ground_props := Node2D.new()
	ground_props.name = "GroundProps"
	ground_props.z_index = -1
	add_child(ground_props)

	var prop_names := ["crate", "trash_bag", "sandbags", "pallet"]
	var half_blocks_x: int = int(arena_half_size.x / block_size)
	var half_blocks_y: int = int(arena_half_size.y / block_size)
	for bx in range(-half_blocks_x, half_blocks_x + 1):
		for by in range(-half_blocks_y, half_blocks_y + 1):
			var block_center := Vector2(bx * block_size, by * block_size)
			if block_center.length() < block_size * 0.9:
				continue # keep the player's spawn block clear
			if _building_blocks.has(Vector2i(bx, by)):
				continue # a genuine empty lot only -- never scatter under a building's roof
			if _visual_rng.randf() < 0.45:
				_add_debris(ground_props, block_center)
				continue
			_add_prop_cluster(dynamic_world, block_center, prop_names)
	_scatter_drain_covers(ground_props)

func _add_debris(ground_props: Node2D, block_center: Vector2) -> void:
	if _visual_rng.randf() < 0.5:
		return
	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/pixel/props/debris_small.png")
	sprite.position = block_center + Vector2(
		_visual_rng.randf_range(-40.0, 40.0),
		_visual_rng.randf_range(-40.0, 40.0)
	)
	ground_props.add_child(sprite)

## Occasional drain/manhole covers set into the road surface near a curb,
## clearly authored placement rather than random scatter across the whole
## arena.
func _scatter_drain_covers(ground_props: Node2D) -> void:
	var half: float = road_width * 0.5
	var x: float = -arena_half_size.x
	while x <= arena_half_size.x:
		var y: float = -arena_half_size.y + block_size * 0.5
		while y <= arena_half_size.y:
			if _visual_rng.randf() < 0.5:
				var sprite := Sprite2D.new()
				sprite.texture = load("res://assets/pixel/props/drain_cover.png")
				sprite.position = Vector2(x + half - 16.0, y)
				ground_props.add_child(sprite)
			y += block_size
		x += block_size

func _add_prop_cluster(dynamic_world: Node, block_center: Vector2, prop_names: Array) -> void:
	if dynamic_world == null:
		return
	var count: int = _visual_rng.randi_range(1, 2)
	var spread: float = block_size * 0.22
	for i in range(count):
		var prop_name: String = prop_names[_visual_rng.randi_range(0, prop_names.size() - 1)]
		var sprite := Sprite2D.new()
		sprite.texture = load("res://assets/pixel/props/%s.png" % prop_name)
		dynamic_world.add_child(sprite)
		# global_position, not position -- dynamic_world (EntityContainer)
		# may not share ArenaBuilder's own transform, and block_center is a
		# world-space coordinate.
		sprite.global_position = block_center + Vector2(
			_visual_rng.randf_range(-spread, spread),
			_visual_rng.randf_range(-spread, spread)
		)
