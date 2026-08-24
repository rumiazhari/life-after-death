class_name ProceduralBuilding
extends BuildingVisibilityController
## Runtime renderer/controller for one already-validated semantic building.
## configure() constructs the complete subtree before tree entry so Room,
## Door, loot, persistence, and destruction components see their final stable
## IDs in their own _ready() callbacks.

const DOOR_SCENE := preload("res://scenes/world/Door.tscn")
const WINDOW_SCENE := preload("res://scenes/world/Window.tscn")

var specification: Dictionary = {}
var _configured := false
var _facade_visual: BuildingFacadeVisual

func configure(spec: Dictionary) -> void:
	assert(not is_inside_tree(), "ProceduralBuilding.configure must run before add_child")
	assert(not _configured, "ProceduralBuilding can only be configured once")
	specification = spec.duplicate(true)
	building_id = specification["id"]
	name = String(building_id).replace("/", "_")
	roof_node_path = NodePath("Roof")
	rooms_container_path = NodePath("Rooms")
	_construct_subtree()
	_configured = true

func _ready() -> void:
	if not _configured:
		push_error("ProceduralBuilding entered the tree before configure()")
		return
	super._ready()

func _construct_subtree() -> void:
	var interior: Dictionary = specification["interior"]
	var rooms_container := Node2D.new()
	rooms_container.name = "Rooms"
	add_child(rooms_container)
	var doors_container := Node2D.new()
	doors_container.name = "Doors"
	add_child(doors_container)

	var rooms_by_id: Dictionary = {}
	for room_spec in interior["rooms"]:
		var room := Room.new()
		room.name = _node_name(room_spec["id"])
		room.room_id = room_spec["id"]
		room.building_id = building_id
		var rect: Rect2 = room_spec["rect"]
		room.position = rect.get_center()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var collision := CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		collision.shape = shape
		room.add_child(collision)
		rooms_container.add_child(room)
		rooms_by_id[room.room_id] = room
		BuildingShellBuilder.fill_floor(room, rect.size * 0.5, room_spec["floor_tile"])

	var doors_by_id: Dictionary = {}
	for door_spec in interior["doors"]:
		var door := DOOR_SCENE.instantiate() as Door
		door.name = _node_name(door_spec["id"])
		door.door_id = door_spec["id"]
		door.position = door_spec["position"]
		door.rotation = float(door_spec["rotation"])
		door.aperture_size = door_spec.get("aperture_size", Vector2(32, 32))
		doors_container.add_child(door)
		doors_by_id[door.door_id] = door
		var room_a: Room = rooms_by_id.get(door_spec["room_a"])
		if room_a:
			room_a.doors.append(door)
		var room_b_id: StringName = door_spec["room_b"]
		var room_b: Room = rooms_by_id.get(room_b_id) if room_b_id != &"" else null
		if room_b:
			room_b.doors.append(door)

	var windows_by_id: Dictionary = {}
	for window_spec in interior["windows"]:
		var window := WINDOW_SCENE.instantiate() as BuildingWindow
		window.name = _node_name(window_spec["id"])
		window.window_id = window_spec["id"]
		window.position = window_spec["position"]
		window.rotation = float(window_spec["rotation"])
		window.is_boarded = bool(window_spec["boarded"])
		add_child(window)
		windows_by_id[window.window_id] = window
		var room: Room = rooms_by_id.get(window_spec["room_id"])
		if room:
			room.windows.append(window)

	_build_shell(interior)
	_build_furniture(interior, rooms_by_id)

func _build_shell(interior: Dictionary) -> void:
	var perimeter_gaps: Array[Rect2] = []
	for door_spec in interior["doors"]:
		if bool(door_spec["exterior"]):
			var aperture: Vector2 = door_spec.get("aperture_size", Vector2(32, 32))
			perimeter_gaps.append(ProceduralBuildingGenerator.door_bay_rect(door_spec["position"], aperture))
	for window_spec in interior["windows"]:
		perimeter_gaps.append(Rect2((window_spec["position"] as Vector2) - Vector2(16, 16), Vector2(32, 32)))
	var wall_texture: Texture2D = load(interior["wall_texture"])
	var interior_wall_texture: Texture2D = load(interior["interior_wall_texture"])
	var half_extent: Vector2 = interior["half_extent"]
	var perimeter_rects: Array = interior.get("perimeter_rects", [Rect2(-half_extent, half_extent * 2.0)])
	if perimeter_rects.size() == 1:
		BuildingShellBuilder.build_perimeter_walls(self, interior["half_extent"], wall_texture, perimeter_gaps)
	else:
		BuildingShellBuilder.build_compound_perimeter_walls(self, perimeter_rects, wall_texture, perimeter_gaps)
	for partition in interior["partitions"]:
		var gaps: Array[Rect2] = []
		for gap in partition["gaps"]:
			gaps.append(gap)
		BuildingShellBuilder.build_partition(self, partition["from"], partition["to"], interior_wall_texture, gaps)
	var exterior_nodes := BuildingExteriorRenderer.build(self, specification, interior)
	_facade_visual = exterior_nodes["facade"]
	_wire_wall_destruction_sync()
	# 2.5D: when the shared 3D building layer exists, it becomes the visual
	# truth (real stacked geometry); the flat facade/roof step aside.
	# Registration is deferred because it needs this node inside the tree
	# (world lookups + container parenting into the entity layer).
	call_deferred("_register_with_world_25d")

