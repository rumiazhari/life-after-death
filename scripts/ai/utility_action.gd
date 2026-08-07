class_name UtilityAction
extends RefCounted
## Base class for one candidate behavior in the utility-AI action set. Each
## concrete action (scripts/ai/actions/*.gd) is a small, independently
## reusable scorer + executor -- SurvivorAI never branches on action type by
## name, it just asks every action for a score and runs whichever wins.
##
## Adding a new survivor behavior is adding a new UtilityAction subclass and
## listing it in SurvivorAI.ACTION_CLASSES; nothing else changes.

var action_name: StringName = &"idle"
## Cost subtracted from every *other* action's score while this one is
## active, so a marginally-higher-scoring alternative doesn't cause
## flickering between near-tied actions every reconsideration.
var interrupt_cost: float = 0.05
## True for actions that may pre-empt whatever is currently running the
## moment their score crosses a threshold, rather than only being picked at
## the next regular reconsideration (see SurvivorAI._check_emergency).
var is_emergency: bool = false

## Returns this action's current desirability, roughly 0..1+. `ai` is the
## owning SurvivorAI, which exposes survivor/data/settlement/perception.
func score(_ai: SurvivorAI) -> float:
	return 0.0

## Cheap pre-check before scoring/selecting (e.g. "is there any food to
## fetch at all") so obviously-unavailable actions don't need a full score.
func can_start(_ai: SurvivorAI) -> bool:
	return true

## Called once when this action becomes active.
func enter(_ai: SurvivorAI) -> void:
	pass

## Called every AI reconsideration tick while active. Return true once the
## action has finished (successfully or not) so the AI reconsiders
## immediately instead of waiting out the rest of the normal interval.
func tick(_ai: SurvivorAI, _delta: float) -> bool:
	return true

## Called when this action stops being active, whether it finished or was
## interrupted -- release any job/inventory reservation and target here.
func exit(_ai: SurvivorAI) -> void:
	pass
