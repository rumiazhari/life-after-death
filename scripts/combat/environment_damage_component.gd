class_name EnvironmentDamageComponent
extends Node
## Durability attached to a StaticBody2D. The component owns no visual or
## collision itself; destroy_target identifies the complete prop (or the wall
## body itself) that must disappear when durability reaches zero.

signal damaged(remaining: float, amount: float)
signal destroyed(object_id: StringName)

@export var object_id: StringName = &""
@export_enum("Small Arms", "Heavy", "Explosive") var minimum_damage_class: int = EnvironmentDamage.DamageClass.SMALL_ARMS
@export var max_durability: float = 30.0
@export var affected_size: Vector2 = Vector2(32, 32)

var destroy_target: Node = null
var _durability: float = 0.0
var _destroyed: bool = false

func _ready() -> void:
	_durability = max_durability
	if object_id != &"":
		if WorldState.get_prop_state_flag(object_id, &"destroyed", false):
			call_deferred("_destroy")
			return
		_durability = float(WorldState.get_prop_state_flag(object_id, &"durability", max_durability))

func apply_damage(amount: float, damage_class: int, _source: Node = null) -> bool:
	if _destroyed or amount <= 0.0 or damage_class < minimum_damage_class:
		return false
	_durability = maxf(_durability - amount, 0.0)
	if object_id != &"":
		WorldState.set_prop_state_flag(object_id, &"durability", _durability)
	damaged.emit(_durability, amount)
	if _durability <= 0.0:
		_destroy()
	return true

func durability() -> float:
	return _durability

func _destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	if object_id != &"":
		WorldState.set_prop_state_flag(object_id, &"destroyed", true)
	var body := get_parent() as Node2D
	var target: Node = destroy_target if destroy_target != null and is_instance_valid(destroy_target) else get_parent()
	var world_position := body.global_position if body else Vector2.ZERO
	_preserve_loot(target, world_position)
	var excluded_rid := RID()
	if get_parent() is CollisionObject2D:
		excluded_rid = (get_parent() as CollisionObject2D).get_rid()
	UrbanNavigationService.mark_area_free(Rect2(world_position - affected_size * 0.5, affected_size), excluded_rid)
	destroyed.emit(object_id)
	if target != null and is_instance_valid(target):
		target.call_deferred("queue_free")

func _preserve_loot(target: Node, world_position: Vector2) -> void:
	if target == null:
		return
	var loot_components: Array[LootContainerComponent] = []
	_collect_loot(target, loot_components)
	var drop_inventory := Inventory.new(0.0)
	for loot in loot_components:
		loot.get_inventory().move_all_to(drop_inventory)
	if drop_inventory.is_empty():
		return
	var drop := WorldDrop.new()
	drop.position = world_position
	drop.reason = &"environment_destroyed"
	drop.created_tick = SimulationClock.tick_count
	drop.inventory = drop_inventory
	WorldState.register_drop(drop)

func _collect_loot(node: Node, output: Array[LootContainerComponent]) -> void:
	if node is LootContainerComponent:
		output.append(node)
	for child in node.get_children():
		_collect_loot(child, output)
