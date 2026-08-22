class_name VoxelPrototypePlayer
extends CharacterBody3D

const AIM_PROJECTOR := preload("res://scripts/voxel/voxel_aim_projector.gd")

@export var move_speed := 5.0
@export var acceleration := 24.0
@export var friction := 28.0

@onready var health_component: HealthComponent = $HealthComponent
@onready var weapon_pivot: Node3D = $WeaponPivot
@onready var body_visual: MeshInstance3D = $Mesh
@onready var interactor: Area3D = $VoxelInteractor3D

var camera: Camera3D
var aim_direction := Vector3.FORWARD
var is_dead := false
var weapon_slot_index := 0
var weapon_slots: Array = []
var weapon
var carried_inventory: Inventory

var _fire_was_held := false
var _damage_flash_remaining := 0.0
var _body_color := Color(0.2, 0.58, 0.92)


func _ready() -> void:
	add_to_group(&"player")
	add_to_group(&"attackable")
	carried_inventory = Inventory.new(60.0)
	health_component.died.connect(_on_died)
	health_component.damaged.connect(_on_damaged)
	health_component.health_changed.connect(_on_health_changed)
	_collect_weapon_slots()
	InputRouter.weapon_slot_requested.connect(equip_weapon_slot)
	InputRouter.weapon_cycle_requested.connect(cycle_weapon)
	_on_health_changed(health_component.current_health, health_component.max_health)
	call_deferred(&"_emit_equipped_weapon")


func _physics_process(delta: float) -> void:
	_update_damage_flash(delta)
	if is_dead:
		return
	_update_aim()
	_update_movement(delta)
	_update_firing()


func _update_aim() -> void:
	aim_direction = AIM_PROJECTOR.ground_direction(camera, global_position, InputRouter.aim_vector, aim_direction)
	weapon_pivot.rotation.y = atan2(aim_direction.x, aim_direction.z)


func _update_movement(delta: float) -> void:
	var input_vector: Vector2 = InputRouter.movement_vector
	var right := Vector3.RIGHT
	var forward := Vector3.FORWARD
	if camera != null:
		right = camera.global_basis.x
		forward = -camera.global_basis.z
		right.y = 0.0
		forward.y = 0.0
		right = right.normalized()
		forward = forward.normalized()
	var desired := (right * input_vector.x + forward * -input_vector.y).normalized() * move_speed
	var rate := acceleration if input_vector != Vector2.ZERO else friction
	velocity.x = move_toward(velocity.x, desired.x, rate * delta)
	velocity.z = move_toward(velocity.z, desired.z, rate * delta)
	velocity.y = -2.0
	move_and_slide()


func _update_firing() -> void:
	if weapon == null or weapon.data == null:
		return
	if InputRouter.reload_pressed:
		weapon.try_reload()
	var fire_held: bool = InputRouter.fire_pressed
	if weapon.data.automatic:
		if fire_held:
			weapon.try_fire(aim_direction)
	elif fire_held and not _fire_was_held:
		weapon.try_fire(aim_direction)
	_fire_was_held = fire_held


func _collect_weapon_slots() -> void:
	weapon_slots.clear()
	for child in weapon_pivot.get_children():
		if child.has_method(&"try_fire") and "data" in child:
			weapon_slots.append(child)
	if weapon_slots.is_empty():
		return
	weapon_slot_index = clampi(weapon_slot_index, 0, weapon_slots.size() - 1)
	for index in range(weapon_slots.size()):
		weapon_slots[index].set_equipped(index == weapon_slot_index)
	weapon = weapon_slots[weapon_slot_index]


func equip_weapon_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= weapon_slots.size() or slot_index == weapon_slot_index:
		return false
	weapon_slots[weapon_slot_index].set_equipped(false)
	weapon_slot_index = slot_index
	weapon = weapon_slots[weapon_slot_index]
	weapon.set_equipped(true)
	_fire_was_held = InputRouter.fire_pressed
	_emit_equipped_weapon()
	return true


func cycle_weapon(direction: int = 1) -> bool:
	if weapon_slots.size() < 2:
		return false
	return equip_weapon_slot(posmod(weapon_slot_index + direction, weapon_slots.size()))


func _emit_equipped_weapon() -> void:
	if weapon == null or weapon.data == null:
		return
	GameEvents.weapon_equipped.emit(weapon.data.weapon_name, weapon_slot_index, weapon_slots.size(), weapon.ammo_in_magazine, weapon.reserve_ammo, weapon.data.magazine_size)


func take_damage(amount: float, source: Node = null) -> void:
	if not is_dead:
		health_component.take_damage(amount, source)


func respawn(spawn_position: Vector3) -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	is_dead = false
	health_component.reset_health()
	for slot_weapon in weapon_slots:
		slot_weapon.reset_weapon()
	if not weapon_slots.is_empty() and weapon_slot_index != 0:
		weapon_slots[weapon_slot_index].set_equipped(false)
		weapon_slot_index = 0
		weapon = weapon_slots[0]
		weapon.set_equipped(true)
	_emit_equipped_weapon()
	GameEvents.player_respawned.emit()


func _on_health_changed(current: float, maximum: float) -> void:
	GameEvents.player_health_changed.emit(current, maximum)


func _on_damaged(amount: float) -> void:
	GameEvents.player_damaged.emit(amount)
	_damage_flash_remaining = 0.2
	body_visual.material_override.albedo_color = Color(1.0, 0.25, 0.25)


func _update_damage_flash(delta: float) -> void:
	if _damage_flash_remaining <= 0.0:
		return
	_damage_flash_remaining -= delta
	if _damage_flash_remaining <= 0.0:
		body_visual.material_override.albedo_color = _body_color


func _on_died() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	GameEvents.player_died.emit()
