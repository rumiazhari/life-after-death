class_name VoxelBuildingShellRuntime
extends Node3D

## Project-Zomboid-style building shell presentation. Extracts wall/window
## voxels out of the merged base chunk into per-building runs grouped as
## camera-facing ("front"), rear-plus-corner-posts ("back"), and interior
## partitions, so entering a building lowers the walls between the camera
## and the player's room while corner posts and rear walls stay full height.
## The fixed isometric yaw means the front/back split is resolved once per
## populate from the tracked camera; a free-rotating camera would need to
## re-split geometry before lowering. A lazily created hidden per-chunk
## collision proxy keeps full-height wall collision regardless of visuals.

const COORDINATES := preload("res://scripts/voxel/voxel_coordinates.gd")
const CHUNK_DATA := preload("res://scripts/voxel/voxel_chunk_data.gd")
const CHUNK_RENDERER := preload("res://scripts/voxel/voxel_chunk.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")

const SIDE_NORMALS: Dictionary = {
	&"north": Vector2(0.0, -1.0),
	&"east": Vector2(1.0, 0.0),
	&"south": Vector2(0.0, 1.0),
	&"west": Vector2(-1.0, 0.0),
}
const DEFAULT_FRONT_SIDES: Array[StringName] = [&"east", &"south"]
const CUT_SCALE_Y := 0.34
const CUT_TWEEN_SECONDS := 0.14
const MAX_CHUNK_BUILDS_PER_FRAME := 2
const WALL_MATERIALS: Array[int] = [MATERIALS.Id.BRICK, MATERIALS.Id.GLASS, MATERIALS.Id.BOARD]
const NO_EXCLUDED_KINDS: Array[StringName] = []

var world_data
var _damage_service
var _shared_materials: Array[Material] = []
var _chunk_buildings: Dictionary = {} # Vector2i -> {stable id -> {root: Node3D, runs: {StringName -> VoxelChunk}}}
var _collision_proxies: Dictionary = {} # Vector2i -> VoxelChunk
var _cutaway_buildings: Dictionary = {} # stable id -> true
var _front_sides: Array[StringName] = DEFAULT_FRONT_SIDES.duplicate()
var _pending_coordinates: Dictionary = {} # Vector2i -> true


func configure(data, damage_service = null) -> void:
	world_data = data
	_damage_service = damage_service
	_shared_materials = MATERIALS.create_render_materials()


func _process(_delta: float) -> void:
	var built := 0
	for coordinate_variant in _pending_coordinates.keys():
		if built >= MAX_CHUNK_BUILDS_PER_FRAME:
			return
		var coordinate: Vector2i = coordinate_variant
		_pending_coordinates.erase(coordinate)
		populate_chunk(coordinate)
		built += 1


func request_chunk(coordinate: Vector2i) -> void:
	_pending_coordinates[coordinate] = true


func cancel_chunk(coordinate: Vector2i) -> void:
	_pending_coordinates.erase(coordinate)


func pending_count() -> int:
	return _pending_coordinates.size()


func populate_chunk(coordinate: Vector2i) -> int:
	clear_chunk(coordinate)
	if world_data == null:
		return 0
	var source = world_data.get_chunk(coordinate)
	if source == null:
		return 0
	var groups: Dictionary = {} # building id -> {group name -> CHUNK_DATA}
	for cell_variant in source.cells:
		var cell: Vector3i = cell_variant
		var material_id := int(source.cells[cell])
		var cell_source: StringName = source.source_at(cell)
		var building_id := _resolve_building_id(material_id, cell_source)
		if building_id == &"":
			continue
		var group := _classify_cell(cell, coordinate, building_id)
		if group == &"":
			continue
		var building_groups: Dictionary = groups.get_or_add(building_id, {})
		var chunk_data: CHUNK_DATA = building_groups.get_or_add(group, CHUNK_DATA.new(coordinate))
		chunk_data.set_cell(cell, material_id, cell_source)
	var created := 0
	for building_id_variant in groups:
		var building_id := StringName(building_id_variant)
		var entry := _create_building_root(coordinate, building_id, groups[building_id])
		_register_damage(coordinate, entry, groups[building_id].keys(), building_id)
		(_chunk_buildings.get_or_add(coordinate, {}) as Dictionary)[building_id] = entry
		if _cutaway_buildings.has(building_id):
			_apply_cutaway(entry, building_id, true, false)
		created += (groups[building_id] as Dictionary).size()
	return created


