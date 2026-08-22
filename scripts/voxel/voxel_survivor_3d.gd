class_name VoxelSurvivor3D
extends CharacterBody3D

const PATH_FOLLOWER := preload("res://scripts/voxel/voxel_path_follower_3d.gd")
const UTILITY_AI := preload("res://scripts/voxel/voxel_survivor_ai_3d.gd")

@export var voxel_movement_speed := 5.9

var data: SurvivorData
var carried_inventory: Inventory
var navigation_service
var path_follower
var utility_ai
var voxel_world_data
var semantic_job_board
var settlement_runtime
var is_dead := false
var _being_helped_by := 0

@onready var health_component: HealthComponent = $HealthComponent
@onready var weapon_pivot: Node3D = $WeaponPivot
@onready var weapon: VoxelWeapon3D = $WeaponPivot/Pistol


func _ready() -> void:
	add_to_group(&"survivors")
	add_to_group(&"attackable")
	carried_inventory = Inventory.new(20.0)
	health_component.damaged.connect(_on_damaged)
	health_component.died.connect(_on_died)
	utility_ai = UTILITY_AI.new()
	utility_ai.name = "VoxelSurvivorAI3D"
	add_child(utility_ai)


func setup(profile: Dictionary) -> void:
	data = SurvivorData.new()
	data.survivor_name = String(profile.get("name", "Survivor"))
	data.age = int(profile.get("age", 30))
	data.combat_skill = float(profile.get("combat_skill", 25.0))
	data.medical_skill = float(profile.get("medical_skill", 25.0))
	data.scavenging_skill = float(profile.get("scavenging_skill", 25.0))
	data.construction_skill = float(profile.get("construction_skill", 25.0))
	data.movement_speed = float(profile.get("movement_speed", 190.0))
	data.personality = (profile.get("personality", {}) as Dictionary).duplicate(true)
	data.max_health = health_component.max_health
	data.health = data.max_health
	WorldState.register_survivor(data)
	if utility_ai != null:
		utility_ai.begin(data)
	GameEvents.survivor_spawned.emit(self)


func configure_navigation(service, world = null, board = null, settlement_services = null) -> void:
	navigation_service = service
	voxel_world_data = world
	semantic_job_board = board
	settlement_runtime = settlement_services
	path_follower = PATH_FOLLOWER.new()
	path_follower.configure(self, service)
	utility_ai.configure(world, service, board, settlement_services)


func move_toward_world_point(point: Vector3, delta: float) -> bool:
	if is_dead or path_follower == null:
		return false
	path_follower.set_target(point)
	return path_follower.physics_step(delta, voxel_movement_speed)


func stop_moving() -> void:
	if path_follower != null:
		path_follower.clear()


func face_and_fire(target_position: Vector3) -> bool:
	var direction := target_position - global_position
	direction.y = 0.0
	if direction.length() <= 0.01:
		return false
	direction = direction.normalized()
	rotation.y = atan2(direction.x, direction.z)
	return weapon.try_fire(direction)


func try_claim_helper(survivor_id: int) -> bool:
	if _being_helped_by != 0 and _being_helped_by != survivor_id:
		return false
	_being_helped_by = survivor_id
	return true


func release_helper(survivor_id: int) -> void:
	if _being_helped_by == survivor_id:
		_being_helped_by = 0


func is_claimed_for_help() -> bool:
	return _being_helped_by != 0


func _physics_process(_delta: float) -> void:
	if data != null:
		data.health = health_component.current_health


func take_damage(amount: float, source: Node = null) -> void:
	if not is_dead:
		health_component.take_damage(amount, source)


func _on_damaged(amount: float) -> void:
	if data != null:
		data.fear = clampf(data.fear + amount * 0.5, 0.0, 100.0)


func _on_died() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	if utility_ai != null:
		utility_ai.stop()
	if data != null:
		data.is_dead = true
	_drop_carried_inventory()
	GameEvents.survivor_died.emit(self)
	queue_free()


func _drop_carried_inventory() -> void:
	if carried_inventory == null or carried_inventory.is_empty():
		return
	var drop := WorldDrop.new()
	drop.position = Vector2(global_position.x, global_position.z)
	drop.source_survivor_id = data.id if data != null else 0
	drop.created_tick = SimulationClock.tick_count
	drop.reason = &"death"
	drop.inventory = Inventory.new(0.0)
	carried_inventory.move_all_to(drop.inventory)
	WorldState.register_drop(drop)
