class_name EnvironmentDamageComponent
extends Node
## Durable destructible structure with a bounded microcell integrity grid.
##
## VISUAL CONTRACT (single-block model): a structure always renders as ONE
## block -- its original sprite, progressively cracked/darkened as integrity
## drops. Per-microcell overlay drawing never happens. At structural failure
## the block SHATTERS: its sprite disappears and up to four quarter-sized
## physical chunks (the "microblocks separating") fly off along the killing
## blow, replacing whole-body silent removal.
##
## LOGIC GRID: the N x N integrity mask stays authoritative for gameplay --
## collision rectangles rebuild from surviving cells and navigation opens
## only where a full-thickness breach exists; masks persist via WorldState.

signal damaged(remaining: float, amount: float)
signal destroyed(object_id: StringName)

const CELL_EPSILON := 0.001
const MAX_SHATTER_CHUNKS := 4

@export var object_id: StringName = &""
@export_enum("Small Arms", "Heavy", "Explosive") var minimum_damage_class: int = EnvironmentDamage.DamageClass.SMALL_ARMS
@export var max_durability: float = 30.0
@export var affected_size: Vector2 = Vector2(32, 32)
## Quarter-chunks spawned at structural failure.
@export var debris_count: int = 0
@export var debris_texture: Texture2D = null
## Integrity grid resolution per axis. Purely logical: breach widths,
## collision rebuilds and persisted masks -- never per-cell rendering.
@export_range(1, 6) var sub_cells: int = 1
@export_range(0.05, 0.9) var fail_threshold := 0.4

var destroy_target: Node = null
var _durability: float = 0.0
var _destroyed: bool = false
var _last_hit_direction := Vector2.ZERO

var _cell_cols := 1
var _cell_rows := 1
var _cell_hp := PackedFloat32Array()
var _cell_max := 0.0
var _grid_active := false

var _sprite: Sprite2D = null
var _crack_overlay: Node2D = null
var _stage := 0

func _ready() -> void:
	_durability = max_durability
	_setup_grid()
	if object_id != &"":
		if WorldState.get_prop_state_flag(object_id, &"destroyed", false):
			call_deferred("_destroy")
			return
		_durability = float(WorldState.get_prop_state_flag(object_id, &"durability", max_durability))
		var stored_mask: Variant = WorldState.get_prop_state_flag(object_id, &"partial_cells", null)
		if _grid_active and stored_mask is PackedFloat32Array:
			var stored: PackedFloat32Array = stored_mask
			if stored.size() == _cell_hp.size():
				_cell_hp = stored
				_rebuild_partial_geometry()

func _setup_grid() -> void:
	if sub_cells <= 1:
		return
	_cell_cols = sub_cells
	_cell_rows = sub_cells
	_cell_max = maxf(max_durability, 1.0) / float(_cell_cols * _cell_rows)
	_cell_hp.resize(_cell_cols * _cell_rows)
	_cell_hp.fill(_cell_max)
	_grid_active = true
	call_deferred("_cache_sprite")

func _cache_sprite() -> void:
	var target := destroy_target if destroy_target != null and is_instance_valid(destroy_target) else get_parent()
	_sprite = _find_sprite(target)
	if _sprite != null:
		_refresh_damage_stage()

static func _find_sprite(root: Node) -> Sprite2D:
	if root is Sprite2D:
		return root as Sprite2D
	for child in root.get_children():
		var found := _find_sprite(child)
		if found != null:
			return found
	return null

func alive_cells() -> Array:
	var alive: Array = []
	for i in range(_cell_hp.size()):
		alive.append(_cell_hp[i] > CELL_EPSILON)
	return alive

func alive_fraction() -> float:
	if not _grid_active:
		return 1.0 if _durability > 0.0 else 0.0
	var alive := 0
	for hp in _cell_hp:
		if hp > CELL_EPSILON:
			alive += 1
	return float(alive) / float(_cell_hp.size())

## Progressive single-block feedback: darkening + deterministic crack lines,
## never per-cell geometry.
func _refresh_damage_stage() -> void:
	var ratio := _durability / maxf(max_durability, 1.0)
	if _grid_active:
		ratio = minf(ratio, alive_fraction())
	var stage := 0
	if ratio < 0.35:
		stage = 3
	elif ratio < 0.6:
		stage = 2
	elif ratio < 0.85:
		stage = 1
	if stage == _stage and _crack_overlay != null:
		return
	_stage = stage
	if _sprite == null or not is_instance_valid(_sprite):
		return
	match stage:
		0:
			_sprite.modulate = Color.WHITE
			if _crack_overlay != null and is_instance_valid(_crack_overlay):
				_crack_overlay.queue_free()
				_crack_overlay = null
		1, 2, 3:
			_sprite.modulate = Color(1.0 - stage * 0.12, 1.0 - stage * 0.14, 1.0 - stage * 0.16)
			if _crack_overlay == null or not is_instance_valid(_crack_overlay):
				_crack_overlay = load("res://scripts/combat/crack_overlay.gd").new()
				_crack_overlay.name = "CrackOverlay"
				var holder: Node = destroy_target if destroy_target != null and is_instance_valid(destroy_target) else get_parent()
				holder.add_child(_crack_overlay)
				_crack_overlay.z_index = 1
				_crack_overlay.global_position = body_global_position()
			_crack_overlay.stage = stage
			_crack_overlay.size = affected_size
			_crack_overlay.seed_hash = int(String(object_id).hash())
			_crack_overlay.queue_redraw()

