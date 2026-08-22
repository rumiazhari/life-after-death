# Voxel world contract

This document describes the implemented renderer-independent voxel data layer.
It does not switch the production `Main.tscn` or replace the current 2D
procedural renderer.

## Coordinates

`VoxelCoordinates` is the only conversion boundary. The existing procedural
world uses 32-pixel semantic tiles and `StreamingWorld.CHUNK_SIZE` is
2,816 pixels, producing 88 horizontal voxel cells per streamed chunk. Chunk
coordinates remain centered on their existing scene origins: chunk `(0, 0)`
owns world cells `-44..43` on both horizontal axes, `(1, 0)` begins at `x=44`,
and `(-1, 0)` ends at `x=-45`.

Semantic `Vector2(x, y)` maps to 3D `Vector3(x, elevation, z)`. Integer
`Vector3i` world cells are persistence coordinates. A cell's persistent key is
`voxel/<x>/<y>/<z>` and never contains a node path, mesh index, or load order.

## Materials

`VoxelMaterialRegistry` owns the numeric material IDs and their gameplay
properties. ID `0` is always air. Ground, road, pavement, brick, roof, dirt,
cobble, floor, glass, and wood are currently defined. The same registry builds
the prototype's `StandardMaterial3D` resources, keeping data IDs and render
surface indices aligned.

## Chunk and world data

`VoxelChunkData` stores local `Vector3i -> material ID` cells plus optional
stable semantic ownership for structural cells. Its snapshot is composed only
of sorted arrays, numbers, and strings. The SHA-256 fingerprint therefore does
not depend on dictionary iteration order.

`VoxelWorldData` owns chunks, stable semantic object anchors, and sparse voxel
overrides. An override records a changed material and remaining durability by
stable world-cell ID; generated base terrain does not need to be duplicated in
save data. Snapshot version `1` rejects incompatible versions instead of
silently interpreting them.

`VoxelWorldStateAdapter` stores the versioned voxel snapshot under
`WorldState.world_flags["voxel_world_snapshot"]`. This makes it part of the
existing `WorldState.to_snapshot()` result without modifying the dirty
`world_state.gd` implementation. It can restore either from live world flags or
from a previously produced full `WorldState` snapshot.

## Semantic conversion

`SemanticVoxelizer.voxelize_chunk()` consumes the dictionaries already emitted
by `ProceduralCityGenerator.generate_streamed_chunk()`. Roads and block
surfaces become ground materials. Building `footprint`, `stable_id`,
`entrance_position`, and `projected_exterior.projection_height_tiles` fields
become owned brick walls, roof cells, entrance clearance, and one stable world
anchor per building.

The current conversion is deliberately limited to terrain and exterior
building volumes. Rooms, partitions, doors, windows, furniture, and structural
damage application remain part of the later world/building migration milestone.

## Verification

`tests/voxel/VoxelWorldContractTest.tscn` checks negative and positive chunk
boundaries, coordinate round trips, deterministic fingerprints, snapshot
round trips, semantic ownership, sparse destruction overrides, `WorldState`
snapshot inclusion, different-seed divergence, and matching east-west road
portal rasterization between adjacent streamed chunks.
