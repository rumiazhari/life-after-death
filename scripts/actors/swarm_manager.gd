class_name SwarmManager
extends Node
## Broad-phase spatial grid for zombie neighbor queries. Zombies use this
## for separation steering instead of an O(n^2) scan or a per-instance
## NavigationAgent2D, so the approach scales to hundreds of zombies.

@export var cell_size: float = 64.0

var _grid: Dictionary = {} # Vector2i -> Array[Node2D]
var _zombies: Array[Node2D] = []

func _ready() -> void:
	add_to_group("swarm_manager")

func register_zombie(zombie: Node2D) -> void:
	if not _zombies.has(zombie):
		_zombies.append(zombie)

func unregister_zombie(zombie: Node2D) -> void:
	_zombies.erase(zombie)

func _physics_process(_delta: float) -> void:
	_rebuild_grid()

func get_nearby(zombie: Node2D, radius: float) -> Array:
	var result: Array = []
	var center_cell: Vector2i = _cell_of(zombie.global_position)
	var cell_radius: int = int(ceil(radius / cell_size))
	for dx in range(-cell_radius, cell_radius + 1):
		for dy in range(-cell_radius, cell_radius + 1):
			var cell: Vector2i = center_cell + Vector2i(dx, dy)
			if _grid.has(cell):
				for other in (_grid[cell] as Array):
					if other != zombie:
						result.append(other)
	return result

func active_count() -> int:
	return _zombies.size()

func _rebuild_grid() -> void:
	_grid.clear()
	var i: int = _zombies.size() - 1
	while i >= 0:
		var zombie: Node2D = _zombies[i]
		if not is_instance_valid(zombie):
			_zombies.remove_at(i)
			i -= 1
			continue
		var cell: Vector2i = _cell_of(zombie.global_position)
		if not _grid.has(cell):
			_grid[cell] = []
		(_grid[cell] as Array).append(zombie)
		i -= 1

func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / cell_size), floori(pos.y / cell_size))
