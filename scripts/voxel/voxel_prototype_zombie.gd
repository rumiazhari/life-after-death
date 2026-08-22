class_name VoxelPrototypeZombie
extends CharacterBody3D

const PATH_FOLLOWER := preload("res://scripts/voxel/voxel_path_follower_3d.gd")
const PERCEPTION := preload("res://scripts/voxel/voxel_zombie_perception_3d.gd")

@export var move_speed := 1.8
@export var contact_damage := 8.0
@export var contact_damage_interval := 0.6
@onready var health_component: HealthComponent = $HealthComponent

var target: Node3D
var navigation_service
var path_follower
var perception
var _contact_damage_remaining := 0.0


func _ready() -> void:
	add_to_group(&"voxel_zombies")
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
	GameEvents.voxel_zombie_damaged.emit(self, amount)


func _on_died() -> void:
	GameEvents.voxel_zombie_died.emit(self, global_position)
	queue_free()