func _register_with_world_25d() -> void:
	if not is_inside_tree():
		return
	var world_25d: Node = _world_25d()
	if world_25d == null:
		return
	var record: Dictionary = world_25d.register_building(self)
	world_25d.attach_display(self, record)
	if _facade_visual != null:
		_facade_visual.visible = false
	var roof := get_node_or_null(roof_node_path) as TileMapLayer
	if roof != null:
		roof.visible = false

## Logical spatial sync between interior wall destruction and the projected
## exterior: destroying a perimeter wall segment erases the roof tile(s)
## above that footprint cell and notches the south facade if the segment sat
## on the street-facing edge -- so the elevation always tells the truth about
## the interior below it. Destroyed state persists by stable id, so rebuilt
## buildings re-open the same holes.
func _wire_wall_destruction_sync() -> void:
	for child in get_children():
		if child is StaticBody2D:
			var damage_comp := child.get_node_or_null("EnvironmentDamageComponent") as EnvironmentDamageComponent
			if damage_comp == null or not String(damage_comp.object_id).contains("/wall_"):
				continue
			damage_comp.destroyed.connect(_on_wall_segment_destroyed.bind(damage_comp))
			if WorldState.get_prop_state_flag(damage_comp.object_id, &"destroyed", false):
				call_deferred("_apply_wall_breach", damage_comp)
	# Restore persisted facade wounds: destroyed wall BODIES are freed, so
	# their positions come from this record rather than live nodes.
	var stored_xs: Variant = WorldState.get_prop_state_flag(_south_breaches_key(), &"xs", null)
	if stored_xs is PackedFloat32Array:
		for stored_x in (stored_xs as PackedFloat32Array):
			if _facade_visual != null:
				_facade_visual.add_ground_breach(stored_x)
		call_deferred("_refresh_south_facade_state")

func _on_wall_segment_destroyed(_object_id: StringName, comp: EnvironmentDamageComponent) -> void:
	_apply_wall_breach(comp)

func _south_breaches_key() -> StringName:
	return StringName("%s/south_breaches" % String(specification["id"]))

## Records a dead south segment's position so the facade wound survives
## rebuilds (the wall body itself is freed on destruction).
func _record_south_breach(local_x: float) -> void:
	var key := _south_breaches_key()
	var arr_variant: Variant = WorldState.get_prop_state_flag(key, &"xs", null)
	var arr: PackedFloat32Array = arr_variant if arr_variant is PackedFloat32Array else PackedFloat32Array()
	for existing in arr:
		if absf(existing - local_x) < 1.0:
			return
	arr.append(local_x)
	arr.sort()
	WorldState.set_prop_state_flag(key, &"xs", arr)
func _apply_wall_breach(comp: EnvironmentDamageComponent) -> void:
	var body := comp.get_parent() as Node2D
	if body == null:
		return
	var local := body.position
	var interior: Dictionary = specification.get("interior", {})
	var edge := _perimeter_edge_for(local, interior.get("perimeter_rects", []))
	var roof := get_node_or_null(roof_node_path) as TileMapLayer
	if roof != null:
		if edge == &"none":
			_collapse_roof_patch(roof, local)
		else:
			_collapse_roof_bay(roof, local, edge, interior.get("perimeter_rects", []), comp)
			_forward_roof_to_25d(_bay_cells_for(interior, local, edge))
	if edge == &"south":
		if _facade_visual != null:
			_facade_visual.add_ground_breach(local.x)
		_record_south_breach(local.x)
		_refresh_south_facade_state()
	_forward_wall_to_25d(local)
