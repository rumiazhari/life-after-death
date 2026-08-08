extends Node

const MAIN_SCENE: PackedScene = preload("res://scenes/main/Main.tscn")
const PROFILE_SECONDS := 20.0

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

func _ready() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().process_frame
	_spawn_manager = get_tree().get_first_node_in_group("spawn_manager")
	_spawn_manager.apply_population_profile(SpawnManager.PopulationProfile.STRESS)
	_spawn_manager.spawn_burst(250)
	set_process(true)

func _process(delta: float) -> void:
	if _spawn_manager == null:
		return
	_warmup += delta
	_total_wait += delta
	var population := get_tree().get_nodes_in_group("zombies").size()
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
	elif _total_wait >= 45.0:
		print("URBAN_250_PROFILE_FAILED population did not stabilize")
		get_tree().quit(1)

func _finish() -> void:
	var checks: int = UrbanNavigationService.direct_path_checks_total - _start_checks
	var requests: int = UrbanNavigationService.path_requests_total - _start_requests
	var report := {
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
	get_tree().quit(0 if valid else 1)
