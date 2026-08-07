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