func _perimeter_edge_for(p: Vector2, rects: Array) -> StringName:
	var margin := PixelAtlasMap.TILE_SIZE * 0.5 + 1.0
	for rect_variant in rects:
		var rect: Rect2 = rect_variant
		if absf(p.y - rect.position.y) <= margin:
			return &"north"
		if absf(p.y - rect.end.y) <= margin:
			return &"south"
		if absf(p.x - rect.position.x) <= margin:
			return &"west"
		if absf(p.x - rect.end.x) <= margin:
			return &"east"
	return &"none"

## Erases the full straight run of roof cells from the breached edge across
## the footprint -- the span that lost its support falls down to the floor.
## Bounded to cells the roof actually painted (compound notches stop it).
func _collapse_roof_bay(roof: TileMapLayer, p: Vector2, edge: StringName, rects: Array, comp: EnvironmentDamageComponent) -> void:
	var target := Rect2()
	var best := INF
	for rect_variant in rects:
		var rect: Rect2 = rect_variant
		var distance: float = absf(p.x - rect.get_center().x) + absf(p.y - rect.get_center().y)
		if distance < best:
			best = distance
			target = rect
	if target.size == Vector2.ZERO:
		return
	var ts := PixelAtlasMap.TILE_SIZE
	var cells: Array[Vector2i] = []
	if edge == &"north" or edge == &"south":
		var cy := floori(p.y / ts)
		var x0 := floori((target.position.x + 8.0) / ts)
		var x1 := floori((target.end.x - 8.0) / ts)
		for cx in range(x0, x1 + 1):
			cells.append(Vector2i(cx, cy))
	else:
		var cx := floori(p.x / ts)
		var y0 := floori((target.position.y + 8.0) / ts)
		var y1 := floori((target.end.y - 8.0) / ts)
		for cy in range(y0, y1 + 1):
			cells.append(Vector2i(cx, cy))
	var erased_positions: Array[Vector2] = []
	var erased := 0
	for cell in cells:
		if not roof.get_used_cells().has(cell):
			continue
		roof.erase_cell(cell)
		erased += 1
		if erased <= 3:
			erased_positions.append(Vector2(cell) * ts + Vector2(ts * 0.5, ts * 0.5))
		if erased >= 64:
			break
	_spawn_falling_roof_debris(roof, comp, erased_positions)

## A few roof pieces rain into the rooms below the collapsed bay.
func _spawn_falling_roof_debris(roof: TileMapLayer, comp: EnvironmentDamageComponent, positions: Array[Vector2]) -> void:
	if positions.is_empty():
		return
	var debris_script: Script = load("res://scripts/physics/physics_debris.gd")
	var container := get_tree().get_first_node_in_group("entity_container")
	if container == null:
		container = self
	var texture := comp.debris_texture
	var rng := RandomNumberGenerator.new()
	rng.seed = int(String(comp.object_id).hash())
	for i in range(positions.size()):
		var world_position := roof.to_global(positions[i])
		debris_script.spawn(container, world_position, texture, Vector2(12, 8),
			Vector2(rng.randf_range(-60, 60), rng.randf_range(-20, 40)), Color(0.85, 0.82, 0.78))

func _collapse_roof_patch(roof: TileMapLayer, p: Vector2) -> void:
	var base := Vector2i(floori(p.x / PixelAtlasMap.TILE_SIZE), floori(p.y / PixelAtlasMap.TILE_SIZE))
	for offset in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var cell: Vector2i = base + offset
		if roof.get_used_cells().has(cell):
			roof.erase_cell(cell)

