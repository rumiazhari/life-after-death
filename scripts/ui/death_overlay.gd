class_name DeathOverlay
extends CanvasLayer
## Game-over screen. Stays interactive while the tree is paused
## (process_mode ALWAYS) and reloads the current scene to restart, which
## resets every system (health, ammo, zombies, kills) without bespoke
## per-system reset bookkeeping.

signal restart_requested()

@onready var restart_button: Button = $Root/Panel/VBox/RestartButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	restart_button.pressed.connect(_on_restart_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("restart"):
		_on_restart_pressed()
		get_viewport().set_input_as_handled()

func open() -> void:
	visible = true

func close() -> void:
	visible = false

func _on_restart_pressed() -> void:
	restart_requested.emit()
