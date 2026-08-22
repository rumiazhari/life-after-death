class_name VoxelPrototypeProjectileManager
extends Node3D

const PROJECTILE_SCRIPT := preload("res://scripts/voxel/voxel_prototype_projectile.gd")

@export var prewarm_count := 32
var damage_service: Node
var _available: Array[Area3D] = []


func _ready() -> void:
	add_to_group(&"voxel_projectile_spawner")
	for index in range(prewarm_count):
		_available.append(_create_projectile(index))


func spawn_projectile(origin: Vector3, direction: Vector3, speed: float = 18.0, damage: float = 25.0, lifetime: float = 1.5, environment_damage_class: int = 0, environment_damage: float = 0.0, explosion_radius: float = 0.0, visual_scale: float = 1.0, visual_tint: Color = Color.WHITE) -> void:
	var projectile = _available.pop_back() if not _available.is_empty() else _create_projectile(get_child_count())
	projectile.damage_service = damage_service
	projectile.setup(origin, direction, speed, damage, lifetime, environment_damage_class, environment_damage, explosion_radius, visual_scale, visual_tint)


func active_projectile_count() -> int:
	return get_child_count() - _available.size()


func pool_capacity() -> int:
	return get_child_count()


func _create_projectile(index: int) -> Area3D:
	var projectile = PROJECTILE_SCRIPT.new()
	projectile.name = "Projectile_%02d" % index
	projectile.collision_layer = 8
	projectile.collision_mask = 1 | 2 | 4
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.08
	shape.shape = sphere
	projectile.add_child(shape)
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.72, 0.18)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.25, 0.02)
	visual.material_override = material
	projectile.add_child(visual)
	add_child(projectile)
	projectile.visible = false
	projectile.monitorable = false
	projectile.set_physics_process(false)
	projectile.released.connect(_on_projectile_released)
	return projectile


func _on_projectile_released(projectile: Area3D) -> void:
	if projectile not in _available:
		_available.append(projectile)
