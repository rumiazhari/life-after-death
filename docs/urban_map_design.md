# Urban map design (Phase 3B, updated for Phase 3B.1)

Why the world is now one fixed, authored district instead of the
Phase 3A `ArenaBuilder` procedural test arena, how that district is built,
and where the pieces live.

**Phase 3B.1 update:** the district is now **baked, not runtime-built** --
see "Baked, not runtime-built" below, which supersedes this doc's original
"Layout" section wherever the two disagree. `DistrictBuilder` is now a
bake-time-only tool input, never attached to the scene that ships in
`Main.tscn`.

## Why fixed, not procedural

`ArenaBuilder` (kept, unused by `Main.tscn`) was always documented as "the
test arena, not a real level." Phase 3B's enterable buildings, persistent
per-room/per-door/per-prop state, and shared navigation grid all need
**stable identity**: a room, door, or shelf has to mean the same thing on
every run for `WorldState.door_states`/`prop_states`/`prop_containers` (and
`UrbanNavigationService`'s door-cell registry) to work at all. A
regenerated-per-seed layout can't give a shelf a stable id across runs;
an authored one can. This is also explicitly what the task spec asked
for: no runtime random building placement, no procedural street layout,
`ArenaBuilder` kept only as an optional/unused test scene.

## Baked, not runtime-built (Phase 3B.1)

`scenes/world/maps/UrbanDistrict01.tscn` is now **committed, authored
scene content** — real `[node]` entries for every TileMapLayer, building
instance, prop, door, window, spawn region, and scavenge point, all
editable/selectable/movable in the Godot editor exactly like any other
hand-built scene. Normal gameplay (`Main.tscn`) instances this file
directly and does **not** run any procedural construction at load time.

**How it's baked — `tools/bake_district.gd`.** A one-time headless tool
(`godot --headless --path . --script tools/bake_district.gd`) that:

1. Instantiates `DistrictBuilder` (`scripts/world/district_builder.gd`)
   directly from its script — not from a scene file, since
   `UrbanDistrict01.tscn` is this tool's own *output*, never a stable
   input to load from. The tool recreates the handful of empty child
   containers (`GroundLayers`, `Buildings`, `StreetProps`, `Navigation`,
   `SpawnRegions`, `Boundaries`) that `DistrictBuilder._ready()` expects
   to already exist and populates into.
2. Lets `_ready()` fully run (tiles painted, buildings instanced, props
   placed, doors/spawn regions/scavenge points created) — the exact same
   deterministic construction logic as before, just executed once, offline,
   instead of every time the game boots.
3. Reparents the resulting `ScavengePoint` instances -- plus the handful
   of street props that also need Y-sorting against actors (the abandoned
   and wrecked cars, the alley dumpster) -- into a `$DynamicEntities`
   container on the district root (so they get baked as part of this scene
   -- see `scripts/world/authored_district.gd` for why they move again,
   into the real Y-sorted `EntityContainer`, at actual runtime). Not named
   `$ScavengePoints`: it holds more than just scavenge points.
4. Detaches `district_builder.gd` and attaches the much smaller
   `scripts/world/authored_district.gd` in its place.
5. Marks every descendant node's `owner` (required for `PackedScene.pack()`
   to include a procedurally-`add_child()`-ed node at all) and saves the
   packed tree over `UrbanDistrict01.tscn`.

Re-run this exact command any time `district_builder.gd`'s layout
constants change, then update `DistrictLayoutChecksum`'s committed
baseline (`tests/test_runner.gd`) to match. Verified deterministic:
baking twice in a row and diffing the two `.tscn` files shows zero
differences outside Godot's own per-save `unique_id` annotations (opaque
editor bookkeeping, not gameplay-relevant).

**What still runs at actual game load time — `scripts/world/authored_district.gd`
(`AuthoredDistrict`, the script the baked scene ships with).** Only the
two things that genuinely cannot be serialized into a `.tscn`:

1. Reparenting `$DynamicEntities`' children into the real, Y-sorted
   `EntityContainer` (a `Main.tscn`-level node, found by group lookup —
   see "Scene organization" below for why it isn't nested under the
   district itself).
