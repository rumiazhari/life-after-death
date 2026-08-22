extends Node

const MAIN_SCENE: PackedScene = preload("res://scenes/main/Main.tscn")
const PROFILE_CITY_SEED := 20260821
const PROFILE_SECONDS := 20.0
const STRESS_SEARCH_ATTEMPTS := 480
const STRESS_PLAYER_HEALTH := 1_000_000.0

var _main: Node
var _spawn_manager: SpawnManager
var _elapsed := 0.0
var _warmup := 0.0
var _start_checks := 0
var _start_requests := 0
var _min_population := 9999
var _max_population := 0
var _fps_sum := 0.0
var _min_fps := INF
var _frame_sum_ms := 0.0
var _worst_frame_ms := 0.0
var _samples := 0
var _total_wait := 0.0
var _generation_ms := 0
var _finished := false

func _ready() -> void:
	_main = MAIN_SCENE.instantiate()
	var world := _main.get_node("World") as StreamingWorld
	world.city_seed = PROFILE_CITY_SEED
	add_child(_main)
	if not world.generation_complete:
		await world.generation_completed
	if not world.generation_succeeded:
		print("URBAN_250_PROFILE_FAILED procedural generation failed for seed %d" % PROFILE_CITY_SEED)
		_finish_and_quit(1)
		return
	_generation_ms = world.generation_duration_ms
	await get_tree().physics_frame
	_spawn_manager = get_tree().get_first_node_in_group("spawn_manager")
	if _spawn_manager == null:
		print("URBAN_250_PROFILE_FAILED SpawnManager was not initialized")
		_finish_and_quit(1)
		return
	_spawn_manager.apply_population_profile(SpawnManager.PopulationProfile.STRESS)
	# Keep production's strict candidate validation, but spend a larger search
	# budget so this harness measures a full stress population instead of the
	# random acceptance rate of one small bounded search.
	_spawn_manager.max_region_search_attempts = STRESS_SEARCH_ATTEMPTS
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player:
		player.health_component.max_health = STRESS_PLAYER_HEALTH
		player.health_component.reset_health()
	_spawn_manager.spawn_burst(250)
	set_process(true)

func _process(delta: float) -> void:
	if _spawn_manager == null:
		return
	_warmup += delta
	_total_wait += delta
	var population := get_tree().get_nodes_in_group("zombies").size()
	if _total_wait >= 45.0 and population < 250:
		print("URBAN_250_PROFILE_FAILED population did not stabilize count=%d wait_seconds=%.3f" % [population, _total_wait])
		_finish_and_quit(1)
		return
	if _warmup < 2.0 or population < 250:
		return
	if _elapsed == 0.0:
		_start_checks = UrbanNavigationService.direct_path_checks_total
		_start_requests = UrbanNavigationService.path_requests_total
		_elapsed = 0.001
	else:
		_elapsed += delta
	_min_population = mini(_min_population, population)
	_max_population = maxi(_max_population, population)
	var fps := Engine.get_frames_per_second()
	_fps_sum += fps
	_min_fps = minf(_min_fps, fps)
	var frame_ms := delta * 1000.0
	_frame_sum_ms += frame_ms
	_worst_frame_ms = maxf(_worst_frame_ms, frame_ms)
	_samples += 1
	if _elapsed >= PROFILE_SECONDS:
		_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	var checks: int = UrbanNavigationService.direct_path_checks_total - _start_checks
	var requests: int = UrbanNavigationService.path_requests_total - _start_requests
	var report := {
		"city_seed": PROFILE_CITY_SEED,
		"generation_ms": _generation_ms,
		"elapsed_seconds": _elapsed,
		"active_zombie_min": _min_population,
		"active_zombie_max": _max_population,
		"direct_checks_total": checks,
		"direct_checks_per_second": checks / _elapsed,
		"path_requests_total": requests,
		"path_requests_per_second": requests / _elapsed,
		"average_fps": _fps_sum / maxf(_samples, 1),
		"minimum_fps": _min_fps,
		"average_frame_ms": _frame_sum_ms / maxf(_samples, 1),
		"worst_frame_ms": _worst_frame_ms,
		"node_count": get_tree().get_node_count(),
		"samples": _samples,
	}
	print("URBAN_250_PROFILE ", JSON.stringify(report))
	var file := FileAccess.open("user://urban_250_profile.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "  "))
	var workspace_file := FileAccess.open("res://tests/performance/urban_250_profile_report.json", FileAccess.WRITE)
	if workspace_file:
		workspace_file.store_string(JSON.stringify(report, "  "))
	var valid := _elapsed >= 19.5 and _min_population >= 245 and _max_population <= 250
	# _finish already owns the completion flag; schedule termination directly.
	call_deferred("_quit_after_report", 0 if valid else 1)

func _finish_and_quit(exit_code: int) -> void:
	if _finished:
		return
	_finished = true
	# Let FileAccess close and the game-helper logger forward the terminal
	# report before ending this custom benchmark scene.
	call_deferred("_quit_after_report", exit_code)

func _quit_after_report(exit_code: int) -> void:
	get_tree().quit(exit_code)
