extends Node

const CITY_GENERATOR := preload("res://scripts/world/procedural_city_generator.gd")
const VOXELIZER := preload("res://scripts/voxel/semantic_voxelizer.gd")
const WORLD_DATA := preload("res://scripts/voxel/voxel_world_data.gd")
const COORDINATES := preload("res://scripts/voxel/voxel_coordinates.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")
const SEMANTIC_RUNTIME := preload("res://scripts/voxel/voxel_semantic_runtime.gd")
const SEMANTIC_INTERACTABLE := preload("res://scripts/voxel/voxel_semantic_interactable_3d.gd")

class TestActor extends Node3D:
	var carried_inventory := Inventory.new(5000.0)

var _failed := false


func _ready() -> void:
	WorldState.reset()
	_run()
	WorldState.reset()
	if _failed:
		get_tree().quit(1)
	else:
		print("VOXEL_CITY_CONVERSION: PASS")
		get_tree().quit(0)


func _run() -> void:
	var seed_value := 20260822
	var coordinate := Vector2i.ZERO
	var city: Dictionary = CITY_GENERATOR.new().generate_streamed_chunk(seed_value, coordinate)
	_assert((city.get("validation_errors", []) as Array).is_empty(), "source Prague city model validates")
	var world = VOXELIZER.new().voxelize_chunk(city, seed_value, coordinate)
	_assert(world.stable_objects.size() == _expected_stable_object_count(city), "all buildings, rooms, doors, windows, furniture, exterior props, and scavenge points retain stable ids")
	_assert(_count_kind(world, &"room") == _interior_count(city, "rooms"), "every authored room has voxel metadata")
	_assert(_count_kind(world, &"door") == _interior_count(city, "doors"), "every authored door has voxel metadata")
	_assert(_count_kind(world, &"window") == _interior_count(city, "windows"), "every authored window has voxel metadata")
	_assert(_count_kind(world, &"furniture") == _interior_count(city, "furniture"), "every authored furniture object has voxel metadata")
	_assert(_count_kind(world, &"settlement_storage") == 4 and _count_kind(world, &"rest_point") == 1 and _count_kind(world, &"guard_post") == 1, "origin Prague chunk derives categorized storage, rest, and guard services from its semantic safehouse")
	for stable_id in world.stable_objects:
		var record: Dictionary = world.get_stable_object(stable_id)
		if record.get("kind", &"") == &"building":
			var building_state: Dictionary = record.get("state", {})
			var bounds: Array = building_state.get("bounds", [])
			_assert(bounds.size() == 4 and int(bounds[0]) <= int(bounds[2]) and int(bounds[1]) <= int(bounds[3]), "every authored building exposes valid world-space roof-occlusion bounds")
			_assert(_has_roof_levels(world, StringName(stable_id), int(building_state.get("wall_height", 0))), "every authored building has a complete roof deck and raised perimeter parapet")
		if record.get("kind", &"") == &"door":
			var door_state: Dictionary = record.get("state", {})
			_assert(StringName(door_state.get("axis", &"")) in [&"x", &"z"], "every authored door retains its generated aperture axis")
			_assert(int(door_state.get("width_cells", 0)) >= 1 and int(door_state.get("height_cells", 0)) == 2, "every authored door exposes valid voxel leaf dimensions")
		if record.get("kind", &"") == &"room":
			var cell: Vector3i = record["cell"]
			var chunk = world.get_chunk(COORDINATES.world_cell_to_chunk(cell))
			var local := COORDINATES.world_cell_to_local(cell, COORDINATES.world_cell_to_chunk(cell))
			_assert(chunk.get_cell(Vector3i(local.x, 0, local.z)) == MATERIALS.Id.FLOOR, "room anchor resolves to authored floor")
	var restored = WORLD_DATA.from_snapshot(world.to_snapshot())
	_assert(restored != null and restored.fingerprint() == world.fingerprint(), "city stable-object metadata survives voxel snapshot restore")
	_test_directional_voxel_faces()
	_test_runtime_door(world)
	_test_runtime_loot(world)
	_test_destroyed_prop(city, seed_value, coordinate)