func _build_furniture(interior: Dictionary, rooms_by_id: Dictionary) -> void:
	for furniture in interior["furniture"]:
		var room: Room = rooms_by_id.get(furniture["room_id"])
		if room == null:
			continue
		var local_position: Vector2 = (furniture["position"] as Vector2) - room.position
		var texture: Texture2D = load(furniture["texture"])
		var mode: StringName = furniture["mode"]
		var visual_size: Vector2 = furniture.get("visual_size", Vector2.ZERO)
		var sprite_rotation: float = (PI * 0.5) if bool(furniture.get("overturned", false)) else 0.0
		var tint := Color.WHITE
		if bool(furniture.get("damaged", false)):
			tint = Color(0.72, 0.68, 0.62)
		if furniture.has("tint"):
			tint = furniture["tint"]
		match mode:
			&"decal":
				# Ground detail with no collision and no interaction.
				var sprite := Sprite2D.new()
				sprite.texture = texture
				if visual_size != Vector2.ZERO and texture != null and texture.get_size().x > 0.0:
					sprite.scale = visual_size / texture.get_size()
				sprite.position = local_position
				sprite.z_index = -6
				if tint != Color.WHITE:
					sprite.modulate = tint
				room.add_child(sprite)
				continue
			&"loot":
				BuildingShellBuilder.add_loot_furniture(
					room, local_position, texture, furniture["size"], furniture["id"],
					float(furniture["capacity"]), furniture["items"], "Search", int(furniture["minimum_damage_class"]),
					visual_size, sprite_rotation, tint
				)
			&"salvage":
				BuildingShellBuilder.add_salvage_prop(
					room, local_position, texture, furniture["size"], furniture["id"], int(furniture["yield"]),
					visual_size, sprite_rotation, tint
				)
			_:
				BuildingShellBuilder.add_physical_prop(
					room, local_position, texture, furniture["size"], furniture["id"],
					int(furniture["yield"]), int(furniture["minimum_damage_class"]),
					visual_size, sprite_rotation, tint
				)
		var built := room.get_child(room.get_child_count() - 1) as Node2D
		if built != null:
			PhysicsReactionComponent.attach(built, PhysicsReactionComponent.mass_class_for_kind(furniture["kind"]))
			PhysicsReactionComponent.restore_moved_transform(built, furniture["id"])
			# Chunky furniture breaks quarter-by-quarter before collapsing.
			if furniture["kind"] in [&"dining_table", &"round_table", &"coffee_table", &"desk", &"sofa", &"sofa_b", &"armchair",
					&"wardrobe", &"dresser", &"shelf_row", &"grocery_shelf_short", &"grocery_shelf_long",
					&"aisle_shelf", &"industrial_shelf", &"workbench", &"cabinet", &"bed_single", &"bed_double",
					&"exam_bed", &"bookshelf", &"locker", &"bar_counter", &"checkout_counter", &"reception_desk",
					&"tv_stand", &"tool_cabinet", &"pallet_rack", &"machinery", &"fridge_display", &"freezer_chest"]:
				var piece_damage := _find_damage_component(built)
				if piece_damage != null:
					piece_damage.sub_cells = 2
					piece_damage.fail_threshold = 0.5

func _find_damage_component(root: Node) -> EnvironmentDamageComponent:
	if root.name == "EnvironmentDamageComponent":
		return root as EnvironmentDamageComponent
	for child in root.get_children():
		var found := _find_damage_component(child)
		if found != null:
			return found
	return null

func _node_name(stable_id: StringName) -> String:
	return String(stable_id).get_file().to_pascal_case()

func semantic_room_count() -> int:
	return (specification.get("interior", {}).get("rooms", []) as Array).size()

func exterior_entrance_positions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for door in specification.get("interior", {}).get("doors", []):
		if bool(door["exterior"]):
			result.append(global_transform * (door["position"] as Vector2))
	return result

## Rubric: a collapsing storey throws real rubble out of its base, once per
## newly collapsed column.
func _spawn_cascade_debris(x: float, ground_y: float) -> void:
	var debris_script: Script = load("res://scripts/physics/physics_debris.gd")
	var container := get_tree().get_first_node_in_group("entity_container")
	if container == null:
		container = self
	var world_base := to_global(Vector2(x, ground_y))
	for i in range(4):
		debris_script.spawn(container, world_base + Vector2(randf_range(-10.0, 10.0), randf_range(-6.0, 6.0)),
			load("res://assets/pixel/props/debris_small.png"), Vector2(12, 9),
			Vector2(randf_range(-140.0, 140.0), randf_range(-160.0, -60.0)), Color(0.85, 0.8, 0.74))
