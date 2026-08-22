class_name Door
extends Node2D
## Reusable interactable door. Closed by default: blocks movement (World
## layer) and vision (Vision layer); interacting toggles both, swaps the
## sprite, and emits a noise. Collision changes are driven purely by
## `is_open`, never by the visual swap alone, so a fade/animation glitch
## can never desync physical/vision blocking from what's drawn.
##
## `door_id` is a stable authored identifier (set per-instance in the
## owning building scene) -- persistent open/closed state is looked up and
## stored in WorldState.door_states[door_id], never inferred from this
## node's own transient state, so a scene reload restores exactly how the
## player left it (see docs/interaction_system.md).

## Fired whenever `_apply_state()` runs, open or closed, whether triggered
## by a real interaction, a programmatic toggle(), or the initial
## WorldState-restored load. BuildingVisibilityController (Phase 3B.1)
## listens to this so opening/closing a door recomputes room-portal
## visibility immediately, even while the player is stationary.
signal state_changed(is_open: bool)

const CLOSED_TEXTURE := preload("res://assets/pixel/props/door_closed.png")
const OPEN_TEXTURE := preload("res://assets/pixel/props/door_open.png")

const TILE := 32.0

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ZOMBIE := 4
const LAYER_SURVIVOR := 16
const LAYER_VISION := 32
const LAYER_INTERACTABLE := 64

@export var door_id: StringName = &""
@export var is_open: bool = false
@export var noise_loudness: float = 8.0
## The aperture is wider than the closed slab.  It is supplied by procedural
## interiors so navigation knows every cell made passable when the door opens.
## WORLD-ALIGNED: x spans the transverse axis of a door in a horizontal wall
## run, y the transverse axis of one in a vertical run (node rotation never
## re-orients the physical bay -- see _setup_aperture).
@export var aperture_size: Vector2 = Vector2(32, 32)

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision: CollisionShape2D = $CollisionBody/CollisionShape2D
@onready var _collision_body: StaticBody2D = $CollisionBody
## Exact door-footprint Area2D -- used ONLY to detect an actor physically
## standing on the door (refuses to close on top of them). Deliberately
## NOT on the Interactable layer and NOT what PlayerInteractor sees.
@onready var _block_check_area: Area2D = $InteractArea
## Larger reach Area2D (see docs/interaction_system.md "Reach vs footprint")
## -- what PlayerInteractor actually detects, sized so a 16px-radius actor
## can stand outside the door's own solid collision and still be within
## interaction range.
@onready var _interact_reach_area: Area2D = $InteractReachArea
@onready var _interactable: InteractableComponent = $InteractReachArea/InteractableComponent

## Instance IDs of every body currently physically overlapping the door's
## own footprint -- closing is refused while this is non-empty, so nothing
## gets stuck inside solid collision. A Dictionary-as-set (not a single
## bool) so two actors standing in the same doorway are tracked
## independently: one exiting must not clear the other's occupancy.
var _blocking_bodies: Dictionary = {} # instance_id (int) -> true

## One 32px leaf sprite per carved wall cell, spanning the full bay, plus
## the offset between this node's semantic center and the bay center.
var _leaves: Array[Sprite2D] = []
var _bay_offset := Vector2.ZERO

func _ready() -> void:
	add_to_group("doors")
	_setup_aperture()
	_collision_body.collision_layer = LAYER_WORLD | LAYER_VISION
	_collision_body.collision_mask = 0
	_block_check_area.collision_layer = 0
	_block_check_area.collision_mask = LAYER_PLAYER | LAYER_ZOMBIE | LAYER_SURVIVOR
	_interact_reach_area.collision_layer = LAYER_INTERACTABLE
	_interact_reach_area.collision_mask = 0
	_interactable.interact_label = "Open Door"
	_interactable.interacted.connect(_on_interacted)
	_block_check_area.body_entered.connect(_on_body_entered)
	_block_check_area.body_exited.connect(_on_body_exited)
	if door_id != &"":
		is_open = WorldState.get_door_open(door_id)
	_build_structure_damage()
	_apply_state(false)

