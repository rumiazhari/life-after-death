class_name VoxelSemanticInteractable3D
extends Area3D

const COORDINATES := preload("res://scripts/voxel/voxel_coordinates.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")
const DOOR_LEAF_COLOR := Color("#6b3f24")
const DOOR_FRAME_COLOR := Color("#3b2418")

var world_data
var structural_damage_service: VoxelStructuralDamageService
var stable_id: StringName = &""
var semantic_kind: StringName = &""
var semantic_state: Dictionary = {}


func configure(data, damage_service: VoxelStructuralDamageService, object_id: StringName, record: Dictionary) -> void:
	world_data = data
	structural_damage_service = damage_service
	stable_id = object_id
	semantic_kind = StringName(record.get("kind", &""))
	semantic_state = (record.get("state", {}) as Dictionary).duplicate(true)
	position = COORDINATES.world_cell_to_world_position(record.get("cell", Vector3i.ZERO)) + Vector3(0.5, 1.0, 0.5)
	if semantic_kind == &"door":
		position = _door_center(record)
	if is_node_ready():
		_apply_configuration()


func _ready() -> void:
	_apply_configuration()


func _apply_configuration() -> void:
	collision_layer = 64
	collision_mask = 0
	if get_node_or_null("CollisionShape3D") == null:
		var shape_node := CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.25, 2.0, 1.25)
		shape_node.shape = shape
		add_child(shape_node)
	var interactable: InteractableComponent = get_node_or_null("InteractableComponent")
	if interactable == null:
		interactable = InteractableComponent.new()
		interactable.name = "InteractableComponent"
		add_child(interactable)
		interactable.interacted.connect(_interact)
	interactable.interact_label = _interaction_label()
	interactable.enabled = _can_interact()
	if semantic_kind == &"door":
		_ensure_door_visual()
		_apply_door_state()


func _interaction_label() -> String:
	if semantic_kind == &"door":
		return "Close" if bool(semantic_state.get("open", false)) else "Open"
	if semantic_kind == &"scavenge_point":
		return "Scavenge"
	var mode := StringName(semantic_state.get("mode", &"physical"))
	return "Salvage" if mode == &"salvage" else "Search"


func _can_interact() -> bool:
	if semantic_kind == &"door":
		return true
	if semantic_kind == &"scavenge_point":
		return int(semantic_state.get("stock", 0)) > 0
	var mode := StringName(semantic_state.get("mode", &"physical"))
	if mode == &"salvage":
		return not bool(semantic_state.get("salvaged", false)) and int(semantic_state.get("yield", 0)) > 0
	return not bool(semantic_state.get("destroyed", false))


func _interact(actor: Node) -> void:
	if semantic_kind == &"door":
		_toggle_door()
	elif semantic_kind == &"scavenge_point":
		_scavenge(actor)
	elif StringName(semantic_state.get("mode", &"physical")) == &"salvage":
		_salvage(actor)
	else:
		_search(actor)
	_apply_configuration()


func _toggle_door() -> void:
	var is_open := not bool(semantic_state.get("open", false))
	semantic_state["open"] = is_open
	WorldState.set_door_open(stable_id, is_open)
	world_data.set_stable_object_state(stable_id, semantic_state)
	var anchor: Vector3i = world_data.get_stable_object(stable_id).get("cell", Vector3i.ZERO)
	var coordinate := COORDINATES.world_cell_to_chunk(anchor)
	for row_variant in semantic_state.get("cells", []):
		var row: Array = row_variant
		var local_cell := Vector3i(int(row[0]), int(row[1]), int(row[2]))
		var world_cell := COORDINATES.local_to_world_cell(local_cell, coordinate)
		structural_damage_service.set_cell_material(world_cell, MATERIALS.Id.AIR if is_open else MATERIALS.Id.WOOD, stable_id)


func _door_center(record: Dictionary) -> Vector3:
	var cells: Array = semantic_state.get("cells", [])
	if cells.is_empty():
		return COORDINATES.world_cell_to_world_position(record.get("cell", Vector3i.ZERO)) + Vector3(0.5, 1.0, 0.5)
	var anchor: Vector3i = record.get("cell", Vector3i.ZERO)
	var coordinate := COORDINATES.world_cell_to_chunk(anchor)
	var minimum := Vector3i(1000000, 1000000, 1000000)
	var maximum := Vector3i(-1000000, -1000000, -1000000)
	for row_variant in cells:
		var row: Array = row_variant
		var local := Vector3i(int(row[0]), int(row[1]), int(row[2]))
		var world_cell := COORDINATES.local_to_world_cell(local, coordinate)
		minimum = Vector3i(mini(minimum.x, world_cell.x), mini(minimum.y, world_cell.y), mini(minimum.z, world_cell.z))
		maximum = Vector3i(maxi(maximum.x, world_cell.x), maxi(maximum.y, world_cell.y), maxi(maximum.z, world_cell.z))
	return Vector3(minimum + maximum) * 0.5 + Vector3.ONE * 0.5


