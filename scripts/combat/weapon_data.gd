class_name WeaponData
extends Resource
## Tunable firearm definition. One resource instance = one weapon "type";
## Weapon (weapon.gd) reads from this at runtime and never hard-codes stats.

@export var weapon_name: String = "Weapon"
@export var damage: float = 10.0
@export var fire_rate: float = 10.0 ## shots per second
@export var magazine_size: int = 30
@export var reload_duration: float = 1.5 ## seconds
@export var projectile_speed: float = 900.0 ## px/sec
@export var projectile_lifetime: float = 1.2 ## seconds
@export var spread_degrees: float = 3.0 ## +/- half-angle random spread
@export var automatic: bool = true ## true = held fire, false = one shot per press
@export var starting_reserve_ammo: int = 180
## Static-environment impact is separate from actor damage. Ordinary firearm
## rounds remain SMALL_ARMS; a future heavy weapon or bomb can opt into the
## stronger classes without changing Projectile's collision contract.
@export_enum("Small Arms", "Heavy", "Explosive") var environment_damage_class: int = EnvironmentDamage.DamageClass.SMALL_ARMS
@export var environment_damage: float = 10.0
## A positive radius turns the impact into a radial blast. Zero preserves the
## existing single-body projectile behavior.
@export var explosion_radius: float = 0.0
@export var explosion_noise_loudness: float = 0.0
@export var projectile_visual_scale: float = 1.0
@export var projectile_tint: Color = Color.WHITE