## MARKER_REST

func apply_damage(amount: float, damage_class: int, source: Node = null) -> bool:
	if _destroyed or amount <= 0.0 or damage_class < minimum_damage_class:
		return false
	if source is Node2D and is_instance_valid(source):
		var direction: Vector2 = body_global_position() - (source as Node2D).global_position
		if direction.length_squared() > 0.01:
			_last_hit_direction = direction.normalized()
	_durability = maxf(_durability - amount, 0.0)
	if _grid_active:
		_apply_grid_damage(amount, damage_class, source)
	if object_id != &"":
		WorldState.set_prop_state_flag(object_id, &"durability", _durability)
	damaged.emit(_durability, amount)
	if not _grid_active:
		_refresh_damage_stage()
	else:
		_persist_mask()
		_refresh_collision()
		_refresh_navigation()
		_refresh_damage_stage()
		if alive_fraction() <= fail_threshold:
			_destroy()
			return true
	if _durability <= 0.0:
		_destroy()
		return true
	return true

## Distributes one damage event across microcells: strict distance order from
## the impact point -- light hits chip the nearest material first, massive
## overkill sweeps until every cell is gone.
func _apply_grid_damage(amount: float, damage_class: int, source: Node) -> void:
	var hit_local := affected_size * 0.5
	if _source_is_node2d(source):
		var local_hit: Vector2 = (source as Node2D).global_position - body_global_position() + affected_size * 0.5
		hit_local = Vector2(clampf(local_hit.x, 0.0, affected_size.x), clampf(local_hit.y, 0.0, affected_size.y))
	var focus_radius := maxf(minf(affected_size.x, affected_size.y) * 0.4, 8.0)
	match damage_class:
		EnvironmentDamage.DamageClass.SMALL_ARMS:
			focus_radius = 6.0
		EnvironmentDamage.DamageClass.HEAVY:
			focus_radius = 10.0
	var ordered: Array[Dictionary] = []
	for row in range(_cell_rows):
		for col in range(_cell_cols):
			var index := row * _cell_cols + col
			if _cell_hp[index] <= CELL_EPSILON:
				continue
			var cell_center := (Vector2(col, row) + Vector2(0.5, 0.5)) * (affected_size / Vector2(_cell_cols, _cell_rows))
			ordered.append({"index": index, "dist": cell_center.distance_to(hit_local)})
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist"] < b["dist"])
	var remaining := amount
	for entry in ordered:
		if remaining <= CELL_EPSILON:
			break
		var dist: float = entry["dist"]
		var index: int = entry["index"]
		var falloff := clampf(1.25 - dist / maxf(focus_radius, 0.01), 0.35, 1.0)
		var applied_to_cell := minf(remaining * falloff, _cell_hp[index])
		_cell_hp[index] -= applied_to_cell
		remaining -= applied_to_cell

func _persist_mask() -> void:
	if object_id != &"" and _grid_active:
		WorldState.set_prop_state_flag(object_id, &"partial_cells", _cell_hp.duplicate())

func _rebuild_partial_geometry() -> void:
	_refresh_collision()
	_refresh_navigation()

func _refresh_collision() -> void:
	var body := get_parent()
	if body == null:
		return
	for child in body.get_children():
		if child is CollisionShape2D and String(child.name) == "CollisionShape2D":
			# The whole-cell collider yields the moment the grid takes over;
			# surviving microcells become THE collision.
			(child as CollisionShape2D).set_deferred("disabled", true)
	for child in body.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).name.begins_with("PartialCell"):
			child.queue_free()
	if not _grid_active:
		return
	var cell_size := affected_size / Vector2(_cell_cols, _cell_rows)
	for row in range(_cell_rows):
		var col := 0
		while col < _cell_cols:
			if _cell_hp[row * _cell_cols + col] <= CELL_EPSILON:
				col += 1
				continue
			var run := 1
			while col + run < _cell_cols and _cell_hp[row * _cell_cols + col + run] > CELL_EPSILON:
				run += 1
			var shape := RectangleShape2D.new()
			shape.size = Vector2(cell_size.x * run, cell_size.y)
			var collider := CollisionShape2D.new()
			collider.name = "PartialCell_%d_%d" % [row, col]
			collider.shape = shape
			var offset := Vector2((col + run * 0.5) * cell_size.x, (row + 0.5) * cell_size.y) - affected_size * 0.5
			collider.position = offset
			body.add_child(collider)
			col += run