2. Building `UrbanNavigationService`'s `AStarGrid2D` from the district's
   now-live static collision (a physics-server query that only makes
   sense once this scene is actually instanced in a running tree) and
   registering doors with it.

`DistrictBuilder` itself (`scripts/world/district_builder.gd`) is
preserved, unchanged in its own construction logic, but is now **only**
the bake tool's input — it is never attached to any scene `Main.tscn`
loads.

## Scene organization

Child containers under the district root: `GroundLayers`, `Buildings`,
`StreetProps`, `Navigation`, `SpawnRegions`, `Boundaries`, and (Phase
3B.1) `DynamicEntities` (scavenge points plus the Y-sorted street props
listed above). `EntityContainer` (Y-sorted, Phase 3A.1) stays at
the `Main.tscn` level rather than under `UrbanDistrict01` — a deliberate
simplification so the existing Y-sort wiring (player/survivors/zombies as
its direct children) didn't need restructuring; these entities reach it
via `AuthoredDistrict`'s one-time reparent (see above) instead of a
group-lookup `add_child()` at construction time.

## Layout — `scripts/world/district_builder.gd`

Everything positional is a **literal `const`**, not a seeded random
choice:

- `ROADS` — 4 entries: one main road through the district (`(0,0)`,
  140 wide), two side streets (`(-500,0)` / `(500,0)`, vertical), one
  narrow service alley (`(150,115)`, 48 wide) feeding the restaurant's
  service door.
- `BUILDING_POSITIONS` / `BUILDING_SCENES` — the 5 enterable buildings
  (`restaurant_01`, `convenience_store_01`, `clinic_01`, `apartment_01`,
  `workshop_01` — the latter two added in Phase 3B.1, replacing two of
  the original four shell-building slots) and their fixed world positions.
- `SHELL_BUILDINGS` — 2 non-enterable background buildings (roof only +
  collision, same technique `ArenaBuilder` used) that fill out the
  district's skyline without each needing full interior authoring.
- `SPAWN_REGIONS` — 7 authored `SpawnRegion` nodes (map-edge streets on
  all 4 sides, the service alley, two concealed exterior corners). See
  "Spawn regions" below.
- `SCAVENGE_POINTS` — 5 fixed scavenging locations (same
  `scripts/world/scavenge_point.gd` from Phase 2A, just repositioned to
  fit the new street layout).

`DistrictLayoutChecksum.compute()` (`scripts/world/district_layout_checksum.gd`)
SHA-256-hashes the string form of exactly these 5 arrays, so an
accidental edit to any of them is caught by
`tests/test_runner.gd::_test_district_layout_checksum_matches_committed_baseline`
comparing against a baseline hash committed alongside this doc. A
deliberate map change updates that literal baseline in the same commit.

The only RNG anywhere in `DistrictBuilder` is `_visual_rng` (seeded
`0x0D157201`), used exclusively for **cosmetic** tile-variant noise
(which asphalt/curb/roof-material variant to paint) — it never affects
position, collision, or existence of anything, the same
cosmetic/gameplay RNG isolation rule from Phase 3A.1's `CosmeticRng`.

## Street layout

One major road runs east–west through the district center. Two side
streets run north–south, each intersecting the main road. A narrow
service alley reaches the restaurant's rear door. A parking lot (SE
corner, painted stall lines) and a small plaza (south-center, benches +
tree + planters) round out the non-building open space. Curb/sidewalk
tiles and intersection corners reuse `ArenaBuilder`'s painting technique
(ported, not reinvented) but are driven by the fixed `ROADS` list instead
of a procedural grid+skip-chance loop.

## Street dressing

Fixed positions for: 2 abandoned cars (one lootable sedan, one salvageable
wreck), trees, a utility box, a street sign, a street lamp, a fire
hydrant, a dumpster (searchable, near the alley), a loose trash bag, a
road barrier + cone (parking entrance), plaza benches + planters. Every
one of these is placed via `BuildingShellBuilder.add_loot_furniture` /
`add_salvage_prop` / `add_physical_prop`, so its collision footprint is
known at authoring time — none of them were placed by a script that could
accidentally block a road or building entrance the way a random-scatter
pass could.

