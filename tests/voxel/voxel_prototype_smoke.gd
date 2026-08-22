extends SceneTree

const AIM_PROJECTOR := preload("res://scripts/voxel/voxel_aim_projector.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")

var _failed := false


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/prototypes/VoxelIsometricPrototype.tscn")
	if scene == null:
		_assert(false, "prototype scene failed to load")
		_finish()
		return
	var prototype = scene.instantiate()
	root.add_child(prototype)
	await process_frame
	await physics_frame
	var contract: Dictionary = prototype.prototype_contract()
	_assert(int(contract.voxel_count) > 625, "voxel world includes ground and building")
	_assert(int(contract.visible_faces) > 0, "hidden-face pass produces visible faces")
	_assert(int(contract.mesh_build.vertex_count) == int(contract.visible_faces) * 6, "single-pass mesh metrics account for six vertices per visible quad")
	_assert(int(contract.mesh_build.rebuild_usec) > 0, "chunk renderer records its measured rebuild cost")
	_assert(int(contract.mesh_surfaces) == 4, "one merged mesh surface exists per used world material")
	_assert(int(contract.roof_voxel_count) == 42, "roof voxels use a separately hideable merged chunk")
	_assert(int(contract.roof_mesh_surfaces) == 1, "roof chunk has one merged material surface")
	_assert(bool(contract.has_collision), "merged voxel collision exists")
	_assert(bool(contract.camera_orthographic), "camera is orthographic")
	_assert(bool(contract.has_hud), "playable voxel scene instances the existing signal-driven HUD")
	_assert((contract.camera_zoom_bounds as Array) == [18.0, 42.0], "orthographic camera exposes bounded presentation zoom")
	_assert(bool(contract.roof_uses_stable_bounds), "roof visibility is driven by stable building bounds")
	_assert(bool(contract.player_is_3d), "player uses CharacterBody3D")
	_assert(bool(contract.zombie_is_3d), "zombie uses CharacterBody3D")
	_assert(bool(contract.survivor_is_3d) and int(contract.survivor_id) > 0, "3D survivor retains a registered SurvivorData identity")
	_assert(String(contract.survivor_weapon) == "Sidearm Pistol", "3D survivor combat reuses the existing pistol WeaponData")
	_assert(float(contract.player_health) == 100.0, "3D player reuses HealthComponent")
	_assert(int(contract.weapon_slots) == 2, "3D player owns two persistent weapon slots")
	_assert(int(contract.projectile_pool) == 32, "3D projectile pool prewarms its bounded capacity")
	_assert(not String(contract.world_fingerprint).is_empty(), "prototype world exposes a deterministic fingerprint")
	_assert(prototype.voxel_navigation != null and prototype.voxel_navigation.is_walkable(Vector3i(-5, 0, -6)), "3D zombie receives the shared voxel navigation grid")

	_test_camera_ray_aim(prototype)
	_test_camera_and_hud(prototype)
	_test_weapon_health_and_pool(prototype)
	await _test_interactions(prototype)
	_test_roof_visibility(prototype)
	_test_structural_damage(prototype)
	_test_explosive_projectile(prototype)
	_finish()


func _test_camera_ray_aim(prototype) -> void:
	var direction: Vector3 = AIM_PROJECTOR.ground_direction(prototype.camera, prototype.player.global_position, Vector2.RIGHT, Vector3.FORWARD)
	_assert(is_zero_approx(direction.y) and is_equal_approx(direction.length(), 1.0), "camera ray produces a normalized ground-plane aim direction")
	_assert(direction != Vector3.FORWARD, "screen-right aim is projected through the isometric camera")


