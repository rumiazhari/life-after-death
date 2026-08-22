class_name VoxelMain
extends Node3D

const CITY_GENERATOR := preload("res://scripts/world/procedural_city_generator.gd")
const VOXELIZER := preload("res://scripts/voxel/semantic_voxelizer.gd")
const WORLD_DATA := preload("res://scripts/voxel/voxel_world_data.gd")
const CHUNK_DATA := preload("res://scripts/voxel/voxel_chunk_data.gd")
const COORDINATES := preload("res://scripts/voxel/voxel_coordinates.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")
const NAVIGATION := preload("res://scripts/voxel/voxel_navigation_service.gd")
const SPAWN_SAMPLER := preload("res://scripts/voxel/voxel_spawn_sampler.gd")
const JOB_BOARD := preload("res://scripts/voxel/voxel_semantic_job_board.gd")
const SETTLEMENT_RUNTIME := preload("res://scripts/voxel/voxel_settlement_runtime.gd")
const GENERATION_QUEUE := preload("res://scripts/voxel/voxel_chunk_generation_queue.gd")
const ZOMBIE_SCENE := preload("res://scenes/actors/VoxelZombie3D.tscn")
const SURVIVOR_SCENE := preload("res://scenes/actors/VoxelSurvivor3D.tscn")
const SHELL_RUNTIME_SCRIPT := preload("res://scripts/voxel/voxel_building_shell_runtime.gd")

const BASE_MATERIALS: Array[int] = [
	MATERIALS.Id.GRASS, MATERIALS.Id.ROAD, MATERIALS.Id.PAVEMENT,
	MATERIALS.Id.DIRT, MATERIALS.Id.COBBLE, MATERIALS.Id.FLOOR,
	MATERIALS.Id.WOOD,
]
const BASE_EXCLUDED_KINDS: Array[StringName] = [&"door", &"window", &"building"]
const SURVIVOR_PROFILES: Array[Dictionary] = [
	{"name": "Marcus", "combat_skill": 55.0, "medical_skill": 15.0, "scavenging_skill": 30.0, "personality": {"brave": 0.6}},
	{"name": "Elena", "combat_skill": 20.0, "medical_skill": 60.0, "scavenging_skill": 25.0, "personality": {"social": 0.6}},
	{"name": "Dax", "combat_skill": 25.0, "medical_skill": 10.0, "scavenging_skill": 55.0, "personality": {"diligent": 0.5}},
	{"name": "Priya", "combat_skill": 15.0, "medical_skill": 35.0, "construction_skill": 45.0, "personality": {"cautious": 0.6}},
]

@export var fallback_world_seed := 20260822
@export_range(1, 24, 1) var zombie_population := 8

@onready var stream_controller = $World/VoxelChunkStreamController
@onready var roof_runtime = $World/VoxelBuildingRoofRuntime
@onready var shell_runtime = $World/VoxelBuildingShellRuntime
@onready var roof_occlusion = $World/VoxelRoofOcclusionController3D
@onready var semantic_runtime = $World/VoxelSemanticRuntime
@onready var world_drop_runtime = $World/VoxelWorldDropRuntime3D
@onready var structural_damage_service = $Systems/VoxelStructuralDamageService
@onready var projectile_manager = $Systems/VoxelProjectileManager
@onready var combat_effects = $Systems/VoxelCombatEffects3D
@onready var player = $Actors/VoxelPlayer3D
@onready var actors: Node3D = $Actors
@onready var camera_rig = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var hud: HUD = $UI/HUD
@onready var pause_menu: PauseMenu = $UI/PauseMenu
@onready var death_overlay: DeathOverlay = $UI/DeathOverlay
@onready var survivor_inspector: SurvivorInspector = $UI/SurvivorInspector
@onready var debug_overlay: DebugOverlay = $UI/DebugOverlay
@onready var mobile_controls: MobileControls = $UI/MobileControls

