extends Node
## Autoload "UrbanNavigationService". One shared AStarGrid2D built once
## from the fixed district's static World-layer collision -- not a
## NavigationAgent2D per zombie each doing its own unbounded pathfinding
## every frame. Callers should prefer direct steering (see
## `is_direct_path_clear`) and only request an actual path when blocked;
## `find_path` itself is budget-capped per physics frame so a burst of
## simultaneous requests (e.g. a whole swarm losing line of sight at once)
## can never spike one frame's cost.
##
## Door-aware: `mark_door_open`/`mark_door_closed` flip that door's single
## grid cell's solidity, so a path already computed through a since-closed
## door is no longer offered, and a newly-opened door reopens that route --
## Door itself calls these from its own toggle().

const CELL_SIZE := 32
const MAX_REQUESTS_PER_FRAME := 8
const WORLD_MASK := 1 # World layer only -- Vision-only occluders (e.g. boarded windows with no physical body) never affect walkability.

## Distinguishes WHY a path request didn't return a usable path -- callers
## (Survivor/Zombie) must treat these differently rather than collapsing
## every failure into "steer straight at the goal anyway," which is exactly
## what could walk an actor straight into an obstacle when the real path is
## blocked but the request was merely deferred or the grid isn't ready yet.
enum PathResult { SUCCESS, BUDGET_DEFERRED, NO_PATH, NOT_READY }

var _grid := AStarGrid2D.new()
var _origin: Vector2 = Vector2.ZERO ## world position of cell (0,0)'s top-left corner
var _built: bool = false
var _requests_this_frame: int = 0
var _door_cells: Dictionary = {} ## StringName door_id -> Vector2i cell
## Bumped whenever the grid is rebuilt or any door's walkability changes --
## a path cached by a caller becomes stale the instant this changes, since
## the route it was computed against may no longer be valid (or a
## previously-blocked route may have just opened up). Callers store the
## revision alongside their cached path and discard it on mismatch rather
## than re-validating the path's own cells themselves.
var _revision: int = 0

func revision() -> int:
	return _revision

func _physics_process(_delta: float) -> void:
	_requests_this_frame = 0

## Builds (or rebuilds) the grid from the district's current static World
## collision via a physics point query per cell -- a one-time cost paid
## once at district load, not per frame. `half_extent` is the district's
## own arena_half_size.
func build(half_extent: Vector2) -> void:
	var size := Vector2i(ceili(half_extent.x * 2.0 / CELL_SIZE), ceili(half_extent.y * 2.0 / CELL_SIZE))
	_origin = -half_extent
	_grid.region = Rect2i(Vector2i.ZERO, size)
	_grid.cell_size = Vector2(CELL_SIZE, CELL_SIZE)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	var space_state := get_tree().root.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = WORLD_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for gx in range(size.x):
		for gy in range(size.y):
			query.position = _cell_to_world(Vector2i(gx, gy))
			var solid: bool = not space_state.intersect_point(query, 1).is_empty()
			_grid.set_point_solid(Vector2i(gx, gy), solid)
	_built = true
	_door_cells.clear()
	_revision += 1

func register_door(door_id: StringName, world_position: Vector2) -> void:
	_door_cells[door_id] = world_to_cell(world_position)

func mark_door_open(door_id: StringName) -> void:
	if _door_cells.has(door_id):
		_grid.set_point_solid(_door_cells[door_id], false)
		_revision += 1

func mark_door_closed(door_id: StringName) -> void:
	if _door_cells.has(door_id):
		_grid.set_point_solid(_door_cells[door_id], true)
		_revision += 1

## True when `pos`'s grid cell exists and isn't solid -- used by
## SpawnManager to reject a candidate spawn point that would land inside
## an out-of-bounds or wall-occupied cell. Before `build()` has run (grid
## not yet established) everything reads as free, since there is no
## solidity data to reject against yet.
func is_position_free(pos: Vector2) -> bool:
	if not _built:
		return true
	var cell: Vector2i = world_to_cell(pos)
	if not _grid.is_in_boundsv(cell):
		return false
	return not _grid.is_point_solid(cell)

func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori((pos.x - _origin.x) / CELL_SIZE), floori((pos.y - _origin.y) / CELL_SIZE))

func _cell_to_world(cell: Vector2i) -> Vector2:
	return _origin + Vector2(cell.x * CELL_SIZE + CELL_SIZE * 0.5, cell.y * CELL_SIZE + CELL_SIZE * 0.5)

## A quick, cheap check for "can I just walk there in a straight line" --
## agents should call this BEFORE find_path() and only fall back to a real
## path when it returns false, so most short-range movement (the vast
## majority of actor movement in this game) never touches the grid at all.
func is_direct_path_clear(from: Vector2, to: Vector2) -> bool:
	var space_state := get_tree().root.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, WORLD_MASK)
	return space_state.intersect_ray(query).is_empty()

## Returns an empty path if the budget is exhausted this frame, the grid
## isn't built yet, or no path exists -- callers must treat all three the
## same way (fall back to direct steering / stay put) rather than crashing
## on an empty result.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if not _built or _requests_this_frame >= MAX_REQUESTS_PER_FRAME:
		return PackedVector2Array()
	_requests_this_frame += 1
	var from_cell: Vector2i = world_to_cell(from)
	var to_cell: Vector2i = world_to_cell(to)
	if not _grid.is_in_boundsv(from_cell) or not _grid.is_in_boundsv(to_cell):
		return PackedVector2Array()
	return _grid.get_point_path(from_cell, to_cell)

## Status-aware sibling of find_path() -- returns
## {status: PathResult, path: PackedVector2Array, revision: int}. Prefer this
## over find_path() for any caller that caches its result across frames
## (Survivor/Zombie): BUDGET_DEFERRED and NO_PATH must not be handled the
## same way (a deferred request should retry, a real no-path result should
## give up and report failure), and `revision` is what a caller compares
## against a fresh UrbanNavigationService.revision() to know its cached path
## is still valid.
func find_path_ex(from: Vector2, to: Vector2) -> Dictionary:
	if not _built:
		return {"status": PathResult.NOT_READY, "path": PackedVector2Array(), "revision": _revision}
	if _requests_this_frame >= MAX_REQUESTS_PER_FRAME:
		return {"status": PathResult.BUDGET_DEFERRED, "path": PackedVector2Array(), "revision": _revision}
	_requests_this_frame += 1
	var from_cell: Vector2i = world_to_cell(from)
	var to_cell: Vector2i = world_to_cell(to)
	if not _grid.is_in_boundsv(from_cell) or not _grid.is_in_boundsv(to_cell):
		return {"status": PathResult.NO_PATH, "path": PackedVector2Array(), "revision": _revision}
	var path: PackedVector2Array = _grid.get_point_path(from_cell, to_cell)
	if path.is_empty():
		return {"status": PathResult.NO_PATH, "path": path, "revision": _revision}
	return {"status": PathResult.SUCCESS, "path": path, "revision": _revision}

func requests_this_frame() -> int:
	return _requests_this_frame

## Clears the built grid and door registry -- used by the test harness so
## one test's `build(small_area)` can never make a later, unrelated test's
## `is_position_free()`/`find_path()` calls see stale out-of-bounds data
## for a completely different part of the map.
func reset() -> void:
	_built = false
	_grid = AStarGrid2D.new()
	_origin = Vector2.ZERO
	_door_cells.clear()
	_requests_this_frame = 0
	_revision += 1
