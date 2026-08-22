extends SceneTree

const COORDINATES := preload("res://scripts/voxel/voxel_coordinates.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")

var _failed := false


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	root.get_node("WorldState").reset()
	root.get_node("SimulationClock").reset()
	var scene: PackedScene = load("res://scenes/main/VoxelMain.tscn")
	_assert(scene != null, "active voxel main scene loads")
	if scene == null:
		_finish()
		return
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await physics_frame
	await process_frame
	var contract: Dictionary = main.runtime_contract()
	_assert(bool(contract.initialized), "voxel main completes startup")
	_assert(int(contract.world_seed) == 20260822, "voxel main uses the deterministic production fallback seed")
	_assert(int(contract.loaded_chunks) >= 1 and int(contract.loaded_chunks) <= 9 and int(contract.collision_chunks) == 1, "voxel main starts with its collision-backed center while adjacent chunks fill progressively")
	_assert(int(contract.stable_objects) > 0 and int(contract.buildings) > 0, "voxel main runs the semantic Prague generator")
	_assert(int(contract.roof_renderers) == int(contract.buildings), "voxel main creates one independently hideable renderer per generated building roof")
	_assert(int(contract.semantic_interactions) > 0, "voxel main materializes generated 3D semantic interactions")
	_assert(int(contract.world_drops) == 0, "voxel main starts with an empty signal-driven 3D drop runtime")
	_assert(bool(contract.combat_effects), "voxel main instances the bounded 3D combat effect runtime")
	_assert(int(contract.zombies) > 0 and int(contract.zombies) <= main.zombie_population, "voxel main spawns a bounded deterministic zombie population")
	_assert(int(contract.survivors) == 4, "voxel main spawns all four persistent 3D survivors")
	_assert(bool(contract.player_is_3d) and bool(contract.camera_orthographic), "active player and isometric camera are fully 3D")
	_assert(bool(contract.hud_visible), "production HUD is visible in voxel main")
	_assert(bool(contract.survivor_inspector), "voxel main instances the production survivor inspector")
	_assert(bool(contract.debug_overlay), "voxel main instances the production performance overlay")
	await _wait_for_prefetch(main)
	contract = main.runtime_contract()
	_assert(int(contract.loaded_chunks) == 9 and int(contract.pending_chunks) == 0, "voxel main completes the bounded radius-one prefetched working set")
	var generation: Dictionary = contract.generation
	_assert(int(generation.active) == 0 and int(generation.queued) == 0 and int(generation.ready) == 0, "background generation queue drains without retaining completed payloads")
	var initial_stream_metrics: Dictionary = main.stream_controller.metrics()
	print("VOXEL_MAIN_STREAM_PROFILE initial_max_build_usec=%d" % int(initial_stream_metrics.maximum_build_step_usec))
	_assert(int(initial_stream_metrics.maximum_build_step_usec) < 150000, "each prefetched integration and renderer attachment stays below the 150 ms safety budget")
	_test_boundary_navigation(main)
	_test_mobile_zoom(main)
	main.debug_overlay._process(0.1)
	_assert(main.debug_overlay.label.text.contains("voxel chunks 9 queued 0") and main.debug_overlay.label.text.contains("survivors 4"), "performance overlay reports the prefetched voxel working set and utility-AI population metrics")
	_assert(main.hud.zombie_count_label.text == "Zombies: %d" % int(contract.zombies), "production HUD receives the active voxel population")
	_test_survivor_inspector(main)
	_test_world_drop_collection(main)
	_test_combat_effects(main)
	_test_zombie_contact_damage(main)
	_test_generated_roof(main)
	await _test_chunk_transition(main)
	main.queue_free()
	await process_frame
	_finish()