func _refresh_navigation() -> void:
	if not _grid_active:
		return
	var cell_size := affected_size / Vector2(_cell_cols, _cell_rows)
	var strips: Array[Rect2] = []
	var col := 0
	while col < _cell_cols:
		if _column_alive(col):
			col += 1
			continue
		var run_start := col
		while col < _cell_cols and not _column_alive(col):
			col += 1
		strips.append(Rect2(Vector2(run_start * cell_size.x, 0.0),
			Vector2(cell_size.x * (col - run_start), affected_size.y)))
	var row := 0
	while row < _cell_rows:
		if _row_alive(row):
			row += 1
			continue
		var h_start := row
		while row < _cell_rows and not _row_alive(row):
			row += 1
		strips.append(Rect2(Vector2(0.0, h_start * cell_size.y), Vector2(affected_size.x, cell_size.y * (row - h_start))))
	for strip in strips:
		if strip.size.x >= 16.0 or strip.size.y >= 16.0:
			var excluded := RID()
			if get_parent() is CollisionObject2D:
				excluded = (get_parent() as CollisionObject2D).get_rid()
			UrbanNavigationService.mark_area_free(Rect2(body_global_position() - affected_size * 0.5 + strip.position, strip.size), excluded)

func _column_alive(col: int) -> bool:
	for row in range(_cell_rows):
		if _cell_hp[row * _cell_cols + col] > CELL_EPSILON:
			return true
	return false

func _row_alive(row: int) -> bool:
	for col in range(_cell_cols):
		if _cell_hp[row * _cell_cols + col] > CELL_EPSILON:
			return true
	return false

func body_global_position() -> Vector2:
	var parent_node := get_parent()
	return (parent_node as Node2D).global_position if parent_node is Node2D else Vector2.ZERO

func _source_is_node2d(source: Node) -> bool:
	return source != null and is_instance_valid(source) and source is Node2D

func durability() -> float:
	return _durability

## Structural failure: the ONE visible block shatters into its quarter
## chunks along the killing blow, then the legacy removal path runs.
func _destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	if object_id != &"":
		WorldState.set_prop_state_flag(object_id, "destroyed", true)
	var body := get_parent() as Node2D
	var target: Node = destroy_target if destroy_target != null and is_instance_valid(destroy_target) else get_parent()
	var world_position := body_global_position()
	_preserve_loot(target, world_position)
	_shatter_structure(body)
	var excluded_rid := RID()
	if get_parent() is CollisionObject2D:
		excluded_rid = (get_parent() as CollisionObject2D).get_rid()
	UrbanNavigationService.mark_area_free(Rect2(world_position - affected_size * 0.5, affected_size), excluded_rid)
	destroyed.emit(object_id)
	if target != null and is_instance_valid(target):
		target.call_deferred("queue_free")

## The microblocks separating: up to four quarter-sized chunks of this very
## structure fly apart along the killing blow. Bounded by PhysicsDebris caps.
func _shatter_structure(body: Node2D) -> void:
	if body == null:
		return
	var texture := debris_texture
	if texture == null:
		var sprite := _find_sprite(destroy_target if destroy_target != null and is_instance_valid(destroy_target) else body)
		texture = sprite.texture if sprite != null else null
	var chunk_count := maxi(debris_count, mini(sub_cells, MAX_SHATTER_CHUNKS))
	if chunk_count <= 0 or texture == null:
		return
	var container := _external_container(body)
	var chunk_size := affected_size * 0.45
	for i in range(mini(chunk_count, MAX_SHATTER_CHUNKS)):
		var direction := _last_hit_direction if _last_hit_direction != Vector2.ZERO else Vector2.RIGHT.rotated(float(i) * TAU / float(chunk_count))
		var spread := direction.rotated((float(i) - float(chunk_count - 1) * 0.5) * 0.55)
		PhysicsDebris.spawn(container, body.global_position + spread * 8.0, texture,
			chunk_size, spread * (240.0 + float(i) * 40.0), Color.WHITE)

func _external_container(body: Node2D) -> Node:
	var dynamic_world := body.get_tree().get_first_node_in_group("entity_container")
	if dynamic_world != null:
		return dynamic_world
	return body.get_tree().current_scene if body.get_tree().current_scene != null else body.get_parent()

func _preserve_loot(target: Node, world_position: Vector2) -> void:
	if target == null:
		return
	var loot_components: Array[LootContainerComponent] = []
	_collect_loot(target, loot_components)
	var drop_inventory := Inventory.new(0.0)
	for loot in loot_components:
		loot.get_inventory().move_all_to(drop_inventory)
	if drop_inventory.is_empty():
		return
	var drop := WorldDrop.new()
	drop.position = world_position
	drop.reason = &"environment_destroyed"
	drop.created_tick = SimulationClock.tick_count
	drop.inventory = drop_inventory
	WorldState.register_drop(drop)

func _collect_loot(node: Node, output: Array[LootContainerComponent]) -> void:
	if node is LootContainerComponent:
		output.append(node)
	for child in node.get_children():
		_collect_loot(child, output)