var world_seed := 0
var world_data
var navigation
var semantic_job_board
var settlement_runtime
var generation_queue
var origin_city: Dictionary = {}
var city_models: Dictionary = {} # Vector2i -> deterministic semantic city model
var current_chunk_coordinate := Vector2i.ZERO
var initialized := false
var kill_count := 0
var _capture_path := ""
var _capture_frames := 0
var _capture_chunk := Vector2i.ZERO
var _capture_chunk_requested := false
var _capture_inspector := false
var _capture_drop := false
var _capture_effects := false
var _capture_mobile := false
var _capture_interior := false
var _last_safe_player_position := Vector3.ZERO
var _transition_wait_frames := 0
var maximum_transition_usec := 0
var _runtime_coordinates: Dictionary = {}


func _ready() -> void:
	add_to_group(&"voxel_main")
	get_tree().paused = false
	world_seed = int(WorldState.world_flags.get(&"city_seed", fallback_world_seed))
	WorldState.world_flags[&"city_seed"] = world_seed
	world_data = WORLD_DATA.new(world_seed)
	origin_city = _generate_chunk(Vector2i.ZERO)
	generation_queue = GENERATION_QUEUE.new()
	generation_queue.configure(world_seed, 2, {
		"door_states": WorldState.door_states.duplicate(),
		"prop_states": WorldState.prop_states.duplicate(true),
	})
	navigation = NAVIGATION.new()
	navigation.configure(world_data)
	semantic_job_board = JOB_BOARD.new()
	semantic_job_board.configure(world_data)
	settlement_runtime = SETTLEMENT_RUNTIME.new()
	settlement_runtime.configure(world_data)
	structural_damage_service.configure(world_data)
	projectile_manager.damage_service = structural_damage_service
	player.camera = camera
	var spawn_semantic: Vector2 = origin_city.get("player_spawn", Vector2.ZERO)
	player.global_position = COORDINATES.semantic_local_to_world_position(spawn_semantic, Vector2i.ZERO, 1.75)
	_last_safe_player_position = player.global_position
	camera_rig.configure(player)
	shell_runtime.configure(world_data, structural_damage_service)
	roof_occlusion.configure(world_data, player, camera, shell_runtime)
	roof_occlusion.building_cutaway_changed.connect(_on_building_cutaway)
	stream_controller.chunk_loaded.connect(_on_chunk_loaded)
	stream_controller.chunk_unloaded.connect(_on_chunk_unloaded)
	var render_materials: Array[Material] = []
	stream_controller.configure(_provide_render_chunk, render_materials, _request_chunk_generation)
	stream_controller.process_build_budget()
	stream_controller.reset_build_timing()
	generation_queue.retain_only(stream_controller.desired_coordinates())
	_spawn_zombies()
	_spawn_survivors()
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.voxel_zombie_died.connect(_on_zombie_died)
	death_overlay.restart_requested.connect(_restart_game)
	pause_menu.quit_requested.connect(func() -> void: get_tree().quit())
	GameEvents.player_health_changed.emit(player.health_component.current_health, player.health_component.max_health)
	GameEvents.zombie_count_changed.emit(get_tree().get_nodes_in_group(&"voxel_zombies").size())
	GameEvents.kill_count_changed.emit(kill_count)
	player.call_deferred(&"_emit_equipped_weapon")
	_parse_capture_argument()
	if _capture_mobile:
		mobile_controls.visible = true
		mobile_controls.set_process_input(true)
	if _capture_chunk_requested and _capture_chunk != Vector2i.ZERO:
		stream_controller.set_center(_capture_chunk)
		generation_queue.retain_only(stream_controller.desired_coordinates())
	if _capture_inspector:
		var survivors := get_tree().get_nodes_in_group(&"survivors")
		if not survivors.is_empty():
			_select_survivor_at_world_position(survivors[0].global_position)
	if _capture_interior:
		for stable_id_variant in world_data.stable_objects:
			var record: Dictionary = world_data.get_stable_object(StringName(stable_id_variant))
			if StringName(record.get("kind", &"")) != &"building":
				continue
			var bounds: Array = record.get("state", {}).get("bounds", [])
			if bounds.size() != 4:
				continue
			player.global_position = Vector3((float(bounds[0]) + float(bounds[2])) * 0.5, 1.75, (float(bounds[1]) + float(bounds[3])) * 0.5)
			camera_rig.configure(player)
			break
	if _capture_drop:
		var drop := WorldDrop.new()
		drop.position = Vector2(player.global_position.x + 2.0, player.global_position.z)
		drop.reason = &"death"
		drop.inventory = Inventory.new(0.0)
		drop.inventory.add_item(&"materials", 2)
		WorldState.register_drop(drop)
	if _capture_effects:
		combat_effects._on_zombie_died(null, player.global_position + Vector3(2.0, 0.0, 1.5))
	initialized = true


