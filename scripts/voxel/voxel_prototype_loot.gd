class_name VoxelPrototypeLoot
extends StaticBody3D

var searched := false


func _ready() -> void:
	$InteractionArea/InteractableComponent.interacted.connect(interact)


func interact(_actor: Node) -> void:
	if searched:
		return
	searched = true
	$Mesh.material_override.albedo_color = Color(0.25, 0.25, 0.25)
