class_name VoxelPrototypeZombie
extends CharacterBody3D

const PATH_FOLLOWER := preload("res://scripts/voxel/voxel_path_follower_3d.gd")
const PERCEPTION := preload("res://scripts/voxel/voxel_zombie_perception_3d.gd")

@export var move_speed := 1.8
@export var contact_damage := 8.0
@export var contact_damage_interval := 0.6
@onready var health_component: HealthComponent = $HealthComponent
@onready var _mesh: MeshInstance3D = $Mesh

## Presentation-only damage feedback: the capsule snaps to FLASH_COLOR and
## tweens back to its base albedo over FLASH_DURATION seconds.
const FLASH_COLOR := Color(1.0, 1.0, 1.0)
const FLASH_DURATION := 0.12

var _base_albedo := Color(0.5, 0.72, 0.3)
var _flash_tween: Tween
var target: Node3D
var navigation_service
var path_follower
var perception
var _contact_damage_remaining := 0.0


func _ready() -> void:
	add_to_group(&"voxel_zombies")
	# The scene ships one shared StandardMaterial3D sub-resource: without a
	# per-instance copy every spawned zombie would tint together on hit.
	if _mesh.material_override is StandardMaterial3D:
		var owned := _mesh.material_override.duplicate() as StandardMaterial3D
		_mesh.material_override = owned
		_base_albedo = owned.albedo_color
	health_component.damaged.connect(_on_damaged)
	health_component.died.connect(_on_died)
	perception = PERCEPTION.new()
	perception.name = "VoxelZombiePerception3D"
	add_child(perception)


func configure_navigation(service) -> void:
	navigation_service = service
	perception.configure(service)


func _physics_process(_delta: float) -> void:
	if health_component.is_dead:
		return
	perception.update(_delta, velocity)
	_tick_contact_damage(_delta)
	target = perception.target if is_instance_valid(perception.target) else null
	var goal: Vector3 = perception.movement_goal()
	if goal == Vector3.INF:
		velocity = Vector3.ZERO
		return
	var offset := goal - global_position
	offset.y = 0.0
	if offset.length() > 1.4:
		if navigation_service != null:
			if path_follower == null:
				path_follower = PATH_FOLLOWER.new()
				path_follower.configure(self, navigation_service)
			path_follower.set_target(goal)
			path_follower.physics_step(_delta, move_speed)
			return
		var direction := offset.normalized()
		velocity = Vector3(direction.x * move_speed, -2.0, direction.z * move_speed)
		rotation.y = atan2(direction.x, direction.z)
		move_and_slide()
	else:
		velocity = Vector3.ZERO


func _tick_contact_damage(delta: float) -> void:
	_contact_damage_remaining = maxf(0.0, _contact_damage_remaining - delta)
	if _contact_damage_remaining > 0.0 or perception.state != PERCEPTION.State.ATTACK or not is_instance_valid(perception.target):
		return
	if global_position.distance_to(perception.target.global_position) > perception.attack_range:
		return
	if perception.target.has_method(&"take_damage"):
		perception.target.call(&"take_damage", contact_damage, self)
		_contact_damage_remaining = contact_damage_interval


func take_damage(amount: float, source: Node = null) -> void:
	health_component.take_damage(amount, source)


func _on_damaged(amount: float) -> void:
	_flash_hit()
	GameEvents.voxel_zombie_damaged.emit(self, amount)


## Presentation-only self hit-flash: re-hitting restarts the tween so rapid
## fire never stacks tweens or strands a white zombie.
func _flash_hit() -> void:
	var mat := _mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	mat.albedo_color = FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(mat, "albedo_color", _base_albedo, FLASH_DURATION)


func _on_died() -> void:
	GameEvents.voxel_zombie_died.emit(self, global_position)
	queue_free()
