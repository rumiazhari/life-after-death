class_name ChunkEdgeContract
extends RefCounted
## Pure deterministic boundary contract for streamed city chunks.  Both sides
## of a border derive their road portals from the same unordered coordinate
## pair, so generation order can never create a road seam.

enum Side { NORTH, EAST, SOUTH, WEST }

const TILE_SIZE := 32
const EDGE_MARGIN_TILES := 6
const MIX_X := 73_856_093
const MIX_Y := 19_349_663
const MIX_SIDE := 83_492_791

static func chunk_seed(world_seed: int, coordinate: Vector2i) -> int:
	var mixed: int = world_seed
	mixed ^= coordinate.x * MIX_X
	mixed ^= coordinate.y * MIX_Y
	mixed ^= 0x45D9F3B
	mixed = (mixed * 1_103_515_245 + 12_345) & 0x7fffffff
	return mixed if mixed > 0 else 1

static func edge_portals(world_seed: int, coordinate: Vector2i, side: int, chunk_tiles: int) -> Array[Dictionary]:
	var neighbor := _neighbor(coordinate, side)
	var first := coordinate
	var second := neighbor
	if _comes_after(first, second):
		first = neighbor
		second = coordinate
	var rng := RandomNumberGenerator.new()
	rng.seed = chunk_seed(world_seed ^ MIX_SIDE, Vector2i(first.x ^ second.x, first.y ^ second.y))
	var count := 1 + rng.randi_range(0, 1)
	var portals: Array[Dictionary] = []
	var available := maxi(chunk_tiles - EDGE_MARGIN_TILES * 2, 1)
	for index in range(count):
		var lane_tile := EDGE_MARGIN_TILES + posmod(rng.randi_range(0, available - 1) + index * 17, available)
		# Two-tile roads always start on even cells, matching the 64px road width.
		lane_tile -= posmod(lane_tile, 2)
		var street_kind: StringName = &"collector" if index == 0 else &"local"
		portals.append({
			"portal_id": StringName("edge_%d_%d_%d_%d_%02d" % [first.x, first.y, second.x, second.y, index]),
			"lane_tile": lane_tile,
			"width": 64.0 if rng.randi_range(0, 3) > 0 else 96.0,
			"kind": street_kind,
			"surface": &"asphalt" if street_kind == &"collector" else &"cobble",
			"tram": index == 0 and posmod(rng.randi(), 7) == 0,
			"canonical_tangent": second - first,
		})
	return portals

static func _neighbor(coordinate: Vector2i, side: int) -> Vector2i:
	match side:
		Side.NORTH: return coordinate + Vector2i.UP
		Side.EAST: return coordinate + Vector2i.RIGHT
		Side.SOUTH: return coordinate + Vector2i.DOWN
		_: return coordinate + Vector2i.LEFT

static func _comes_after(a: Vector2i, b: Vector2i) -> bool:
	return a.x > b.x or (a.x == b.x and a.y > b.y)