**Known gap (Section 13 deferral):** the exhaustive street-prop list in
the original spec (van/truck, bicycles, vending machines, shopping carts,
patio furniture beyond the restaurant's own, additional signage) was not
fully generated — see the Phase 3B completion report for the full list of
deferred art.

## Spawn regions

`scripts/world/spawn_region.gd` (`class_name SpawnRegion`) is a plain
`Node2D` with `region_id` / `radius` / `category`, added to group
`"spawn_regions"`. `random_point(rng)` takes the **caller's** RNG (never
its own) — `SpawnManager` draws from its own private gameplay RNG stream
when picking a region and a point within it, keeping spawn-position RNG
isolated the same way Phase 3A.1 isolated it from `CosmeticRng`. All 7
regions sit on map edges, the service alley, or concealed exterior
corners — never inside the safehouse (`Settlement` was moved off the new
main road to `(-950,-950)` specifically to keep it clear of both the road
and the district's spawn regions).

**Phase 3B.1: `SpawnManager` actually uses them now.** Production
spawning (`SpawnManager._spawn_one()` → `_pick_region_spawn_position()`)
picks a random authored region, then a random point within it, then
rejects that candidate if it's inside World collision (a wall or
furniture), inside the safehouse, inside the player's current room
(`Room.room_containing()`), inside an invalid/solid `UrbanNavigationService`
cell, overlapping another actor (a bounded physics point query against
Player|Zombie|Survivor), closer than `min_distance_to_player`, or
directly visible to the player within `player_visibility_check_range` (a
`World | Vision` raycast). All of this happens within a bounded search
(`max_region_search_attempts`, default 24); if nothing valid turns up,
that spawn attempt is simply skipped — **never** a silent fallback to an
arbitrary camera-relative position — and the next periodic spawn tick
retries. See `docs/perception_system.md`'s collision-layer table for the
`World`/`Vision`/actor layer bits this reuses.

## Boundaries and navigation

A perimeter boundary (`StaticBody2D` walls) matches the district's outer
extent. `UrbanNavigationService` builds its `AStarGrid2D` from this same
static World-layer collision once, at `DistrictBuilder._ready()`'s end
(after `await get_tree().physics_frame` so newly-added `StaticBody2D`s are
already queryable) — see `docs/perception_system.md` "Navigation" for the
grid itself.

## Known limitations

- All 5 requested enterable-building archetypes now exist (Restaurant,
  Convenience Store, Clinic, Apartment, Workshop — see
  `docs/building_system.md`).
- No upper floors, basements, drivable vehicles, destructible walls, or
  procedural generation — all explicitly out of scope per the task spec.
- The service alley and parking lot are single fixed instances, not a
  repeated pattern across the district (the spec's "≥2 side streets, ≥1
  alley, a parking area, a delivery area, a small plaza" is satisfied
  once each, not as a tileable pattern that would extend to a larger
  district later without further authoring work).
- The baked scene's own drift-detection (Phase 3B.1) is a structural
  check (building/door/spawn-region/scavenge-point counts and ids, plus
  "the Ground layer has painted cells") via
  `tests/test_runner.gd::_test_baked_district_scene_has_expected_structure`,
  not a full pixel-perfect hash of every tile cell -- a change that
  silently altered tile ART without changing counts/positions wouldn't be
  caught by either this or the constants-based checksum.

## Adding another district later

Author a new scene under `scenes/world/maps/` with its own
`DistrictBuilder`-style script (or a generalized subclass taking its
`ROADS`/`BUILDING_POSITIONS`/etc. as data instead of hard-coded consts),
give it its own `DistrictLayoutChecksum`-style baseline test, and swap
`Main.tscn`'s `World` node to instance it. Building scenes
(`scenes/world/buildings/*.tscn`) are already fully reusable across
districts since they're self-contained (`BuildingShellBuilder`-authored,
position-independent) — only their placement in a new district's
`BUILDING_POSITIONS` needs to change.
