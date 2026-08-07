class_name SurvivorData
extends Resource
## Persistent, serializable model for one survivor. This is the source of
## truth: `Survivor` (the CharacterBody2D actor, scripts/actors/survivor.gd)
## reads and writes this resource but the resource itself does not depend on
## the actor existing -- it is registered with WorldState and survives scene
## reloads / the actor being far off-screen and simulated cheaply.

## Stable ID assigned by WorldState.register_survivor(). 0 = unregistered.
@export var id: int = 0
@export var survivor_name: String = "Survivor"
@export var age: int = 30

## --- Vitals (0..100 unless noted) ------------------------------------
@export var health: float = 100.0
@export var max_health: float = 100.0
@export var hunger: float = 0.0 ## 0 = fed, 100 = starving
@export var thirst: float = 0.0 ## 0 = hydrated, 100 = dehydrated
@export var fatigue: float = 0.0 ## 0 = rested, 100 = exhausted
@export var morale: float = 70.0 ## 0 = despair, 100 = thriving
@export var fear: float = 0.0 ## 0 = calm, 100 = panicked
@export var infection_exposure: float = 0.0 ## 0 = clean, 100 = turning

## --- Skills (0..100) ---------------------------------------------------
@export var combat_skill: float = 20.0
@export var medical_skill: float = 20.0
@export var scavenging_skill: float = 20.0
@export var construction_skill: float = 20.0

@export var movement_speed: float = 200.0

## Personality modifiers, roughly -1.0..1.0. Keys used by the utility AI:
## "brave" (risk tolerance), "cautious" (safety-seeking bias),
## "diligent" (work/haul bias), "social" (help-others bias).
@export var personality: Dictionary = {
	"brave": 0.0,
	"cautious": 0.0,
	"diligent": 0.0,
	"social": 0.0,
}

@export var current_settlement: int = 0 ## Settlement ID, 0 = none
## Survivor ID -> relationship score (-100..100). Not used for scoring yet
## in this slice; reserved for the future family/faction systems.
@export var relationships: Dictionary = {}

@export var current_goal: String = ""
@export var current_action: String = ""

@export var is_dead: bool = false

func to_dict() -> Dictionary:
	return {
		"id": id,
		"survivor_name": survivor_name,
		"age": age,
		"health": health,
		"max_health": max_health,
		"hunger": hunger,
		"thirst": thirst,
		"fatigue": fatigue,
		"morale": morale,
		"fear": fear,
		"infection_exposure": infection_exposure,
		"combat_skill": combat_skill,
		"medical_skill": medical_skill,
		"scavenging_skill": scavenging_skill,
		"construction_skill": construction_skill,
		"movement_speed": movement_speed,
		"personality": personality.duplicate(),
		"current_settlement": current_settlement,
		"relationships": relationships.duplicate(),
		"current_goal": current_goal,
		"current_action": current_action,
		"is_dead": is_dead,
	}
