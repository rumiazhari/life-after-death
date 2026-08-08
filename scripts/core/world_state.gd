extends Node
## Persistent registry for settlements, survivors, inventories, jobs, and
## world flags (autoload "WorldState"). This is the authoritative source of
## simulation data -- runtime nodes (Survivor, Settlement, StorageContainer)
## hold a reference to their id and look their data up here rather than
## being the source of truth themselves, so a survivor far off-screen (or
## not spawned as a node at all) still exists as data.
##
## Builds serializable dictionaries via to_snapshot() in preparation for a
## future save/load system, but does not read/write them to disk yet.

## Presentation hook only (e.g. WorldDropVisualManager) -- fires after the
## drop is already registered in `drops`, so a listener can rely on
## get_drop(id) returning it immediately.
signal drop_registered(drop: WorldDrop)

var survivors: Dictionary = {} ## int id -> SurvivorData
var settlements: Dictionary = {} ## int id -> SettlementData
var containers: Dictionary = {} ## int id -> Inventory
var jobs: Dictionary = {} ## int id -> Job
var drops: Dictionary = {} ## int id -> WorldDrop
var world_flags: Dictionary = {}

## Phase 3B persistent authored-object state -- keyed by STABLE authored
## StringName ids (e.g. "restaurant01/kitchen/door_service"), never a scene
## node reference and never an auto-incrementing int, so re-entering a
## building or reloading the scene resolves back to the exact same record
## instead of registering a fresh (and therefore duplicate-loot-capable)
## one. See docs/interaction_system.md "Persistent world-prop state".
var door_states: Dictionary = {} ## StringName door_id -> bool is_open
var prop_states: Dictionary = {} ## StringName prop_id -> Dictionary (searched/salvaged/etc. flags)
var prop_containers: Dictionary = {} ## StringName prop_id -> Inventory

var _next_survivor_id: int = 1
var _next_settlement_id: int = 1
var _next_container_id: int = 1
var _next_job_id: int = 1
var _next_drop_id: int = 1

func register_survivor(data: SurvivorData) -> int:
	if data.id == 0:
		data.id = _next_survivor_id
		_next_survivor_id += 1
	survivors[data.id] = data
	return data.id

## Deliberate purge -- NOT called on natural death. A dead survivor's
## SurvivorData stays registered (with is_dead = true) as a persistent
## historical record; see get_living_survivors()/is_survivor_alive().
func unregister_survivor(id: int) -> void:
	survivors.erase(id)

func get_survivor(id: int) -> SurvivorData:
	return survivors.get(id)

func is_survivor_alive(id: int) -> bool:
	var data: SurvivorData = survivors.get(id)
	return data != null and not data.is_dead

func get_living_survivors() -> Array[SurvivorData]:
	var result: Array[SurvivorData] = []
	for id in survivors:
		var data: SurvivorData = survivors[id]
		if not data.is_dead:
			result.append(data)
	return result

func register_settlement(data: SettlementData) -> int:
	if data.id == 0:
		data.id = _next_settlement_id
		_next_settlement_id += 1
	settlements[data.id] = data
	return data.id

func get_settlement(id: int) -> SettlementData:
	return settlements.get(id)

func register_container(inventory: Inventory) -> int:
	var id: int = _next_container_id
	_next_container_id += 1
	containers[id] = inventory
	return id

func unregister_container(id: int) -> void:
	containers.erase(id)

func get_container(id: int) -> Inventory:
	return containers.get(id)

func next_job_id() -> int:
	var id: int = _next_job_id
	_next_job_id += 1
	return id

func register_job(job: Job) -> void:
	jobs[job.id] = job

func unregister_job(id: int) -> void:
	jobs.erase(id)

func get_job(id: int) -> Job:
	return jobs.get(id)

## Registers a persistent item drop (see WorldDrop) -- e.g. a dead
## survivor's carried inventory, or cargo redirected from a haul that
## could never reach its destination or any fallback storage.
func register_drop(drop: WorldDrop) -> int:
	if drop.id == 0:
		drop.id = _next_drop_id
		_next_drop_id += 1
	drops[drop.id] = drop
	drop_registered.emit(drop)
	return drop.id

func get_drop(id: int) -> WorldDrop:
	return drops.get(id)

## --- Phase 3B: doors, and generic persistent world-prop state -----------

func get_door_open(door_id: StringName) -> bool:
	return door_states.get(door_id, false)

func set_door_open(door_id: StringName, is_open: bool) -> void:
	door_states[door_id] = is_open

