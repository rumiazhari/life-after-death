class_name EnvironmentDamageComponent
extends Node
## Durable, partially destructible structure: a bounded microcell damage mask.
##
## A destructible body (wall cell, barricade, large furniture piece) carries
## an N x N grid of microcells across its `affected_size`. Damage events carry
## world hit geometry (position/direction/radius via the source node) and eat
## away nearby microcells instead of deleting the whole object:
##   intact -> damaged -> partially broken -> structurally failed.
## Collision is rebuilt from surviving cells as merged rectangles; navigation
## only opens where an actual full-thickness breach exists; the mask persists
## through WorldState prop state. At structural failure the legacy whole-body
## destruction path takes over (debris burst, loot drop, nav free).

signal damaged(remaining: float, amount: float)
signal destroyed(object_id: StringName)
signal partially_damaged(fraction: float)

## Microcells below this integrity count as destroyed (float-dust guard).
const CELL_EPSILON := 0.001

@export var object_id: StringName = &""
@export_enum("Small Arms", "Heavy", "Explosive") var minimum_damage_class: int = 0
@export var max_durability: float = 30.0
@export var affected_size: Vector2 = Vector2(32, 32)
## Structural destruction spawns this many bounded physical debris chunks at
## FULL structural failure. Zero keeps the no-debris behavior.
@export var debris_count: int = 0
@export var debris_texture: Texture2D = null
## Microgrid resolution per axis. 1 = legacy whole-object durability;
## walls use 4 (8 px microcells), chunky furniture 2-3.
var sub_cells: int = 1
## Alive fraction at or below which the structure collapses entirely.
var fail_threshold := 0.4

var destroy_target: Node = null
var _durability: float = 0.0
var _destroyed: bool = false
var _last_hit_direction := Vector2.ZERO

# --- partial grid state ---
var _cell_cols := 1
var _cell_rows := 1
var _cell_hp := PackedFloat32Array()
var _cell_max := 0.0
var _grid_active := false
var _partial_visual: Node2D = null

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
	# Deferred: _ready cascades run while parents are mid-setup and cannot
	# accept new children.
	call_deferred("_build_partial_visual")

func _build_partial_visual() -> void:
	var parent_node := get_parent()
	if parent_node == null or not (parent_node is Node2D):
		return
	var sprite := (parent_node as Node2D).get_child(0) if (parent_node as Node2D).get_child_count() > 0 else null
	var texture: Texture2D = debris_texture
	if sprite is Sprite2D and (sprite as Sprite2D).texture != null:
		texture = (sprite as Sprite2D).texture
		sprite.visible = false
	if texture == null:
		return
	# Lazy load: an eager preload here would create a parse-time dependency
	# cycle across the damage classes.
	_partial_visual = load("res://scripts/combat/partial_structure_visual.gd").new()
	_partial_visual.name = "PartialVisual"
	(parent_node as Node2D).add_child(_partial_visual)
	_partial_visual.setup(texture, Vector2.ZERO, affected_size / Vector2(_cell_cols, _cell_rows), _cell_cols, _cell_rows, alive_cells())

func alive_cells() -> Array:
	var alive: Array = []
	for i in range(_cell_hp.size()):
		alive.append(_cell_hp[i] > 0.0)
	return alive

func alive_fraction() -> float:
	if not _grid_active:
		return 1.0 if _durability > 0.0 else 0.0
	var alive := 0
	for hp in _cell_hp:
		if hp > CELL_EPSILON:
			alive += 1
	return float(alive) / float(_cell_hp.size())

func apply_damage(amount: float, damage_class: int, source: Node = null) -> bool:
	if _destroyed or amount <= 0.0 or damage_class < minimum_damage_class:
		return false
	if _source_is_node2d(source):
		var direction: Vector2 = body_global_position() - (source as Node2D).global_position
		if direction.length_squared() > 0.01:
			_last_hit_direction = direction.normalized()
	_durability = maxf(_durability - amount, 0.0)
	if _grid_active:
		_apply_grid_damage(amount, damage_class, source)
	if object_id != &"":
		WorldState.set_prop_state_flag(object_id, &"durability", _durability)
	damaged.emit(_durability, amount)
	partially_damaged.emit(alive_fraction())
	if _grid_active:
		if alive_fraction() <= fail_threshold:
			_destroy()
			return true
	elif _durability <= 0.0:
		_destroy()
		return true
	return true

