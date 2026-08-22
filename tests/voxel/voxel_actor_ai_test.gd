extends Node

const WORLD_DATA := preload("res://scripts/voxel/voxel_world_data.gd")
const CHUNK_DATA := preload("res://scripts/voxel/voxel_chunk_data.gd")
const NAVIGATION := preload("res://scripts/voxel/voxel_navigation_service.gd")
const PERCEPTION := preload("res://scripts/voxel/voxel_zombie_perception_3d.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")

var _failed := false


func _ready() -> void:
	WorldState.reset()
	NoiseManager.reset()
	_test_voxel_perception()
	await _test_survivor_persistence()
	WorldState.reset()
	NoiseManager.reset()
	if _failed:
		get_tree().quit(1)
	else:
		print("VOXEL_ACTOR_AI: PASS")
		get_tree().quit(0)


func _test_voxel_perception() -> void:
	var world = WORLD_DATA.new(42)
	var chunk = CHUNK_DATA.new(Vector2i.ZERO)
	for z in range(-6, 7):
		for x in range(-6, 7):
			chunk.set_cell(Vector3i(x, 0, z), MATERIALS.Id.FLOOR)
	for z in range(-6, 7):
		chunk.set_cell(Vector3i(0, 1, z), MATERIALS.Id.BRICK)
		chunk.set_cell(Vector3i(0, 2, z), MATERIALS.Id.BRICK)
	world.add_chunk(chunk)
	var navigation = NAVIGATION.new()
	navigation.configure(world)
	var zombie := CharacterBody3D.new()
	zombie.position = Vector3(-3.5, 1.0, 0.5)
	add_child(zombie)
	var perception = PERCEPTION.new()
	zombie.add_child(perception)
	perception.configure(navigation)
	var target := CharacterBody3D.new()
	target.position = Vector3(3.5, 1.0, 0.5)
	target.add_to_group(&"attackable")
	add_child(target)
	perception.update(0.3, Vector3.RIGHT)
	perception.update(0.3, Vector3.RIGHT)
	_assert(perception.target == null, "voxel zombie sight is blocked by occupied headroom cells")
	chunk.set_cell(Vector3i(0, 1, 0), MATERIALS.Id.AIR)
	chunk.set_cell(Vector3i(0, 2, 0), MATERIALS.Id.AIR)
	perception.update(0.3, Vector3.RIGHT)
	perception.update(0.3, Vector3.RIGHT)
	_assert(perception.target == target and perception.state == PERCEPTION.State.CHASE, "voxel zombie acquires and chases a target through an open aperture")
	target.remove_from_group(&"attackable")
	perception.target = null
	perception.state = PERCEPTION.State.IDLE
	NoiseManager.emit_noise(Vector2(2.0, 0.5), 2.0, &"test", target)
	perception.update(0.3, Vector3.RIGHT)
	_assert(perception.state == PERCEPTION.State.INVESTIGATE and perception.movement_goal() != Vector3.INF, "3D hearing converts the existing bounded noise event into an investigate goal")
	remove_child(target)
	target.free()
	remove_child(zombie)
	zombie.free()


func _test_survivor_persistence() -> void:
	var packed: PackedScene = load("res://scenes/prototypes/VoxelIsometricPrototype.tscn")
	var prototype = packed.instantiate()
	add_child(prototype)
	await get_tree().process_frame
	var survivor = prototype.survivor
	var stable_id: int = survivor.data.id
	survivor.health_component.invulnerability_duration = 0.0
	survivor.take_damage(10.0)
	_assert(is_equal_approx(survivor.data.fear, 5.0), "3D survivor mirrors damage into persistent fear")
	survivor.carried_inventory.add_item(&"materials", 4)
	survivor.take_damage(500.0)
	await get_tree().process_frame
	_assert(WorldState.survivors.has(stable_id) and WorldState.survivors[stable_id].is_dead, "dead 3D survivor data remains registered under its stable id")
	_assert(WorldState.drops.size() == 1, "dead 3D survivor creates one persistent inventory drop")
	if WorldState.drops.size() == 1:
		var drop: WorldDrop = WorldState.drops.values()[0]
		_assert(drop.inventory.get_count(&"materials") == 4, "3D survivor death preserves the exact carried stack")
	prototype.queue_free()
	await get_tree().process_frame


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("VOXEL_ACTOR_AI: FAIL: %s" % message)
