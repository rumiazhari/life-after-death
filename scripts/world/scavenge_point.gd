class_name ScavengePoint
extends Node2D
## A nearby scavenging location. Depletes as survivors scavenge it and frees
## itself when empty -- SettlementJobBoard jobs targeting it then fail
## target validation and get cancelled automatically instead of needing a
## separate "is this point still good" check.

@export var item_id: StringName = &"materials"
@export var yield_per_scavenge: int = 3
@export var remaining_stock: int = 9
@export var scavenge_duration: float = 2.5 ## seconds of standing here to work the job
## Rough danger rating (0..100) folded into utility risk scoring -- higher
## for points further from the settlement or historically zombie-heavy.
@export var danger: float = 20.0

func _ready() -> void:
	add_to_group("scavenge_point")

func is_depleted() -> bool:
	return remaining_stock <= 0

## Removes one yield's worth of stock and returns how much was actually
## produced (may be less than yield_per_scavenge on the last pass). Frees
## the node once emptied.
func harvest() -> int:
	var amount: int = mini(yield_per_scavenge, remaining_stock)
	remaining_stock -= amount
	if remaining_stock <= 0:
		call_deferred("queue_free")
	return amount
