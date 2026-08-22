extends Node

const WORLD_DATA := preload("res://scripts/voxel/voxel_world_data.gd")
const CHUNK_DATA := preload("res://scripts/voxel/voxel_chunk_data.gd")
const NAVIGATION := preload("res://scripts/voxel/voxel_navigation_service.gd")
const JOB_BOARD := preload("res://scripts/voxel/voxel_semantic_job_board.gd")
const SETTLEMENT_RUNTIME := preload("res://scripts/voxel/voxel_settlement_runtime.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")

var _failed := false


func _ready() -> void:
	WorldState.reset()
	var prototype = load("res://scenes/prototypes/VoxelIsometricPrototype.tscn").instantiate()
	add_child(prototype)
	var survivor = prototype.survivor
	prototype.zombie.remove_from_group(&"voxel_zombies")
	var world = WORLD_DATA.new(81)
	var chunk = CHUNK_DATA.new(Vector2i.ZERO)
	for z in range(-6, 7):
		for x in range(-6, 7):
			chunk.set_cell(Vector3i(x, 0, z), MATERIALS.Id.FLOOR)
	world.add_chunk(chunk)
	world.register_stable_object(&"test/scavenge", &"scavenge_point", Vector3i(2, 1, 0), {
		"item_id": "materials", "yield": 3, "stock": 3, "danger": 0.0,
	})
	world.register_stable_object(&"test/storage", &"settlement_storage", Vector3i(4, 1, 0), {"capacity": 1000.0, "role": "general"})
	world.register_stable_object(&"test/storage_food", &"settlement_storage", Vector3i(4, 1, 1), {"capacity": 500.0, "role": "food"})
	world.register_stable_object(&"test/storage_water", &"settlement_storage", Vector3i(4, 1, 2), {"capacity": 500.0, "role": "water"})
	world.register_stable_object(&"test/storage_medical", &"settlement_storage", Vector3i(4, 1, 3), {"capacity": 300.0, "role": "medical"})
	world.register_stable_object(&"test/bed", &"rest_point", Vector3i(0, 1, 2))
	world.register_stable_object(&"test/guard", &"guard_post", Vector3i(0, 1, -2))
	var navigation = NAVIGATION.new()
	navigation.configure(world)
	var board = JOB_BOARD.new()
	board.configure(world)
	var settlement = SETTLEMENT_RUNTIME.new()
	settlement.configure(world)
	survivor.configure_navigation(navigation, world, board, settlement)
	survivor.global_position = Vector3(0.5, 1.0, 0.5)
	survivor.data.hunger = 0.0
	survivor.data.thirst = 0.0
	survivor.utility_ai.force_reconsider()
	_assert(survivor.utility_ai.current_action == &"scavenge", "voxel utility scoring selects an available low-risk scavenge job")
	_assert(board.claimed_by(&"test/scavenge") == survivor.data.id, "voxel scavenge job is reserved by stable survivor id")
	survivor.utility_ai.stop()
	_assert(board.claimed_by(&"test/scavenge") == 0 and survivor.utility_ai.current_action == &"idle", "stopping voxel utility AI releases its reservation and resets the action lifecycle")
	survivor.utility_ai.begin(survivor.data)
	_assert(survivor.utility_ai.current_action == &"scavenge" and board.claimed_by(&"test/scavenge") == survivor.data.id, "rebound voxel utility AI reacquires its semantic job after a streamed transition")
	_assert(not board.claim(&"test/scavenge", survivor.data.id + 100), "a second survivor cannot claim the reserved semantic job")
	survivor.global_position = Vector3(2.5, 1.0, 0.5)
	survivor.utility_ai._tick_scavenge(0.6)
	_assert(survivor.carried_inventory.get_count(&"materials") == 3, "voxel scavenge transfers the exact semantic yield")
	_assert(int(world.get_stable_object(&"test/scavenge").get("state", {}).get("stock", -1)) == 0, "voxel scavenge persists depleted stock in world data")
	_assert(int(WorldState.get_prop_state_flag(&"test/scavenge", &"remaining_stock", -1)) == 0, "voxel scavenge persists depleted stock in WorldState")
	_assert(survivor.utility_ai.current_action == &"deposit", "carried construction material creates a personal haul-to-storage action")
	survivor.global_position = Vector3(4.5, 1.0, 0.5)
	survivor.utility_ai._tick_deposit(0.1)
	_assert(survivor.carried_inventory.get_count(&"materials") == 0 and settlement.storage_inventory().get_count(&"materials") == 3, "voxel hauling conserves the exact material stack in settlement storage")
	survivor.data.hunger = 95.0
	survivor.carried_inventory.add_item(&"food_ration", 1)
	survivor.utility_ai.force_reconsider()
	_assert(survivor.utility_ai.current_action == &"eat", "voxel utility scoring prioritizes critical hunger when food is carried")
	survivor.utility_ai._tick_action(0.1)
	_assert(survivor.carried_inventory.get_count(&"food_ration") == 0 and survivor.data.hunger < 95.0, "voxel eat action consumes exactly one ration and restores hunger")
	survivor.health_component.take_damage(50.0)
	survivor.data.health = survivor.health_component.current_health
	survivor.carried_inventory.add_item(&"medical_supplies", 1)
	survivor.utility_ai.force_reconsider()
	_assert(survivor.utility_ai.current_action == &"treat_self", "voxel utility scoring selects self-treatment below the existing health threshold")
	survivor.utility_ai._tick_action(0.1)
	_assert(survivor.carried_inventory.get_count(&"medical_supplies") == 0 and survivor.health_component.current_health > 50.0, "voxel self-treatment consumes one medical unit and heals through HealthComponent")
	survivor.data.fatigue = 95.0
	survivor.utility_ai.force_reconsider()
	_assert(survivor.utility_ai.current_action == &"sleep" and settlement.claimed_by(&"test/bed") == survivor.data.id, "voxel sleep reserves the semantic rest point")
	_assert(not settlement.claim_service(&"test/bed", survivor.data.id + 100), "a second survivor cannot occupy the reserved voxel rest point")
	survivor.global_position = Vector3(0.5, 1.0, 2.5)
	survivor.utility_ai._tick_sleep(1.0)
	_assert(survivor.data.fatigue < 95.0, "resting at the voxel bed reduces persistent fatigue")
	survivor.data.fatigue = 0.0
	survivor.data.combat_skill = 80.0
	survivor.utility_ai.force_reconsider()
	_assert(survivor.utility_ai.current_action == &"guard" and settlement.claimed_by(&"test/guard") == survivor.data.id, "idle combat-capable survivor reserves the semantic guard post")
	settlement.storage_inventory(&"food").add_item(&"food_ration", 1)
	survivor.data.hunger = 90.0
	survivor.utility_ai.force_reconsider()
	_assert(survivor.utility_ai.current_action == &"retrieve", "voxel utility scoring requests missing food from settlement storage")
	_assert(not settlement.reserve_item(survivor.data.id + 100, &"food_ration", 1), "reserved settlement food cannot be promised to a second survivor")
	survivor.global_position = Vector3(4.5, 1.0, 1.5)
	survivor.utility_ai._tick_retrieve(0.1)
	_assert(survivor.carried_inventory.get_count(&"food_ration") == 1 and settlement.storage_inventory(&"food").get_count(&"food_ration") == 0, "voxel retrieval confirms the exact reserved stack into carried inventory")
	survivor.utility_ai._tick_action(0.1)
	survivor.data.hunger = 0.0
	survivor.carried_inventory.add_item(&"food_ration", 3)
	var routed := settlement.deposit_item(survivor.carried_inventory, &"food_ration", 2)
	_assert(routed == 2 and settlement.storage_inventory(&"food").get_count(&"food_ration") == 2 and settlement.storage_inventory(&"general").get_count(&"food_ration") == 0, "voxel settlement routes food only to the existing food category")
	var second_prototype = load("res://scenes/prototypes/VoxelIsometricPrototype.tscn").instantiate()
	add_child(second_prototype)
	second_prototype.zombie.remove_from_group(&"voxel_zombies")
	var injured = second_prototype.survivor
	injured.configure_navigation(navigation, world, board, settlement)
	injured.global_position = survivor.global_position
	injured.health_component.take_damage(60.0)
	injured.data.health = injured.health_component.current_health
	survivor.carried_inventory.add_item(&"medical_supplies", 1)
	survivor.data.medical_skill = 80.0
	survivor.utility_ai.force_reconsider()
	_assert(survivor.utility_ai.current_action == &"help_injured" and injured.is_claimed_for_help(), "voxel medical utility reserves one injured survivor")
	_assert(not injured.try_claim_helper(survivor.data.id + 100), "a second helper cannot claim the same injured survivor")
	survivor.utility_ai._tick_help_injured(0.1)
	_assert(injured.health_component.current_health > 40.0 and survivor.carried_inventory.get_count(&"medical_supplies") == 0, "voxel help action consumes one medical unit and heals the claimed survivor")
	var threat := Node3D.new()
	threat.position = survivor.global_position + Vector3.RIGHT * 2.0
	threat.add_to_group(&"voxel_zombies")
	add_child(threat)
	survivor.data.fear = 0.0
	survivor.data.combat_skill = 100.0
	survivor.utility_ai.force_reconsider()
	_assert(survivor.utility_ai.current_action == &"fight", "confident armed voxel survivor selects fight over flee")
	var ammunition_before: int = survivor.weapon.ammo_in_magazine
	survivor.utility_ai._tick_fight(0.1)
	_assert(survivor.weapon.ammo_in_magazine == ammunition_before - 1, "voxel survivor combat fires through VoxelWeapon3D and consumes one round")
	survivor.data.fear = 90.0
	survivor.data.combat_skill = 20.0
	survivor.utility_ai.force_reconsider()
	_assert(survivor.utility_ai.current_action == &"flee", "nearby visible voxel zombie interrupts normal work with the emergency flee score")
	threat.remove_from_group(&"voxel_zombies")
	survivor.global_position = Vector3(-5.5, 1.0, 0.5)
	survivor.utility_ai.force_reconsider()
	_assert(survivor.utility_ai.current_action == &"seek_safety", "fearful voxel survivor outside the safehouse radius selects the semantic safe position")
	prototype.queue_free()
	second_prototype.queue_free()
	threat.queue_free()
	await get_tree().process_frame
	WorldState.reset()
	if _failed:
		get_tree().quit(1)
	else:
		print("VOXEL_UTILITY_AI: PASS")
		get_tree().quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("VOXEL_UTILITY_AI: FAIL: %s" % message)