func clear_chunk(coordinate: Vector2i) -> void:
	var buildings: Dictionary = _chunk_buildings.get(coordinate, {})
	for building_id_variant in buildings:
		var entry: Dictionary = buildings[building_id_variant]
		var root: Node = entry.get("root")
		if is_instance_valid(root):
			root.queue_free()
	_chunk_buildings.erase(coordinate)
	var proxy: Node = _collision_proxies.get(coordinate)
	if is_instance_valid(proxy):
		proxy.queue_free()
	_collision_proxies.erase(coordinate)


func set_cutaway(building_id: StringName, active: bool, front_sides: Array[StringName]) -> void:
	if active:
		_cutaway_buildings[building_id] = true
	else:
		_cutaway_buildings.erase(building_id)
	set_front_sides(front_sides)
	for coordinate_variant in _chunk_buildings:
		var buildings: Dictionary = _chunk_buildings[coordinate_variant]
		if buildings.has(building_id):
			_apply_cutaway(buildings[building_id], building_id, active, true)


func set_front_sides(front_sides: Array[StringName]) -> void:
	if front_sides.is_empty():
		return
	_front_sides = front_sides.duplicate()


func is_cutaway(building_id: StringName) -> bool:
	return _cutaway_buildings.has(building_id)


func front_sides() -> Array[StringName]:
	return _front_sides.duplicate()


func shell_root_count() -> int:
	var total := 0
	for coordinate_variant in _chunk_buildings:
		total += (_chunk_buildings[coordinate_variant] as Dictionary).size()
	return total


func collision_proxy_count() -> int:
	return _collision_proxies.size()


func set_collision_coordinates(coordinates: Array[Vector2i]) -> void:
	var wanted: Dictionary = {}
	for coordinate in coordinates:
		wanted[coordinate] = true
	for coordinate_variant in _collision_proxies.keys():
		var existing_coordinate: Vector2i = coordinate_variant
		if not wanted.has(existing_coordinate):
			var stale: Node = _collision_proxies[existing_coordinate]
			if is_instance_valid(stale):
				stale.queue_free()
			_collision_proxies.erase(existing_coordinate)
	for coordinate_variant in wanted:
		var coordinate: Vector2i = coordinate_variant
		if _collision_proxies.has(coordinate):
			continue
		var source = world_data.get_chunk(coordinate) if world_data != null else null
		if source == null:
			continue
		_create_collision_proxy(coordinate, source)


func _resolve_building_id(material_id: int, cell_source: StringName) -> StringName:
	if material_id == MATERIALS.Id.BRICK:
		return cell_source if _kind_of(cell_source) == &"building" else &""
	if material_id == MATERIALS.Id.GLASS or material_id == MATERIALS.Id.BOARD:
		if _kind_of(cell_source) != &"window":
			return &""
		var record: Dictionary = world_data.get_stable_object(cell_source)
		var owner_id := StringName((record.get("state", {}) as Dictionary).get("building", &""))
		return owner_id if _kind_of(owner_id) == &"building" else &""
	return &""


func _kind_of(stable_id: StringName) -> StringName:
	if stable_id == &"" or world_data == null:
		return &""
	return StringName(world_data.get_stable_object(stable_id).get("kind", &""))


func _classify_cell(cell: Vector3i, coordinate: Vector2i, building_id: StringName) -> StringName:
	var record: Dictionary = world_data.get_stable_object(building_id)
	var bounds: Array = (record.get("state", {}) as Dictionary).get("bounds", [])
	if bounds.size() != 4:
		return &""
	var world_cell := COORDINATES.local_to_world_cell(cell, coordinate)
	var min_x := int(bounds[0])
	var min_z := int(bounds[1])
	var max_x := int(bounds[2])
	var max_z := int(bounds[3])
	var x_extreme := world_cell.x == min_x or world_cell.x == max_x
	var z_extreme := world_cell.z == min_z or world_cell.z == max_z
	if x_extreme and z_extreme:
		return &"back"
	if x_extreme or z_extreme:
		var outward := Vector2(
			1.0 if world_cell.x == max_x else (-1.0 if world_cell.x == min_x else 0.0),
			1.0 if world_cell.z == max_z else (-1.0 if world_cell.z == min_z else 0.0)
		).normalized()
		for side_name in _front_sides:
			if (SIDE_NORMALS[side_name] as Vector2).dot(outward) > 0.5:
				return &"front"
		return &"back"
	return &"interior"


