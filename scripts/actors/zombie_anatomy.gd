class_name ZombieAnatomy
extends RefCounted
## Per-zone structural integrity for one zombie. The fundamental rule of the
## system: a zombie only truly dies when its HEAD is destroyed. Torso/limb
## damage cripples, severs and staggers -- but the creature keeps coming until
## the head goes. Zones: head, torso, arm_l, arm_r, leg_l, leg_r.

const ZONES := [&"head", &"torso", &"arm_l", &"arm_r", &"leg_l", &"leg_r"]
const SEVER_AT := 0.0

var integrity := {
	&"head": 40.0,
	&"torso": 100.0,
	&"arm_l": 22.0,
	&"arm_r": 22.0,
	&"leg_l": 28.0,
	&"leg_r": 28.0,
}
## Zones that have fully detached.
var severed: Array[StringName] = []

func head_alive() -> bool:
	return integrity[&"head"] > 0.0

func zone_alive(zone: StringName) -> bool:
	return integrity[zone] > 0.0

## Applies damage to one zone; returns what happened so the zombie can react.
func apply_zone_damage(zone: StringName, amount: float) -> Dictionary:
	var result := {"zone": zone, "severed": false, "head_destroyed": false, "amount": amount}
	if not integrity.has(zone):
		return result
	integrity[zone] = maxf(integrity[zone] - amount, 0.0)
	if integrity[zone] <= SEVER_AT and zone != &"head":
		if not severed.has(zone):
			severed.append(zone)
			result["severed"] = true
	if zone == &"head" and integrity[&"head"] <= 0.0:
		result["head_destroyed"] = true
		# Decapitation is fatal no matter how much torso remains.
		integrity[&"torso"] = minf(integrity[&"torso"], 0.001)
	return result

## Resolves a world-space hit to an anatomical zone for a top-down body.
## The head is the central bullseye (a generous ring -- precise aim must be
## rewarded); the torso ring surrounds it; hits landing beyond the torso are
## assigned to limbs by their dominant axis.
static func resolve_zone(hit_world: Vector2, actor_center: Vector2) -> StringName:
	var offset := hit_world - actor_center
	var dist := offset.length()
	if dist <= 9.0:
		return &"head"
	if dist <= 16.0:
		return &"torso"
	if absf(offset.x) >= absf(offset.y):
		return &"arm_r" if offset.x > 0.0 else &"arm_l"
	return &"leg_r" if offset.y > 0.0 else &"leg_l"

func movement_factor() -> float:
	var legs := 2 - ([&"leg_l", &"leg_r"].filter(func(z: StringName) -> bool: return severed.has(z))).size()
	match legs:
		2:
			return 1.0 if integrity[&"torso"] > 30.0 else 0.7
		1:
			return 0.45
	return 0.12 # crawling wreck: still coming, just barely

func attack_factor() -> float:
	var arms := 2 - ([&"arm_l", &"arm_r"].filter(func(z: StringName) -> bool: return severed.has(z))).size()
	match arms:
		2:
			return 1.0
		1:
			return 0.5
	return 0.0 # cannot grab or bite without arms