func _ensure_door_visual() -> void:
	if get_node_or_null("DoorVisual") != null:
		return
	var width := float(maxi(1, int(semantic_state.get("width_cells", 1))))
	var height := float(maxi(1, int(semantic_state.get("height_cells", 2))))
	var axis := StringName(semantic_state.get("axis", "z"))
	var visual := Node3D.new()
	visual.name = "DoorVisual"
	add_child(visual)
	var frame_material := _door_material(DOOR_FRAME_COLOR)
	var leaf_material := _door_material(DOOR_LEAF_COLOR)
	var side_offset := width * 0.5 + 0.08
	for side in [-1.0, 1.0]:
		var post_size := Vector3(0.18, height + 0.3, 0.18)
		var post_position := Vector3(side * side_offset, 0.0, 0.0) if axis == &"x" else Vector3(0.0, 0.0, side * side_offset)
		_add_door_box(visual, "FramePost", post_size, post_position, frame_material)
	var header_size := Vector3(width + 0.34, 0.18, 0.18) if axis == &"x" else Vector3(0.18, 0.18, width + 0.34)
	_add_door_box(visual, "FrameHeader", header_size, Vector3(0.0, height * 0.5 + 0.15, 0.0), frame_material)
	var pivot := Node3D.new()
	pivot.name = "DoorPivot"
	pivot.position = Vector3(-width * 0.5, 0.0, 0.0) if axis == &"x" else Vector3(0.0, 0.0, -width * 0.5)
	visual.add_child(pivot)
	var leaf_size := Vector3(width, height, 0.12) if axis == &"x" else Vector3(0.12, height, width)
	var leaf_offset := Vector3(width * 0.5, 0.0, 0.0) if axis == &"x" else Vector3(0.0, 0.0, width * 0.5)
	_add_door_box(pivot, "DoorLeaf", leaf_size, leaf_offset, leaf_material)
	var body := StaticBody3D.new()
	body.name = "DoorBody"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = leaf_size
	collision.shape = shape
	body.add_child(collision)


func _apply_door_state() -> void:
	var is_open := bool(semantic_state.get("open", false))
	var pivot: Node3D = get_node_or_null("DoorVisual/DoorPivot")
	if pivot != null:
		pivot.rotation.y = -PI * 0.5 if is_open else 0.0
	var collision: CollisionShape3D = get_node_or_null("DoorBody/CollisionShape3D")
	if collision != null:
		collision.disabled = is_open


func _add_door_box(parent: Node, node_name: String, size: Vector3, local_position: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = local_position
	parent.add_child(mesh_instance)


func _door_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	return material


func _search(actor: Node) -> void:
	if not ("carried_inventory" in actor):
		return
	var initial_items: Dictionary = semantic_state.get("items", {})
	var capacity := float(semantic_state.get("capacity", 200.0))
	var inventory: Inventory = WorldState.get_or_create_prop_container(stable_id, capacity, initial_items)
	var moved := inventory.move_all_to(actor.carried_inventory)
	if moved.is_empty():
		return
	var depleted := inventory.is_empty()
	semantic_state["searched"] = depleted
	WorldState.set_prop_state_flag(stable_id, &"searched", depleted)
	world_data.set_stable_object_state(stable_id, semantic_state)


func _salvage(actor: Node) -> void:
	if not ("carried_inventory" in actor):
		return
	var remaining := int(WorldState.get_prop_state_flag(stable_id, &"remaining_yield", semantic_state.get("yield", 0)))
	if remaining <= 0:
		return
	var added: int = actor.carried_inventory.add_item(&"materials", remaining)
	remaining -= added
	semantic_state["yield"] = remaining
	semantic_state["salvaged"] = remaining <= 0
	WorldState.set_prop_state_flag(stable_id, &"remaining_yield", remaining)
	WorldState.set_prop_state_flag(stable_id, &"salvaged", remaining <= 0)
	world_data.set_stable_object_state(stable_id, semantic_state)


func _scavenge(actor: Node) -> void:
	if not ("carried_inventory" in actor):
		return
	var stock := int(semantic_state.get("stock", 0))
	var item_id := StringName(semantic_state.get("item_id", &""))
	var requested := mini(stock, int(semantic_state.get("yield", 0)))
	var added: int = actor.carried_inventory.add_item(item_id, requested)
	if added <= 0:
		return
	stock -= added
	semantic_state["stock"] = stock
	WorldState.set_prop_state_flag(stable_id, &"remaining_stock", stock)
	world_data.set_stable_object_state(stable_id, semantic_state)
