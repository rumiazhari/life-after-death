# Voxel performance budget

`VoxelChunk.rebuild()` performs one pass over occupied cells, routes exposed faces into one `SurfaceTool` per used material, and emits one merged surface per material. Its `build_metrics()` report records voxel, face, vertex, surface, rebuild-time, and collision state values. Hidden faces remain absent and each exposed quad accounts for exactly six vertices.

`VoxelStructuralDamageService.apply_explosion()` encloses cell damage in a refresh batch. Every affected chunk coordinate is rebuilt once at batch completion, so a blast cost depends on affected renderers rather than the number of destroyed voxels. Direct single-cell edits still refresh immediately.

`VoxelChunkStreamController` owns the runtime working set. Its default radius queues a 3-by-3 visual set, builds at most one queued chunk per frame, retains only the configured radius, and enables trimesh collision only on the active center chunk. A center shift keeps overlapping renderers and queues only the entering edge. The chunk provider is a `Callable`, keeping the streaming policy independent of Prague semantic generation.

Production uses `VoxelChunkGenerationQueue` ahead of that provider. Two worker threads perform deterministic Prague generation and semantic voxelization from copied persistence dictionaries; the main thread only merges a completed payload and attaches one renderer per frame. Roof and interaction nodes are activated for the center and loaded boundary destinations rather than every visual-prefetch chunk. `VoxelMain` records the worst renderer-attachment and transition-commit times; smoke coverage limits them to 150 milliseconds and 100 milliseconds respectively on the project test environment.

Expensive simulation queries already use explicit cadences in the voxel actors: zombie sight and hearing update every 0.25 seconds in `VoxelZombiePerception3D`, survivor utility decisions every 0.75 seconds in `VoxelSurvivorAI3D`, and survivor need changes every 1.0 second. Movement remains on physics frames.

`VoxelStreamingBudgetTest.tscn` verifies one-build-per-step scheduling, bounded retention, center-only collision, and no rebuilding of overlap chunks. `VoxelPraguePerformanceProfile.tscn` profiles the actual deterministic origin and east Prague chunks without collision; its safety limits are one second for a mesh build and three seconds for two chunks through generation, voxelization, and meshing.
