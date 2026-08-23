class_name SurvivorBaseService
extends RefCounted
## Claims ordinary generated buildings as survivor bases. Building geometry
## and building occupancy are deliberately separate concerns: a claimed
## apartment/store/workshop stays the exact same generated building it always
## was -- only SettlementData occupancy state (and non-destructive dressing)
## marks it as lived-in. No dedicated base geometry exists or is needed.
##
## Selection is deterministic per world seed: buildings are scored on usable
## interior, entrance reachability, size, archetype suitability and
## defensibility (fewer exterior doors to watch), with stable-id tiebreaks.

const ARCHETYPE_BASE_WEIGHT := {
	&"apartment": 1.25,
	&"clinic": 0.9,
	&"store": 1.0,
	&"restaurant": 0.85,
	&"workshop": 0.7,
}

## Scores every generated building in a city model and returns the best
## candidates, best first. Pure function of (city_model, world_seed).
static func rank_buildings(city_model: Dictionary, world_seed: int) -> Array[Dictionary]:
	var scored: Array[Dictionary] = []
	for building_variant in city_model.get("buildings", []):
		var building: Dictionary = building_variant
		scored.append({"building": building, "score": _score_building(building, world_seed)})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a["score"], b["score"]):
			return a["score"] > b["score"]
		return String(a["building"]["id"]) < String(b["building"]["id"]))
	var result: Array[Dictionary] = []
	for entry in scored:
		result.append(entry["building"])
	return result

static func _score_building(building: Dictionary, world_seed: int) -> float:
	var interior: Dictionary = building.get("interior", {})
	var rooms: Array = interior.get("rooms", [])
	# A base must be actually usable: real rooms and a reachable street
	# entrance are hard requirements; everything else grades quality.
	if rooms.is_empty():
		return -1.0
	var footprint: Rect2 = building.get("footprint", Rect2())
	if footprint.get_area() <= 0.0:
		return -1.0
	var score := 0.0
	score += mini(rooms.size(), 6) * 2.0
	score += footprint.get_area() / 8000.0
	score += float(ARCHETYPE_BASE_WEIGHT.get(building.get("archetype", &"apartment"), 0.5)) * 12.0
	# Defensibility: fewer exterior doors means fewer approaches to watch.
	var exterior_doors := 0
	for door in interior.get("doors", []):
		if bool(door.get("exterior", false)):
			exterior_doors += 1
	score -= exterior_doors * 1.5
	# Deterministic per-building jitter so equal-quality candidates still
	# resolve stably without depending on dictionary iteration order.
	score += float(posmod(int(String(building["id"]).hash() ^ world_seed), 100)) * 0.01
	return score

## Deterministically picks one eligible building for a survivor group:
## always from the top-scoring candidates, weighted toward the best so
## quality dominates while different seeds legitimately settle into
## different kinds of ordinary buildings.
static func select_building(city_model: Dictionary, world_seed: int) -> Dictionary:
	var ranked := rank_buildings(city_model, world_seed)
	if ranked.is_empty():
		return {}
	var candidates: Array[Dictionary] = []
	for i in range(mini(ranked.size(), 5)):
		candidates.append(ranked[i])
	var weights: Array[int] = [45, 25, 15, 10, 5]
	var roll := posmod(ChunkEdgeContract.chunk_seed(world_seed ^ 0xB0B5, Vector2i(77, 13)), 100)
	var cumulative := 0
	for i in range(candidates.size()):
		cumulative += weights[i]
		if roll < cumulative or i == candidates.size() - 1:
			return candidates[i]
	return candidates[0]

## Deterministically claims an eligible generated building for one survivor
## group. Buildings already claimed by another group are skipped and the
## ranked list continues, so multiple groups settle into different ordinary
## buildings instead of contending for one. Returns null only when nothing
## eligible remains at all.
func claim_best_base(city_model: Dictionary, world_seed: int, settlement_name: String = "Survivor Base") -> SettlementData:
	for building_variant in rank_buildings(city_model, world_seed):
		var building: Dictionary = building_variant
		if building_already_claimed(building["id"]):
			continue
		return claim_building(building, settlement_name)
	return null

func claim_building(building: Dictionary, settlement_name: String = "Survivor Base") -> SettlementData:
	var data := SettlementData.new()
	data.settlement_name = settlement_name
	data.building_id = building["id"]
	data.base_type = building.get("archetype", &"apartment")
	data.security_level = 1
	data.barricade_level = 0
	data.power_state = false
	data.water_state = false
	WorldState.register_settlement(data)
	return data

func building_already_claimed(building_id: StringName) -> bool:
	for data_variant in WorldState.settlements.values():
		var data: SettlementData = data_variant
		if data.building_id == building_id:
			return true
	return false

## A group abandoning its base clears ONLY the occupancy state. The generated
## building itself was never special and remains exactly as generated.
func abandon_base(settlement_id: int) -> void:
	var data := WorldState.get_settlement(settlement_id)
	if data == null:
		return
	data.building_id = &""
	data.base_type = &""
	data.security_level = 0
	data.barricade_level = 0
	data.stored_resources.clear()
	data.power_state = false
	data.water_state = false
	WorldState.unregister_settlement(settlement_id)
