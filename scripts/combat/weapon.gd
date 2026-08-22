class_name Weapon
extends Node2D
## Firing/reload state machine for one equipped firearm. Reads tuning from a
## WeaponData resource, requests projectiles from whatever node is in the
## "projectile_spawner" group (see ProjectileManager), and reports state
## changes through GameEvents rather than a direct HUD reference.

signal fired()

@export var data: WeaponData
@export var owning_actor_path: NodePath
@export var equipped: bool = true

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
var _owning_actor: Node = null

func _ready() -> void:
	_resolve_owning_actor()
	if data:
		ammo_in_magazine = data.magazine_size
		reserve_ammo = data.starting_reserve_ammo
	muzzle_flash.visible = false
	set_process(equipped)
	if equipped:
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
	if not equipped or data == null or is_reloading or _cooldown_remaining > 0.0:
		return false
	if ammo_in_magazine <= 0:
		try_reload()
		return false
	ammo_in_magazine -= 1
	_cooldown_remaining = 1.0 / maxf(data.fire_rate, 0.01)
	_spawn_projectile(direction)
	NoiseManager.emit_actor_noise(_owning_actor, muzzle.global_position, 20.0, &"gunshot")
	GameEvents.weapon_fired.emit(ammo_in_magazine, data.magazine_size)
	_notify_ammo()
	fired.emit()
	return true

func setup_owning_actor(actor: Node) -> void:
	_owning_actor = actor if actor != null and "detectable" in actor else null

func _resolve_owning_actor() -> void:
	if owning_actor_path != NodePath():
		var explicit := get_node_or_null(owning_actor_path)
		if explicit != null and "detectable" in explicit:
			_owning_actor = explicit
			return
	var node: Node = get_parent()
	while node != null:
		if "detectable" in node:
			_owning_actor = node
			return
		node = node.get_parent()

func try_reload() -> bool:
	if not equipped or data == null or is_reloading:
		return false
	if ammo_in_magazine >= data.magazine_size or reserve_ammo <= 0:
		return false
	is_reloading = true
	_reload_remaining = data.reload_duration
	if _reports_player_state():
		GameEvents.weapon_reload_started.emit(data.reload_duration)
	return true

func reset_weapon() -> void:
	is_reloading = false
	_cooldown_remaining = 0.0
	_reload_remaining = 0.0
	if data:
		ammo_in_magazine = data.magazine_size
		reserve_ammo = data.starting_reserve_ammo
	if equipped:
		_notify_ammo()

func set_equipped(value: bool) -> void:
	equipped = value
	set_process(value)
	if not value:
		muzzle_flash.visible = false
		_muzzle_flash_remaining = 0.0
		return
	_notify_ammo()

func _finish_reload() -> void:
	is_reloading = false
	var needed: int = data.magazine_size - ammo_in_magazine
	var loaded: int = mini(needed, reserve_ammo)
	ammo_in_magazine += loaded
	reserve_ammo -= loaded
	if _reports_player_state():
		GameEvents.weapon_reload_finished.emit(ammo_in_magazine, reserve_ammo)
	_notify_ammo()

func _notify_ammo() -> void:
	if _reports_player_state():
		GameEvents.weapon_ammo_changed.emit(ammo_in_magazine, reserve_ammo)

func _reports_player_state() -> bool:
	return _owning_actor != null and is_instance_valid(_owning_actor) and _owning_actor.is_in_group("player")

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
		data.projectile_lifetime,
		data.environment_damage_class,
		data.environment_damage,
		data.explosion_radius,
		data.explosion_noise_loudness,
		data.projectile_visual_scale,
		data.projectile_tint
	)
	muzzle_flash.visible = true
	_muzzle_flash_remaining = MUZZLE_FLASH_DURATION
