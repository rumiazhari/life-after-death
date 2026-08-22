# Urban map design (runtime procedural city)

`Main.tscn` now instances `scenes/world/maps/StreamingWorld.tscn`.
`StreamingWorld` keeps a bounded square of `ProceduralDistrict` chunks around
the player. `ProceduralCityGenerator` first creates each deterministic semantic
chunk model; `ProceduralDistrict` then paints and instantiates that model. The earlier
`DistrictBuilder -> bake_district.gd -> UrbanDistrict01.tscn` pipeline is
retained unchanged as historical regression/reference content, but it is
no longer normal gameplay's world source.

## Current streamed Prague contract

Normal gameplay divides the unbounded coordinate space into 2816x2816-pixel
chunks. `ChunkEdgeContract` derives identical portal ids, positions, widths,
surfaces, tram flags and canonical tangents from each unordered neighbor pair.
`PragueRegionalPlan` selects `historic_core`, `inner_city`,
`hillside_residential` or `industrial_transition` from a four-chunk regional
field, then supplies irregular inner axes, tram orientation, local paving,
public-space type and roof palette.

Streamed buildings use a fixed north-up camera-facing elevation. Their lots and
interiors remain rectangular top-down geometry, but the roof art is displaced
north and each exposed south footprint boundary becomes a multi-storey facade
down to the real entrance baseline. This adds visible street walls without
changing the regional road graph, party-wall parcels, door coordinates,
navigation grid or chunk-edge contract.

Continuous frontage remains the governing street rule. Adjacent lots meet at
party walls; facade style comes from the Prague regional profile and building
archetype, while windows, awnings, signs, wear and flower boxes are deterministic
per stable building ID. Rare courtyards keep their two-cell passages, and
compound rear/side wings receive a facade only where their south edge is exposed.

Each streamed chunk contains nine larger urban quarters rather than reusing the
finite fixture's 4x4 block grid. Connected edge streets and building approach
branches extend the regional street hierarchy. Street boundaries align with
the 64-pixel building module grid, frontage modules are distributed between
neighboring lots without equal-split waste, and ordinary quarters fill at least
88 percent of their buildable area with enterable building footprints. Only the
origin chunk reserves the safehouse quarter; other chunks develop that land.

Plazas are deterministic five-percent chunk events. Courtyards are independent
six-percent events on eligible quarters. A selected courtyard reserves 192
pixels of rear depth and a 64-pixel street passage; otherwise paired lots share
a continuous party-wall frontage without an open gap. Plaza dogleg lanes and
courtyard paving are generated only when their semantic open-space record
exists.

Local streets use generated cobblestone or stone-sett paving; regional roads
retain asphalt, and one selected arterial orientation receives tram rails.
Facade metadata selects painted plaster, active shopfront or brick industrial
treatment. Building roofs use profile-weighted clay/slate/patina materials and
a deterministic ridge strip over each rectangular wing, including compound
rear- and side-wing footprints.

## Finite regression generation contract

The retained finite generator uses one seed to determine five horizontal and five vertical connected
street axes, 25 intersections, sixteen variable-size blocks, zone assignments,
explicit parcels/frontages, parking areas, alleys, exterior objects,
scavenging points and population regions. Generation has an eight-attempt
deterministic bound and returns explicit validation errors rather than a
partially valid city. All coordinates remain aligned to the existing 32-pixel
tile grid. The same seed reproduces the complete semantic signature; cosmetic
asphalt, sidewalk and ground variants draw from a separate visual RNG.

Every non-safehouse/non-park block receives an enterable Apartment,
Restaurant, Convenience Store, Clinic or Workshop selected by its zone. The
building is not a placed complete scene: its footprint, room modules,
partitions, doors, windows, roof, functional furniture and reserved circulation
areas are generated and validated before `ProceduralBuilding` constructs it.
Generated IDs prefix every room, door, window, loot container, salvage prop
and destructible segment, preserving `WorldState` identity across same-seed
reconstruction.