## Returns the SAME Inventory instance across repeated calls for a given
## prop_id (registering it once on first access), so contents/depletion
## survive being re-queried and can never duplicate. `initial_items` only
## seeds a brand-new registration; a later call for the same id ignores it.
func get_or_create_prop_container(prop_id: StringName, capacity_weight: float, initial_items: Dictionary = {}) -> Inventory:
	if prop_containers.has(prop_id):
		return prop_containers[prop_id]
	var inv := Inventory.new(capacity_weight)
	for item_id in initial_items:
		inv.add_item(StringName(item_id), int(initial_items[item_id]))
	prop_containers[prop_id] = inv
	return inv

func get_prop_state(prop_id: StringName) -> Dictionary:
	return prop_states.get(prop_id, {})

func set_prop_state_flag(prop_id: StringName, flag: StringName, value) -> void:
	if not prop_states.has(prop_id):
		prop_states[prop_id] = {}
	prop_states[prop_id][flag] = value

func get_prop_state_flag(prop_id: StringName, flag: StringName, default_value = false):
	return prop_states.get(prop_id, {}).get(flag, default_value)

func to_snapshot() -> Dictionary:
	var survivor_dicts: Dictionary = {}
	for id in survivors:
		survivor_dicts[id] = (survivors[id] as SurvivorData).to_dict()
	var settlement_dicts: Dictionary = {}
	for id in settlements:
		settlement_dicts[id] = (settlements[id] as SettlementData).to_dict()
	var container_dicts: Dictionary = {}
	for id in containers:
		container_dicts[id] = (containers[id] as Inventory).to_dict()
	var job_dicts: Dictionary = {}
	for id in jobs:
		job_dicts[id] = (jobs[id] as Job).to_dict()
	var drop_dicts: Dictionary = {}
	for id in drops:
		drop_dicts[id] = (drops[id] as WorldDrop).to_dict()
	# Phase 3B.1: door/prop persistent state, keyed by the same stable
	# StringName ids used everywhere else (never a node reference) -- see
	# restore_phase_3b_state() below for the matching read path.
	var prop_container_dicts: Dictionary = {}
	for prop_id in prop_containers:
		prop_container_dicts[prop_id] = (prop_containers[prop_id] as Inventory).to_dict()
	return {
		"sim_day": SimulationClock.game_day,
		"sim_hour": SimulationClock.game_hour,
		"sim_minute": SimulationClock.game_minute,
		"survivors": survivor_dicts,
		"settlements": settlement_dicts,
		"containers": container_dicts,
		"jobs": job_dicts,
		"drops": drop_dicts,
		"world_flags": world_flags.duplicate(),
		"door_states": door_states.duplicate(),
		"prop_states": prop_states.duplicate(true),
		"prop_containers": prop_container_dicts,
	}

## Restores the Phase 3B.1 persistent-world-prop dictionaries
## (door_states/prop_states/prop_containers) from a snapshot produced by
## to_snapshot(). Deliberately scoped to just these three -- survivors/
## settlements/containers/jobs/drops remain snapshot-only preparation for
## a future save/load system (see to_snapshot()'s own doc comment above),
## not restored here, since reconstructing their live runtime nodes is a
## separate, larger undertaking this pass doesn't attempt.
##
## Idempotent: each of the three dictionaries is fully replaced (cleared,
## then rebuilt from the snapshot), never merged on top of whatever state
## already exists -- restoring the same snapshot twice in a row produces
## the identical end state, never a duplicate registration or doubled
## loot. Every restored Inventory is a fresh instance built from the
## snapshot's own counts, so a later get_or_create_prop_container() call
## for the same prop_id resolves to THIS restored instance (matching the
## normal "same id always resolves to the same Inventory" contract) rather
## than reseeding from that call's starting_items.
func restore_phase_3b_state(snapshot: Dictionary) -> void:
	door_states.clear()
	prop_states.clear()
	prop_containers.clear()
	var restored_doors: Dictionary = snapshot.get("door_states", {})
	for door_id in restored_doors:
		door_states[StringName(door_id)] = bool(restored_doors[door_id])
	var restored_prop_states: Dictionary = snapshot.get("prop_states", {})
	for prop_id in restored_prop_states:
		prop_states[StringName(prop_id)] = (restored_prop_states[prop_id] as Dictionary).duplicate(true)
	var restored_containers: Dictionary = snapshot.get("prop_containers", {})
	for prop_id in restored_containers:
		var data: Dictionary = restored_containers[prop_id]
		var inv := Inventory.new(float(data.get("capacity_weight", 0.0)))
		var counts: Dictionary = data.get("counts", {})
		for item_id in counts:
			inv.add_item(StringName(item_id), int(counts[item_id]))
		prop_containers[StringName(prop_id)] = inv

func reset() -> void:
	survivors.clear()
	settlements.clear()
	containers.clear()
	jobs.clear()
	drops.clear()
	world_flags.clear()
	door_states.clear()
	prop_states.clear()
	prop_containers.clear()
	_next_survivor_id = 1
	_next_settlement_id = 1
	_next_container_id = 1
	_next_job_id = 1
	_next_drop_id = 1
