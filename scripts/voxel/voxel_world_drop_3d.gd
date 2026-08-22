class_name VoxelWorldDrop3D
extends Area3D

const REASON_TINTS := {
	&"death": Color(0.95, 0.8, 0.25),
	&"haul_stalled": Color(0.45, 0.7, 1.0),
	&"storage_destroyed": Color(1.0, 0.45, 0.3),
}

var drop_id := 0


func configure(drop: WorldDrop) -> void:
	drop_id = drop.id
	position = Vector3(drop.position.x, 0.55, drop.position.y)
	name = "WorldDrop3D_%d" % drop.id
	_build_nodes(REASON_TINTS.get(drop.reason, Color(0.95, 0.8, 0.25)))


func _ready() -> void:
	collision_layer = 64
	collision_mask = 0


func _build_nodes(tint: Color) -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var shape := SphereShape3D.new()
	shape.radius = 0.65
	shape_node.shape = shape
	add_child(shape_node)
	var visual := MeshInstance3D.new()
	visual.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.7, 0.45, 0.55)
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.85
	visual.material_override = material
	add_child(visual)
	var interactable := InteractableComponent.new()
	interactable.name = "InteractableComponent"
	interactable.interact_label = "Collect supplies"
	interactable.interacted.connect(_collect)
	add_child(interactable)


func _collect(actor: Node) -> void:
	if not ("carried_inventory" in actor):
		return
	var drop: WorldDrop = WorldState.get_drop(drop_id)
	if drop == null or drop.inventory == null:
		return
	drop.inventory.move_all_to(actor.carried_inventory)
	if drop.inventory.is_empty():
		WorldState.unregister_drop(drop_id)
