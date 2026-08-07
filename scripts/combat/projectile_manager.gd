class_name ProjectileManager
extends Node2D
## Owns the projectile pool. Any weapon finds this node via the
## "projectile_spawner" group and calls spawn_projectile() -- no direct
## script reference between combat/ and actors/ is required.

@export var projectile_scene: PackedScene
@export var prewarm_count: int = 64

var _pool: ObjectPool

func _ready() -> void:
	add_to_group("projectile_spawner")
	if projectile_scene:
		_pool = ObjectPool.new(projectile_scene, self, prewarm_count)

func spawn_projectile(start_position: Vector2, direction: Vector2, speed: float, damage: float, lifetime: float) -> void:
	if _pool == null:
		return
	var projectile: Projectile = _pool.acquire()
	projectile.setup(start_position, direction, speed, damage, lifetime, _pool)

func active_projectile_count() -> int:
	return get_child_count() - _pool.available_count()

func pool_capacity() -> int:
	return _pool.capacity() if _pool else 0