Exterior and interior spawn regions are part of the semantic model and carry
environment tags plus distinct initial-population and replenishment eligibility
and weights. `SpawnManager` uses a city-seed-derived RNG, then retains collision,
safehouse, current-room, connected-navigation, actor-overlap, distance and
visibility rejection checks. Indoor regions are emitted only for rooms proven
reachable from a valid exterior entrance; outdoor candidates must remain on the
connected exterior component.

Physical furniture and exterior props compose the existing interaction and
salvage components with `EnvironmentDamageComponent`. Firearm resources
carry a structural damage class. Small arms can damage light objects,
heavy impacts are required for vehicles, and walls accept explosive-class
damage only. Destroyed collision re-samples its affected navigation cells
against remaining colliders and advances the navigation revision; destroyed
loot is conserved in a `WorldDrop`.

## Historical fixed-district rationale

`ArenaBuilder` was documented as "the
test arena, not a real level." Phase 3B's enterable buildings, persistent
per-room/per-door/per-prop state, and shared navigation grid all need
**stable identity**: a room, door, or shelf had to mean the same thing on
every run for `WorldState.door_states`/`prop_states`/`prop_containers` (and
`UrbanNavigationService`'s door-cell registry) to work at all. The current
generator solves this with seed/block/building/local-object IDs rather
than transient node names. The remaining sections preserve the earlier
authored-map design and bake workflow as historical reference.

## Baked, not runtime-built (Phase 3B.1)

`scenes/world/maps/UrbanDistrict01.tscn` is **committed, authored
scene content** — real `[node]` entries for every TileMapLayer, building
instance, prop, door, window, spawn region, and scavenge point, all
editable/selectable/movable in the Godot editor exactly like any other
hand-built scene. It was the Phase 3B.1–3C runtime map; current normal
gameplay instead loads `ProceduralDistrict.tscn`.

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

## The city plan (Phase 3C) — `scripts/world/district_builder.gd`

Everything positional is still a **literal `const`**, not a seeded random
choice. What changed in Phase 3C is what those constants describe: no
longer "a few roads plus a handful of building coordinates", but a whole
city plan — a street grid, the blocks that grid encloses, and what fills
each block.

### The street grid — `ROADS`

Ten streets in a 5x5 grid. All centers and widths are multiples of the
32px tile, so every carriageway edge lands exactly on a tile boundary and
nothing paints a ragged half-tile seam:

| Street | Axis | Center | Width |
| --- | --- | --- | --- |
| Grand Avenue | east–west | `y = 0` | 192 (arterial) |
| Market Street | north–south | `x = 0` | 192 (arterial) |
| Ash Street | east–west | `y = -672` | 128 |
| Kiln Street | east–west | `y = 672` | 128 |
| Civic Street | north–south | `x = -672` | 128 |
| Foundry Street | north–south | `x = 672` | 128 |
| North / South / West / East Ring Road | — | `±1280` | 128 |

The two arterials get a dashed centre line plus a solid lane divider
either side (they are six lanes across and read as an empty runway
without it); the rest get a centre line only. Lane markings **stop at the
intersection mouth** — `_is_junction_cell()` skips any cell of one street
that another street also covers — and each of the grid's 25 junctions gets
a zebra crossing on all four approaches.

### The blocks — `BLOCKS` and `SURFACE_PATCHES`

Sixteen entries, one per block the grid encloses, each a whole-block
`Rect2` plus the ground it is paved with. The outer 64px
(`BLOCK_SIDEWALK_DEPTH`, two tiles) of every block is automatically its
curb + sidewalk frontage; `buildable_rect()` is the inset remainder that
buildings, yards and alleys sit inside.

| Block | Zone |
| --- | --- |
| Safehouse Compound (NW) | the settlement's own walled block, sandbagged checkpoint on its street frontage |
| Ash Row / Ash Terrace | residential terraces + `apartment_01`, split by back alleys |
| Foundry Works (NE) | `workshop_01` and its dirt loading yard |
| Civic Square | `clinic_01`, civic hall, library, and a lawn between them |
| Market Block NW / NE / SW | the downtown core — rows of shopfronts on continuous street frontage, `convenience_store_01` and `restaurant_01`, each block split by a mid-block service alley |
| Depot Yard | parking apron + offices |
| Willow Green | a public park: grass, crossed dirt paths, trees, benches |
| Market Plaza | the town square, paved edge to edge, market stalls |
| Storage Yard / South Works | warehouses and open industrial yards |
| Kiln Row / South Row | two more residential quarters |
| Derelict Lot | a cleared, rubble-strewn lot with one gutted tenement |

`SURFACE_PATCHES` then paints what differs *inside* a block — the alleys,
the yards, the civic lawn, the park paths — which is what stops a block
interior reading as one flat slab of concrete between its buildings.

Sidewalks are **derived from the grid, not from each road's own extent**:
any cell that is neither carriageway nor block interior is pedestrian
ground, and gets a curb face on whichever side(s) a street actually
touches it (a corner curb where two do). That single rule is what keeps
sidewalk from being painted straight across an intersection — the bug the
old per-road sidewalk pass had wherever two roads met.

### What fills the blocks

- `BUILDING_POSITIONS` / `BUILDING_SCENES` — the 5 enterable buildings
  (`restaurant_01`, `convenience_store_01`, `clinic_01`, `apartment_01`,
  `workshop_01`), each seated against its own block's buildable edge so
  its front door opens straight onto that block's sidewalk.
  `enterable_half_extent()` reads each one's footprint from that
  building's OWN `HALF_EXTENT` constant rather than restating it.
- `SHELL_BUILDINGS` — 32 non-enterable buildings (roof + collision, no
  interior). These do the actual city-filling: rows of them abut into
  continuous street frontage along a block edge, leaving a deliberate
  mid-block alley or yard behind. Half-extents are multiples of 32 so
  each roof paints flush to its own footprint, and `roof` picks one of
  the four shared roof materials per zone (A brick red residential,
  B slate downtown, C tan civic, D green patina industrial/derelict).
- `PARKING_LOTS` — asphalt aprons with painted stall lines (no collision;
  the cars standing on them bring their own).
- `SPAWN_REGIONS` — 12 authored `SpawnRegion` nodes (six on the ring road,
  three mid-block alleys, three concealed: park, storage yard, derelict
  lot). See "Spawn regions" below.
- `SCAVENGE_POINTS` — 8 fixed scavenging locations, one per zone so no
  quarter of the city is worth ignoring.

### Street dressing

- `PROP_LINES` — repeating furniture laid along a line at a fixed step
  (the lamp posts and street trees down each avenue). Each line runs along
  a sidewalk row and may be authored as one clean sweep across the whole
  district: `_prop_position_is_clear()` skips any generated position that
  would land in a carriageway or inside a building, so no hand-clipping
  per intersection.
- `PROPS` — one-off solid furniture, grouped by the block it dresses.
- `DECALS` — flat ground detail with **no collision body at all** (drain
  covers, rubble). Deliberately not a physical prop with a tiny shape:
  anything with a collider can mark a navigation cell solid, and a manhole
  cover that blocks pathfinding is worse than no manhole cover.
- `LOOT_PROPS` / `SALVAGE_PROPS` — searchable dumpsters and cars, and
  salvageable wrecks. Y-sorted against actors, so these are built into the
  `"entity_container"` group's node rather than `$StreetProps`.

Rooftop fixtures (vents, ducts, water tanks, signs) are stamped by
`BuildingShellBuilder.paint_roof()` itself, so every roof in the game gets
them — onto a **child** `TileMapLayer` of the roof, since the fixture
tiles are drawn with transparent surrounds and one `TileMapLayer` holds
only one tile per cell. Being a child is also what keeps
`BuildingVisibilityController` correct for free: hiding a building's roof
hides its fixtures with it.

### Drift protection

`DistrictLayoutChecksum.compute()` (`scripts/world/district_layout_checksum.gd`)
SHA-256-hashes the string form of every one of those arrays, so an
accidental edit to any of them is caught by
`tests/test_runner.gd::_test_district_layout_checksum_matches_committed_baseline`
comparing against a baseline hash committed alongside this doc. A
deliberate map change updates that literal baseline in the same commit.
Prop textures are stored in the constants as **paths**, never as
`preload()`ed `Texture2D` handles: a `Texture2D` stringifies to a per-run
object id, which would make the checksum differ on every run and detect
nothing.

Two further tests guard the plan itself, because "it looked right in a
screenshot" is not a regression test:

- `_test_district_buildings_fit_their_blocks_without_overlapping` —
  every footprint sits fully inside some block's buildable area, never
  overlaps another building, never sits in a carriageway, never encroaches
  on the safehouse compound; no spawn region or scavenge point is inside a
  building.
- `_test_baked_district_landmarks_are_reachable` — instantiates the real
  baked scene, lets `AuthoredDistrict` build the navigation grid from its
  live static collision, and asserts every landmark (each front-door
  approach, each alley, the park, the plaza, the yards) is a free
  navigation cell *and* path-connected to the middle of the street grid.
  A block accidentally walled shut by its own building row fails here
  rather than during play. This is what caught `restaurant_01`'s dining
  furniture being authored in building-local coordinates while parented to
  an offset room node — which put its chairs on the street directly in
  front of its own entrance and made the door impassable.

The only RNG anywhere in `DistrictBuilder` is `_visual_rng` (seeded
`0x0D157201`), used exclusively for **cosmetic** tile-variant noise
(which asphalt/sidewalk/grass variant to paint) — it never affects
position, collision, or existence of anything, the same
cosmetic/gameplay RNG isolation rule from Phase 3A.1's `CosmeticRng`.

Reference renders of the result live in `docs/screenshots/phase-3c/`.

## Spawn regions

`scripts/world/spawn_region.gd` (`class_name SpawnRegion`) is a plain
`Node2D` with `region_id` / `radius` / `category`, added to group
`"spawn_regions"`. `random_point(rng)` takes the **caller's** RNG (never
its own) — `SpawnManager` draws from its own private gameplay RNG stream
when picking a region and a point within it, keeping spawn-position RNG
isolated the same way Phase 3A.1 isolated it from `CosmeticRng`. All 12
regions sit on the ring road, in a mid-block alley, or in one of the three
concealed zones (the park, the storage yard, the derelict lot) — never
inside a building (a test asserts that) and never inside the safehouse
(`Settlement` sits at `(-976,-976)`, centred in the Safehouse Compound
block, which owns that block outright and carries no other buildings).

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

