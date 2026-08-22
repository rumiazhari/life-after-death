class_name VoxelCombatEffects3D
extends Node3D

const MAX_BLOOD_DECALS := 96

var hit_effect_count := 0
var explosion_effect_count := 0
var blood_decal_count := 0
var _blood_decals: Array[Node3D] = []


func _ready() -> void:
	GameEvents.voxel_zombie_damaged.connect(_on_zombie_damaged)
	GameEvents.voxel_zombie_died.connect(_on_zombie_died)
	GameEvents.voxel_environment_explosion.connect(_on_environment_explosion)


func _on_zombie_damaged(zombie: Node3D, _amount: float) -> void:
	if not is_instance_valid(zombie):
		return
	hit_effect_count += 1
	var flash := MeshInstance3D.new()
	flash.mesh = _sphere_mesh(0.16)
	flash.material_override = _material(Color(1.0, 0.9, 0.45))
	add_child(flash)
	flash.global_position = zombie.global_position + Vector3.UP * 1.0
	var tween := create_tween()
	tween.tween_property(flash, "scale", Vector3.ONE * 1.8, 0.12)
	tween.tween_callback(flash.queue_free)


func _on_environment_explosion(origin: Vector3, radius: float) -> void:
	explosion_effect_count += 1
	var burst := MeshInstance3D.new()
	burst.mesh = _sphere_mesh(maxf(radius, 0.2))
	burst.material_override = _material(Color(1.0, 0.35, 0.06))
	burst.scale = Vector3.ONE * 0.12
	add_child(burst)
	burst.global_position = origin
	var tween := create_tween()
	tween.tween_property(burst, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(burst.queue_free)


func _on_zombie_died(_zombie: Node3D, position: Vector3) -> void:
	var decal := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.48
	mesh.bottom_radius = 0.48
	mesh.height = 0.025
	mesh.radial_segments = 12
	decal.mesh = mesh
	decal.material_override = _material(Color(0.32, 0.035, 0.035))
	decal.rotation.y = fmod(float(blood_decal_count) * 2.399963, TAU)
	add_child(decal)
	decal.global_position = Vector3(position.x, 0.025, position.z)
	_blood_decals.append(decal)
	blood_decal_count += 1
	while _blood_decals.size() > MAX_BLOOD_DECALS:
		var oldest: Node3D = _blood_decals.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func _sphere_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	return material
