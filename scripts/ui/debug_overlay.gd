class_name DebugOverlay
extends CanvasLayer
## Always-on performance readout for tuning population profiles: FPS,
## frame/physics time, active zombies/projectiles, projectile pool
## capacity, and spatial-grid broad-phase load. Purely a debug aid -- it
## only reads counters other systems already expose, never writes to them.

@onready var label: Label = $Panel/Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	var swarm_mgr: SwarmManager = get_tree().get_first_node_in_group("swarm_manager")
	var spawn_mgr: SpawnManager = get_tree().get_first_node_in_group("spawn_manager")
	var projectile_mgr: ProjectileManager = get_tree().get_first_node_in_group("projectile_spawner")

	var frame_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var zombies: int = spawn_mgr.active_zombie_count() if spawn_mgr else 0
	var projectiles: int = projectile_mgr.active_projectile_count() if projectile_mgr else 0
	var pool_capacity: int = projectile_mgr.pool_capacity() if projectile_mgr else 0
	var grid_queries: int = swarm_mgr.queries_last_frame if swarm_mgr else 0
	var grid_candidates: int = swarm_mgr.candidates_examined_last_frame if swarm_mgr else 0

	label.text = "FPS %d | frame %.2fms | physics %.2fms\nzombies %d | projectiles %d/%d | grid queries %d candidates %d" % [
		Engine.get_frames_per_second(), frame_ms, physics_ms,
		zombies, projectiles, pool_capacity, grid_queries, grid_candidates,
	]
