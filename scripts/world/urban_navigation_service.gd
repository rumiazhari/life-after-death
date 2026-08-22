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
var direct_path_checks_total: int = 0
var path_requests_total: int = 0
var _door_cells: Dictionary = {} ## StringName door_id -> Array[Vector2i] aperture cells
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
	# Preserve the authored district's historical grid origin exactly.  Its
	# 1400px half extent is intentionally not tile-aligned, and changing that
	# origin shifts every landmark/navigation fixture by eight pixels.
	var size := Vector2i(ceili(half_extent.x * 2.0 / CELL_SIZE), ceili(half_extent.y * 2.0 / CELL_SIZE))
	_origin = -half_extent
	_build_grid(size)

## StreamingWorld rebuilds only the currently resident rectangle.  The grid
## therefore remains bounded even though semantic chunk coordinates do not.
func build_rect(world_rect: Rect2) -> void:
	var aligned_position := Vector2(floorf(world_rect.position.x / CELL_SIZE) * CELL_SIZE, floorf(world_rect.position.y / CELL_SIZE) * CELL_SIZE)
	var aligned_end := Vector2(ceilf(world_rect.end.x / CELL_SIZE) * CELL_SIZE, ceilf(world_rect.end.y / CELL_SIZE) * CELL_SIZE)
	var size := Vector2i(roundi((aligned_end.x - aligned_position.x) / CELL_SIZE), roundi((aligned_end.y - aligned_position.y) / CELL_SIZE))
	_origin = aligned_position
	_build_grid(size)

func _build_grid(size: Vector2i) -> void:
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

func register_door(door_id: StringName, world_position: Vector2, aperture_size: Vector2 = Vector2(CELL_SIZE, CELL_SIZE)) -> void:
	var aperture := Rect2(world_position - aperture_size * 0.5, aperture_size)
	var cells: Array[Vector2i] = []
	var from_cell := world_to_cell(aperture.position)
	var to_cell := world_to_cell(aperture.end - Vector2(0.001, 0.001))
	for x in range(from_cell.x, to_cell.x + 1):
		for y in range(from_cell.y, to_cell.y + 1):
			var cell := Vector2i(x, y)
			if _grid.is_in_boundsv(cell):
				cells.append(cell)
	_door_cells[door_id] = cells

func mark_door_open(door_id: StringName) -> void:
	if _door_cells.has(door_id):
		for cell: Vector2i in _door_cells[door_id]:
			_grid.set_point_solid(cell, false)
		_revision += 1

func mark_door_closed(door_id: StringName) -> void:
	if _door_cells.has(door_id):
		for cell: Vector2i in _door_cells[door_id]:
			_grid.set_point_solid(cell, true)
		_revision += 1

## Destructible environment bodies call this while their body is being
## removed. Cells are re-sampled against every OTHER World collider instead
## of blindly opened; overlapping walls/furniture therefore stay solid.
func mark_area_free(world_rect: Rect2, excluded_rid: RID = RID()) -> void:
	if not _built:
		return
	var from_cell := world_to_cell(world_rect.position)
	var to_cell := world_to_cell(world_rect.end - Vector2(0.001, 0.001))
	var changed := false
	var space_state := get_tree().root.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = WORLD_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	if excluded_rid.is_valid():
		query.exclude = [excluded_rid]
	for x in range(from_cell.x, to_cell.x + 1):
		for y in range(from_cell.y, to_cell.y + 1):
			var cell := Vector2i(x, y)
			if not _grid.is_in_boundsv(cell):
				continue
			query.position = _cell_to_world(cell)
			var should_be_solid := not space_state.intersect_point(query, 1).is_empty()
			if _grid.is_point_solid(cell) != should_be_solid:
				_grid.set_point_solid(cell, should_be_solid)
				changed = true
	if changed:
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

## Unbudgeted connectivity predicate for spawn/landmark validation. It does
## not increment the per-frame actor path budget and returns true before the
## grid is built, matching is_position_free()'s pre-build contract.
func are_positions_connected(from: Vector2, to: Vector2) -> bool:
	if not _built:
		return true
	var from_cell := world_to_cell(from)
	var to_cell := world_to_cell(to)
	if not _grid.is_in_boundsv(from_cell) or not _grid.is_in_boundsv(to_cell):
		return false
	if _grid.is_point_solid(from_cell) or _grid.is_point_solid(to_cell):
		return false
	return not _grid.get_id_path(from_cell, to_cell).is_empty()

func is_built() -> bool:
	return _built

func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori((pos.x - _origin.x) / CELL_SIZE), floori((pos.y - _origin.y) / CELL_SIZE))

func _cell_to_world(cell: Vector2i) -> Vector2:
	return _origin + Vector2(cell.x * CELL_SIZE + CELL_SIZE * 0.5, cell.y * CELL_SIZE + CELL_SIZE * 0.5)

## A quick, cheap check for "can I just walk there in a straight line" --
## agents should call this BEFORE find_path() and only fall back to a real
## path when it returns false, so most short-range movement (the vast
## majority of actor movement in this game) never touches the grid at all.
func is_direct_path_clear(from: Vector2, to: Vector2) -> bool:
	direct_path_checks_total += 1
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
	path_requests_total += 1
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
	direct_path_checks_total = 0
	path_requests_total = 0
	_revision += 1