func _test_generated_roof(main) -> void:
	_assert(int(main.runtime_contract().shell_collision_proxies) >= 1, "origin chunk builds a hidden full-height wall collision proxy")
	var tested := false
	for stable_id_variant in main.world_data.stable_objects:
		var stable_id := StringName(stable_id_variant)
		var record: Dictionary = main.world_data.get_stable_object(stable_id)
		if record.get("kind", &"") != &"building":
			continue
		var bounds: Array = record.get("state", {}).get("bounds", [])
		var renderer = main.roof_runtime.renderer_for(stable_id)
		_assert(renderer != null and bounds.size() == 4, "generated building resolves to its stable roof renderer and bounds")
		if renderer == null or bounds.size() != 4:
			return
		main.player.global_position = Vector3((float(bounds[0]) + float(bounds[2])) * 0.5, 1.75, (float(bounds[1]) + float(bounds[3])) * 0.5)
		main.roof_occlusion.update_visibility()
		_assert(not renderer.visible, "generated roof hides when the 3D player enters its stable bounds")
		_assert(main.shell_runtime.is_cutaway(stable_id), "entering a generated building engages the PZ-style wall cutaway")
		_assert(not main.shell_runtime.front_sides().is_empty(), "cutaway resolves camera-facing wall sides")
		var window_found := false
		for window_id_variant in main.world_data.stable_objects:
			var window_record: Dictionary = main.world_data.get_stable_object(StringName(window_id_variant))
			if StringName(window_record.get("kind", &"")) == &"window":
				window_found = true
				break
		_assert(window_found, "generated buildings register windows linked to their owning building")
		main.player.global_position = Vector3(-43.0, 1.75, -43.0)
		main.roof_occlusion.update_visibility()
		_assert(renderer.visible, "generated roof restores when the 3D player exits")
		_assert(not main.shell_runtime.is_cutaway(stable_id), "exiting a generated building restores full wall height")
		tested = true
		break
	_assert(tested, "generated voxel main exposes a building for roof testing")


func _test_boundary_navigation(main) -> void:
	var origin = main.world_data.get_chunk(Vector2i.ZERO)
	var east = main.world_data.get_chunk(Vector2i.RIGHT)
	for z in range(-COORDINATES.HALF_CHUNK_CELLS, COORDINATES.HALF_CHUNK_CELLS):
		var origin_cell := Vector3i(COORDINATES.HALF_CHUNK_CELLS - 1, 0, z)
		var east_cell := Vector3i(-COORDINATES.HALF_CHUNK_CELLS, 0, z)
		if not MATERIALS.definition(origin.get_cell(origin_cell)).get("walkable", false):
			continue
		if not MATERIALS.definition(east.get_cell(east_cell)).get("walkable", false):
			continue
		var from := COORDINATES.world_cell_to_world_position(COORDINATES.local_to_world_cell(origin_cell, Vector2i.ZERO)) + Vector3(0.5, 1.0, 0.5)
		var to := COORDINATES.world_cell_to_world_position(COORDINATES.local_to_world_cell(east_cell, Vector2i.RIGHT)) + Vector3(0.5, 1.0, 0.5)
		_assert(main.navigation.is_direct_path_clear(from, to), "navigation crosses a matching prefetched east-west road portal")
		return
	_assert(false, "prefetched origin and east chunks expose a shared walkable road portal")


func _test_mobile_zoom(main) -> void:
	var controls = main.get_node("UI/MobileControls")
	var starting_size: float = main.camera.size
	controls.zoom_in_button.pressed.emit()
	_assert(main.camera.size == starting_size - main.camera_rig.zoom_step, "mobile zoom-in button routes through InputRouter into the voxel camera rig")
	controls.zoom_out_button.pressed.emit()
	_assert(main.camera.size == starting_size, "mobile zoom-out button restores the bounded voxel camera size")


func _test_zombie_contact_damage(main) -> void:
	var zombies: Array[Node] = get_nodes_in_group(&"voxel_zombies")
	if zombies.is_empty():
		_assert(false, "voxel main exposes a zombie for contact-damage testing")
		return
	var zombie = zombies[0]
	_assert(not zombie.is_in_group(&"attackable"), "voxel zombies cannot select other zombies as hostile targets")
	main.player.health_component.invulnerability_duration = 0.0
	var health_before: float = main.player.health_component.current_health
	zombie.global_position = main.player.global_position + Vector3.RIGHT
	zombie.perception.target = main.player
	var states: Dictionary = zombie.perception.get_script().get_script_constant_map().get("State", {})
	zombie.perception.state = int(states.get("ATTACK", -1))
	zombie._tick_contact_damage(1.0)
	_assert(main.player.health_component.current_health == health_before - zombie.contact_damage, "3D zombie attack state applies bounded contact damage to the player")
	main.player.health_component.reset_health()


func _test_survivor_inspector(main) -> void:
	var survivors: Array[Node] = get_nodes_in_group(&"survivors")
	if survivors.is_empty():
		_assert(false, "voxel main exposes a survivor for inspector testing")
		return
	var survivor: Node3D = survivors[0]
	var screen_position: Vector2 = main.camera.unproject_position(survivor.global_position)
	main._try_select_survivor_screen(screen_position)
	main.survivor_inspector._process(0.0)
	_assert(main.survivor_inspector.panel.visible, "right-click camera projection selects a 3D survivor")
	_assert(main.survivor_inspector.label.text.contains(survivor.data.survivor_name) and main.survivor_inspector.label.text.contains("Action:"), "production inspector renders 3D SurvivorData and utility action state")


