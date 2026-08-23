class_name BuildingWorld3D
extends Node3D
## The 2.5D layer: every generated building is rebuilt here as REAL stacked
## geometry -- floor slabs, one wall box per wall cell per storey, and a
## per-tile roof -- rendered through an orthographic camera matched to the
## 2D camera. Destruction in the semantic model drives this geometry:
## dead wall cells lose their columns (all storeys), roof bays rain down,
## and structural cascades flatten whole columns. Gameplay collision stays
## on the 2D plane (ground floor); this layer is presentation truth.

const STOREY_HEIGHT := 34.0
const CELL := 32.0
const WALL_COLOR := Color(0.78, 0.70, 0.55)
const WALL_SIDING := Color(0.66, 0.58, 0.46)
const FLOOR_COLOR := Color(0.45, 0.40, 0.34)
const ROOF_COLORS := {
	"A": Color(0.59, 0.27, 0.24), "B": Color(0.35, 0.43, 0.51),
	"C": Color(0.59, 0.54, 0.38), "D": Color(0.39, 0.55, 0.43),
}

var _viewport: SubViewport
var _camera: Camera3D
var _tracked_rig: Node = null
## building_id -> {cells: {Vector2i -> Array[MeshInstance3D]}, roof: {Vector2i -> MeshInstance3D}, spec}
var _buildings: Dictionary = {}

func _ready() -> void:
	add_to_group("building_world_25d")
	_viewport = SubViewport.new()
	_viewport.name = "Viewport25D"
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, 18.0, 0.0)
	light.light_energy = 1.15
	_viewport.add_child(light)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_viewport.add_child(_camera)
	_apply_camera_transform(Vector2.ZERO, 1.0)
	get_viewport().size_changed.connect(_match_viewport_size)
	_match_viewport_size()

func _match_viewport_size() -> void:
	if _viewport == null:
		return
	var size := get_viewport().get_visible_rect().size
	_viewport.size = Vector2i(size)

## Matches the 2D camera: same screen center, same zoom, fixed 2.5D pitch.
## Mapping: 2D (x, y) -> 3D (x, up=height, z=y).
func track(camera_rig: Node) -> void:
	_tracked_rig = camera_rig

func _process(_delta: float) -> void:
	if _tracked_rig == null or not is_instance_valid(_tracked_rig):
		return
	var center: Vector2 = _tracked_rig.get_screen_center_position()
	var zoom: Vector2 = _tracked_rig.zoom
	_apply_camera_transform(center, zoom.y)

func _apply_camera_transform(center: Vector2, zoom_y: float) -> void:
	if _viewport == null:
		return
	var view_size := Vector2(_viewport.size)
	_camera.size = maxf(view_size.y / maxf(zoom_y, 0.01), 100.0)
	# Pull back along the view direction so the ortho frustum centers on the
	# 2D screen center at ground level.
	var distance := 600.0
	var pitch := deg_to_rad(-52.0)
	var offset := Vector3(0.0, sin(-pitch) * distance, cos(-pitch) * distance)
	_camera.global_position = Vector3(center.x, 0.0, center.y) + offset
	_camera.look_at(Vector3(center.x, 0.0, center.y), Vector3.UP)

static func to3d(p: Vector2, height := 0.0) -> Vector3:
	return Vector3(p.x, height, p.y)

## Builds the stacked geometry for one generated building spec.
func register_building(building: ProceduralBuilding) -> void:
	var spec: Dictionary = building.specification
	var id: StringName = spec["id"]
	if _buildings.has(id):
		return
	var interior: Dictionary = spec["interior"]
	var half_extent: Vector2 = interior["half_extent"]
	var storeys: int = clampi(int(spec.get("storeys", 3)), 2, 6)
	var record := {"cells": {}, "roof": {}, "spec": spec, "building": building}
	_buildings[id] = record

	# Floor slab per footprint rect.
	for rect_variant in interior.get("perimeter_rects", []):
		var rect: Rect2 = rect_variant
		var slab := _box(Vector3(rect.size.x, 4.0, rect.size.y), FLOOR_COLOR)
		slab.position = to3d(rect.get_center(), 0.0)
		add_child(slab)

	# Wall columns: one box per semantic wall cell per storey.
	for child in building.get_children():
		if not (child is StaticBody2D):
			continue
		var damage_comp := child.get_node_or_null("EnvironmentDamageComponent") as EnvironmentDamageComponent
		if damage_comp == null or not "/wall_" in String(damage_comp.object_id):
			continue
		var local: Vector2 = (child as Node2D).position
		var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
		for storey in range(storeys):
			var mesh := _box(Vector3(CELL, STOREY_HEIGHT * 0.96, CELL),
				WALL_COLOR if storey % 2 == 0 else WALL_SIDING)
			mesh.position = to3d(local, STOREY_HEIGHT * float(storey) + STOREY_HEIGHT * 0.5)
			add_child(mesh)
			if not record["cells"].has(cell):
				record["cells"][cell] = []
			(record["cells"][cell] as Array).append(mesh)

	# Roof tiles mirror the 2D roof layer exactly (compound shapes included).
	var roof_layer := building.get_node_or_null("Roof") as TileMapLayer
	if roof_layer != null:
		var roof_color: Color = ROOF_COLORS.get(String(interior.get("roof_material", "A")), Color(0.5, 0.3, 0.3))
		for cell in roof_layer.get_used_cells():
			var tile := _box(Vector3(CELL, 6.0, CELL), roof_color.darkened(0.08 * float(absi(cell.x + cell.y) % 3)))
			tile.position = to3d(Vector2(cell) * CELL + Vector2(CELL * 0.5, CELL * 0.5), STOREY_HEIGHT * float(storeys))
			add_child(tile)
			record["roof"][cell] = tile

