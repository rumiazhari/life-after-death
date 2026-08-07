class_name Survivor
extends CharacterBody2D
## Autonomous settlement resident. Shares HealthComponent and the
## Weapon/WeaponData combat pipeline with Player, and the same seek-style
## steering shape as Zombie, but is driven entirely by its SurvivorAI child
## (scripts/ai/survivor_ai.gd) instead of InputRouter -- nothing in this
## script or SurvivorAI ever reads player input.

@export var arrive_threshold: float = 14.0
@export var steer_acceleration: float = 1600.0

@onready var health_component: HealthComponent = $HealthComponent
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var weapon: Weapon = $WeaponPivot/Weapon
@onready var body_visual: Polygon2D = $BodyVisual
@onready var ai: SurvivorAI = $SurvivorAI
@onready var screen_notifier: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D

var data: SurvivorData
var carried_inventory: Inventory
var is_dead: bool = false
var is_on_screen: bool = true

var aim_direction: Vector2 = Vector2.RIGHT

## Lightweight single-claim lock so at most one helper commits to treating
## this survivor at a time (ActionHelpInjured) -- cheaper than routing every
## injury through the settlement job board for a same-settlement 1:1 claim.
var _being_helped_by: int = 0

func try_claim_helper(survivor_id: int) -> bool:
	if _being_helped_by != 0 and _being_helped_by != survivor_id:
		return false
	_being_helped_by = survivor_id
	return true

func release_helper(survivor_id: int) -> void:
	if _being_helped_by == survivor_id:
		_being_helped_by = 0

func is_claimed_for_help() -> bool:
	return _being_helped_by != 0

func _ready() -> void:
	add_to_group("survivors")
	add_to_group("attackable")
	carried_inventory = Inventory.new(20.0)
	health_component.died.connect(_on_died)
	health_component.damaged.connect(_on_damaged)
	screen_notifier.screen_entered.connect(func(): is_on_screen = true)
	screen_notifier.screen_exited.connect(func(): is_on_screen = false)

## Called by whatever spawns this survivor (Main) right after add_child, so
## @onready state exists but the AI hasn't ticked yet. Registers the backing
## SurvivorData with WorldState and joins the settlement's member registry.
func setup(profile: Dictionary, home_settlement: Settlement) -> void:
	data = SurvivorData.new()
	data.survivor_name = profile.get("name", "Survivor")
	data.age = profile.get("age", 30)
	data.combat_skill = profile.get("combat_skill", 25.0)
	data.medical_skill = profile.get("medical_skill", 25.0)
	data.scavenging_skill = profile.get("scavenging_skill", 25.0)
	data.construction_skill = profile.get("construction_skill", 25.0)
	data.movement_speed = profile.get("movement_speed", 190.0)
	data.personality = profile.get("personality", {"brave": 0.0, "cautious": 0.0, "diligent": 0.0, "social": 0.0})
	data.max_health = health_component.max_health
	data.health = data.max_health
	WorldState.register_survivor(data)
	if home_settlement:
		data.current_settlement = home_settlement.data.id
		home_settlement.add_member(data.id)
	ai.begin(data)
	GameEvents.survivor_spawned.emit(self)

func _physics_process(_delta: float) -> void:
	if is_dead:
		return
	# Movement/aim/firing are driven by the active UtilityAction through
	# SurvivorAI's own _physics_process -- this only keeps the persisted
	# health mirror in sync for the inspector/HUD.
	if data:
		data.health = health_component.current_health

## Seeks `point`, returns true once within arrive_threshold. Shared by every
## movement-driven action instead of each one re-implementing steering.
func move_toward_point(point: Vector2, delta: float) -> bool:
	var to_point: Vector2 = point - global_position
	var distance: float = to_point.length()
	var speed: float = data.movement_speed if data else 190.0
	if distance <= arrive_threshold:
		velocity = velocity.move_toward(Vector2.ZERO, steer_acceleration * delta)
		move_and_slide()
		return true
	var dir: Vector2 = to_point / distance
	_face(dir)
	velocity = velocity.move_toward(dir * speed, steer_acceleration * delta)
	move_and_slide()
	return false

func stop_moving(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, steer_acceleration * delta)
	move_and_slide()

func face_and_fire(target_position: Vector2) -> bool:
	var dir: Vector2 = (target_position - global_position)
	if dir.length() > 0.001:
		_face(dir.normalized())
	if weapon == null or weapon.data == null:
		return false
	return weapon.try_fire(aim_direction)

func _face(dir: Vector2) -> void:
	aim_direction = dir
	weapon_pivot.rotation = dir.angle()

func take_damage(amount: float, source: Node = null) -> void:
	if is_dead:
		return
	health_component.take_damage(amount, source)

func _on_damaged(amount: float) -> void:
	if data:
		data.fear = clampf(data.fear + amount * 0.5, 0.0, 100.0)
	body_visual.modulate = Color(1, 0.3, 0.3)
	var tween := create_tween()
	tween.tween_property(body_visual, "modulate", Color(1, 1, 1), 0.2)

func _on_died() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	ai.stop()
	if data:
		data.is_dead = true
		if data.current_settlement != 0:
			var settlement: Settlement = get_tree().get_first_node_in_group("settlement")
			if settlement and settlement.data.id == data.current_settlement:
				settlement.remove_member(data.id)
		WorldState.unregister_survivor(data.id)
	GameEvents.survivor_died.emit(self)
	queue_free()