func _test_world_drop_collection(main) -> void:
	var drop = load("res://scripts/world/world_drop.gd").new()
	drop.position = Vector2(main.player.global_position.x, main.player.global_position.z)
	drop.reason = &"death"
	drop.inventory = load("res://scripts/items/inventory.gd").new(0.0)
	drop.inventory.add_item(&"materials", 2)
	var world_state = root.get_node("WorldState")
	var drop_id: int = world_state.register_drop(drop)
	var node = main.world_drop_runtime.node_for(drop_id)
	_assert(node != null and main.world_drop_runtime.active_drop_count() == 1, "registered persistent cargo creates one voxel drop interaction")
	var materials_before: int = main.player.carried_inventory.get_count(&"materials")
	node.get_node("InteractableComponent").interact(main.player)
	_assert(main.player.carried_inventory.get_count(&"materials") == materials_before + 2, "collecting a voxel drop conserves and transfers its exact inventory")
	_assert(world_state.get_drop(drop_id) == null and main.world_drop_runtime.active_drop_count() == 0, "depleted voxel drop unregisters its persistent record and runtime node")


func _test_combat_effects(main) -> void:
	var zombies: Array[Node] = get_nodes_in_group(&"voxel_zombies")
	if zombies.is_empty():
		_assert(false, "voxel main exposes a zombie for combat-effect testing")
		return
	var zombie: Node3D = zombies[0]
	zombie.health_component.invulnerability_duration = 0.0
	zombie.take_damage(1.0, main.player)
	_assert(main.combat_effects.hit_effect_count == 1, "voxel zombie damage emits one 3D hit flash")
	root.get_node("GameEvents").voxel_environment_explosion.emit(main.player.global_position, 2.0)
	_assert(main.combat_effects.explosion_effect_count == 1, "voxel structural explosion emits one expanding 3D burst")
	for index in range(100):
		main.combat_effects._on_zombie_died(zombie, main.player.global_position + Vector3(index % 4, 0.0, index % 3))
	_assert(main.combat_effects.blood_decal_count == 100 and main.combat_effects._blood_decals.size() == 96, "voxel blood decals retain exact event metrics while enforcing the 96-decal runtime cap")


func _test_chunk_transition(main) -> void:
	var survivor_ids: Array[int] = []
	var tracked_survivor = null
	for survivor in get_nodes_in_group(&"survivors"):
		survivor_ids.append(int(survivor.data.id))
		if tracked_survivor == null:
			tracked_survivor = survivor
	survivor_ids.sort()
	tracked_survivor.carried_inventory.add_item(&"materials", 3)
	var origin_chunk = main.world_data.get_chunk(Vector2i.ZERO)
	var destroyed_local := Vector3i.ZERO
	var found_brick := false
	for cell_variant in origin_chunk.cells:
		var cell: Vector3i = cell_variant
		if int(origin_chunk.cells[cell]) == MATERIALS.Id.BRICK:
			destroyed_local = cell
			found_brick = true
			break
	_assert(found_brick, "origin stream chunk exposes structural brick for regeneration testing")
	var destroyed_world := COORDINATES.local_to_world_cell(destroyed_local, Vector2i.ZERO)
	_assert(main.structural_damage_service.apply_cell(destroyed_world, 999.0, 2), "active chunk structural damage records a persistent override")
	main.player.global_position = Vector3(42.0, 1.75, 0.0)
	main._process(0.0)
	_assert(int(main.stream_controller.metrics().collision_chunks) == 2, "approaching a loaded boundary promotes only the center and destination collision meshes")
	var builds_before_transition: int = main.stream_controller.total_chunk_builds
	main.player.global_position = Vector3(45.0, 1.75, 0.0)
	main._process(0.0)
	var east_contract: Dictionary = main.runtime_contract()
	_assert(east_contract.current_chunk == Vector2i.RIGHT and int(east_contract.loaded_chunks) >= 6, "player crossing commits immediately into the prefetched east chunk while retaining overlap")
	_assert(main.world_data.get_chunk(Vector2i.ZERO) != null and main.world_data.get_chunk(Vector2i.RIGHT) != null, "stream transition retains origin and east navigation data across the shared boundary")
	_assert(main.stream_controller.total_chunk_builds == builds_before_transition, "entering a prefetched chunk performs no synchronous generation or mesh build")
	_assert(int(east_contract.transition_wait_frames) == 0 and int(east_contract.maximum_transition_usec) < 100000, "prefetched transition needs no blocked frame and stays below the 100 ms commit budget")
	await process_frame
	east_contract = main.runtime_contract()
	_assert(int(east_contract.roof_renderers) == int(east_contract.buildings), "east chunk rebuilds independent generated roof renderers")
	_assert(main.hud.zombie_count_label.text == "Zombies: %d" % int(east_contract.zombies), "stream transition replaces the local zombie population and HUD count")
	var east_survivor_ids: Array[int] = []
	for survivor in get_nodes_in_group(&"survivors"):
		east_survivor_ids.append(int(survivor.data.id))
	east_survivor_ids.sort()
	_assert(east_survivor_ids == survivor_ids, "stream transition preserves survivor identities")
	_assert(is_instance_valid(tracked_survivor) and tracked_survivor.carried_inventory.get_count(&"materials") == 3, "stream transition preserves survivor runtime inventory")
	_test_cross_chunk_gameplay(main)
	await _wait_for_prefetch(main)
	_assert(main.stream_controller.loaded_chunks.size() == 9 and main.stream_controller.pending_coordinates.is_empty(), "east center refills only its three entering-edge chunks")
	main.player.global_position = Vector3(0.0, 1.75, 0.0)
	main._process(0.0)
	var rebuilt_origin = main.world_data.get_chunk(Vector2i.ZERO)
	_assert(rebuilt_origin != null and rebuilt_origin.get_cell(destroyed_local) == MATERIALS.Id.AIR, "returning through retained overlap preserves the sparse destroyed-voxel override")
	await _wait_for_prefetch(main)
	_assert(main.stream_controller.total_chunk_builds == 15 and main.stream_controller.total_chunk_unloads == 6, "round-trip shifts build only one entering edge per center change and unload only expired edges")