## Retained authored-map limitations

- All 5 requested enterable-building archetypes now exist (Restaurant,
  Convenience Store, Clinic, Apartment, Workshop — see
  `docs/building_system.md`).
- No upper floors, basements, or drivable vehicles. Runtime procedural
  generation and class-gated destructible walls now live in
  `ProceduralDistrict`; they are not backported into this baked scene.
- Only 5 of the city's 37 buildings are enterable; the other 32 are
  shells (roof + collision). Filling a block visually is cheap, authoring
  an interior is not, so the district is deliberately dense on the outside
  and shallow on the inside. Promoting a shell to a real building is
  swapping one `SHELL_BUILDINGS` entry for a `BUILDING_POSITIONS` one.
- The block plan is authored per block, not tileable: extending the city
  to a 6x6 or 7x7 grid means authoring the new blocks' contents by hand,
  not raising a constant.
- `BuildingShellBuilder.build_perimeter_walls()` rounds each half-extent
  to whole tiles, so a building whose `HALF_EXTENT` isn't a multiple of 32
  has walls a few pixels inside or outside its nominal footprint (e.g.
  `clinic_01`'s 100x70 half-extent builds walls at ±96/±64). The overlap
  test uses the nominal footprint, which is the conservative direction,
  but interior furniture authored right up against a wall can end up
  inside it.
- Some interior furniture in `convenience_store_01` and `clinic_01` still
  sits partly inside its own wall row for that reason. Nothing blocks a
  doorway (the reachability test covers that), but the interiors have not
  had a full pass since the Phase 3C exterior redesign.
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
