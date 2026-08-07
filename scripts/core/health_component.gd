class_name HealthComponent
extends Node
## Reusable health/damage component.
##
## Attach as a child of any entity that can take damage (Player, Zombie).
## The owning entity reacts to `died` / `health_changed` instead of
## re-implementing health bookkeeping, so damage rules live in one place.

signal health_changed(current: float, max_health: float)
signal damaged(amount: float)
signal died()

@export var max_health: float = 100.0
@export var invulnerability_duration: float = 0.0

var current_health: float
var is_dead: bool = false

var _invulnerable_until_msec: int = 0

func _ready() -> void:
	current_health = max_health

func take_damage(amount: float, _source: Node = null) -> void:
	if is_dead or amount <= 0.0:
		return
	if is_invulnerable():
		return
	current_health = maxf(current_health - amount, 0.0)
	damaged.emit(amount)
	health_changed.emit(current_health, max_health)
	if invulnerability_duration > 0.0:
		_invulnerable_until_msec = Time.get_ticks_msec() + int(invulnerability_duration * 1000.0)
	if current_health <= 0.0 and not is_dead:
		is_dead = true
		died.emit()

func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current_health = minf(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)

func is_invulnerable() -> bool:
	return invulnerability_duration > 0.0 and Time.get_ticks_msec() < _invulnerable_until_msec

func reset_health() -> void:
	current_health = max_health
	is_dead = false
	_invulnerable_until_msec = 0
	health_changed.emit(current_health, max_health)
