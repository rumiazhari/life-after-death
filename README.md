# Life After Death

A top-down zombie-action prototype built in Godot 4.7.1. This is the
Phase 0 / Phase 1 vertical slice: a stable action-combat foundation
(movement, aiming, shooting, a swarm of zombies, and a minimal HUD/pause/
death loop) for later systems — settlements, quests, economy, survivors,
crafting, procedural world generation — to build on. None of those later
systems are implemented yet.

## Requirements

- Godot 4.7.1 (Mobile renderer, already configured in `project.godot`)

## Running

Open the project in Godot and press Play (F5), or run headless:

```
godot --path .
```

`scenes/main/Main.tscn` is the configured main scene.

## Controls

| Action          | Binding                  |
|-----------------|---------------------------|
| Move            | `WASD` or Arrow keys      |
| Aim             | Mouse position             |
| Fire            | Left mouse button (hold — automatic weapon) |
| Reload          | `R`                       |
| Interact        | `E` (mapped, unused in this slice) |
| Pause / Resume  | `Escape`                  |
| Restart (on death) | `Enter` or the on-screen Restart button |

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
  a pause menu, and a death/restart overlay.

See [`docs/architecture.md`](docs/architecture.md) for how the systems
are wired together and where later systems should hook in.

## Project layout

```
scenes/
  main/     Main.tscn — top-level scene composition
  actors/   Player.tscn, Zombie.tscn
  combat/   Projectile.tscn
  ui/       HUD.tscn, PauseMenu.tscn, DeathOverlay.tscn
scripts/
  core/     signal bus, health component, object pool, Main controller
  actors/   player, zombie, spawn manager, swarm manager
  combat/   weapon, weapon data, projectile, projectile manager
  world/    procedural arena builder, camera rig
  ui/       HUD, pause menu, death overlay
resources/
  weapons/  WeaponData .tres instances (e.g. smg.tres)
  actors/   reserved for future actor-tuning resources
tests/      reserved for automated tests
docs/       architecture.md
```

## Known limitations (expected at this stage)

- Zombies steer directly at the player and do not path around obstacles —
  they can get stuck on building corners. Acceptable for a prototype;
  real pathfinding is a later concern.
- `interact` is bound but has no target yet (no interactable objects
  exist in this slice).
- No save/load, no persistence between runs.
