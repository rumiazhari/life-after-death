class_name VoxelIsometricPrototype
extends Node3D

const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")
const CHUNK_DATA := preload("res://scripts/voxel/voxel_chunk_data.gd")
const WORLD_DATA := preload("res://scripts/voxel/voxel_world_data.gd")
const NAVIGATION := preload("res://scripts/voxel/voxel_navigation_service.gd")
const SEMANTIC_JOB_BOARD := preload("res://scripts/voxel/voxel_semantic_job_board.gd")
const SETTLEMENT_RUNTIME := preload("res://scripts/voxel/voxel_settlement_runtime.gd")
const MAT_GRASS := MATERIALS.Id.GRASS
const MAT_ROAD := MATERIALS.Id.ROAD
const MAT_PAVEMENT := MATERIALS.Id.PAVEMENT
const MAT_BRICK := MATERIALS.Id.BRICK
const MAT_ROOF := MATERIALS.Id.ROOF

@onready var chunk = $VoxelChunk
@onready var roof_chunk = $RoofChunk
@onready var player = $Actors/Player
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var camera_rig = $CameraRig
@onready var roof_occlusion = $RoofOcclusionController
@onready var hud: HUD = $HUD
@onready var zombie = $Actors/Zombie
@onready var survivor = $Actors/Survivor
@onready var projectile_manager = $ProjectileManager
@onready var structural_damage_service = $StructuralDamageService

var _capture_path := ""
var _capture_frames := 0
var voxel_world_data
var voxel_chunk_data
var voxel_explosion_events := 0
var voxel_navigation
var voxel_semantic_job_board
var voxel_settlement_runtime
var voxel_kill_count := 0


func _ready() -> void:
	voxel_chunk_data = CHUNK_DATA.new(Vector2i.ZERO)
	var base_cells := _build_voxels()
	for cell in base_cells:
		voxel_chunk_data.set_cell(cell, base_cells[cell])
	var roof_cells := _build_roof_voxels()
	for cell in roof_cells:
		voxel_chunk_data.set_cell(cell, roof_cells[cell], &"prototype/building")
	voxel_world_data = WORLD_DATA.new(20260822)
	voxel_world_data.add_chunk(voxel_chunk_data)
	voxel_world_data.register_stable_object(&"prototype/building", &"building", Vector3i(8, 1, -4), {
		"bounds": [6, -7, 11, -1],
		"roof_height": 4,
	})
	structural_damage_service.configure(voxel_world_data)
	voxel_navigation = NAVIGATION.new()
	voxel_navigation.configure(voxel_world_data)
	voxel_semantic_job_board = SEMANTIC_JOB_BOARD.new()
	voxel_semantic_job_board.configure(voxel_world_data)
	voxel_settlement_runtime = SETTLEMENT_RUNTIME.new()
	voxel_settlement_runtime.configure(voxel_world_data)
	var base_materials: Array[int] = [MAT_GRASS, MAT_ROAD, MAT_PAVEMENT, MAT_BRICK, MATERIALS.Id.DIRT, MATERIALS.Id.COBBLE, MATERIALS.Id.FLOOR, MATERIALS.Id.GLASS, MATERIALS.Id.WOOD]
	var roof_materials: Array[int] = [MAT_ROOF]
	structural_damage_service.register_renderer(Vector2i.ZERO, chunk, base_materials)
	structural_damage_service.register_renderer(Vector2i.ZERO, roof_chunk, roof_materials)
	player.camera = camera
	camera_rig.configure(player)
	roof_occlusion.configure(voxel_world_data, player)
	roof_occlusion.register_roof(&"prototype/building", roof_chunk)
	zombie.configure_navigation(voxel_navigation)
	survivor.configure_navigation(voxel_navigation, voxel_world_data, voxel_semantic_job_board, voxel_settlement_runtime)
	survivor.setup({"name": "Mara", "movement_speed": 190.0})
	projectile_manager.damage_service = structural_damage_service
	GameEvents.voxel_environment_explosion.connect(_on_voxel_environment_explosion)
	GameEvents.voxel_zombie_died.connect(_on_voxel_zombie_died)
	GameEvents.player_health_changed.emit(player.health_component.current_health, player.health_component.max_health)
	GameEvents.zombie_count_changed.emit(1)
	GameEvents.kill_count_changed.emit(voxel_kill_count)
	player.call_deferred(&"_emit_equipped_weapon")
	_parse_capture_argument()


