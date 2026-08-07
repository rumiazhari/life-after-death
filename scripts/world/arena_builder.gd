class_name ArenaBuilder
extends Node2D
## Builds a procedural urban test arena at runtime: a road grid over a
## pavement base, block-shaped building obstacles, and a solid perimeter
## boundary. Everything is primitive-drawn (Polygon2D / Line2D /
## StaticBody2D) -- no imported textures.

const PAVEMENT_COLOR := Color(0.55, 0.55, 0.58)
const ROAD_COLOR := Color(0.20, 0.20, 0.22)
const ROAD_LINE_COLOR := Color(0.85, 0.75, 0.25)
const BUILDING_COLOR := Color(0.45, 0.30, 0.24)
const BUILDING_OUTLINE_COLOR := Color(0.28, 0.18, 0.14)
const BOUNDARY_COLOR := Color(0.35, 0.08, 0.08)

const WORLD_COLLISION_LAYER := 1

@export var arena_half_size: Vector2 = Vector2(1400, 1400)
@export var block_size: float = 420.0
@export var road_width: float = 100.0
@export var building_margin: float = 28.0 ## pavement gap between a building and the road
@export var boundary_thickness: float = 40.0
@export var random_seed: int = 20260807

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = random_seed
	_build_pavement()
	_build_roads()
	_build_buildings()
	_build_boundary()

func get_arena_size() -> Vector2:
	return arena_half_size * 2.0

func _build_pavement() -> void:
	var pavement := Polygon2D.new()
	pavement.name = "Pavement"
	pavement.color = PAVEMENT_COLOR
	pavement.polygon = PackedVector2Array([
		Vector2(-arena_half_size.x, -arena_half_size.y),
		Vector2(arena_half_size.x, -arena_half_size.y),
		Vector2(arena_half_size.x, arena_half_size.y),
		Vector2(-arena_half_size.x, arena_half_size.y),
	])
	pavement.z_index = -10
	add_child(pavement)

func _build_roads() -> void:
	var roads := Node2D.new()
	roads.name = "Roads"
	roads.z_index = -9
	add_child(roads)
	var x: float = -arena_half_size.x
	while x <= arena_half_size.x:
		_add_road_strip(roads, Vector2(x, 0.0), Vector2(road_width, arena_half_size.y * 2.0), true)
		x += block_size
	var y: float = -arena_half_size.y
	while y <= arena_half_size.y:
		_add_road_strip(roads, Vector2(0.0, y), Vector2(arena_half_size.x * 2.0, road_width), false)
		y += block_size

func _add_road_strip(parent: Node2D, center: Vector2, size: Vector2, vertical: bool) -> void:
	var half: Vector2 = size * 0.5
	var strip := Polygon2D.new()
	strip.color = ROAD_COLOR
	strip.polygon = PackedVector2Array([
		center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y), center + Vector2(-half.x, half.y),
	])
	parent.add_child(strip)

	var line := Line2D.new()
	line.width = 3.0
	line.default_color = ROAD_LINE_COLOR
	if vertical:
		line.points = PackedVector2Array([center + Vector2(0, -half.y), center + Vector2(0, half.y)])
	else:
		line.points = PackedVector2Array([center + Vector2(-half.x, 0), center + Vector2(half.x, 0)])
	parent.add_child(line)

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

	var visual := Polygon2D.new()
	visual.color = BUILDING_COLOR
	visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	body.add_child(visual)

	var outline := Line2D.new()
	outline.width = 4.0
	outline.default_color = BUILDING_OUTLINE_COLOR
	outline.closed = true
	outline.points = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	body.add_child(outline)

	return body

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

	var visual := Polygon2D.new()
	visual.color = BOUNDARY_COLOR
	var half: Vector2 = size * 0.5
	visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	body.add_child(visual)

	return body