func _test_cross_chunk_gameplay(main) -> void:
	var coordinate := Vector2i.RIGHT
	var door_id := _find_stable_object(main, coordinate, [&"door"])
	_assert(door_id != &"", "entered east chunk exposes a semantic door interaction")
	if door_id != &"":
		var door = main.semantic_runtime.node_for(door_id)
		var was_open := bool(main.world_data.get_stable_object(door_id).get("state", {}).get("open", false))
		_assert(door != null, "entered east door has an activated chunk-local interaction node")
		if door != null:
			door.get_node("InteractableComponent").interact(main.player)
			var door_state: Dictionary = main.world_data.get_stable_object(door_id).get("state", {})
			_assert(bool(door_state.get("open", false)) != was_open and root.get_node("WorldState").get_door_open(door_id) != was_open, "east door interaction updates voxel geometry and persistent WorldState")
			door.get_node("InteractableComponent").interact(main.player)

	var loot_id := _find_loot_object(main, coordinate)
	_assert(loot_id != &"", "entered east chunk exposes searchable semantic loot")
	if loot_id != &"":
		var loot = main.semantic_runtime.node_for(loot_id)
		var items: Dictionary = main.world_data.get_stable_object(loot_id).get("state", {}).get("items", {})
		var moved := 0
		for item_id_variant in items:
			var item_id := StringName(item_id_variant)
			var before: int = main.player.carried_inventory.get_count(item_id)
			loot.get_node("InteractableComponent").interact(main.player)
			moved += main.player.carried_inventory.get_count(item_id) - before
			break
		_assert(moved > 0, "east searchable loot transfers inventory through the production player interaction path")

	var east_chunk = main.world_data.get_chunk(coordinate)
	var brick_local := Vector3i.ZERO
	var found_brick := false
	for cell_variant in east_chunk.cells:
		var cell: Vector3i = cell_variant
		if int(east_chunk.cells[cell]) == MATERIALS.Id.BRICK:
			brick_local = cell
			found_brick = true
			break
	_assert(found_brick, "entered east chunk exposes structural brick")
	if found_brick:
		var brick_world := COORDINATES.local_to_world_cell(brick_local, coordinate)
		_assert(not main.structural_damage_service.apply_cell(brick_world, 999.0, 0), "east brick still rejects small-arms structural damage")
		_assert(main.structural_damage_service.apply_cell(brick_world, 999.0, 2) and east_chunk.get_cell(brick_local) == MATERIALS.Id.AIR, "east brick accepts explosive damage and records the streamed voxel edit")

	var zombies: Array[Node] = get_nodes_in_group(&"voxel_zombies")
	if not zombies.is_empty():
		var zombie = zombies[0]
		zombie.health_component.invulnerability_duration = 0.0
		var health_before: float = zombie.health_component.current_health
		main.player.weapon._cooldown_remaining = 0.0
		var ammo_before: int = main.player.weapon.ammo_in_magazine
		_assert(main.player.weapon.try_fire(Vector3.FORWARD), "player weapon fires after the streamed transition")
		var projectile = null
		for child in main.projectile_manager.get_children():
			if child.active:
				projectile = child
				break
		_assert(projectile != null and main.player.weapon.ammo_in_magazine == ammo_before - 1, "east combat uses the pooled projectile manager and consumes one round")
		if projectile != null:
			projectile._resolve_hit({"collider": zombie, "position": zombie.global_position, "normal": Vector3.BACK})
			projectile._release()
			_assert(zombie.health_component.current_health < health_before, "east pooled projectile applies actor damage after transition")
	else:
		_assert(false, "entered east chunk exposes a zombie for cross-chunk combat")

	for zombie in zombies:
		zombie.remove_from_group(&"voxel_zombies")
	var survivors: Array[Node] = get_nodes_in_group(&"survivors")
	var worker = survivors[1] if survivors.size() > 1 else null
	_assert(worker != null, "entered east chunk retains a survivor for semantic job execution")
	if worker != null:
		for survivor in survivors:
			survivor.utility_ai.stop()
		var carried_counts: Dictionary = worker.carried_inventory.to_dict().get("counts", {})
		for item_id_variant in carried_counts:
			var item_id := StringName(item_id_variant)
			worker.carried_inventory.remove_item(item_id, worker.carried_inventory.get_available(item_id))
		worker.data.hunger = 0.0
		worker.data.thirst = 0.0
		worker.data.fatigue = 0.0
		worker.data.fear = 0.0
		worker.utility_ai.begin(worker.data)
		_assert(worker.utility_ai.current_action == &"scavenge" and worker.utility_ai.reserved_target_id != &"", "retained survivor claims a streamed semantic scavenge job")
		if worker.utility_ai.reserved_target_id != &"":
			var job_id: StringName = worker.utility_ai.reserved_target_id
			var job_record: Dictionary = main.world_data.get_stable_object(job_id)
			var job_state: Dictionary = job_record.get("state", {})
			var job_item := StringName(job_state.get("item_id", &""))
			var before_count: int = worker.carried_inventory.get_count(job_item)
			var before_stock := int(job_state.get("stock", 0))
			worker.global_position = COORDINATES.world_cell_to_world_position(job_record.get("cell", Vector3i.ZERO)) + Vector3(0.5, 1.0, 0.5)
			worker.utility_ai._work_remaining = 0.0
			worker.utility_ai._tick_scavenge(0.1)
			var after_stock := int(main.world_data.get_stable_object(job_id).get("state", {}).get("stock", 0))
			_assert(worker.carried_inventory.get_count(job_item) > before_count and after_stock < before_stock, "retained survivor harvests and persists the claimed streamed job")
	for zombie in zombies:
		if is_instance_valid(zombie):
			zombie.add_to_group(&"voxel_zombies")


