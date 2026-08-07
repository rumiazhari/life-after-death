class_name Player
extends CharacterBody2D
## Eight-direction, mouse-aiming player controller. Movement direction and
## aim direction are computed independently: WASD/arrows drive velocity,
## the mouse cursor drives WeaponPivot rotation, so you can strafe one way
## while aiming another.

@export var max_speed: float = 260.0
@export var acceleration: float = 1800.0
@export var friction: float = 2000.0

@onready var health_component: HealthComponent = $HealthComponent
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var weapon: Weapon = $WeaponPivot/Weapon
@onready var body_visual: Polygon2D = $BodyVisual

var aim_direction: Vector2 = Vector2.RIGHT
var is_dead: bool = false

func _ready() -> void:
	add_to_group("player")
	health_component.died.connect(_on_died)
	health_component.damaged.connect(_on_damaged)
	health_component.health_changed.connect(_on_health_changed)
	_on_health_changed(health_component.current_health, health_component.max_health)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_update_aim()
	_update_movement(delta)
	_update_firing()

func _update_aim() -> void:
	var to_mouse: Vector2 = get_global_mouse_position() - global_position
	if to_mouse.length() > 1.0:
		aim_direction = to_mouse.normalized()
	weapon_pivot.rotation = aim_direction.angle()

func _update_movement(delta: float) -> void:
	var input_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()
	if input_dir != Vector2.ZERO:
		velocity = velocity.move_toward(input_dir * max_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	move_and_slide()

func _update_firing() -> void:
	if weapon == null or weapon.data == null:
		return
	if Input.is_action_just_pressed("reload"):
		weapon.try_reload()
	if weapon.data.automatic:
		if Input.is_action_pressed("fire"):
			weapon.try_fire(aim_direction)
	else:
		if Input.is_action_just_pressed("fire"):
			weapon.try_fire(aim_direction)

func take_damage(amount: float, source: Node = null) -> void:
	if is_dead:
		return
	health_component.take_damage(amount, source)

func respawn(spawn_position: Vector2) -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	is_dead = false
	health_component.reset_health()
	if weapon:
		weapon.reset_weapon()
	body_visual.modulate = Color(1, 1, 1)
	GameEvents.player_respawned.emit()

func _on_health_changed(current: float, max_health: float) -> void:
	GameEvents.player_health_changed.emit(current, max_health)

func _on_damaged(_amount: float) -> void:
	GameEvents.player_damaged.emit(_amount)
	body_visual.modulate = Color(1, 0.3, 0.3)
	var tween := create_tween()
	tween.tween_property(body_visual, "modulate", Color(1, 1, 1), 0.2)

func _on_died() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	GameEvents.player_died.emit()
