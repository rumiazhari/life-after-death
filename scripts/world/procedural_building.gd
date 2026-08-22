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

func _build_furniture(interior: Dictionary, rooms_by_id: Dictionary) -> void:
	for furniture in interior["furniture"]:
		var room: Room = rooms_by_id.get(furniture["room_id"])
		if room == null:
			continue
		var local_position: Vector2 = (furniture["position"] as Vector2) - room.position
		var texture: Texture2D = load(furniture["texture"])
		var mode: StringName = furniture["mode"]
		match mode:
			&"loot":
				BuildingShellBuilder.add_loot_furniture(
					room, local_position, texture, furniture["size"], furniture["id"],
					float(furniture["capacity"]), furniture["items"], "Search", int(furniture["minimum_damage_class"])
				)
			&"salvage":
				BuildingShellBuilder.add_salvage_prop(
					room, local_position, texture, furniture["size"], furniture["id"], int(furniture["yield"])
				)
			_:
				BuildingShellBuilder.add_physical_prop(
					room, local_position, texture, furniture["size"], furniture["id"],
					int(furniture["yield"]), int(furniture["minimum_damage_class"])
				)

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