## Distributes one damage event across microcells: cells are consumed in
## strict distance order from the impact point, so a small round kills the
## nearest cell or two (a corner chip), a heavy blast eats an irregular
## radial bite, and massive overkill keeps sweeping until the block is level.
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
	if OS.has_environment("GRID_DEBUG"):
		var dump := "sorted:"
		for i in range(mini(ordered.size(), 4)):
			dump += " i=%d d=%.1f" % [ordered[i]["index"], ordered[i]["dist"]]
		print(dump, " amount=", amount)
	for entry in ordered:
		if remaining <= CELL_EPSILON:
			break
		var dist: float = entry["dist"]
		var index: int = entry["index"]
		var falloff := clampf(1.25 - dist / maxf(focus_radius, 0.01), 0.35, 1.0)
		var applied_to_cell := minf(remaining * falloff, _cell_hp[index])
		_cell_hp[index] -= applied_to_cell
		remaining -= applied_to_cell
	_persist_mask()
	_rebuild_partial_geometry()

func _rebuild_partial_geometry() -> void:
	_refresh_visual()
	_refresh_collision()
	_refresh_navigation()

func _refresh_visual() -> void:
	if _partial_visual != null and is_instance_valid(_partial_visual):
		_partial_visual.set_cells(alive_cells())

## Rebuilds merged collision rectangles from surviving cells (row-run greedy
## merge keeps shape count tiny).
func _refresh_collision() -> void:
	var body := get_parent()
	if body == null:
		return
	for child in body.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).name.begins_with("PartialCell"):
			child.queue_free()
	if not _grid_active:
		return
	var cell_size := affected_size / Vector2(_cell_cols, _cell_rows)
	for row in range(_cell_rows):
		var col := 0
		while col < _cell_cols:
			if _cell_hp[row * _cell_cols + col] <= 0.0:
				col += 1
				continue
			var run := 1
			while col + run < _cell_cols and _cell_hp[row * _cell_cols + col + run] > 0.0:
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

## Opens navigation ONLY where dead microcells form a full-thickness breach
## wide enough for an actor -- chipping a corner never frees the whole cell.
func _refresh_navigation() -> void:
	if not _grid_active:
		return
	var cell_size := affected_size / Vector2(_cell_cols, _cell_rows)
	var strips: Array[Rect2] = []
	# Vertical breaches: full-height runs of dead columns.
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
	# Horizontal breaches: full-width runs of dead rows.
	var row := 0
	while row < _cell_rows:
		if _row_alive(row):
			row += 1
			continue
		var h_start := row
		while row < _cell_rows and not _row_alive(row):
			row += 1
		strips.append(Rect2(Vector2(0, h_start * cell_size.y), Vector2(affected_size.x, cell_size.y * (row - h_start))))
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

func _persist_mask() -> void:
	if object_id != &"" and _grid_active:
		WorldState.set_prop_state_flag(object_id, &"partial_cells", _cell_hp.duplicate())

func body_global_position() -> Vector2:
	var parent_node := get_parent()
	return (parent_node as Node2D).global_position if parent_node is Node2D else Vector2.ZERO

func _source_is_node2d(source: Node) -> bool:
	return source != null and is_instance_valid(source) and source is Node2D

func durability() -> float:
	return _durability

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
	_spawn_destruction_debris(body)
	var excluded_rid := RID()
	if get_parent() is CollisionObject2D:
		excluded_rid = (get_parent() as CollisionObject2D).get_rid()
	UrbanNavigationService.mark_area_free(Rect2(world_position - affected_size * 0.5, affected_size), excluded_rid)
	destroyed.emit(object_id)
	if target != null and is_instance_valid(target):
		target.call_deferred("queue_free")

## A bounded burst of physical chunks flying along the last hit direction.
## Loaded lazily: keeps this script's compile-time dependencies minimal.
func _spawn_destruction_debris(body: Node2D) -> void:
	if debris_count <= 0 or debris_texture == null or body == null:
		return
	var container := _external_container(body)
	var debris_script: Script = load("res://scripts/physics/physics_debris.gd")
	for i in range(debris_count):
		var direction := _last_hit_direction if _last_hit_direction != Vector2.ZERO else Vector2.RIGHT.rotated(float(i) * TAU / float(debris_count))
		var spread := direction.rotated((float(i) - float(debris_count - 1) * 0.5) * 0.5)
		debris_script.spawn(container, body.global_position + spread * 6.0, debris_texture,
			Vector2(9.0, 7.0), spread * 300.0)

## Debris belongs to the shared entity layer when one exists so it survives
## chunk-local teardown ordering like every other world object.
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