func _process(_delta: float) -> void:
	if generation_queue != null:
		generation_queue.poll()
	if _capture_chunk_requested and stream_controller.is_loaded(_capture_chunk):
		player.global_position = Vector3(_capture_chunk.x * COORDINATES.CHUNK_CELLS, 1.75, _capture_chunk.y * COORDINATES.CHUNK_CELLS)
		_transition_to_chunk(_capture_chunk)
		camera_rig.configure(player)
		_capture_chunk_requested = false
	if initialized and is_instance_valid(player):
		var player_coordinate := COORDINATES.world_cell_to_chunk(COORDINATES.world_position_to_world_cell(player.global_position))
		if player_coordinate != current_chunk_coordinate:
			if stream_controller.is_loaded(player_coordinate):
				_transition_to_chunk(player_coordinate)
			else:
				_transition_wait_frames += 1
				player.global_position = _last_safe_player_position
		else:
			_last_safe_player_position = player.global_position
	_update_boundary_collision()
	roof_occlusion.update_visibility()
	if _capture_path.is_empty():
		return
	if _capture_chunk_requested or not stream_controller.pending_coordinates.is_empty():
		return
	_capture_frames += 1
	if _capture_effects and _capture_frames == 82:
		combat_effects._on_environment_explosion(player.global_position + Vector3(2.5, 0.5, 0.0), 2.0)
		var zombies := get_tree().get_nodes_in_group(&"voxel_zombies")
		if not zombies.is_empty():
			combat_effects._on_zombie_damaged(zombies[0], 1.0)
	if _capture_frames < 90:
		return
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("VOXEL_MAIN_CAPTURE requires a rendering display driver")
		get_tree().quit(1)
		return
	var result := image.save_png(_capture_path)
	print("VOXEL_MAIN_CAPTURE path=%s result=%s" % [_capture_path, error_string(result)])
	get_tree().quit(0 if result == OK else 1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_try_select_survivor_screen(event.position)
		get_viewport().set_input_as_handled()


func runtime_contract() -> Dictionary:
	var buildings := 0
	var loaded_buildings := 0
	for stable_id in world_data.stable_objects:
		var record: Dictionary = world_data.stable_objects[stable_id]
		if record.get("kind", &"") != &"building":
			continue
		loaded_buildings += 1
		var cell: Vector3i = record.get("cell", Vector3i.ZERO)
		if _runtime_coordinates.has(COORDINATES.world_cell_to_chunk(cell)):
			buildings += 1
	return {
		"initialized": initialized,
		"world_seed": world_seed,
		"loaded_chunks": stream_controller.loaded_chunks.size(),
		"pending_chunks": stream_controller.pending_coordinates.size(),
		"current_chunk": current_chunk_coordinate,
		"stable_objects": world_data.stable_objects.size(),
		"buildings": buildings,
		"loaded_buildings": loaded_buildings,
		"runtime_chunks": _runtime_coordinates.size(),
		"roof_renderers": roof_runtime.roof_count(),
		"shell_roots": shell_runtime.shell_root_count(),
		"shell_collision_proxies": shell_runtime.collision_proxy_count(),
		"semantic_interactions": semantic_runtime.get_child_count(),
		"world_drops": world_drop_runtime.active_drop_count(),
		"combat_effects": is_instance_valid(combat_effects),
		"zombies": get_tree().get_nodes_in_group(&"voxel_zombies").size(),
		"survivors": get_tree().get_nodes_in_group(&"survivors").size(),
		"player_is_3d": player is CharacterBody3D,
		"camera_orthographic": camera.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"hud_visible": hud.visible,
		"survivor_inspector": is_instance_valid(survivor_inspector),
		"debug_overlay": is_instance_valid(debug_overlay),
		"collision_chunks": stream_controller.metrics().collision_chunks,
		"generation": generation_queue.metrics() if generation_queue != null else {},
		"transition_wait_frames": _transition_wait_frames,
		"maximum_transition_usec": maximum_transition_usec,
	}


func _generate_chunk(coordinate: Vector2i) -> Dictionary:
	var city: Dictionary
	if city_models.has(coordinate):
		city = (city_models[coordinate] as Dictionary).duplicate(true)
	else:
		city = CITY_GENERATOR.new().generate_streamed_chunk(world_seed, coordinate)
		city_models[coordinate] = city.duplicate(true)
	var generated_world = VOXELIZER.new().voxelize_chunk(city, world_seed, coordinate)
	world_data.merge_chunk_world(generated_world)
	world_data.apply_overrides_to_chunk(coordinate)
	return city


func _provide_render_chunk(coordinate: Vector2i):
	if world_data.get_chunk(coordinate) == null:
		if generation_queue == null or not generation_queue.has_ready(coordinate):
			return null
		var payload: Dictionary = generation_queue.take_ready(coordinate)
		_integrate_payload(coordinate, payload)
	var source = world_data.get_chunk(coordinate)
	var filtered = CHUNK_DATA.new(coordinate)
	for cell in source.cells:
		var cell_source: StringName = source.source_at(cell)
		var source_record: Dictionary = world_data.get_stable_object(cell_source) if cell_source != &"" else {}
		var kind := StringName(source_record.get("kind", &""))
		if int(source.cells[cell]) == MATERIALS.Id.ROOF or kind in [&"door", &"window", &"building"]:
			continue
		filtered.set_cell(cell, int(source.cells[cell]), cell_source)
	return filtered


func _request_chunk_generation(coordinate: Vector2i) -> void:
	if world_data.get_chunk(coordinate) != null:
		return
	generation_queue.request(coordinate)


func _integrate_payload(coordinate: Vector2i, payload: Dictionary) -> void:
	var city: Dictionary = payload.get("city", {})
	var generated_world = payload.get("world")
	city_models[coordinate] = city.duplicate(true)
	world_data.merge_chunk_world(generated_world)
	world_data.apply_overrides_to_chunk(coordinate)


func _on_chunk_loaded(coordinate: Vector2i) -> void:
	var renderer: Node = stream_controller.loaded_chunks[coordinate]
	structural_damage_service.register_renderer(coordinate, renderer, BASE_MATERIALS, false, &"", BASE_EXCLUDED_KINDS)
	shell_runtime.request_chunk(coordinate)
	if coordinate == current_chunk_coordinate:
		_activate_chunk_runtime(coordinate)


func _on_chunk_unloaded(coordinate: Vector2i) -> void:
	structural_damage_service.unregister_coordinate(coordinate)
	shell_runtime.cancel_chunk(coordinate)
	shell_runtime.clear_chunk(coordinate)
	_deactivate_chunk_runtime(coordinate)
	world_data.remove_chunk(coordinate)
	city_models.erase(coordinate)


func _spawn_zombies(coordinate: Vector2i = Vector2i.ZERO) -> int:
	var sampler = SPAWN_SAMPLER.new()
	sampler.configure(navigation)
	var spawned := 0
	var city: Dictionary = city_models.get(coordinate, origin_city)
	for region_variant in city.get("spawn_regions", []):
		if spawned >= zombie_population:
			break
		var position: Vector3 = sampler.sample_region(region_variant, coordinate, world_seed + coordinate.x * 193 + coordinate.y * 389 + spawned * 97)
		if position == Vector3.INF or position.distance_to(player.global_position) < 8.0:
			continue
		var zombie = ZOMBIE_SCENE.instantiate()
		zombie.position = position
		actors.add_child(zombie)
		zombie.configure_navigation(navigation)
		spawned += 1
	return spawned


func _spawn_survivors() -> void:
	for index in range(SURVIVOR_PROFILES.size()):
		var survivor = SURVIVOR_SCENE.instantiate()
		survivor.position = _nearby_walkable(player.global_position, index + 1)
		actors.add_child(survivor)
		survivor.configure_navigation(navigation, world_data, semantic_job_board, settlement_runtime)
		survivor.setup(SURVIVOR_PROFILES[index])


func _nearby_walkable(origin: Vector3, ordinal: int) -> Vector3:
	for radius in range(2, 12):
		for offset in [Vector2i(radius, ordinal), Vector2i(-radius, ordinal), Vector2i(ordinal, radius), Vector2i(ordinal, -radius)]:
			var cell := Vector3i(floori(origin.x) + offset.x, 0, floori(origin.z) + offset.y)
			if navigation.is_walkable(cell):
				return COORDINATES.world_cell_to_world_position(cell) + Vector3(0.5, 1.0, 0.5)
	return origin


func _try_select_survivor_screen(screen_position: Vector2) -> void:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	if absf(ray_direction.y) <= 0.0001:
		return
	var distance := (1.0 - ray_origin.y) / ray_direction.y
	if distance < 0.0:
		return
	_select_survivor_at_world_position(ray_origin + ray_direction * distance)


func _select_survivor_at_world_position(world_position: Vector3) -> void:
	var best: Node3D = null
	var best_distance := 1.6
	for node in get_tree().get_nodes_in_group(&"survivors"):
		if not node is Node3D:
			continue
		var distance := Vector2(world_position.x, world_position.z).distance_to(Vector2(node.global_position.x, node.global_position.z))
		if distance < best_distance:
			best = node
			best_distance = distance
	if best != null:
		GameEvents.survivor_selected.emit(best)


func _transition_to_chunk(coordinate: Vector2i) -> void:
	if coordinate == current_chunk_coordinate:
		return
	var started_at := Time.get_ticks_usec()
	for zombie in get_tree().get_nodes_in_group(&"voxel_zombies"):
		if is_instance_valid(zombie):
			zombie.queue_free()
	current_chunk_coordinate = coordinate
	_activate_chunk_runtime(coordinate)
	generation_queue.update_persistent_state({
		"door_states": WorldState.door_states.duplicate(),
		"prop_states": WorldState.prop_states.duplicate(true),
	})
	stream_controller.set_center(coordinate)
	generation_queue.retain_only(stream_controller.desired_coordinates())
	for survivor in get_tree().get_nodes_in_group(&"survivors"):
		if not is_instance_valid(survivor) or not survivor is Node3D:
			continue
		survivor.utility_ai.stop()
		survivor.configure_navigation(navigation, world_data, semantic_job_board, settlement_runtime)
		survivor.global_position = _nearby_walkable(player.global_position, int(survivor.data.id))
		survivor.utility_ai.begin(survivor.data)
	var spawned := _spawn_zombies(coordinate)
	GameEvents.zombie_count_changed.emit(spawned)
	maximum_transition_usec = maxi(maximum_transition_usec, Time.get_ticks_usec() - started_at)
	_last_safe_player_position = player.global_position
	_update_boundary_collision()


func _update_boundary_collision() -> void:
	var coordinates: Array[Vector2i] = [current_chunk_coordinate]
	var cell := COORDINATES.world_position_to_world_cell(player.global_position)
	var local := COORDINATES.world_cell_to_local(cell, current_chunk_coordinate)
	var margin := 3
	var candidates: Array[Vector2i] = []
	if local.x >= COORDINATES.HALF_CHUNK_CELLS - margin:
		candidates.append(current_chunk_coordinate + Vector2i.RIGHT)
	if local.x < -COORDINATES.HALF_CHUNK_CELLS + margin:
		candidates.append(current_chunk_coordinate + Vector2i.LEFT)
	if local.z >= COORDINATES.HALF_CHUNK_CELLS - margin:
		candidates.append(current_chunk_coordinate + Vector2i.DOWN)
	if local.z < -COORDINATES.HALF_CHUNK_CELLS + margin:
		candidates.append(current_chunk_coordinate + Vector2i.UP)
	for coordinate in candidates:
		if stream_controller.is_loaded(coordinate):
			coordinates.append(coordinate)
			_activate_chunk_runtime(coordinate)
	stream_controller.set_collision_coordinates(coordinates)
	shell_runtime.set_collision_coordinates(coordinates)


func _activate_chunk_runtime(coordinate: Vector2i) -> void:
	if _runtime_coordinates.has(coordinate) or world_data.get_chunk(coordinate) == null:
		return
	roof_runtime.populate_chunk(world_data, coordinate, roof_occlusion, structural_damage_service)
	semantic_runtime.populate_chunk(world_data, structural_damage_service, coordinate)
	_runtime_coordinates[coordinate] = true


func _deactivate_chunk_runtime(coordinate: Vector2i) -> void:
	if not _runtime_coordinates.has(coordinate):
		return
	roof_runtime.clear_chunk(coordinate, roof_occlusion)
	semantic_runtime.clear_chunk(coordinate)
	_runtime_coordinates.erase(coordinate)


func _on_building_cutaway(building_id: StringName, active: bool) -> void:
	var bounds: Array = world_data.get_stable_object(building_id).get("state", {}).get("bounds", [])
	if bounds.size() != 4:
		return
	var front_sides: Array[StringName] = shell_runtime.front_sides()
	for door in semantic_runtime.get_children():
		if not (door is Area3D and "stable_id" in door):
			continue
		var record: Dictionary = world_data.get_stable_object(door.stable_id)
		if StringName(record.get("kind", &"")) != &"door":
			continue
		if StringName((record.get("state", {}) as Dictionary).get("building", &"")) != building_id:
			continue
		var side := _door_side(door.global_position, bounds)
		_tween_door_visual(door, active and (side == &"" or side in front_sides))


func _door_side(position: Vector3, bounds: Array) -> StringName:
	if position.x <= float(bounds[0]) + 1.5:
		return &"west"
	if position.x >= float(bounds[2]) - 0.49:
		return &"east"
	if position.z >= float(bounds[3]) - 0.49:
		return &"south"
	if position.z <= float(bounds[1]) + 1.5:
		return &"north"
	return &""


func _tween_door_visual(door: Node3D, lowered: bool) -> void:
	var visual: Node3D = door.get_node_or_null("DoorVisual")
	if visual == null:
		return
	var target_scale := SHELL_RUNTIME_SCRIPT.CUT_SCALE_Y if lowered else 1.0
	if visual.has_meta("cutaway_tween"):
		var existing: Tween = visual.get_meta("cutaway_tween")
		if existing != null and existing.is_valid():
			existing.kill()
	if is_equal_approx(visual.scale.y, target_scale):
		return
	var tween := create_tween()
	tween.tween_property(visual, "scale:y", target_scale, SHELL_RUNTIME_SCRIPT.CUT_TWEEN_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	visual.set_meta("cutaway_tween", tween)


func _exit_tree() -> void:
	if generation_queue != null:
		generation_queue.shutdown()


func _on_zombie_died(_zombie: Node3D, _position: Vector3) -> void:
	kill_count += 1
	GameEvents.zombie_count_changed.emit(maxi(0, get_tree().get_nodes_in_group(&"voxel_zombies").size() - 1))
	GameEvents.kill_count_changed.emit(kill_count)


func _on_player_died() -> void:
	pause_menu.can_pause = false
	get_tree().paused = true
	death_overlay.open()


func _restart_game() -> void:
	get_tree().paused = false
	NoiseManager.reset()
	UrbanNavigationService.reset()
	WorldState.reset()
	WorldState.world_flags[&"city_seed"] = world_seed
	SimulationClock.reset()
	get_tree().reload_current_scene()


func _parse_capture_argument() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-voxel-main="):
			_capture_path = argument.trim_prefix("--capture-voxel-main=")
		elif argument.begins_with("--capture-voxel-main-chunk="):
			var parts := argument.trim_prefix("--capture-voxel-main-chunk=").split(",")
			if parts.size() == 2:
				_capture_chunk = Vector2i(int(parts[0]), int(parts[1]))
				_capture_chunk_requested = true
		elif argument == "--capture-voxel-main-inspector":
			_capture_inspector = true
		elif argument == "--capture-voxel-main-drop":
			_capture_drop = true
		elif argument == "--capture-voxel-main-effects":
			_capture_effects = true
		elif argument == "--capture-voxel-main-mobile":
			_capture_mobile = true
		elif argument == "--capture-voxel-main-interior":
			_capture_interior = true