func _process(_delta: float) -> void:
	_update_roof_visibility()
	if _capture_path.is_empty():
		return
	_capture_frames += 1
	if _capture_frames < 8:
		return
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("VOXEL_CAPTURE requires a rendering display driver")
		get_tree().quit(1)
		_capture_path = ""
		return
	var result := image.save_png(_capture_path)
	print("VOXEL_CAPTURE path=%s result=%s" % [_capture_path, error_string(result)])
	get_tree().quit(0 if result == OK else 1)


func prototype_contract() -> Dictionary:
	return {
		"voxel_count": chunk.voxels.size(),
		"visible_faces": chunk.visible_face_count(),
		"mesh_build": chunk.build_metrics(),
		"mesh_surfaces": chunk.mesh_instance.mesh.get_surface_count() if chunk.mesh_instance.mesh != null else 0,
		"roof_voxel_count": roof_chunk.voxels.size(),
		"roof_mesh_surfaces": roof_chunk.mesh_instance.mesh.get_surface_count() if roof_chunk.mesh_instance.mesh != null else 0,
		"has_collision": chunk.collision_shape.shape != null,
		"camera_orthographic": camera.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"camera_zoom_bounds": [camera_rig.minimum_size, camera_rig.maximum_size],
		"roof_uses_stable_bounds": voxel_world_data.get_stable_object(&"prototype/building").get("state", {}).get("bounds", []).size() == 4,
		"has_hud": is_instance_valid(hud),
		"player_is_3d": player is CharacterBody3D,
		"zombie_is_3d": zombie is CharacterBody3D,
		"survivor_is_3d": survivor is CharacterBody3D,
		"survivor_id": survivor.data.id,
		"survivor_weapon": survivor.weapon.data.weapon_name,
		"player_health": player.health_component.current_health,
		"weapon_slots": player.weapon_slots.size(),
		"projectile_pool": projectile_manager.pool_capacity(),
		"world_fingerprint": voxel_world_data.fingerprint(),
	}


func _build_voxels() -> Dictionary:
	var cells: Dictionary = {}
	for x in range(-12, 13):
		for z in range(-12, 13):
			var material := MAT_GRASS
			if absi(x) <= 2:
				material = MAT_ROAD
			elif absi(x) <= 4:
				material = MAT_PAVEMENT
			cells[Vector3i(x, 0, z)] = material
	# Enterable building east of the road. The south wall has a two-cell door gap.
	for y in range(1, 4):
		for x in range(6, 12):
			cells[Vector3i(x, y, -7)] = MAT_BRICK
			if not (x in [8, 9] and y <= 2):
				cells[Vector3i(x, y, -1)] = MAT_BRICK
		for z in range(-6, -1):
			cells[Vector3i(6, y, z)] = MAT_BRICK
			cells[Vector3i(11, y, z)] = MAT_BRICK
	return cells


func _build_roof_voxels() -> Dictionary:
	var cells: Dictionary = {}
	for x in range(6, 12):
		for z in range(-7, 0):
			cells[Vector3i(x, 4, z)] = MAT_ROOF
	return cells


func _update_roof_visibility() -> void:
	roof_occlusion.update_visibility()


func _on_voxel_environment_explosion(_origin: Vector3, _radius: float) -> void:
	voxel_explosion_events += 1


func _on_voxel_zombie_died(_actor: Node3D, _position: Vector3) -> void:
	voxel_kill_count += 1
	GameEvents.zombie_count_changed.emit(get_tree().get_nodes_in_group(&"voxel_zombies").size() - 1)
	GameEvents.kill_count_changed.emit(voxel_kill_count)


func _parse_capture_argument() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-voxel="):
			_capture_path = argument.trim_prefix("--capture-voxel=")
