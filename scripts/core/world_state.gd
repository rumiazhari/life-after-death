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

var survivors: Dictionary = {} ## int id -> SurvivorData
var settlements: Dictionary = {} ## int id -> SettlementData
var containers: Dictionary = {} ## int id -> Inventory
var jobs: Dictionary = {} ## int id -> Job
var drops: Dictionary = {} ## int id -> WorldDrop
var world_flags: Dictionary = {}

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
	return drop.id

func get_drop(id: int) -> WorldDrop:
	return drops.get(id)

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
	}

func reset() -> void:
	survivors.clear()
	settlements.clear()
	containers.clear()
	jobs.clear()
	drops.clear()
	world_flags.clear()
	_next_survivor_id = 1
	_next_settlement_id = 1
	_next_container_id = 1
	_next_job_id = 1
	_next_drop_id = 1
