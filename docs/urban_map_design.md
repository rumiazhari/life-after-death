# Urban map design (Phase 3B)

Why the world is now one fixed, authored district instead of the
Phase 3A `ArenaBuilder` procedural test arena, how that district is built,
and where the pieces live.

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

## Scene organization

`scenes/world/maps/UrbanDistrict01.tscn` — root `DistrictBuilder`
(`scripts/world/district_builder.gd`), instanced directly by
`scenes/main/Main.tscn`'s `World` node (previously an `ArenaBuilder`
script). Child containers: `GroundLayers`, `Buildings`, `StreetProps`,
`Navigation`, `SpawnRegions`, `Boundaries`. `EntityContainer` (Y-sorted,
Phase 3A.1) stays at the `Main.tscn` level rather than moving under
`UrbanDistrict01` — a deliberate simplification so the existing Y-sort
wiring (player/survivors/zombies/scavenge points as its direct children)
didn't need restructuring this late; `DistrictBuilder` still populates it
by group lookup (`"entity_container"`) the same way `ArenaBuilder` did.
`DynamicWorld` as a literal named container was likewise not introduced —
`EntityContainer` continues serving that role.

## Layout — `scripts/world/district_builder.gd`

Everything positional is a **literal `const`**, not a seeded random
choice:

- `ROADS` — 4 entries: one main road through the district (`(0,0)`,
  140 wide), two side streets (`(-500,0)` / `(500,0)`, vertical), one
  narrow service alley (`(150,115)`, 48 wide) feeding the restaurant's
  service door.
- `BUILDING_POSITIONS` / `BUILDING_SCENES` — the 3 enterable buildings
  (`restaurant_01`, `convenience_store_01`, `clinic_01`) and their fixed
  world positions.
- `SHELL_BUILDINGS` — 4 non-enterable background buildings (roof only +
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
its own) — `SpawnManager` is expected to draw from its own private
gameplay RNG stream when picking a region and a point within it, keeping
spawn-position RNG isolated the same way Phase 3A.1 isolated it from
`CosmeticRng`. All 7 regions sit on map edges, the service alley, or
concealed exterior corners — never inside the safehouse (`Settlement` was
moved off the new main road to `(-950,-950)` specifically to keep it
clear of both the road and the district's spawn regions).

## Boundaries and navigation

A perimeter boundary (`StaticBody2D` walls) matches the district's outer
extent. `UrbanNavigationService` builds its `AStarGrid2D` from this same
static World-layer collision once, at `DistrictBuilder._ready()`'s end
(after `await get_tree().physics_frame` so newly-added `StaticBody2D`s are
already queryable) — see `docs/perception_system.md` "Navigation" for the
grid itself.

## Known limitations

- Only 3 of the spec's 5 requested enterable-building archetypes exist
  (Restaurant, Convenience Store, Clinic — not Apartment or
  Workshop/Office/Warehouse). See `docs/building_system.md`.
- No upper floors, basements, drivable vehicles, destructible walls, or
  procedural generation — all explicitly out of scope per the task spec.
- The service alley and parking lot are single fixed instances, not a
  repeated pattern across the district (the spec's "≥2 side streets, ≥1
  alley, a parking area, a delivery area, a small plaza" is satisfied
  once each, not as a tileable pattern that would extend to a larger
  district later without further authoring work).

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
