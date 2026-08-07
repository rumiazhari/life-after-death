# Life After Death

A top-down zombie-action prototype built in Godot 4.7.1. This is the
Phase 0 / Phase 1 vertical slice: a stable action-combat foundation
(movement, aiming, shooting, a swarm of zombies, and a minimal HUD/pause/
death loop) for later systems — settlements, quests, economy, survivors,
crafting, procedural world generation — to build on. None of those later
systems are implemented yet.

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
  zombies/projectiles, projectile pool capacity, and spatial-grid
  query/candidate counts — for tuning population profiles.

See [`docs/architecture.md`](docs/architecture.md) for how the systems
are wired together and where later systems should hook in.

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
  actors/   Player.tscn, Zombie.tscn
  combat/   Projectile.tscn
  ui/       HUD.tscn, PauseMenu.tscn, DeathOverlay.tscn,
            MobileControls.tscn, VirtualJoystick.tscn, DebugOverlay.tscn
scripts/
  core/     signal bus, health component, object pool, Main controller,
            InputRouter, platform utils
  actors/   player, zombie, spawn manager, swarm manager
  combat/   weapon, weapon data, projectile, projectile manager
  world/    procedural arena builder, camera rig
  ui/       HUD, pause menu, death overlay, safe area, mobile controls,
            virtual joystick, debug overlay
resources/
  weapons/  WeaponData .tres instances (e.g. smg.tres)
  actors/   reserved for future actor-tuning resources
tests/      reserved for automated tests
docs/       architecture.md
export_presets.cfg   Android export preset (see Mobile / Android above)
```

## Known limitations (expected at this stage)

- Zombies steer directly at the player and do not path around obstacles —
  they can get stuck on building corners. Acceptable for a prototype;
  real pathfinding is a later concern.
- `interact` is bound but has no target yet (no interactable objects
  exist in this slice).
- No save/load, no persistence between runs.
- No Android SDK/export templates in this environment — the Android
  export preset is unverified; see Mobile / Android above.
- Multi-aspect-ratio layout was verified by code/anchor review, not by
  an actual window resize — this dev environment's game window is
  embedded for screenshot capture and reports "can't be resized."
  Recommend a manual desktop-resize or real-device check.
