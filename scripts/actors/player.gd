class_name Player
extends CharacterBody2D
## Eight-direction controller. Movement and aim are computed independently
## and both come from InputRouter (never Input/InputMap directly), so the
## same code drives desktop mouse+keyboard and mobile dual-joystick input
## without knowing which is active.

@export var max_speed: float = 260.0
@export var acceleration: float = 1800.0
@export var friction: float = 2000.0

@onready var health_component: HealthComponent = $HealthComponent
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var weapon: Weapon = $WeaponPivot/Weapon
@onready var body_visual: ActorVisual = $BodyVisual

var aim_direction: Vector2 = Vector2.RIGHT
var is_dead: bool = false
## Phase 3B: what loot containers/salvage transfer into. 60kg is generous
## relative to a Survivor's 20kg since the player is the one doing most of
## the district looting in this slice.
var carried_inventory: Inventory

var _fire_was_held: bool = false

func _ready() -> void:
	add_to_group("player")
	add_to_group("attackable")
	carried_inventory = Inventory.new(60.0)
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
	body_visual.update_from_velocity(velocity)

func _update_aim() -> void:
	if InputRouter.aim_vector != Vector2.ZERO:
		aim_direction = InputRouter.aim_vector
	weapon_pivot.rotation = aim_direction.angle()

func _update_movement(delta: float) -> void:
	var input_dir: Vector2 = InputRouter.movement_vector
	if input_dir != Vector2.ZERO:
		velocity = velocity.move_toward(input_dir * max_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	move_and_slide()

func _update_firing() -> void:
	if weapon == null or weapon.data == null:
		return
	if InputRouter.reload_pressed:
		weapon.try_reload()
	var fire_held: bool = InputRouter.fire_pressed
	if weapon.data.automatic:
		if fire_held:
			weapon.try_fire(aim_direction)
	else:
		if fire_held and not _fire_was_held:
			weapon.try_fire(aim_direction)
	_fire_was_held = fire_held

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
