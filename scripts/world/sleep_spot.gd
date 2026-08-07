class_name SleepSpot
extends Node2D
## A claimable sleeping position inside a settlement. Not job-board managed
## (sleep is a personal need, not shared settlement work) -- just enough
## occupancy tracking that two survivors don't both walk to the same cot.

var _occupant_survivor_id: int = 0

func is_free() -> bool:
	return _occupant_survivor_id == 0

func occupant_id() -> int:
	return _occupant_survivor_id

func try_occupy(survivor_id: int) -> bool:
	if _occupant_survivor_id != 0 and _occupant_survivor_id != survivor_id:
		return false
	_occupant_survivor_id = survivor_id
	return true

func vacate(survivor_id: int) -> void:
	if _occupant_survivor_id == survivor_id:
		_occupant_survivor_id = 0
