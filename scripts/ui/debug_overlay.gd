class_name DebugOverlay
extends CanvasLayer
## Always-on performance readout for tuning population profiles: FPS,
## frame/physics time, active zombies/projectiles, projectile pool
## capacity, and spatial-grid broad-phase load. Purely a debug aid -- it
## only reads counters other systems already expose, never writes to them.

@onready var label: Label = $Panel/Label

## decisions/s and actions-eval/s are accumulated over a rolling ~1s window
## rather than sampled per-frame -- individual survivor reconsiderations are
## sparse relative to 60fps, so an instantaneous per-frame rate would read
## as 0.0 almost always even while decisions are happening steadily.
const RATE_WINDOW_SECONDS := 1.0

var _window_start_decisions: int = 0
var _window_start_actions: int = 0
var _window_elapsed: float = 0.0
var _decisions_per_second: float = 0.0
var _actions_evaluated_per_second: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	var swarm_mgr: SwarmManager = get_tree().get_first_node_in_group("swarm_manager")
	var spawn_mgr: SpawnManager = get_tree().get_first_node_in_group("spawn_manager")
	var projectile_mgr: ProjectileManager = get_tree().get_first_node_in_group("projectile_spawner")
	var job_board: SettlementJobBoard = get_tree().get_first_node_in_group("job_board")
	var voxel_main: Node = get_tree().get_first_node_in_group(&"voxel_main")

	var frame_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var voxel_projectiles: Node = voxel_main.projectile_manager if voxel_main != null else null
	var zombies: int = spawn_mgr.active_zombie_count() if spawn_mgr else get_tree().get_nodes_in_group(&"voxel_zombies").size()
	var projectiles: int = projectile_mgr.active_projectile_count() if projectile_mgr else (voxel_projectiles.active_projectile_count() if voxel_projectiles != null else 0)
	var pool_capacity: int = projectile_mgr.pool_capacity() if projectile_mgr else (voxel_projectiles.pool_capacity() if voxel_projectiles != null else 0)
	var grid_queries: int = swarm_mgr.queries_last_frame if swarm_mgr else 0
	var grid_candidates: int = swarm_mgr.candidates_examined_last_frame if swarm_mgr else 0

	var survivor_stats: Dictionary = _collect_survivor_stats(delta)
	var reservations: int = _count_inventory_reservations()

	var voxel_stream: Dictionary = voxel_main.stream_controller.metrics() if voxel_main != null else {}
	var voxel_jobs: Dictionary = voxel_main.semantic_job_board.metrics() if voxel_main != null else {}
	label.text = ("FPS %d | frame %.2fms | physics %.2fms\n" +
		"zombies %d | projectiles %d/%d | grid queries %d candidates %d\n" +
		"survivors %d | decisions/s %.1f | actions eval/s %.1f | avg decision %.3fms\n" +
		"jobs: %d avail / %d reserved / %d active | inventory reservations %d\n" +
		"voxel chunks %d queued %d | voxels %d | faces %d") % [
		Engine.get_frames_per_second(), frame_ms, physics_ms,
		zombies, projectiles, pool_capacity, grid_queries, grid_candidates,
		survivor_stats.count, _decisions_per_second, _actions_evaluated_per_second, survivor_stats.avg_decision_ms,
		job_board.jobs_available_count() if job_board else int(voxel_jobs.get("available", 0)),
		job_board.jobs_reserved_count() if job_board else int(voxel_jobs.get("reserved", 0)),
		job_board.jobs_active_count() if job_board else 0,
		reservations,
		int(voxel_stream.get("loaded_chunks", 0)), int(voxel_stream.get("pending_chunks", 0)),
		int(voxel_stream.get("voxel_count", 0)), int(voxel_stream.get("visible_faces", 0)),
	]

func _collect_survivor_stats(delta: float) -> Dictionary:
	var decisions_total: int = 0
	var actions_total: int = 0
	var decision_time_sum: float = 0.0
	var count: int = 0
	for survivor in get_tree().get_nodes_in_group("survivors"):
		var ai = survivor.ai if survivor is Survivor else (survivor.utility_ai if "utility_ai" in survivor else null)
		if ai == null:
			continue
		count += 1
		decisions_total += ai.decisions_made
		actions_total += ai.actions_evaluated
		decision_time_sum += ai.average_decision_time_ms()

	_window_elapsed += delta
	if _window_elapsed >= RATE_WINDOW_SECONDS:
		_decisions_per_second = float(decisions_total - _window_start_decisions) / _window_elapsed
		_actions_evaluated_per_second = float(actions_total - _window_start_actions) / _window_elapsed
		_window_start_decisions = decisions_total
		_window_start_actions = actions_total
		_window_elapsed = 0.0

	return {
		"count": count,
		"avg_decision_ms": (decision_time_sum / count) if count > 0 else 0.0,
	}

func _count_inventory_reservations() -> int:
	var total: int = 0
	for container_id in WorldState.containers:
		total += (WorldState.containers[container_id] as Inventory).reservation_count()
	return total
