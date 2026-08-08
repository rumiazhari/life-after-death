class_name Weapon
extends Node2D
## Firing/reload state machine for one equipped firearm. Reads tuning from a
## WeaponData resource, requests projectiles from whatever node is in the
## "projectile_spawner" group (see ProjectileManager), and reports state
## changes through GameEvents rather than a direct HUD reference.

signal fired()

@export var data: WeaponData

@onready var muzzle: Marker2D = $Muzzle
@onready var muzzle_flash: Sprite2D = $Muzzle/MuzzleFlash

const MUZZLE_FLASH_DURATION := 0.05

var ammo_in_magazine: int = 0
var reserve_ammo: int = 0
var is_reloading: bool = false

var _cooldown_remaining: float = 0.0
var _reload_remaining: float = 0.0
var _muzzle_flash_remaining: float = 0.0
var _projectile_spawner: Node = null

func _ready() -> void:
	if data:
		ammo_in_magazine = data.magazine_size
		reserve_ammo = data.starting_reserve_ammo
	muzzle_flash.visible = false
	_notify_ammo()

func _process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
	if is_reloading:
		_reload_remaining -= delta
		if _reload_remaining <= 0.0:
			_finish_reload()
	if _muzzle_flash_remaining > 0.0:
		_muzzle_flash_remaining -= delta
		if _muzzle_flash_remaining <= 0.0:
			muzzle_flash.visible = false

func try_fire(direction: Vector2) -> bool:
	if data == null or is_reloading or _cooldown_remaining > 0.0:
		return false
	if ammo_in_magazine <= 0:
		try_reload()
		return false
	ammo_in_magazine -= 1
	_cooldown_remaining = 1.0 / maxf(data.fire_rate, 0.01)
	_spawn_projectile(direction)
	NoiseManager.emit_noise(muzzle.global_position, 20.0, &"gunshot")
	GameEvents.weapon_fired.emit(ammo_in_magazine, data.magazine_size)
	_notify_ammo()
	fired.emit()
	return true

func try_reload() -> bool:
	if data == null or is_reloading:
		return false
	if ammo_in_magazine >= data.magazine_size or reserve_ammo <= 0:
		return false
	is_reloading = true
	_reload_remaining = data.reload_duration
	GameEvents.weapon_reload_started.emit(data.reload_duration)
	return true

func reset_weapon() -> void:
	is_reloading = false
	_cooldown_remaining = 0.0
	_reload_remaining = 0.0
	if data:
		ammo_in_magazine = data.magazine_size
		reserve_ammo = data.starting_reserve_ammo
	_notify_ammo()

func _finish_reload() -> void:
	is_reloading = false
	var needed: int = data.magazine_size - ammo_in_magazine
	var loaded: int = mini(needed, reserve_ammo)
	ammo_in_magazine += loaded
	reserve_ammo -= loaded
	GameEvents.weapon_reload_finished.emit(ammo_in_magazine, reserve_ammo)
	_notify_ammo()

func _notify_ammo() -> void:
	GameEvents.weapon_ammo_changed.emit(ammo_in_magazine, reserve_ammo)

func _spawn_projectile(direction: Vector2) -> void:
	if _projectile_spawner == null or not is_instance_valid(_projectile_spawner):
		_projectile_spawner = get_tree().get_first_node_in_group("projectile_spawner")
		if _projectile_spawner == null:
			return
	var spread_rad: float = deg_to_rad(data.spread_degrees)
	var angle_offset: float = randf_range(-spread_rad, spread_rad)
	var fire_direction: Vector2 = direction.rotated(angle_offset)
	_projectile_spawner.call(
		"spawn_projectile",
		muzzle.global_position,
		fire_direction,
		data.projectile_speed,
		data.damage,
		data.projectile_lifetime
	)
	muzzle_flash.visible = true
	_muzzle_flash_remaining = MUZZLE_FLASH_DURATION
