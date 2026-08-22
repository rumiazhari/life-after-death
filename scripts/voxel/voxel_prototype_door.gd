class_name VoxelPrototypeDoor
extends StaticBody3D

var is_open := false
var _closed_rotation := 0.0


func _ready() -> void:
	_closed_rotation = rotation.y
	$InteractionArea/InteractableComponent.interacted.connect(interact)


func interact(_actor: Node) -> void:
	is_open = not is_open
	rotation.y = _closed_rotation + (-PI * 0.5 if is_open else 0.0)
	$CollisionShape3D.disabled = is_open
