class_name StorageContainer
extends Node2D
## A settlement storage point (general / food / water / medical). Owns an
## Inventory registered with WorldState under a stable container id --
## Survivor and Player both read/write through that same Inventory instance,
## so NPC and player storage access share one set of rules.
##
## Reparenting vs. destruction are deliberately handled by different
## notifications, since _exit_tree() alone can't tell them apart (it fires
## for both):
## - _exit_tree()/_enter_tree() fire on ANY tree removal/insertion,
##   including an ordinary reparent -- these only cache the last valid
##   world position and (re-)announce ownership to the new parent
##   settlement, never touching WorldState's registration or contents.
## - NOTIFICATION_PREDELETE fires only when the node is truly being freed
##   (after it has already left the tree, which is why the position is
##   cached earlier in _exit_tree() rather than read here) -- that's where
##   contents get preserved into a WorldDrop and the container actually
##   unregisters from WorldState.

## "general" / "food" / "water" / "medical" -- matched by
## SettlementJobBoard._refresh_haul_jobs() and by AI actions looking for a
## place to deposit/withdraw a given item category.
@export var storage_role: String = "general"
@export var capacity_weight: float = 500.0
## item_id (string) -> starting count, authored per-instance in the scene.
@export var starting_items: Dictionary = {}
@export var physical_interaction_enabled: bool = false
## Explicit persistent-structure id override; when empty, the legacy
## "safehouse/storage_<role>" id is used.
@export var structure_id: StringName = &""

var container_id: int = 0
var _inventory: Inventory
var _last_global_position: Vector2 = Vector2.ZERO
var _interactable: InteractableComponent

func _ready() -> void:
	# A persisted destroyed safehouse container must not register or seed a new
	# inventory and then emit that starting stock as another destruction drop.
	# EnvironmentDamageComponent cannot make this decision early enough because
	# StorageContainer owns the inventory lifecycle, so gate reconstruction here.
	if physical_interaction_enabled and WorldState.get_prop_state_flag(_structure_object_id(), &"destroyed", false):
		call_deferred("queue_free")
		return
	add_to_group("storage_container")
	_inventory = Inventory.new(capacity_weight)
	for item_id in starting_items:
		_inventory.add_item(StringName(item_id), int(starting_items[item_id]))
	container_id = WorldState.register_container(_inventory)
	_last_global_position = global_position
	if physical_interaction_enabled:
		_build_player_interaction_and_durability()

func _build_player_interaction_and_durability() -> void:
	var body := StaticBody2D.new()
	body.name = "CollisionBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var body_shape := RectangleShape2D.new()
	body_shape.size = Vector2(24, 24)
	var body_collider := CollisionShape2D.new()
	body_collider.shape = body_shape
	body.add_child(body_collider)
	var damage := EnvironmentDamageComponent.new()
	damage.name = "EnvironmentDamageComponent"
	damage.object_id = _structure_object_id()
	damage.minimum_damage_class = EnvironmentDamage.DamageClass.HEAVY
	damage.max_durability = 60.0
	damage.affected_size = body_shape.size
	damage.destroy_target = self
	body.add_child(damage)
	add_child(body)

	var area := Area2D.new()
	area.name = "InteractArea"
	area.collision_layer = 64
	area.collision_mask = 0
	var reach_shape := RectangleShape2D.new()
	reach_shape.size = Vector2(80, 80)
	var reach_collider := CollisionShape2D.new()
	reach_collider.shape = reach_shape
	area.add_child(reach_collider)
	_interactable = InteractableComponent.new()
	_interactable.name = "InteractableComponent"
	_interactable.interact_label = "Use %s Storage" % storage_role.capitalize()
	_interactable.interacted.connect(_on_player_interacted)
	area.add_child(_interactable)
	add_child(area)

func _structure_object_id() -> StringName:
	if structure_id != &"":
		return structure_id
	return StringName("safehouse/storage_%s" % storage_role)

## Without an inventory UI, one action remains deterministic: carrying any
## items deposits as much as capacity permits; an empty-handed player takes
## as much as their carried inventory can accept.
func _on_player_interacted(actor: Node) -> void:
	if not ("carried_inventory" in actor):
		return
	var carried: Inventory = actor.carried_inventory
	if carried.is_empty():
		_inventory.move_all_to(carried)
	else:
		carried.move_all_to(_inventory)

## Fires on every tree entry after the very first (container_id == 0 means
## this is that first entry -- _ready(), about to run, handles it): i.e.
## every reparent. Re-registers with WorldState only if something else
## already unregistered this id (defensive/deterministic recovery, using
## the SAME Inventory instance so contents are never reset), then
## announces this container to its new owning Settlement so ownership
## doesn't depend solely on that settlement's one-time initial scan.
func _enter_tree() -> void:
	if container_id == 0:
		return
	if WorldState.get_container(container_id) != _inventory:
		container_id = WorldState.register_container(_inventory)
	var settlement := _find_owning_settlement()
	if settlement:
		settlement.register_storage_container(self)

## Fires on ANY tree exit, reparent included -- deliberately does nothing
## to WorldState's registration (that would treat a reparent as
## destruction). Only caches the last valid global position, since by the
## time NOTIFICATION_PREDELETE can distinguish true destruction from a
## reparent, this node has already been detached and its transform is no
## longer reliable.
func _exit_tree() -> void:
	_last_global_position = global_position

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_handle_permanent_destruction()

## True deletion only (never a reparent -- see class doc comment). Moves
## every item this container held -- reserved and unreserved alike, since
## a WorldDrop has no reservation concept and the destination is simply
## "whatever physically existed here" -- into one fresh WorldDrop at this
## container's last known position, then unregisters from WorldState so
## periodic job validation (Job.is_target_valid()) cancels any
## reservation-backed job pointed at it. Skipped if WorldState.reset()
## already cleared this container's registration (an ordinary restart
## tearing the whole registry down at once is not "this one container got
## destroyed") or if it never held anything (no empty drops).
func _handle_permanent_destruction() -> void:
	if container_id == 0 or _inventory == null:
		return
	if WorldState.get_container(container_id) != _inventory:
		return
	if not _inventory.is_empty():
		var drop := WorldDrop.new()
		drop.position = _last_global_position
		drop.source_container_id = container_id
		drop.storage_role = storage_role
		drop.created_tick = SimulationClock.tick_count
		drop.reason = &"storage_destroyed"
		drop.inventory = Inventory.new(0.0)
		_inventory.move_all_to(drop.inventory)
		WorldState.register_drop(drop)
	WorldState.unregister_container(container_id)

func _find_owning_settlement() -> Settlement:
	var node: Node = get_parent()
	while node:
		if node is Settlement:
			return node
		node = node.get_parent()
	return null

func get_inventory() -> Inventory:
	return _inventory
