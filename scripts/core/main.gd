class_name Main
extends Node2D
## Wires the vertical-slice systems together: finds the player, hands the
## camera and spawn manager their targets, routes pause/death/restart flow,
## and (Phase 2A) sets up the settlement's standing jobs and spawns the
## autonomous survivor population. Individual systems (SpawnManager,
## SwarmManager, Weapon, HUD, Settlement, SettlementJobBoard) remain
## independently reusable -- this script only connects them.

const SURVIVOR_SCENE: PackedScene = preload("res://scenes/actors/Survivor.tscn")
const SELECT_RADIUS := 40.0

## Starting skills/personality per survivor -- deliberately varied so the
## utility AI visibly makes different choices per survivor (a brave/combat
## survivor guards and fights more readily; a cautious/diligent one leans
## into hauling and scavenging). Not data-driven yet; four hand-authored
## presets are enough to validate the scoring system for this slice.
const SURVIVOR_PROFILES: Array[Dictionary] = [
	{
		"name": "Marcus", "age": 34, "combat_skill": 55.0, "medical_skill": 15.0,
		"scavenging_skill": 30.0, "construction_skill": 20.0, "movement_speed": 195.0,
		"personality": {"brave": 0.6, "cautious": -0.2, "diligent": 0.1, "social": 0.0},
	},
	{
		"name": "Elena", "age": 41, "combat_skill": 20.0, "medical_skill": 60.0,
		"scavenging_skill": 25.0, "construction_skill": 15.0, "movement_speed": 180.0,
		"personality": {"brave": -0.1, "cautious": 0.3, "diligent": 0.2, "social": 0.6},
	},
	{
		"name": "Dax", "age": 27, "combat_skill": 25.0, "medical_skill": 10.0,
		"scavenging_skill": 55.0, "construction_skill": 30.0, "movement_speed": 205.0,
		"personality": {"brave": 0.2, "cautious": -0.3, "diligent": 0.5, "social": 0.1},
	},
	{
		"name": "Priya", "age": 52, "combat_skill": 15.0, "medical_skill": 35.0,
		"scavenging_skill": 20.0, "construction_skill": 45.0, "movement_speed": 165.0,
		"personality": {"brave": -0.4, "cautious": 0.6, "diligent": 0.4, "social": 0.3},
	},
]

@onready var camera_rig: CameraRig = $CameraRig
@onready var spawn_manager: SpawnManager = $SpawnManager
@onready var hud: HUD = $UI/HUD
@onready var pause_menu: PauseMenu = $UI/PauseMenu
@onready var death_overlay: DeathOverlay = $UI/DeathOverlay
@onready var settlement: Settlement = $Settlement
@onready var job_board: SettlementJobBoard = $Settlement/JobBoard
@onready var survivor_container: Node2D = $SurvivorContainer

func _ready() -> void:
	get_tree().paused = false
	var player: Node2D = get_tree().get_first_node_in_group("player")
	camera_rig.set_target(player)
	spawn_manager.set_camera(camera_rig)
	spawn_manager.begin()

	_setup_settlement_jobs()
	_spawn_survivors()

	GameEvents.player_died.connect(_on_player_died)
	death_overlay.restart_requested.connect(_restart_game)
	pause_menu.quit_requested.connect(_on_quit_requested)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_try_select_survivor(get_global_mouse_position())

func _setup_settlement_jobs() -> void:
	settlement.setup_jobs(job_board)
	for point in get_tree().get_nodes_in_group("scavenge_point"):
		job_board.create_job(Job.Type.SCAVENGE, 2.0, &"", 1, point)

func _spawn_survivors() -> void:
	for i in range(SURVIVOR_PROFILES.size()):
		var survivor: Survivor = SURVIVOR_SCENE.instantiate()
		var angle: float = (TAU / SURVIVOR_PROFILES.size()) * i
		survivor.global_position = settlement.global_position + Vector2.RIGHT.rotated(angle) * 90.0
		survivor_container.add_child(survivor)
		survivor.setup(SURVIVOR_PROFILES[i], settlement)

func _try_select_survivor(world_position: Vector2) -> void:
	var best: Node2D = null
	var best_dist: float = SELECT_RADIUS
	for node in get_tree().get_nodes_in_group("survivors"):
		var survivor: Node2D = node as Node2D
		if survivor == null:
			continue
		var dist: float = world_position.distance_to(survivor.global_position)
		if dist < best_dist:
			best_dist = dist
			best = survivor
	if best:
		GameEvents.survivor_selected.emit(best)

func _on_player_died() -> void:
	pause_menu.can_pause = false
	get_tree().paused = true
	death_overlay.open()

func _restart_game() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_quit_requested() -> void:
	get_tree().quit()