func _test_camera_and_hud(prototype) -> void:
	_assert(prototype.hud.health_label.text == "HP: 100 / 100", "voxel player health initializes the existing HUD")
	_assert(prototype.hud.weapon_label.text.contains("SMG-9"), "voxel weapon state initializes the existing HUD")
	_assert(prototype.hud.zombie_count_label.text == "Zombies: 1", "voxel actor count initializes the existing HUD")
	var initial_rig_position: Vector3 = prototype.camera_rig.global_position
	prototype.player.global_position += Vector3(6.0, 0.0, 0.0)
	var distance_before: float = prototype.camera_rig.global_position.distance_to(prototype.player.global_position)
	prototype.camera_rig._process(0.1)
	_assert(prototype.camera_rig.global_position.distance_to(prototype.player.global_position) < distance_before, "camera rig smoothly follows the voxel player")
	prototype.player.global_position = initial_rig_position
	prototype.camera_rig.global_position = initial_rig_position
	prototype.camera.size = 30.0
	root.get_node("InputRouter").request_camera_zoom(-1.0)
	_assert(prototype.camera.size == 28.0, "InputRouter zoom-in request changes orthographic size")
	prototype.camera_rig.zoom(-100.0)
	_assert(prototype.camera.size == 18.0, "camera zoom clamps to the configured near bound")
	prototype.camera_rig.zoom(100.0)
	_assert(prototype.camera.size == 42.0, "camera zoom clamps to the configured far bound")
	prototype.camera.size = 30.0


func _test_weapon_health_and_pool(prototype) -> void:
	var player = prototype.player
	_assert(player.weapon.data.weapon_name == "SMG-9", "slot one reuses the existing SMG WeaponData")
	var starting_ammo: int = player.weapon.ammo_in_magazine
	_assert(player.weapon.try_fire(Vector3.FORWARD), "equipped 3D SMG fires")
	_assert(player.weapon.ammo_in_magazine == starting_ammo - 1, "3D weapon firing consumes one magazine round")
	_assert(prototype.projectile_manager.active_projectile_count() == 1, "firing acquires one pooled 3D projectile")
	var active_projectile = null
	for projectile in prototype.projectile_manager.get_children():
		if projectile.active:
			active_projectile = projectile
	_assert(active_projectile != null, "active projectile remains addressable through the pool")
	if active_projectile != null:
		active_projectile._resolve_hit({"position": prototype.zombie.global_position, "collider": prototype.zombie, "normal": Vector3.BACK})
		active_projectile._release()
	_assert(prototype.projectile_manager.active_projectile_count() == 0, "released 3D projectile returns to the pool")
	_assert(prototype.zombie.health_component.current_health == 38.0, "3D projectile routes actor damage through the zombie HealthComponent")
	player.weapon.ammo_in_magazine = 0
	player.weapon.reserve_ammo = 5
	_assert(player.weapon.try_reload(), "3D weapon starts reload through the shared timing contract")
	player.weapon._process(player.weapon.data.reload_duration + 0.01)
	_assert(player.weapon.ammo_in_magazine == 5 and player.weapon.reserve_ammo == 0, "3D reload transfers the exact available reserve")
	player.weapon.ammo_in_magazine = 17
	player.weapon.reserve_ammo = 91
	_assert(player.equip_weapon_slot(1), "3D player equips the breaching-charge slot")
	_assert(player.weapon.data.weapon_name == "Breaching Charge", "slot two reuses explosive WeaponData")
	player.weapon.ammo_in_magazine = 0
	player.weapon.reserve_ammo = 2
	_assert(player.equip_weapon_slot(0), "3D player switches back to the SMG")
	_assert(player.weapon.ammo_in_magazine == 17 and player.weapon.reserve_ammo == 91, "3D weapon slots preserve independent ammunition")
	player.take_damage(25.0)
	_assert(player.health_component.current_health == 75.0, "3D player damage routes through HealthComponent")
	_assert(prototype.hud.health_label.text == "HP: 75 / 100", "voxel damage updates the existing HUD through GameEvents")
	player.respawn(Vector3(-5, 1.75, 5))
	_assert(player.health_component.current_health == 100.0 and player.weapon_slot_index == 0, "3D respawn resets health and selected weapon")
	_assert(prototype.hud.health_label.text == "HP: 100 / 100", "voxel respawn restores the HUD health display")