func _test_runtime_door(world) -> void:
	var door_id := _first_id_of_kind(world, &"door")
	_assert(door_id != &"", "generated city exposes at least one door")
	if door_id == &"":
		return
	var damage_service := VoxelStructuralDamageService.new()
	add_child(damage_service)
	damage_service.configure(world)
	var runtime = SEMANTIC_RUNTIME.new()
	add_child(runtime)
	runtime.populate(world, damage_service)
	var door_area: Node = _runtime_area(runtime, door_id)
	_assert(door_area != null, "voxel runtime instantiates the authored door interaction")
	if door_area == null:
		return
	var actor := TestActor.new()
	add_child(actor)
	var pivot: Node3D = door_area.get_node_or_null("DoorVisual/DoorPivot")
	var door_collision: CollisionShape3D = door_area.get_node_or_null("DoorBody/CollisionShape3D")
	_assert(pivot != null and door_area.get_node_or_null("DoorVisual/FrameHeader") != null, "voxel door renders a hinged leaf inside a permanent frame")
	_assert(door_collision != null and not door_collision.disabled, "closed voxel door owns an explicit blocking collision shape")
	(door_area.get_node("InteractableComponent") as InteractableComponent).interact(actor)
	_assert(WorldState.get_door_open(door_id), "voxel door writes its open state to WorldState")
	_assert(pivot != null and is_equal_approx(absf(pivot.rotation.y), PI * 0.5), "opening a voxel door rotates its visible leaf by ninety degrees")
	_assert(door_collision != null and door_collision.disabled, "opening a voxel door disables its blocking collision")
	var record: Dictionary = world.get_stable_object(door_id)
	var anchor: Vector3i = record["cell"]
	var coordinate := COORDINATES.world_cell_to_chunk(anchor)
	var chunk = world.get_chunk(coordinate)
	for row_variant in (record.get("state", {}) as Dictionary).get("cells", []):
		var row: Array = row_variant
		_assert(chunk.get_cell(Vector3i(int(row[0]), int(row[1]), int(row[2]))) == MATERIALS.Id.AIR, "opening a door clears every voxel in its aperture")
	(door_area.get_node("InteractableComponent") as InteractableComponent).interact(actor)
	_assert(not WorldState.get_door_open(door_id), "voxel door closes through the same persistent state contract")
	_assert(pivot != null and is_zero_approx(pivot.rotation.y) and door_collision != null and not door_collision.disabled, "closing a voxel door restores its leaf and collision")
	runtime.queue_free()
	damage_service.queue_free()
	actor.queue_free()


func _test_runtime_loot(world) -> void:
	var loot_id := _first_loot_id(world)
	_assert(loot_id != &"", "generated city exposes at least one voxel loot object")
	if loot_id == &"":
		return
	var damage_service := VoxelStructuralDamageService.new()
	add_child(damage_service)
	damage_service.configure(world)
	var runtime = SEMANTIC_RUNTIME.new()
	add_child(runtime)
	runtime.populate(world, damage_service)
	var loot_area: Node = _runtime_area(runtime, loot_id)
	_assert(loot_area != null, "voxel runtime instantiates the authored loot interaction")
	if loot_area == null:
		return
	var actor := TestActor.new()
	add_child(actor)
	var starting_items: Dictionary = world.get_stable_object(loot_id).get("state", {}).get("items", {})
	(loot_area.get_node("InteractableComponent") as InteractableComponent).interact(actor)
	for item_id in starting_items:
		_assert(actor.carried_inventory.get_count(StringName(item_id)) == int(starting_items[item_id]), "voxel loot transfers the exact authored item count")
	_assert(WorldState.get_prop_state_flag(loot_id, &"searched", false), "depleted voxel loot persists its searched flag")
	var before := actor.carried_inventory.to_dict()
	(loot_area.get_node("InteractableComponent") as InteractableComponent).interact(actor)
	_assert(actor.carried_inventory.to_dict() == before, "repeated voxel loot interaction cannot duplicate items")
	runtime.queue_free()
	damage_service.queue_free()
	actor.queue_free()