func _find_stable_object(main, coordinate: Vector2i, kinds: Array[StringName]) -> StringName:
	for stable_id_variant in main.world_data.stable_objects:
		var stable_id := StringName(stable_id_variant)
		var record: Dictionary = main.world_data.get_stable_object(stable_id)
		if StringName(record.get("kind", &"")) in kinds and COORDINATES.world_cell_to_chunk(record.get("cell", Vector3i.ZERO)) == coordinate:
			return stable_id
	return &""


func _find_loot_object(main, coordinate: Vector2i) -> StringName:
	for stable_id_variant in main.world_data.stable_objects:
		var stable_id := StringName(stable_id_variant)
		var record: Dictionary = main.world_data.get_stable_object(stable_id)
		if COORDINATES.world_cell_to_chunk(record.get("cell", Vector3i.ZERO)) != coordinate:
			continue
		if StringName(record.get("kind", &"")) not in [&"furniture", &"exterior_prop"]:
			continue
		if not (record.get("state", {}).get("items", {}) as Dictionary).is_empty() and main.semantic_runtime.node_for(stable_id) != null:
			return stable_id
	return &""


func _wait_for_prefetch(main, maximum_frames := 600) -> void:
	for frame in range(maximum_frames):
		if main.stream_controller.pending_coordinates.is_empty():
			return
		await process_frame
	_assert(false, "prefetched voxel working set completes within the bounded frame allowance")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("VOXEL_MAIN_SMOKE: FAIL: %s" % message)


func _finish() -> void:
	if _failed:
		quit(1)
	else:
		print("VOXEL_MAIN_SMOKE: PASS")
		quit(0)
