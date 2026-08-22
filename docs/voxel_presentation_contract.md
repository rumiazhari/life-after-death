# Voxel presentation contract

`VoxelIsometricPrototype.tscn` now uses the production `HUD.tscn` instead of a prototype-only status overlay. `VoxelIsometricPrototype` initializes player health, equipped weapon, active-zombie count, and kill count through the existing `GameEvents` signals. The existing `VoxelInteractor3D` continues to publish `interact_prompt_changed`, so the same HUD prompt displays 3D door and loot interactions.

`VoxelIsometricCameraRig` owns orthographic camera follow and zoom. It follows the configured `Node3D` target with frame-rate-independent exponential smoothing and clamps camera size to 18 through 42 world units. Mouse-wheel input enters through `InputRouter.camera_zoom_requested`; the mobile `−` and `+` buttons call `InputRouter.request_camera_zoom()` without coupling the touch UI to the camera node.

`VoxelRoofOcclusionController3D` maps stable building IDs to independently hideable roof renderers. It reads the building's world-space `[min_x, min_z, max_x, max_z]` bounds from `VoxelWorldData` rather than carrying scene-specific rectangles. `SemanticVoxelizer` writes those bounds for every generated building, and the prototype registers the same state contract for its authored test building.

## Building shell cutaway (`VoxelBuildingShellRuntime`)

Walls no longer render from the merged base chunk. `SemanticVoxelizer` links every window and door stable object to its owning building (`"building"` state field), and `VoxelBuildingShellRuntime` extracts BRICK, GLASS, and boarded-window BOARD voxels into per-building shell roots grouped into three runs: `front` (camera-facing perimeter), `back` (rear perimeter plus corner posts), and `interior` (partitions). Generated buildings use a uniform three-cell wall height so skylines stay consistent, and boarded windows use the distinct BOARD material instead of WOOD.

When the tracked actor stands inside a building's stable bounds, the occlusion controller hides that building's roof and lowers the `front` and `interior` runs to `CUT_SCALE_Y` (0.34) with a short tween, while `back` runs and corner posts keep full height -- Project-Zomboid-style cutaway. Exiting restores everything. Because the production camera has a fixed 45-degree yaw, the front/back split is resolved once per populate from the camera basis (defaulting to east/south); a free-rotating camera would need geometry re-splitting before lowering.

Wall collision never lowers: each chunk that joins the active collision set lazily builds a hidden `WallCollision_*` proxy renderer containing all wall/window voxels at full height. Both shell runs and proxies register with `VoxelStructuralDamageService` through cell filters keyed on stable-object kind, so explosive damage still opens holes in the correct renderer and the matching collision shape rebuilds together. Shell population is spread by a bounded queue (`MAX_CHUNK_BUILDS_PER_FRAME = 2`) driven by stream load/unload events so chunk attachment stays inside the streaming frame budget.

`voxel_main_smoke.gd` verifies the origin collision proxy, cutaway engagement/restoration around generated bounds, camera-derived front sides, and building-linked window registration alongside the existing roof hide/restore checks.

`voxel_prototype_smoke.gd` verifies HUD initialization and updates, prompt delivery, smooth follow, both zoom clamps, and stable-bound roof visibility. The production `voxel_main_smoke.gd` emits both mobile zoom buttons and verifies the exact camera-size changes through `InputRouter`. `voxel_city_conversion_test.gd` verifies that every generated Prague building exposes valid occlusion bounds and that the bounds survive the existing version-2 world snapshot round trip.
