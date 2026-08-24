class_name BuildingWorld3D
extends Node3D
## The 2.5D layer: every generated building gets a dedicated small 3D
## viewport containing REAL stacked geometry -- floor slabs, one wall box
## per wall cell per storey (with window/door insets on the street face),
## and a per-tile roof -- displayed through an orthographic camera at a
## fixed 2.5D pitch. Each display container is parented into the y-sorted
## entity layer anchored at the building's south baseline, so occlusion
## against actors behaves exactly like the old flat facade did.
##
## Destruction in the semantic model drives this geometry: dead wall cells
## lose their columns (all storeys), roof bays rain down tile-by-tile, and
## structural cascades flatten whole x-columns. Gameplay collision stays on
## the 2D plane (ground floor); this layer is presentation truth.

const STOREY_HEIGHT := 40.0
const CELL := 32.0
const WALL_COLOR := Color(0.78, 0.70, 0.55)
const WALL_SIDING := Color(0.66, 0.58, 0.46)
const FLOOR_COLOR := Color(0.45, 0.40, 0.34)
const GLASS_COLOR := Color(0.16, 0.22, 0.26)
const DOOR_COLOR := Color(0.36, 0.22, 0.13)
const ROOF_COLORS := {
	"A": Color(0.59, 0.27, 0.24), "B": Color(0.35, 0.43, 0.51),
	"C": Color(0.59, 0.54, 0.38), "D": Color(0.39, 0.55, 0.43),
}
const CAMERA_PITCH_DEG := 55.0
const CAMERA_DISTANCE := 900.0
## Ground-plane depth compresses by sin(pitch) on screen; used for framing.
const PAD_X := 28.0
const PAD_TOP := 26.0
const PAD_BOTTOM := 14.0

## building_id -> record {viewport, container, camera, cells, roof, spec, details}
var _buildings: Dictionary = {}

## Mapping: 2D (x, y) -> 3D (x, up=height, z=y).
static func to3d(p: Vector2, height := 0.0) -> Vector3:
	return Vector3(p.x, height, p.y)

func register_building(building: ProceduralBuilding) -> Dictionary:
	var spec: Dictionary = building.specification
	var id: StringName = spec["id"]
	if _buildings.has(id):
		return _buildings[id]
	var interior: Dictionary = spec["interior"]
	var half_extent: Vector2 = interior["half_extent"]
	var storeys: int = clampi(int(spec.get("storeys", 3)), 2, 6)

	var ground_depth := half_extent.y * 2.0
	var wall_stack := STOREY_HEIGHT * float(storeys)
	var view_w := half_extent.x * 2.0 + PAD_X * 2.0
	var view_h := ground_depth * 0.82 + wall_stack * 0.60 + PAD_TOP + PAD_BOTTOM

	var viewport := SubViewport.new()
	viewport.name = String(id).get_file() + "_25D"
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.size = Vector2i(maxi(int(view_w), 64), maxi(int(view_h), 64))

	var container := SubViewportContainer.new()
	container.name = String(id).get_file() + "_Display"
	container.stretch = true
	container.size = Vector2(view_w, view_h)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	container.add_child(viewport)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, 18.0, 0.0)
	light.light_energy = 1.15
	viewport.add_child(light)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(view_h, 100.0)
	camera.current = true
	var target := Vector3(0.0, wall_stack * 0.32, half_extent.y * 0.35)
	var pitch := deg_to_rad(CAMERA_PITCH_DEG)
	camera.position = target + Vector3(0.0, sin(pitch) * CAMERA_DISTANCE, cos(pitch) * CAMERA_DISTANCE)
	camera.look_at(target, Vector3.UP)
	viewport.add_child(camera)

	var record := {
		"viewport": viewport, "container": container, "camera": camera,
		"spec": spec, "storeys": storeys, "half_extent": half_extent,
		"cells": {}, "roof": {}, "details": 0,
	}
	_buildings[id] = record

	_build_geometry(record, building, interior, storeys)
	return record

