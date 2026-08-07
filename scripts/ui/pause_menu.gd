class_name PauseMenu
extends CanvasLayer
## Owns the pause/resume state itself (via get_tree().paused) so it keeps
## working while the rest of the tree is paused. Main only toggles
## `can_pause` to lock this out during game-over.

signal quit_requested()

var can_pause: bool = true

@onready var resume_button: Button = $Root/Panel/VBox/ResumeButton
@onready var quit_button: Button = $Root/Panel/VBox/QuitButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	resume_button.pressed.connect(_on_resume_pressed)
	quit_button.pressed.connect(func() -> void: quit_requested.emit())

func _unhandled_input(event: InputEvent) -> void:
	if not can_pause:
		return
	if event.is_action_pressed("pause"):
		if visible:
			_on_resume_pressed()
		else:
			open()
		get_viewport().set_input_as_handled()

func open() -> void:
	visible = true
	get_tree().paused = true
	GameEvents.game_paused.emit()

func _on_resume_pressed() -> void:
	visible = false
	get_tree().paused = false
	GameEvents.game_resumed.emit()