func _test_destroyed_prop(city: Dictionary, seed_value: int, coordinate: Vector2i) -> void:
	var props: Array = city.get("props", [])
	if props.is_empty():
		_assert(false, "generated city exposes an exterior prop for persistence testing")
		return
	var stable_id := StringName((props[0] as Dictionary).get("id", &""))
	WorldState.set_prop_state_flag(stable_id, &"destroyed", true)
	var rebuilt = VOXELIZER.new().voxelize_chunk(city, seed_value, coordinate)
	var record: Dictionary = rebuilt.get_stable_object(stable_id)
	var cell: Vector3i = record["cell"]
	var chunk = rebuilt.get_chunk(COORDINATES.world_cell_to_chunk(cell))
	var local := COORDINATES.world_cell_to_local(cell, COORDINATES.world_cell_to_chunk(cell))
	_assert(bool(record.get("state", {}).get("destroyed", false)), "destroyed exterior prop state survives regeneration")
	_assert(chunk.get_cell(local) == MATERIALS.Id.AIR, "destroyed exterior prop does not regenerate its voxel")


func _expected_stable_object_count(city: Dictionary) -> int:
	var settlement_services := 6 if bool(city.get("has_safehouse", false)) else 0
	return (city.get("buildings", []) as Array).size() + _interior_count(city, "rooms") + _interior_count(city, "doors") + _interior_count(city, "windows") + _interior_count(city, "furniture") + (city.get("props", []) as Array).size() + (city.get("scavenge_points", []) as Array).size() + settlement_services


func _interior_count(city: Dictionary, field: String) -> int:
	var total := 0
	for building_variant in city.get("buildings", []):
		var building: Dictionary = building_variant
		total += ((building.get("interior", {}) as Dictionary).get(field, []) as Array).size()
	return total


func _count_kind(world, kind: StringName) -> int:
	var total := 0
	for stable_id in world.stable_objects:
		if world.stable_objects[stable_id].get("kind", &"") == kind:
			total += 1
	return total


func _first_id_of_kind(world, kind: StringName) -> StringName:
	for stable_id in world.stable_objects:
		if world.stable_objects[stable_id].get("kind", &"") == kind:
			return StringName(stable_id)
	return &""


func _first_loot_id(world) -> StringName:
	for stable_id in world.stable_objects:
		var record: Dictionary = world.stable_objects[stable_id]
		if record.get("kind", &"") not in [&"furniture", &"exterior_prop"]:
			continue
		var state: Dictionary = record.get("state", {})
		if not (state.get("items", {}) as Dictionary).is_empty():
			return StringName(stable_id)
	return &""


func _has_roof_levels(world, stable_id: StringName, wall_height: int) -> bool:
	var deck_cells := 0
	var parapet_cells := 0
	for coordinate in world.chunks:
		var chunk = world.get_chunk(coordinate)
		for cell_variant in chunk.cells:
			var cell: Vector3i = cell_variant
			if chunk.source_at(cell) != stable_id or int(chunk.cells[cell]) != MATERIALS.Id.ROOF:
				continue
			deck_cells += 1 if cell.y == wall_height + 1 else 0
			parapet_cells += 1 if cell.y == wall_height + 2 else 0
	return deck_cells > 0 and parapet_cells > 0 and deck_cells > parapet_cells


func _test_directional_voxel_faces() -> void:
	var renderer := VoxelChunk.new()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	renderer.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	renderer.add_child(collision)
	renderer.generate_collision = false
	add_child(renderer)
	renderer.configure({Vector3i.ZERO: MATERIALS.Id.BRICK}, MATERIALS.create_render_materials())
	var mesh: ArrayMesh = mesh_instance.mesh
	var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var unique_colors: Dictionary = {}
	for color in colors:
		unique_colors[color] = true
	_assert(colors.size() == 36 and unique_colors.size() >= 4, "voxel walls and roofs carry directional face shading in merged geometry")
	var material := mesh.surface_get_material(0) as StandardMaterial3D
	_assert(material != null and material.vertex_color_use_as_albedo, "voxel materials apply directional vertex colors to their registered surface color")
	renderer.queue_free()


func _runtime_area(runtime: Node, stable_id: StringName):
	for child in runtime.get_children():
		if is_instance_of(child, SEMANTIC_INTERACTABLE) and child.stable_id == stable_id:
			return child
	return null


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("VOXEL_CITY_CONVERSION: FAIL: %s" % message)