func _build_geometry(record: Dictionary, building: ProceduralBuilding, interior: Dictionary, storeys: int) -> void:
	var viewport: SubViewport = record["viewport"]
	var half_extent: Vector2 = record["half_extent"]

	for rect_variant in interior.get("perimeter_rects", []):
		var rect: Rect2 = rect_variant
		var slab := _box(Vector3(rect.size.x, 4.0, rect.size.y), FLOOR_COLOR)
		slab.position = to3d(rect.get_center(), 0.0)
		viewport.add_child(slab)

	# Entrance x (world-local) for the ground-floor door inset.
	var entrance_x := INF
	for door_variant in interior.get("doors", []):
		var door: Dictionary = door_variant
		if bool(door["exterior"]):
			entrance_x = (door["position"] as Vector2).x
			break

	for child in building.get_children():
		if not (child is StaticBody2D):
			continue
		var damage_comp := child.get_node_or_null("EnvironmentDamageComponent") as EnvironmentDamageComponent
		if damage_comp == null or not "/wall_" in String(damage_comp.object_id):
			continue
		var local: Vector2 = (child as Node2D).position
		var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
		var south_face := local.y >= half_extent.y - CELL
		for storey in range(storeys):
			var mesh := _box(Vector3(CELL, STOREY_HEIGHT * 0.96, CELL),
				WALL_COLOR if storey % 2 == 0 else WALL_SIDING)
			mesh.position = to3d(local, STOREY_HEIGHT * float(storey) + STOREY_HEIGHT * 0.5)
			viewport.add_child(mesh)
			if south_face:
				record["details"] += _add_street_face_details(mesh, storeys, storey, entrance_x, local.x)
			if not record["cells"].has(cell):
				record["cells"][cell] = []
			(record["cells"][cell] as Array).append(mesh)

	var roof_layer := building.get_node_or_null("Roof") as TileMapLayer
	if roof_layer != null:
		var roof_color: Color = ROOF_COLORS.get(String(interior.get("roof_material", "A")), Color(0.5, 0.3, 0.3))
		for cell in roof_layer.get_used_cells():
			var tile := _box(Vector3(CELL, 6.0, CELL), roof_color.darkened(0.08 * float(absi(cell.x + cell.y) % 3)))
			tile.position = to3d(Vector2(cell) * CELL + Vector2(CELL * 0.5, CELL * 0.5), STOREY_HEIGHT * float(storeys))
			viewport.add_child(tile)
			record["roof"][cell] = tile

## Windows on every above-ground storey + a door inset beside the entrance
## on the ground floor. Insets are CHILDREN of the wall box so they fall
## with it on destruction.
func _add_street_face_details(wall_mesh: MeshInstance3D, total_storeys: int, storey: int, entrance_x: float, cell_center_x: float) -> int:
	var added := 0
	var face_z := CELL * 0.5 + 1.2
	if storey == 0:
		if absf(cell_center_x - entrance_x) <= CELL * 0.75:
			var door := _box(Vector3(20.0, 26.0, 2.4), DOOR_COLOR)
			door.position = Vector3(0.0, -STOREY_HEIGHT * 0.18, face_z)
			wall_mesh.add_child(door)
			added += 1
		return added
	var window_y := STOREY_HEIGHT * 0.08
	for offset_x in [-8.0, 8.0]:
		var window := _box(Vector3(11.0, 10.0, 2.2), GLASS_COLOR)
		window.position = Vector3(offset_x, window_y, face_z)
		wall_mesh.add_child(window)
		added += 1
	return added

## Places the display container into the live scene: inside the shared
## y-sorted entity layer anchored at the building's south baseline when one
## exists (restoring facade-style actor occlusion), otherwise attached to
## the building itself.
func attach_display(building: ProceduralBuilding, record: Dictionary) -> void:
	var container: SubViewportContainer = record["container"]
	if container == null or not container.is_inside_tree():
		return
	var interior: Dictionary = building.specification["interior"]
	var half_extent: Vector2 = interior["half_extent"]
	var entity_layer: Node2D = building.get_tree().get_first_node_in_group("entity_container") as Node2D
	var parent_node: Node2D = entity_layer if entity_layer != null else building
	if container.get_parent() != parent_node:
		container.reparent(parent_node, true)
	# Align: project the south-baseline center through the camera and place
	# the container so that pixel lands exactly on the world anchor.
	var anchor_local := Vector2(0.0, half_extent.y)
	var anchor_world: Vector2 = building.to_global(anchor_local)
	var camera: Camera3D = record["camera"]
	var pixel: Vector2 = camera.unproject_position(to3d(anchor_local))
	container.global_position = anchor_world - pixel
	if entity_layer != null and container.get_parent() != entity_layer:
		pass # already reparented above

func remove_wall_column(world_local: Vector2) -> void:
	var cell := Vector2i(floori(world_local.x / CELL), floori(world_local.y / CELL))
	for building_id in _buildings:
		var record: Dictionary = _buildings[building_id]
		if not (record["cells"] as Dictionary).has(cell):
			continue
		for mesh in (record["cells"][cell] as Array):
			_drop_and_free(mesh)
		record["cells"].erase(cell)

func collapse_roof_tiles(cells: Array) -> void:
	for building_id in _buildings:
		var roof_map: Dictionary = (_buildings[building_id] as Dictionary)["roof"]
		for cell_variant in cells:
			var cell: Vector2i = cell_variant
			if roof_map.has(cell):
				_drop_and_free(roof_map[cell])
				roof_map.erase(cell)

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

func get_facade_detail_count() -> int:
	var total := 0
	for building_id in _buildings:
		total += int((_buildings[building_id] as Dictionary).get("details", 0))
	return total

func get_record_for(building: ProceduralBuilding) -> Dictionary:
	return _buildings.get(specification_id(building), {})

func specification_id(building: ProceduralBuilding) -> StringName:
	return building.specification["id"]

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