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
@onready var detectable: DetectableComponent = $DetectableComponent

var aim_direction: Vector2 = Vector2.RIGHT
var is_dead: bool = false
var weapon_slot_index: int = 0
var weapon_slots: Array[Weapon] = []
## Phase 3B: what loot containers/salvage transfer into. 60kg is generous
## relative to a Survivor's 20kg since the player is the one doing most of
## the district looting in this slice.
var carried_inventory: Inventory

var _fire_was_held: bool = false
## External physical pushes (explosions) layered onto input movement.
var _knockback := Vector2.ZERO

func apply_knockback(push: Vector2) -> void:
	_knockback = (_knockback + push).limit_length(420.0)

func _ready() -> void:
	add_to_group("player")
	add_to_group("attackable")
	carried_inventory = Inventory.new(60.0)
	health_component.died.connect(_on_died)
	health_component.damaged.connect(_on_damaged)
	health_component.health_changed.connect(_on_health_changed)
	_collect_weapon_slots()
	InputRouter.weapon_slot_requested.connect(equip_weapon_slot)
	InputRouter.weapon_cycle_requested.connect(cycle_weapon)
	_on_health_changed(health_component.current_health, health_component.max_health)
	call_deferred("_emit_equipped_weapon")

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_update_aim()
	_update_movement(delta)
	_update_firing()
	body_visual.update_from_velocity(velocity)
	detectable.report_movement_speed(velocity.length())

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
	# External physical pushes ride on top of input movement, decaying fast.
	velocity += _knockback
	_knockback = _knockback.lerp(Vector2.ZERO, minf(9.0 * delta, 1.0))
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

func _collect_weapon_slots() -> void:
	weapon_slots.clear()
	for child in weapon_pivot.get_children():
		if child is Weapon:
			weapon_slots.append(child as Weapon)
	if weapon_slots.is_empty():
		return
	weapon_slot_index = clampi(weapon_slot_index, 0, weapon_slots.size() - 1)
	for i in range(weapon_slots.size()):
		weapon_slots[i].set_equipped(i == weapon_slot_index)
	weapon = weapon_slots[weapon_slot_index]

func equip_weapon_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= weapon_slots.size() or slot_index == weapon_slot_index:
		return false
	weapon_slots[weapon_slot_index].set_equipped(false)
	weapon_slot_index = slot_index
	weapon = weapon_slots[weapon_slot_index]
	weapon.set_equipped(true)
	_fire_was_held = InputRouter.fire_pressed
	_emit_equipped_weapon()
	return true

func cycle_weapon(direction: int = 1) -> bool:
	if weapon_slots.size() < 2:
		return false
	var next_slot := posmod(weapon_slot_index + direction, weapon_slots.size())
	return equip_weapon_slot(next_slot)

func _emit_equipped_weapon() -> void:
	if weapon == null or weapon.data == null:
		return
	GameEvents.weapon_equipped.emit(
		weapon.data.weapon_name,
		weapon_slot_index,
		weapon_slots.size(),
		weapon.ammo_in_magazine,
		weapon.reserve_ammo,
		weapon.data.magazine_size
	)

func take_damage(amount: float, source: Node = null) -> void:
	if is_dead:
		return
	health_component.take_damage(amount, source)

func respawn(spawn_position: Vector2) -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	is_dead = false
	health_component.reset_health()
	for slot_weapon in weapon_slots:
		slot_weapon.reset_weapon()
	if not weapon_slots.is_empty():
		if weapon_slot_index != 0:
			weapon_slots[weapon_slot_index].set_equipped(false)
		weapon_slot_index = 0
		weapon = weapon_slots[0]
		weapon.set_equipped(true)
		_emit_equipped_weapon()
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
