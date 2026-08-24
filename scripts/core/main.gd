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
## Phase 3A.1: survivors now spawn straight into EntityContainer (same
## y_sort_enabled=true node Player/Zombies/ScavengePoints/props live in),
## instead of a separate non-sorted SurvivorContainer, so they sort
## correctly against everything else in the dynamic world layer.
@onready var survivor_container: Node2D = $EntityContainer
@onready var world: Node2D = $World

func _ready() -> void:
	get_tree().paused = false
	var player: Node2D = get_tree().get_first_node_in_group("player")
	camera_rig.set_target(player)
	spawn_manager.set_camera(camera_rig)
	# ProceduralDistrict builds collision, rooms, semantic spawn regions and
	# navigation asynchronously over two physics frames. Population systems
	# must not sample the world until that contract is complete.
	if "generation_complete" in world and not world.get("generation_complete"):
		await world.generation_completed
	if "generation_succeeded" in world and not bool(world.get("generation_succeeded")):
		push_error("Main initialization stopped because procedural world generation failed")
		return
	if world.has_method("get_safehouse_position"):
		settlement.global_position = world.call("get_safehouse_position")
	if player and world.has_method("get_player_spawn"):
		player.global_position = world.call("get_player_spawn")
	if "resolved_seed" in world:
		spawn_manager.set_world_seed(int(world.get("resolved_seed")), player.global_position if player else Vector2.ZERO)
	spawn_manager.begin()

	# Survivor groups occupy ordinary generated buildings: deterministically
	# claim the best eligible building from the origin chunk as the group's
	# base. The dedicated safehouse reservation now only bootstraps the
	# player spawn; the settlement itself lives in a generic building.
	var origin_model := _origin_city_model()
	if not origin_model.is_empty():
		var seed_value := int(world.get("resolved_seed")) if "resolved_seed" in world else 0
		settlement.claim_building_base(origin_model, seed_value, survivor_container)

	_setup_settlement_jobs()
	_spawn_survivors()

	# Story & dialogue: one controller + one UI for the session. Gameplay
	# hooks (interactables, triggers) call controller.start(id).
	var dialogue_controller := DialogueController.new()
	dialogue_controller.name = "DialogueController"
	add_child(dialogue_controller)
	var dialogue_ui := DialogueUI.new()
	dialogue_ui.name = "DialogueUI"
	add_child(dialogue_ui)
	dialogue_ui.bind(dialogue_controller)
	GameEvents.player_died.connect(dialogue_controller.cancel)

	# 2.5D building layer: real stacked geometry for generated buildings,
	# rendered through a subviewport camera matched to the 2D camera.
	var world_25d := BuildingWorld3D.new()
	world_25d.name = "BuildingWorld3D"
	add_child(world_25d)

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

## The generated semantic model of the origin chunk (or the whole legacy
## district) -- the pool ordinary survivor bases are claimed from.
func _origin_city_model() -> Dictionary:
	var world_node := world
	if world_node is StreamingWorld:
		var chunk := (world_node as StreamingWorld).get_chunk(Vector2i.ZERO)
		return chunk.city_model if chunk != null else {}
	if world_node is ProceduralDistrict:
		return (world_node as ProceduralDistrict).city_model
	return {}

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
	_prepare_restart_state()
	get_tree().reload_current_scene()

## Performs the persistent/autoload half of the production restart. Kept
## separate from SceneTree.reload_current_scene() so the full Main lifecycle
## can exercise this exact reset order inside the regression runner without
## replacing the TestRunner scene itself.
func _prepare_restart_state() -> int:
	get_tree().paused = false
	var selected_seed := int(world.get("resolved_seed")) if world and "resolved_seed" in world else -1
	NoiseManager.reset()
	UrbanNavigationService.reset()
	# WorldState/SimulationClock are autoloads and survive
	# reload_current_scene() (only the scene tree gets torn down and
	# rebuilt) -- reset them explicitly here, before the reload, so the new
	# scene's Settlement/StorageContainer/Survivor nodes register into a
	# clean registry (fresh ids starting at 1 again) instead of piling onto
	# whatever the previous run left behind.
	WorldState.reset()
	# A restart clears all generated nodes and persistent prop/door state, but
	# rebuilds the same selected city. Changing the seed is an explicit world
	# selection action, not an accidental side effect of dying/restarting.
	if selected_seed >= 0:
		WorldState.world_flags[&"city_seed"] = selected_seed
	SimulationClock.reset()
	return selected_seed

func _on_quit_requested() -> void:
	get_tree().quit()
