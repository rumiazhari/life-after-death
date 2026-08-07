class_name UtilityMath
extends RefCounted
## Shared scoring helpers so every UtilityAction computes urgency/risk/
## distance the same way instead of re-deriving these curves per action.

## 0 below `threshold`, ramps 0..1 from `threshold`..100. Used to turn a
## 0..100 need value (hunger, thirst, fatigue) into an urgency score that
## only matters once it's actually a problem.
static func urgency(value: float, threshold: float = 40.0) -> float:
	if value <= threshold:
		return 0.0
	return clampf((value - threshold) / (100.0 - threshold), 0.0, 1.0)

## 0 (right here) .. 1 (at or beyond max_range). Used to discount an
## action's score by how far the survivor has to travel for it.
static func distance_cost(distance: float, max_range: float) -> float:
	if max_range <= 0.0:
		return 0.0
	return clampf(distance / max_range, 0.0, 1.0)

## Settlement danger scaled down by the survivor's bravery personality trait.
static func risk_from_danger(danger_level: float, brave: float) -> float:
	var bravery_discount: float = clampf(1.0 - brave * 0.5, 0.2, 1.5)
	return clampf((danger_level / 100.0) * bravery_discount, 0.0, 1.0)

## How willing this survivor is to fight right now: combat skill tempered by
## fear and the brave personality trait. 0..1.
static func combat_confidence(data: SurvivorData) -> float:
	var skill_component: float = data.combat_skill / 100.0
	var fear_penalty: float = data.fear / 100.0
	var brave_bonus: float = data.personality.get("brave", 0.0) * 0.25
	return clampf(skill_component - fear_penalty * 0.6 + brave_bonus, 0.0, 1.0)
