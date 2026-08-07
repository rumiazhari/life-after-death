class_name MobileControls
extends CanvasLayer
## Root controller for on-screen touch input: owns raw multi-touch
## dispatch so the two joysticks (and whichever other finger taps a
## button) never steal each other's finger, and is the ONLY node that
## talks to InputRouter about touch state. Player, Weapon, and every
## other gameplay script have no idea this scene exists.
##
## Hidden entirely on desktop; visible on an actual mobile export, or on
## desktop/editor when PlatformUtils.should_show_mobile_controls() is
## forced on via the "debug/mobile_controls/force_visible" project
## setting (a dev-only toggle for testing touch controls without a
## device).

@onready var left_joystick: TouchJoystick = $SafeArea/LeftJoystick
@onready var right_joystick: TouchJoystick = $SafeArea/RightJoystick
@onready var reload_button: Button = $SafeArea/ActionButtons/ReloadButton
@onready var interact_button: Button = $SafeArea/ActionButtons/InteractButton
@onready var pause_button: Button = $SafeArea/ActionButtons/PauseButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = PlatformUtils.should_show_mobile_controls()
	set_process_input(visible)

	left_joystick.value_changed.connect(_on_left_joystick_changed)
	right_joystick.value_changed.connect(_on_right_joystick_changed)
	reload_button.pressed.connect(func() -> void: InputRouter.request_reload())
	interact_button.pressed.connect(func() -> void: InputRouter.request_interact())
	pause_button.pressed.connect(func() -> void: InputRouter.request_pause())

func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	# Offer the raw event to both joysticks; each only reacts if the touch
	# index already belongs to it, or (touch-down only) is unclaimed and
	# lands in its own catch area -- so one finger can never steal the
	# other joystick's finger.
	var consumed: bool = left_joystick.handle_touch_event(event)
	consumed = right_joystick.handle_touch_event(event) or consumed
	if consumed:
		get_viewport().set_input_as_handled()

func _on_left_joystick_changed(vector: Vector2, active: bool) -> void:
	if active:
		InputRouter.set_touch_movement(vector)
	else:
		InputRouter.clear_touch_movement()

func _on_right_joystick_changed(vector: Vector2, active: bool) -> void:
	if active:
		# Holding or dragging the right joystick fires automatically, even
		# before it's been dragged off-center (vector may still be zero).
		InputRouter.set_touch_aim(vector, true)
	else:
		InputRouter.clear_touch_aim()
