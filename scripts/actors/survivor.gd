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
@onready var body_visual: ActorVisual = $BodyVisual
@onready var ai: SurvivorAI = $SurvivorAI
@onready var screen_notifier: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D
@onready var detectable: DetectableComponent = $DetectableComponent

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
	body_visual.variant = ActorSpriteLibrary.variant_for(&"survivor", data.id)
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
	body_visual.update_from_velocity(velocity)
	detectable.report_movement_speed(velocity.length())

## Path-around-walls fallback (Phase 3B.1): only consulted when direct
## steering toward the current goal is actually blocked, re-evaluated on
## `_nav_recheck_timer` rather than every physics frame -- the same
## design Zombie._seek_point() uses (see docs/perception_system.md
## "Navigation"), applied here at the single shared move_toward_point()
## every UtilityAction already calls, so no individual action needed its
## own pathfinding logic. Shares UrbanNavigationService's global per-frame
## request budget with every zombie -- never an unrestricted
## NavigationAgent2D of its own.
const NAV_RECHECK_INTERVAL := 1.0
var _nav_path: PackedVector2Array = PackedVector2Array()
var _nav_path_index: int = 0
var _nav_recheck_timer: float = 0.0
var _nav_target: Vector2 = Vector2.ZERO

## Seeks `point`, returns true once within arrive_threshold. Shared by every
## movement-driven action instead of each one re-implementing steering.
func move_toward_point(point: Vector2, delta: float) -> bool:
	var to_point: Vector2 = point - global_position
	var distance: float = to_point.length()
	var speed: float = data.movement_speed if data else 190.0
	if distance <= arrive_threshold:
		_nav_path.clear()
		velocity = velocity.move_toward(Vector2.ZERO, steer_acceleration * delta)
		move_and_slide()
		return true
	var dir: Vector2 = _seek_direction(point, to_point, distance)
	_face(dir)
	velocity = velocity.move_toward(dir * speed, steer_acceleration * delta)
	move_and_slide()
	return false

func _seek_direction(point: Vector2, to_point: Vector2, distance: float) -> Vector2:
	if not point.is_equal_approx(_nav_target):
		_nav_target = point
		_nav_path.clear()
		_nav_recheck_timer = 0.0
	_nav_recheck_timer -= get_physics_process_delta_time()
	if _nav_recheck_timer <= 0.0:
		_nav_recheck_timer = NAV_RECHECK_INTERVAL
		if UrbanNavigationService.is_direct_path_clear(global_position, point):
			_nav_path.clear()
		elif _nav_path.is_empty():
			_nav_path = UrbanNavigationService.find_path(global_position, point)
			_nav_path_index = 0
	if _nav_path.is_empty():
		return to_point / distance
	while _nav_path_index < _nav_path.size() - 1 and global_position.distance_to(_nav_path[_nav_path_index]) <= arrive_threshold:
		_nav_path_index += 1
	var waypoint: Vector2 = _nav_path[_nav_path_index]
	if global_position.distance_to(waypoint) <= arrive_threshold and _nav_path_index >= _nav_path.size() - 1:
		_nav_path.clear()
		return to_point / distance
	return (waypoint - global_position).normalized()

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
	_drop_carried_inventory()
	if data:
		data.is_dead = true
		if data.current_settlement != 0:
			var settlement: Settlement = get_tree().get_first_node_in_group("settlement")
			if settlement and settlement.data.id == data.current_settlement:
				settlement.remove_member(data.id)
		# SurvivorData deliberately stays registered in WorldState (now with
		# is_dead = true) as a persistent record instead of being erased --
		# see WorldState.get_living_survivors()/is_survivor_alive() and
		# to_snapshot(), and note the survivor id is never reused within a
		# run as a result.
	GameEvents.survivor_died.emit(self)
	queue_free()

## Preserves whatever the survivor was carrying -- including any in-transit
## HAUL cargo (ai.stop(), just above, may already have failed that job via
## SettlementJobBoard.release_survivor_permanently(), but failing a job only
## touches its own bookkeeping, never the physical items) -- as a persistent
## WorldDrop instead of letting it vanish along with this actor. No-op if
## the survivor wasn't carrying anything.
func _drop_carried_inventory() -> void:
	if carried_inventory == null or carried_inventory.is_empty():
		return
	var drop := WorldDrop.new()
	drop.position = global_position
	drop.source_survivor_id = data.id if data else 0
	drop.created_tick = SimulationClock.tick_count
	drop.reason = &"death"
	drop.inventory = Inventory.new(0.0)
	carried_inventory.move_all_to(drop.inventory)
	WorldState.register_drop(drop)