## A destroyed wall cell loses its WHOLE column (every storey) -- pieces
## tumble down and fade.
func remove_wall_column(world_local: Vector2) -> void:
	var cell := Vector2i(floori(world_local.x / CELL), floori(world_local.y / CELL))
	for building_id in _buildings:
		var record: Dictionary = _buildings[building_id]
		if not (record["cells"] as Dictionary).has(cell):
			continue
		for mesh in (record["cells"][cell] as Array):
			_drop_and_free(mesh)
		record["cells"].erase(cell)

## Roof bay collapse: erase the given cells' tiles with falling animation.
func collapse_roof_tiles(cells: Array) -> void:
	for building_id in _buildings:
		var roof_map: Dictionary = (_buildings[building_id] as Dictionary)["roof"]
		for cell_variant in cells:
			var cell: Vector2i = cell_variant
			if roof_map.has(cell):
				_drop_and_free(roof_map[cell])
				roof_map.erase(cell)

## Structural cascade: flatten an entire x-column across all upper storeys
## plus its roof strip.
func collapse_column(local_x: float) -> void:
	var cell_x := floori(local_x / CELL)
	for building_id in _buildings:
		var record: Dictionary = _buildings[building_id]
		var cells: Dictionary = record["cells"]
		for cell_key in cells.keys():
			if (cell_key as Vector2i).x != cell_x:
				continue
			for mesh in (cells[cell_key] as Array):
				_drop_and_free(mesh)
			cells.erase(cell_key)
		var roof_map: Dictionary = record["roof"]
		for cell_key in roof_map.keys():
			if (cell_key as Vector2i).x != cell_x:
				continue
			_drop_and_free(roof_map[cell_key])
			roof_map.erase(cell_key)

## Falling animation: drop, tumble slightly, then free. Cheap tween -- no 3D
## physics simulation needed for presentation.
func _drop_and_free(mesh: MeshInstance3D) -> void:
	if mesh == null or not is_instance_valid(mesh):
		return
	var tween := mesh.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh, "position:y", mesh.position.y - STOREY_HEIGHT * 1.5, 0.8)
	tween.tween_property(mesh, "rotation:x", randf_range(-0.7, 0.7), 0.8)
	tween.tween_property(mesh, "rotation:z", randf_range(-0.7, 0.7), 0.8)
	tween.chain().tween_callback(mesh.queue_free)

## Test/automation introspection -------------------------------------------

func get_column_mesh_count(cell: Vector2i) -> int:
	for building_id in _buildings:
		var cells: Dictionary = (_buildings[building_id] as Dictionary)["cells"]
		if cells.has(cell):
			return (cells[cell] as Array).filter(func(m: MeshInstance3D) -> bool:
				return is_instance_valid(m)).size()
	return 0

func count_meshes_in_column_x(cell_x: int) -> int:
	var total := 0
	for building_id in _buildings:
		var record: Dictionary = _buildings[building_id]
		for cell_key in (record["cells"] as Dictionary):
			if (cell_key as Vector2i).x == cell_x:
				for mesh in (record["cells"][cell_key] as Array):
					if is_instance_valid(mesh):
						total += 1
		for cell_key in (record["roof"] as Dictionary):
			if (cell_key as Vector2i).x == cell_x and is_instance_valid(record["roof"][cell_key]):
				total += 1
	return total

func get_roof_tile_count() -> int:
	var total := 0
	for building_id in _buildings:
		var roof_map: Dictionary = (_buildings[building_id] as Dictionary)["roof"]
		for key in roof_map:
			if is_instance_valid(roof_map[key]):
				total += 1
	return total

func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh_instance.material_override = material
	return mesh_instance