func _create_building_root(coordinate: Vector2i, building_id: StringName, groups: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = "Shell_%s_%d_%d" % [_safe_suffix(building_id), coordinate.x, coordinate.y]
	root.position = Vector3(coordinate.x * COORDINATES.CHUNK_CELLS, 0.0, coordinate.y * COORDINATES.CHUNK_CELLS)
	add_child(root)
	var runs: Dictionary = {}
	for group_name_variant in groups:
		var group_name := StringName(group_name_variant)
		var chunk_data: CHUNK_DATA = groups[group_name]
		var renderer = _create_renderer(root, group_name, chunk_data)
		runs[group_name] = renderer
	return {"root": root, "runs": runs}


func _create_renderer(parent: Node, group_name: StringName, chunk_data):
	var renderer = CHUNK_RENDERER.new()
	renderer.name = String(group_name)
	renderer.generate_collision = false
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	renderer.add_child(mesh)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	renderer.add_child(collision)
	renderer.configure(chunk_data.cells, _shared_materials.duplicate())
	parent.add_child(renderer)
	return renderer


func _register_damage(coordinate: Vector2i, entry: Dictionary, group_names: Array, building_id: StringName) -> void:
	if _damage_service == null:
		return
	var runs: Dictionary = entry.get("runs", {})
	for group_name_variant in group_names:
		var renderer = runs.get(StringName(group_name_variant))
		if renderer == null:
			continue
		_damage_service.register_renderer(coordinate, renderer, WALL_MATERIALS.duplicate(), false, &"", NO_EXCLUDED_KINDS.duplicate(), _building_filter.bind(building_id))


func _create_collision_proxy(coordinate: Vector2i, source) -> void:
	var filtered = CHUNK_DATA.new(coordinate)
	for cell_variant in source.cells:
		var cell: Vector3i = cell_variant
		var material_id := int(source.cells[cell])
		var cell_source: StringName = source.source_at(cell)
		var kind := _kind_of(cell_source)
		var is_wall := material_id == MATERIALS.Id.BRICK and kind == &"building"
		is_wall = is_wall or ((material_id == MATERIALS.Id.GLASS or material_id == MATERIALS.Id.BOARD) and kind == &"window")
		if is_wall:
			filtered.set_cell(cell, material_id, cell_source)
	if filtered.cells.is_empty():
		return
	var proxy = CHUNK_RENDERER.new()
	proxy.name = "WallCollision_%d_%d" % [coordinate.x, coordinate.y]
	proxy.position = Vector3(coordinate.x * COORDINATES.CHUNK_CELLS, 0.0, coordinate.y * COORDINATES.CHUNK_CELLS)
	proxy.generate_collision = true
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.visible = false
	proxy.add_child(mesh)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	proxy.add_child(collision)
	proxy.configure(filtered.cells, _shared_materials.duplicate())
	add_child(proxy)
	_collision_proxies[coordinate] = proxy
	if _damage_service != null:
		_damage_service.register_renderer(coordinate, proxy, WALL_MATERIALS.duplicate(), false, &"", NO_EXCLUDED_KINDS.duplicate(), _any_wall_filter)


func _building_filter(_cell: Vector3i, material_id: int, cell_source: StringName, building_id: StringName) -> bool:
	return _resolve_building_id(material_id, cell_source) == building_id


func _any_wall_filter(_cell: Vector3i, material_id: int, cell_source: StringName) -> bool:
	var kind := _kind_of(cell_source)
	if material_id == MATERIALS.Id.BRICK:
		return kind == &"building"
	return kind == &"window"


func _apply_cutaway(entry: Dictionary, _building_id: StringName, active: bool, animate: bool) -> void:
	var runs: Dictionary = entry.get("runs", {})
	var lowered: Dictionary = {}
	if active:
		lowered[&"front"] = true
		lowered[&"interior"] = true
	for group_name_variant in runs:
		var group_name := StringName(group_name_variant)
		var renderer: Node3D = runs[group_name_variant]
		if not is_instance_valid(renderer):
			continue
		var target_scale := CUT_SCALE_Y if lowered.has(group_name) else 1.0
		_tween_scale_y(renderer, target_scale, animate)


func _tween_scale_y(node: Node3D, target_scale: float, animate: bool) -> void:
	if node.has_meta("cutaway_tween"):
		var existing: Tween = node.get_meta("cutaway_tween")
		if existing != null and existing.is_valid():
			existing.kill()
	if not animate:
		node.scale.y = target_scale
		return
	if is_equal_approx(node.scale.y, target_scale):
		return
	var tween := create_tween()
	tween.tween_property(node, "scale:y", target_scale, CUT_TWEEN_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	node.set_meta("cutaway_tween", tween)


func _safe_suffix(building_id: StringName) -> String:
	return String(building_id).replace("/", "__").replace(":", "_")