## Fits the door's visuals, collision, and damage footprint exactly into
## the wall bay carved for it (see ProceduralBuildingGenerator.door_bay_rect).
## `aperture_size` is interpreted WORLD-ALIGNED: x is the transverse span of
## a door in a horizontal wall run, y the transverse span of one in a
## vertical run. The node's authored rotation is treated as visual-only --
## it is zeroed here and transferred onto the leaf sprites -- because
## rotating the physical children used to turn every vertical-door slab
## PERPENDICULAR to its carved opening, leaving closed rotated doors
## transparent to movement and vision. The bay itself always anchors at
## local (-16,-16) and extends along +X/+Y by the aperture, so the closed
## slab (aperture-2px) seals exactly the cells the builders carve for
## `door_bay_rect(position, aperture)`. A 64px aperture becomes a two-leaf
## double door spanning the full carved span edge-to-edge, so no open wall
## shows beside a closed door. Authored fixtures use the same convention.
func _setup_aperture() -> void:
	var visual_rotation := rotation
	rotation = 0.0 # children are laid out world-aligned; art rotates per-leaf
	var tile := Vector2(TILE, TILE)
	var bay_size := Vector2(maxf(aperture_size.x, 30.0), maxf(aperture_size.y, 30.0))
	_bay_offset = (aperture_size - tile) * 0.5
	_sprite.visible = false # replaced by the bay-fitted leaves below
	var leaves_root := get_node_or_null("Leaves") as Node2D
	if leaves_root == null:
		leaves_root = Node2D.new()
		leaves_root.name = "Leaves"
		add_child(leaves_root)
	for row in range(maxi(1, roundi(bay_size.y / TILE))):
		for column in range(maxi(1, roundi(bay_size.x / TILE))):
			var leaf := Sprite2D.new()
			leaf.name = "Leaf_%d_%d" % [row, column]
			leaf.texture = CLOSED_TEXTURE
			leaf.rotation = visual_rotation
			# Bay tiles anchor at (-16,-16): leaf k centers on k*TILE so the
			# leaf run spans [-16, aperture-16], matching the carved cells.
			leaf.position = Vector2(float(column) * TILE, float(row) * TILE)
			leaves_root.add_child(leaf)
			_leaves.append(leaf)
	# The closed slab seals the entire carved bay: aperture-2px, leaving a
	# 1px seam against each intact wall cell.
	var body_shape := RectangleShape2D.new()
	body_shape.size = bay_size - Vector2(2.0, 2.0)
	_collision.shape = body_shape
	_collision_body.position = _bay_offset
	var block_shape := RectangleShape2D.new()
	block_shape.size = bay_size - Vector2(2.0, 2.0)
	(_block_check_area.get_node("CollisionShape2D") as CollisionShape2D).shape = block_shape
	_block_check_area.position = _bay_offset
	var reach := _interact_reach_area.get_node("CollisionShape2D") as CollisionShape2D
	var reach_shape := RectangleShape2D.new()
	reach_shape.size = Vector2(
		maxf(reach.shape.size.x, bay_size.x + 56.0),
		maxf(reach.shape.size.y, bay_size.y + 56.0)
	)
	reach.shape = reach_shape
	_interact_reach_area.position = _bay_offset

func _build_structure_damage() -> void:
	if _collision_body.get_node_or_null("EnvironmentDamageComponent"):
		return
	var damage := EnvironmentDamageComponent.new()
	damage.name = "EnvironmentDamageComponent"
	damage.object_id = StringName("%s/structure" % String(door_id))
	damage.minimum_damage_class = EnvironmentDamage.DamageClass.EXPLOSIVE
	damage.max_durability = 80.0
	damage.affected_size = Vector2(
		maxf(30.0, aperture_size.x - 4.0),
		maxf(30.0, aperture_size.y - 4.0)
	)
	damage.destroy_target = self
	damage.destroyed.connect(_on_structure_destroyed)
	_collision_body.add_child(damage)

func _on_structure_destroyed(_object_id: StringName) -> void:
	is_open = true
	if door_id != &"":
		WorldState.set_door_open(door_id, true)
		UrbanNavigationService.mark_door_open(door_id)

func _on_interacted(actor: Node) -> void:
	toggle(actor)

## Public so DistrictBuilder/tests can also flip a door programmatically
## (e.g. permanently-open service entrances) without going through the
## interaction signal path -- `actor` defaults to null so those callers
## don't need to pass one; a real interaction passes the interacting actor
## so its noise routes through that actor's own DetectableComponent.
func toggle(actor: Node = null) -> void:
	if is_open and _is_blocked_by_body():
		return # refuse to close on top of an actor
	is_open = not is_open
	_apply_state(true, actor)

func _apply_state(emit_noise: bool, actor: Node = null) -> void:
	for leaf in _leaves:
		leaf.texture = OPEN_TEXTURE if is_open else CLOSED_TEXTURE
	# This method is invoked from interaction/input, outside the physics query
	# callback that owns collision processing.  Apply immediately so portal
	# visibility and passage agree in the same frame.
	_collision.disabled = is_open
	_interactable.interact_label = "Close Door" if is_open else "Open Door"
	if door_id != &"":
		WorldState.set_door_open(door_id, is_open)
		if is_open:
			UrbanNavigationService.mark_door_open(door_id)
		else:
			UrbanNavigationService.mark_door_closed(door_id)
	if emit_noise:
		NoiseManager.emit_actor_noise(actor, global_position, noise_loudness, &"door")
	state_changed.emit(is_open)

func _on_body_entered(body: Node) -> void:
	_blocking_bodies[body.get_instance_id()] = true

func _on_body_exited(body: Node) -> void:
	_blocking_bodies.erase(body.get_instance_id())

## Also prunes any tracked body that was freed without ever firing
## body_exited (e.g. queue_free'd mid-overlap), so a stale instance ID can
## never permanently wedge the door open.
func _is_blocked_by_body() -> bool:
	for id in _blocking_bodies.keys().duplicate():
		var body: Object = instance_from_id(id)
		if body == null or not is_instance_valid(body):
			_blocking_bodies.erase(id)
			continue
		return true
	return false
