# Life After Death

A top-down zombie-action prototype built in Godot 4.7.1. Phase 0/1 is a
stable action-combat foundation (movement, aiming, shooting, a swarm of
zombies, and a minimal HUD/pause/death loop). Phase 2A, on top of that,
is an autonomous survivor and settlement simulation vertical slice: a
small safehouse with four independent survivors who recognize their own
needs, claim settlement work, respond to zombies, and keep themselves
alive without the player directly commanding them. Phase 3B (completed in
Phase 3B.1) replaces the procedural test arena with one fixed,
**baked/committed** urban district containing all 5 planned enterable
buildings, a systemic interaction framework (doors, loot, salvage), a
bounded zombie-perception rebuild (vision cone + hearing + line-of-sight,
no more unlimited-range targeting), authored zombie spawn regions with
real rejection checks, a bounded room-portal visibility system, and
survivor pathfinding through the same shared navigation grid zombies use
— see [What's here](#whats-here) and `docs/urban_map_design.md`/
`docs/building_system.md`/`docs/perception_system.md`/
`docs/interaction_system.md` for the full writeups. Quests, economy,
crafting, procedural world generation, factions, crime, children, upper
floors/basements, drivable vehicles, and advanced construction are not
implemented yet.

Runs on desktop (keyboard/mouse) and is configured for Android (landscape,
dual on-screen joysticks, touch buttons) — see [Mobile / Android](#mobile--android) below for current export status.

## Requirements

- Godot 4.7.1 (Mobile renderer, already configured in `project.godot`)

## Running

Open the project in Godot and press Play (F5), or run headless:

```
godot --path .
```

`scenes/main/Main.tscn` is the configured main scene.

### Testing

A lightweight headless regression suite (no external test framework, 76
tests as of Phase 3B.1) covers the survivor inventory/job data-integrity
lifecycle -- reservation success/failure, capacity-aware scavenging,
haul-job interruption before and after pickup, survivor death retaining a
persistent record, and restart resetting simulation state -- plus
(Phase 3B) the fixed district's layout checksum, door/window state and
collision, loot/salvage duplication prevention, persistent prop-container
identity, zombie perception gating (distance/cone/wall/hearing),
navigation-grid door awareness and request budget, and a survivor's local
threat sensor -- plus (Phase 3B.1) authored spawn-region selection and
rejection checks, `DetectableComponent` visibility/noise behavior,
survivor navigation around walls/through doors, bounded room-portal
visibility (view cone, 2-hop depth, windows), snapshot serialization
round-trips, and the baked district scene's own structural validation.
Run from the project root:

```
godot --headless --path . res://tests/TestRunner.tscn
```

Exits 0 if every test passes. See `tests/README.md`.

### Visual asset pipeline (Phase 3A)

Every texture under `assets/pixel/` is placeholder pixel art, generated
(not downloaded, not copied from any reference/commercial game) by a
deterministic headless script — no Pillow/Photoshop/Aseprite involved.
Regenerate it with:

```
godot --headless --path . --script tools/generate_pixel_assets.gd
```

Every random choice inside the generator is seeded per-asset
(`SEED xor tag.hash()`), so running it twice produces byte-identical PNGs
(verified via `sha256sum` over `assets/pixel/**/*.png` during development).
See `docs/art_direction.md` for the full locked spec (tile/frame
dimensions, palette, layer order, naming conventions) and how to replace
this placeholder art with licensed or hand-drawn assets later without
touching gameplay code.

## Controls

### Desktop

| Action          | Binding                  |
|-----------------|---------------------------|
| Move            | `WASD` or Arrow keys      |
| Aim             | Mouse position             |
| Fire            | Left mouse button (hold — automatic weapon) |
| Reload          | `R`                       |
| Interact        | `E` (doors, loot/salvage props) |
| Pause / Resume  | `Escape`                  |
| Restart (on death) | `Enter` or the on-screen Restart button |

### Touch (Android, or forced visible on desktop — see below)

| Action   | Control                                    |
|----------|---------------------------------------------|
| Move     | Left virtual joystick                       |
| Aim      | Right virtual joystick                      |
| Fire     | Automatic while the right joystick is held/dragged |
| Reload / Interact / Pause | Dedicated on-screen buttons   |
| Restart (on death) | On-screen Restart button          |

Both input schemes drive the same `InputRouter` autoload
(`scripts/core/input_router.gd`); gameplay code never reads `Input`/
`InputMap` or the touch UI directly. See `docs/architecture.md`.

## What's here

- **Player**: eight-direction movement with acceleration/deceleration,
  mouse aiming decoupled from movement direction, health with brief
  post-hit invulnerability, and a death state.
- **Combat**: a data-driven `WeaponData` resource, pooled projectiles,
  reload, ammo HUD, a pixel muzzle-flash/hit-flash, and capped/recycled
  blood decals on zombie death (`BloodDecalManager`, Phase 3A).
- **Zombies**: cheap CharacterBody2D actors that seek the player and
  separate from nearby zombies via a spatial-grid broad phase
  (`SwarmManager`) instead of per-instance pathfinding — built to scale
  to hundreds of concurrent zombies.
- **World**: a procedurally generated test arena (roads, sidewalks/curbs,
  crosswalks, ground variety, building obstacles with tiled rooftops,
  boundary walls, decorative props) painted onto `TileMapLayer`s from the
  generated pixel atlas (Phase 3A); collision geometry
  (`StaticBody2D`/`RectangleShape2D`) and the seeded layout math are
  unchanged from the original primitive-drawn build — see
  `docs/architecture.md`'s "Rendering / visual layer" section.
- **UI**: HUD (health, ammo, reload status, zombie count, kills, FPS),
  a pause menu, and a death/restart overlay. All screen-edge UI insets
  itself to the platform safe area (notches, rounded corners, system
  bars) via a reusable `SafeArea` control.
- **Input**: a centralized `InputRouter` autoload exposes
  `movement_vector` / `aim_vector` / `fire_pressed` / `reload_pressed` /
  `interact_pressed` / `pause_pressed`. Desktop keeps using the project's
  InputMap actions; `MobileControls` (dual joysticks + buttons) reports
  touch state into the same router. Neither side talks to the other.
- **Debug overlay**: always-on readout of FPS, frame/physics time, active
  zombies/projectiles, projectile pool capacity, spatial-grid
  query/candidate counts, and (Phase 2A) survivor/job/reservation
  counters — for tuning population profiles and watching the simulation.
- **Survivors**: four autonomous residents of one prototype safehouse,
  each with different skills and personality traits. A scored utility-AI
  (`docs/architecture.md`) picks among 14 behaviors — idle, wander, eat,
  drink, sleep, seek safety, flee, fight, retrieve supplies, haul
  supplies to storage, scavenge, treat own injury, help an injured
  survivor, guard the entrance — based on need urgency, risk, distance,
  personality, and settlement priorities. Survivors reserve the specific
  items/jobs they commit to (see `SettlementJobBoard`/`Inventory`
  reservations in the architecture doc) so two survivors never converge
  on the same food ration or scavenging point.
- **Settlement**: one safehouse with general/food/water/medical storage,
  sleeping spots, guard posts, and a danger level driven by nearby
  zombies; several scavenging points nearby yield food, water, medical
  supplies, or materials until depleted.
- **Simulation clock**: a `SimulationClock` autoload drives deterministic
  game time (pause/normal/fast, configurable real-seconds-per-game-minute)
  that survivor need decay and settlement danger checks key off of,
  independent of render FPS.
- **Survivor inspector**: right-click a survivor to open a read-only
  panel showing its needs, utility scores, current goal/action, reserved
  target, inventory, health, fear, and morale. Selecting never controls
  the survivor — the player still doesn't issue orders in this phase.
- **Urban district (Phase 3B, baked in Phase 3B.1)**: one fixed, **baked
  and committed** map (`UrbanDistrict01`) — a main road, two side streets,
  a service alley, a parking lot, a plaza, fixed street dressing (cars,
  trees, a dumpster, benches, planters, signage), and 7 authored spawn
  regions, all real editor-editable nodes (see `tools/bake_district.gd`).
  Replaces the procedurally generated `ArenaBuilder` test arena as the
  main game world (`ArenaBuilder` is kept, unused, as an optional
  test/perf scene). See `docs/urban_map_design.md`.
- **Enterable buildings**: all 5 planned archetypes — Restaurant,
  Convenience Store, Clinic, Apartment, and Workshop — each with real
  interior walls, multiple named rooms, doors, and windows — not one big
  roof tile over an empty box. Roofs hide and rooms reveal on entry
  through a bounded view-cone/line-of-sight portal graph (up to 2 door/
  window hops, Project-Zomboid-style), reacting immediately to a door
  opening/closing even while standing still; leaving restores the
  exterior view. See `docs/building_system.md`.
- **Interaction**: press/tap Interact near a door, shelf, fridge,
  cabinet, car, or dumpster. Doors open/close (and block movement +
  vision while closed); containers hold real, depletable inventory
  (searching twice never duplicates loot); salvage props yield materials
  once; door/prop state round-trips through `WorldState`'s snapshot/
  restore API. See `docs/interaction_system.md`.
- **Zombie perception (Phase 3B rebuild)**: zombies no longer target the
  player at unlimited range. Detection now needs line of sight, distance,
  and facing (a view cone), with a short suspicion buildup before
  committing to a chase; walls and closed doors block it; a loud nearby
  noise (gunshot, door, search, salvage) can draw investigation without
  ever seeing anything. A shared `DetectableComponent` makes a stationary
  actor harder to spot than a moving one. Zombies spawn only in authored
  regions, rejecting candidates inside walls, the safehouse, the player's
  current room, or directly visible to the player. See
  `docs/perception_system.md`.
- **Survivor navigation**: survivors path around walls/closed doors using
  the same shared navigation grid zombies use, so every existing
  behavior (retrieve supplies, haul, flee, ...) can enter/exit buildings
  and route around obstacles without its own pathfinding logic.

See [`docs/architecture.md`](docs/architecture.md) for how the systems
are wired together (including the full Phase 2A writeup: simulation tick
architecture, persistent data vs. runtime nodes, the utility-scoring
formula, job/reservation lifecycles, active vs. off-screen simulation)
and where later systems should hook in.

## Mobile / Android

- Landscape orientation, `canvas_items` + `expand` stretch so the layout
  adapts to 16:9 / 18:9 / 19.5:9 phones and wider tablet aspect ratios
  without a hard-coded resolution.
- Zombie population is selectable via `SpawnManager.PopulationProfile`
  (Low 50 / Medium 100 / High 150 / Stress 250). **Android defaults to
  Medium (100)** regardless of the desktop profile, until a real device
  has been profiled — see `mobile_population_profile` on `SpawnManager`.
- To test touch controls on desktop without a device, enable the
  `debug/mobile_controls/force_visible` project setting.
- `export_presets.cfg` has a hand-authored "Android Debug" preset (no
  signing credentials embedded — it relies on Godot's own local debug
  keystore). **This environment has no Android SDK or export templates
  installed**, so the preset has not been verified by an actual export
  or run on a device/emulator. Before exporting: install Android build
  templates (Editor → Manage Export Templates) and point Editor Settings
  → Export → Android at a valid SDK, then re-check the preset in the
  Export dialog.

## Project layout

```
scenes/
  main/     Main.tscn — top-level scene composition
  actors/   Player.tscn, Zombie.tscn, Survivor.tscn
  combat/   Projectile.tscn
  world/    Safehouse.tscn (settlement), ScavengePoint.tscn, Door.tscn,
            Window.tscn, maps/UrbanDistrict01.tscn (Phase 3B, baked
            committed content as of Phase 3B.1 -- see
            tools/bake_district.gd), buildings/Restaurant01.tscn,
            ConvenienceStore01.tscn, Clinic01.tscn, Apartment01.tscn,
            Workshop01.tscn (Phase 3B / 3B.1)
  ui/       HUD.tscn, PauseMenu.tscn, DeathOverlay.tscn,
            MobileControls.tscn, VirtualJoystick.tscn, DebugOverlay.tscn,
            SurvivorInspector.tscn
scripts/
  core/     signal bus, health component, object pool, Main controller,
            InputRouter, platform utils, SimulationClock, WorldState,
            NoiseManager (Phase 3B), DetectableComponent (Phase 3B.1)
  actors/   player, zombie, spawn manager, swarm manager, survivor
  ai/       UtilityAction base, UtilityMath, SurvivorAI, actions/ (14
            behavior scripts), ZombiePerceptionComponent (Phase 3B)
  combat/   weapon, weapon data, projectile, projectile manager
  items/    ItemData, Inventory, ItemDatabase
  interaction/  InteractableComponent, PlayerInteractor,
            LootContainerComponent, SalvageableComponent,
            RestPointComponent (Phase 3B)
  jobs/     Job, SettlementJobBoard
  survivors/  SurvivorData
  world/    procedural arena builder (TileMapLayer-based, Phase 3A, kept
            as an unused test/perf scene), shared PixelTilesetBuilder,
            camera rig, Settlement, SettlementData, StorageContainer,
            ScavengePoint, SleepSpot, GuardPost,
            SafehouseInteriorBuilder, WorldDropVisualManager,
            DistrictBuilder (Phase 3B, now a bake-time-only tool input --
            see tools/bake_district.gd), DistrictLayoutChecksum,
            AuthoredDistrict (Phase 3B.1, the baked scene's own lightweight
            runtime script), BuildingShellBuilder,
            BuildingVisibilityController, Room, Door, Window, SpawnRegion,
            UrbanNavigationService (Phase 3B),
            buildings/ (Restaurant01, ConvenienceStore01, Clinic01,
            Apartment01, Workshop01 scripts)
  visuals/  ActorVisual, ActorSpriteLibrary (Phase 3A shared sprite/
            animation layer for Player/Survivor/Zombie)
  combat/   weapon, weapon data, projectile, projectile manager,
            BloodDecalManager (Phase 3A)
  ui/       HUD, pause menu, death overlay, safe area, mobile controls,
            virtual joystick, debug overlay, survivor inspector
resources/
  weapons/  WeaponData .tres instances (e.g. smg.tres, pistol.tres)
  items/    ItemData .tres instances (food_ration, water_bottle,
            medical_supplies, ammunition, materials)
  actors/   reserved for future actor-tuning resources
  theme/    pixel_theme.tres (Phase 3A UI theme)
assets/
  pixel/    generated placeholder pixel art (environment, actors, props,
            effects, ui, building/interior assets) -- see "Visual asset
            pipeline" above and docs/art_direction.md
tests/      test_runner.gd + TestRunner.tscn — headless regression suite
docs/       architecture.md, art_direction.md, urban_map_design.md,
            building_system.md, perception_system.md,
            interaction_system.md (Phase 3B / 3B.1), screenshots/phase-3a/,
            screenshots/phase-3b/
tools/      generate_pixel_assets.gd — deterministic pixel-art generator,
            bake_district.gd — bakes the district into committed scene
            content (Phase 3B.1, see docs/urban_map_design.md)
export_presets.cfg   Android export preset (see Mobile / Android above)
```

## Known limitations (expected at this stage)

- Zombies and survivors both steer directly at their target and only
  consult the shared navigation grid as a fallback when directly blocked
  (see `docs/perception_system.md` "Navigation") — not full unconditional
  pathfinding.
- Building interior/roof reveal uses a bounded view-cone/line-of-sight
  portal graph (up to 2 door/window hops), not a full per-room roof
  segmentation — a window can't yet reveal a room's interior to someone
  standing *outside* the building; see `docs/building_system.md` "Known
  limitations."
- No save/load, no persistence between runs. `WorldState.to_snapshot()`
  produces a serializable shape (including Phase 3B door/prop state, with
  a matching `restore_phase_3b_state()` read path) but nothing reads/
  writes it to disk yet.
- The district's own drift-detection (`DistrictLayoutChecksum` plus a
  baked-scene structural test) checks counts/ids/positions, not a
  full pixel-perfect tile-data hash.
- The `ammunition` item is defined but not wired to `Weapon`'s reload,
  which still uses its own internal reserve-ammo counter — survivors and
  the player don't consume carried ammunition when firing.
- `ActionHelpInjured` uses a lightweight single-claim lock on the target
  `Survivor` rather than routing through `SettlementJobBoard` (a same-
  settlement 1:1 claim didn't need full job lifecycle machinery); `Job.Type.HELP_INJURED`
  is declared for a future use that needs it.
- Off-screen survivors get cheaper (less frequent) AI decisions and
  perception, but their physics movement isn't throttled — at four
  survivors this is inexpensive regardless of screen state, but it won't
  scale to a much larger population without a coarser off-screen path.
- Only one settlement exists; `SettlementJobBoard`/`Settlement` don't yet
  disambiguate between settlements if a second one were added.
- No Android SDK/export templates in this environment — the Android
  export preset is unverified; see Mobile / Android above.
- Multi-aspect-ratio layout was verified by code/anchor review, not by
  an actual window resize — this dev environment's game window is
  embedded for screenshot capture and reports "can't be resized."
  Recommend a manual desktop-resize or real-device check.