## Deterministic structural cascade for the street face: destroyed segments
## are known from the persisted south-breach record (destroyed wall bodies
## are freed), so rebuilds re-collapse the same columns.
func _refresh_south_facade_state() -> void:
	if _facade_visual == null:
		return
	var interior: Dictionary = specification.get("interior", {})
	var half_extent: Vector2 = interior.get("half_extent", Vector2.ZERO)
	var entries: Array[Dictionary] = []
	var stored_xs: Variant = WorldState.get_prop_state_flag(_south_breaches_key(), &"xs", null)
	if stored_xs is PackedFloat32Array:
		for stored_x in (stored_xs as PackedFloat32Array):
			entries.append({"x": float(stored_x), "destroyed": true})
	for child in get_children():
		if not (child is StaticBody2D):
			continue
		var candidate := child.get_node_or_null("EnvironmentDamageComponent") as EnvironmentDamageComponent
		if candidate == null or not "/wall_" in String(candidate.object_id):
			continue
		var pos: Vector2 = (child as Node2D).position
		if pos.y < half_extent.y - PixelAtlasMap.TILE_SIZE:
			continue
		if WorldState.get_prop_state_flag(candidate.object_id, &"destroyed", false):
			continue
		var duplicate := false
		for entry in entries:
			if absf(float(entry["x"]) - pos.x) < PixelAtlasMap.TILE_SIZE * 0.5:
				duplicate = true
				break
		if not duplicate:
			entries.append({"x": pos.x, "destroyed": false})
	if entries.size() < 2:
		for entry in entries:
			_facade_visual.set_upper_damage(entry["x"], 1 if bool(entry["destroyed"]) else 0)
		return
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["x"] < b["x"])
	var destroyed_count := 0
	for entry in entries:
		destroyed_count += 1 if bool(entry["destroyed"]) else 0
	var cascading := destroyed_count * 2 >= entries.size()
	var runs: Array[Array] = []
	var current_run: Array = []
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		if bool(entry["destroyed"]):
			if not current_run.is_empty() and absf(float(entry["x"]) - float((current_run.back() as Dictionary)["x"])) > PixelAtlasMap.TILE_SIZE * 1.5:
				runs.append(current_run)
				current_run = []
			current_run.append(entry)
		elif not current_run.is_empty():
			runs.append(current_run)
			current_run = []
	if not current_run.is_empty():
		runs.append(current_run)
	for run in runs:
		var run_collapses: bool = run.size() >= 2 or cascading
		for entry_variant in run:
			var entry: Dictionary = entry_variant
			var x: float = entry["x"]
			if run_collapses:
				if not _facade_visual.collapse_columns.has(x):
					_spawn_cascade_debris(x, half_extent.y)
				_facade_visual.add_collapse_column(x)
				_forward_cascade_to_25d(x)
			else:
				_facade_visual.set_upper_damage(x, clampi(run.size(), 1, 3))
	for run in runs:
		if run.size() >= 2 or cascading:
			continue
		for entry_variant in run:
			var entry: Dictionary = entry_variant
			_facade_visual.set_upper_damage(entry["x"], clampi(run.size(), 1, 3))
## --- 2.5D bridge -------------------------------------------------------
## When a BuildingWorld3D layer exists (Main creates it), destruction events
## are mirrored into real stacked geometry. Without it (standalone fixtures,
## tests) these are silent no-ops.
func _world_25d() -> Node:
	return get_tree().get_first_node_in_group("building_world_25d") if is_inside_tree() else null

func _forward_wall_to_25d(local: Vector2) -> void:
	var world: Node = _world_25d()
	if world != null:
		world.remove_wall_column(local)

func _forward_roof_to_25d(cells: Array) -> void:
	var world: Node = _world_25d()
	if world != null:
		world.collapse_roof_tiles(cells)

func _forward_cascade_to_25d(local_x: float) -> void:
	var world: Node = _world_25d()
	if world != null:
		world.collapse_column(local_x)

func _bay_cells_for(interior: Dictionary, local: Vector2, edge: StringName) -> Array:
	var ts := PixelAtlasMap.TILE_SIZE
	var target := target_of_rect(interior, local)
	var cells: Array = []
	if edge == &"north" or edge == &"south":
		var cy := floori(local.y / ts)
		var x0 := floori((target.position.x + 8.0) / ts)
		var x1 := floori((target.end.x - 8.0) / ts)
		for cx in range(x0, x1 + 1):
			cells.append(Vector2i(cx, cy))
	else:
		var cx := floori(local.x / ts)
		var y0 := floori((target.position.y + 8.0) / ts)
		var y1 := floori((target.end.y - 8.0) / ts)
		for cy in range(y0, y1 + 1):
			cells.append(Vector2i(cx, cy))
	return cells

func target_of_rect(interior: Dictionary, local: Vector2) -> Rect2:
	var best := Rect2()
	var best_distance := INF
	for rect_variant in interior.get("perimeter_rects", []):
		var rect: Rect2 = rect_variant
		var distance: float = absf(local.x - rect.get_center().x) + absf(local.y - rect.get_center().y)
		if distance < best_distance:
			best_distance = distance
			best = rect
	return best

func attach_exterior_sort_parent(sort_parent: Node2D) -> BuildingFacadeVisual:
	if _facade_visual == null or sort_parent == null or _facade_visual.get_parent() == sort_parent:
		return _facade_visual
	_facade_visual.reparent(sort_parent, true)
	return _facade_visual

func projected_facade() -> BuildingFacadeVisual:
	return _facade_visual

func _exit_tree() -> void:
	if is_instance_valid(_facade_visual) and _facade_visual.get_parent() != self and not _facade_visual.is_queued_for_deletion():
		_facade_visual.queue_free()
