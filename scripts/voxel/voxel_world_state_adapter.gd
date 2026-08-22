class_name VoxelWorldStateAdapter
extends RefCounted

const SNAPSHOT_KEY := &"voxel_world_snapshot"
const WORLD_DATA_SCRIPT := preload("res://scripts/voxel/voxel_world_data.gd")


static func store(world_data) -> void:
	WorldState.world_flags[SNAPSHOT_KEY] = world_data.to_snapshot()


static func restore():
	var snapshot: Dictionary = WorldState.world_flags.get(SNAPSHOT_KEY, {})
	if snapshot.is_empty():
		return null
	return WORLD_DATA_SCRIPT.from_snapshot(snapshot)


static func restore_from_world_state_snapshot(world_state_snapshot: Dictionary):
	var flags: Dictionary = world_state_snapshot.get("world_flags", {})
	var snapshot: Dictionary = flags.get(SNAPSHOT_KEY, {})
	if snapshot.is_empty():
		return null
	return WORLD_DATA_SCRIPT.from_snapshot(snapshot)


static func clear() -> void:
	WorldState.world_flags.erase(SNAPSHOT_KEY)
