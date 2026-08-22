class_name VoxelWeapon3D
extends Node3D

signal fired()

const SEMANTIC_TO_VOXEL := 1.0 / 32.0
const MUZZLE_FLASH_DURATION := 0.05

@export var data: WeaponData
@export var equipped := true

@onready var muzzle: Marker3D = $Muzzle
@onready var muzzle_flash: MeshInstance3D = $Muzzle/MuzzleFlash

var ammo_in_magazine := 0
var reserve_ammo := 0
var is_reloading := false
var owning_actor: Node

var _cooldown_remaining := 0.0
var _reload_remaining := 0.0
var _muzzle_flash_remaining := 0.0
var _projectile_spawner: Node


func _ready() -> void:
	owning_actor = _find_owning_actor()
	if data != null:
		ammo_in_magazine = data.magazine_size
		reserve_ammo = data.starting_reserve_ammo
	muzzle_flash.visible = false
	set_process(equipped)
	if equipped:
		_notify_ammo()


func _process(delta: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if is_reloading:
		_reload_remaining -= delta
		if _reload_remaining <= 0.0:
			_finish_reload()
	if _muzzle_flash_remaining > 0.0:
		_muzzle_flash_remaining -= delta
		if _muzzle_flash_remaining <= 0.0:
			muzzle_flash.visible = false


func try_fire(direction: Vector3) -> bool:
	if not equipped or data == null or is_reloading or _cooldown_remaining > 0.0:
		return false
	if ammo_in_magazine <= 0:
		try_reload()
		return false
	ammo_in_magazine -= 1
	_cooldown_remaining = 1.0 / maxf(data.fire_rate, 0.01)
	_spawn_projectile(direction)
	GameEvents.weapon_fired.emit(ammo_in_magazine, data.magazine_size)
	_notify_ammo()
	fired.emit()
	return true


func try_reload() -> bool:
	if not equipped or data == null or is_reloading or ammo_in_magazine >= data.magazine_size or reserve_ammo <= 0:
		return false
	is_reloading = true
	_reload_remaining = data.reload_duration
	if _reports_player_state():
		GameEvents.weapon_reload_started.emit(data.reload_duration)
	return true


func set_equipped(value: bool) -> void:
	equipped = value
	set_process(value)
	visible = value
	if not value:
		muzzle_flash.visible = false
	else:
		_notify_ammo()


func reset_weapon() -> void:
	is_reloading = false
	_cooldown_remaining = 0.0
	_reload_remaining = 0.0
	if data != null:
		ammo_in_magazine = data.magazine_size
		reserve_ammo = data.starting_reserve_ammo
	if equipped:
		_notify_ammo()


func _finish_reload() -> void:
	is_reloading = false
	var loaded := mini(data.magazine_size - ammo_in_magazine, reserve_ammo)
	ammo_in_magazine += loaded
	reserve_ammo -= loaded
	if _reports_player_state():
		GameEvents.weapon_reload_finished.emit(ammo_in_magazine, reserve_ammo)
	_notify_ammo()


func _spawn_projectile(direction: Vector3) -> void:
	if _projectile_spawner == null or not is_instance_valid(_projectile_spawner):
		_projectile_spawner = get_tree().get_first_node_in_group(&"voxel_projectile_spawner")
	if _projectile_spawner == null:
		return
	var spread := deg_to_rad(data.spread_degrees)
	var fire_direction := direction.rotated(Vector3.UP, randf_range(-spread, spread)).normalized()
	_projectile_spawner.spawn_projectile(
		muzzle.global_position,
		fire_direction,
		data.projectile_speed * SEMANTIC_TO_VOXEL,
		data.damage,
		data.projectile_lifetime,
		data.environment_damage_class,
		data.environment_damage,
		data.explosion_radius * SEMANTIC_TO_VOXEL,
		data.projectile_visual_scale,
		data.projectile_tint
	)
	muzzle_flash.visible = true
	_muzzle_flash_remaining = MUZZLE_FLASH_DURATION


func _notify_ammo() -> void:
	if _reports_player_state():
		GameEvents.weapon_ammo_changed.emit(ammo_in_magazine, reserve_ammo)


func _reports_player_state() -> bool:
	return owning_actor != null and is_instance_valid(owning_actor) and owning_actor.is_in_group(&"player")


func _find_owning_actor() -> Node:
	var candidate := get_parent()
	while candidate != null:
		if candidate.has_method(&"take_damage"):
			return candidate
		candidate = candidate.get_parent()
	return null
