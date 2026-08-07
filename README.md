# Life After Death

A top-down zombie-action prototype built in Godot 4.7.1. Phase 0/1 is a
stable action-combat foundation (movement, aiming, shooting, a swarm of
zombies, and a minimal HUD/pause/death loop). Phase 2A, on top of that,
is an autonomous survivor and settlement simulation vertical slice: a
small safehouse with four independent survivors who recognize their own
needs, claim settlement work, respond to zombies, and keep themselves
alive without the player directly commanding them. Quests, economy,
crafting, procedural world generation, factions, crime, children, and
advanced construction are not implemented yet.

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

## Controls

### Desktop

| Action          | Binding                  |
|-----------------|---------------------------|
| Move            | `WASD` or Arrow keys      |
| Aim             | Mouse position             |
| Fire            | Left mouse button (hold — automatic weapon) |
| Reload          | `R`                       |
| Interact        | `E` (mapped, unused in this slice) |
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
  reload, ammo HUD, and procedural muzzle-flash/hit feedback (no sprites).
- **Zombies**: cheap CharacterBody2D actors that seek the player and
  separate from nearby zombies via a spatial-grid broad phase
  (`SwarmManager`) instead of per-instance pathfinding — built to scale
  to hundreds of concurrent zombies.
- **World**: a procedurally generated test arena (roads, pavement,
  building obstacles, boundary walls) built entirely from primitives
  (`Polygon2D` / `Line2D` / `StaticBody2D`) — no imported textures.
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
  world/    Safehouse.tscn (settlement), ScavengePoint.tscn
  ui/       HUD.tscn, PauseMenu.tscn, DeathOverlay.tscn,
            MobileControls.tscn, VirtualJoystick.tscn, DebugOverlay.tscn,
            SurvivorInspector.tscn
scripts/
  core/     signal bus, health component, object pool, Main controller,
            InputRouter, platform utils, SimulationClock, WorldState
  actors/   player, zombie, spawn manager, swarm manager, survivor
  ai/       UtilityAction base, UtilityMath, SurvivorAI, actions/ (14
            behavior scripts)
  combat/   weapon, weapon data, projectile, projectile manager
  items/    ItemData, Inventory, ItemDatabase
  jobs/     Job, SettlementJobBoard
  survivors/  SurvivorData
  world/    procedural arena builder, camera rig, Settlement,
            SettlementData, StorageContainer, ScavengePoint, SleepSpot,
            GuardPost
  ui/       HUD, pause menu, death overlay, safe area, mobile controls,
            virtual joystick, debug overlay, survivor inspector
resources/
  weapons/  WeaponData .tres instances (e.g. smg.tres, pistol.tres)
  items/    ItemData .tres instances (food_ration, water_bottle,
            medical_supplies, ammunition, materials)
  actors/   reserved for future actor-tuning resources
tests/      reserved for automated tests
docs/       architecture.md
export_presets.cfg   Android export preset (see Mobile / Android above)
```

## Known limitations (expected at this stage)

- Zombies steer directly at their nearest target (player or survivor) and
  do not path around obstacles — they can get stuck on building corners.
  Acceptable for a prototype; real pathfinding is a later concern.
- `interact` is bound but has no target yet (no interactable objects
  exist in this slice).
- No save/load, no persistence between runs. `WorldState.to_snapshot()`
  produces a serializable shape but nothing reads/writes it to disk yet.
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
