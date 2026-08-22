# Voxel city conversion

`SemanticVoxelizer` consumes the existing `ProceduralCityGenerator.generate_streamed_chunk()` dictionary. The 32-pixel semantic tile remains one voxel cell, and the existing 2816-pixel streamed chunk remains an 88-by-88 voxel chunk. Roads, block surfaces, compound building perimeters, room floors, partitions, door apertures, windows, furniture, exterior props, and scavenge points therefore retain the generator's current geometry and stable IDs.

`VoxelWorldData.stable_objects` stores each authored object's voxel anchor, semantic kind, and runtime state. Its version-2 snapshot preserves this data alongside chunk cells, building anchors, and structural overrides. `WorldState` remains authoritative for door open state, prop flags, and persistent loot inventories; regenerating a voxel chunk reads those existing dictionaries instead of reseeding an object.

`VoxelSemanticRuntime` creates 3D interaction areas for generated doors, loot, salvage props, and scavenge points. Door interaction updates every voxel in the authored aperture through `VoxelStructuralDamageService`, which rebuilds registered renderers. Loot uses the existing capacity-aware `Inventory.move_all_to()` path, and repeated interaction resolves the same `WorldState` container, preventing duplication.

Run `res://tests/voxel/VoxelCityConversionTest.tscn` for semantic coverage, persistence, door mutation, and exact loot-transfer checks. Run `res://scenes/prototypes/VoxelPragueStreamPreview.tscn` to inspect two adjacent generated Prague chunks and their shared streamed boundary. The conversion prototype remains a focused fixture; production now launches `VoxelMain.tscn` and uses the same semantic conversion through its bounded background-prefetch queue.