func _test_interactions(prototype) -> void:
	var door = prototype.get_node("Door")
	prototype.player.global_position = Vector3(7.0, 1.75, -1.0)
	await physics_frame
	await physics_frame
	_assert(prototype.hud.interact_prompt_panel.visible and prototype.hud.interact_prompt_label.text == "Open / close door", "voxel interaction candidates drive the existing HUD prompt")
	_assert(prototype.player.interactor.interact_best(), "Area3D interactor selects an overlapping door")
	_assert(door.is_open and door.get_node("CollisionShape3D").disabled, "door interaction opens and disables collision")
	var loot = prototype.get_node("LootCrate")
	prototype.player.global_position = Vector3(8.5, 1.75, -4.0)
	await physics_frame
	await physics_frame
	_assert(prototype.player.interactor.interact_best(), "Area3D interactor selects an overlapping loot crate")
	_assert(loot.searched, "loot interaction changes state exactly once")
	prototype.player.interactor.interact_best()
	_assert(loot.searched, "repeated loot interaction remains idempotent")


func _test_roof_visibility(prototype) -> void:
	prototype.player.global_position = Vector3(9, 1.75, -4)
	prototype._update_roof_visibility()
	_assert(not prototype.roof_chunk.visible, "roof hides while the player is inside")
	prototype.player.global_position = Vector3(-5, 1.75, 5)
	prototype._update_roof_visibility()
	_assert(prototype.roof_chunk.visible, "roof restores after the player exits")


func _test_structural_damage(prototype) -> void:
	var wall_cell := Vector3i(6, 1, -7)
	_assert(not prototype.structural_damage_service.apply_cell(wall_cell, 999.0, 0), "small-arms class cannot damage brick voxels")
	_assert(prototype.voxel_chunk_data.get_cell(wall_cell) == MATERIALS.Id.BRICK, "rejected structural hit leaves brick intact")
	_assert(prototype.structural_damage_service.apply_cell(wall_cell, 180.0, 2), "explosive class damages brick voxels")
	_assert(prototype.voxel_chunk_data.get_cell(wall_cell) == MATERIALS.Id.AIR, "zero-durability brick is removed from chunk data")
	var override: Dictionary = prototype.voxel_world_data.get_voxel_override(wall_cell)
	_assert(int(override.get("material_id", -1)) == MATERIALS.Id.AIR, "destroyed voxel persists as a sparse world override")
	_assert(prototype.chunk.collision_shape.shape != null, "structural removal rebuilds merged voxel collision")


func _test_explosive_projectile(prototype) -> void:
	var previous_overrides: int = prototype.voxel_world_data.voxel_overrides.size()
	var refreshes_before: int = prototype.structural_damage_service.renderer_refresh_count
	_assert(prototype.player.equip_weapon_slot(1), "breaching charge remains selectable for explosive projectile test")
	_assert(prototype.player.weapon.try_fire(Vector3.FORWARD), "breaching charge spawns a 3D explosive projectile")
	var explosive = null
	for projectile in prototype.projectile_manager.get_children():
		if projectile.active:
			explosive = projectile
			break
	_assert(explosive != null and is_equal_approx(explosive.explosion_radius, 4.0), "128px blast radius converts to four voxel world units")
	if explosive != null:
		explosive._resolve_hit({"position": Vector3(8.5, 2.0, -6.5), "collider": prototype.chunk, "normal": Vector3.BACK})
		explosive._release()
	_assert(prototype.voxel_explosion_events == 1, "3D explosion emits the dedicated Vector3 GameEvents signal")
	_assert(prototype.voxel_world_data.voxel_overrides.size() > previous_overrides, "3D explosion applies persistent structural voxel damage")
	_assert(prototype.structural_damage_service.renderer_refresh_count - refreshes_before == 2, "explosion batches all destroyed voxels into one refresh per registered chunk renderer")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("VOXEL_PROTOTYPE_SMOKE: FAIL: %s" % message)


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("VOXEL_PROTOTYPE_SMOKE: PASS")
	quit(0)
