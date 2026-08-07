class_name Main
extends Node2D
## Wires the vertical-slice systems together: finds the player, hands the
## camera and spawn manager their targets, and routes pause/death/restart
## flow. Individual systems (SpawnManager, SwarmManager, Weapon, HUD)
## remain independently reusable -- this script only connects them.

@onready var camera_rig: CameraRig = $CameraRig
@onready var spawn_manager: SpawnManager = $SpawnManager
@onready var hud: HUD = $UI/HUD
@onready var pause_menu: PauseMenu = $UI/PauseMenu
@onready var death_overlay: DeathOverlay = $UI/DeathOverlay

func _ready() -> void:
	get_tree().paused = false
	var player: Node2D = get_tree().get_first_node_in_group("player")
	camera_rig.set_target(player)
	spawn_manager.set_camera(camera_rig)
	spawn_manager.begin()

	GameEvents.player_died.connect(_on_player_died)
	death_overlay.restart_requested.connect(_restart_game)
	pause_menu.quit_requested.connect(_on_quit_requested)

func _on_player_died() -> void:
	pause_menu.can_pause = false
	get_tree().paused = true
	death_overlay.open()

func _restart_game() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_quit_requested() -> void:
	get_tree().quit()
