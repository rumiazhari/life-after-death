# Architecture

This document describes the systems implemented in the Phase 0 / Phase 1
vertical slice and where later systems (settlements, quests, economy,
survivors, crafting, procedural world generation) are expected to attach.

## Guiding rules

- **Modularity over one big script.** Each concern (health, weapon state,
  spawning, swarm broad-phase, arena generation, camera, each UI panel)
  is its own script attached to its own node. `scripts/core/main.gd` only
  wires these systems together; it does not implement gameplay itself.
- **Decoupling via signals, not direct references.** Systems that need to
  react to something happening elsewhere (HUD reacting to damage, kills,
  ammo; SpawnManager counting a kill) do so through the `GameEvents`
  autoload signal bus, not by holding a reference to the emitting node.
  This is what keeps `scripts/ui/`, `scripts/actors/`, and
  `scripts/combat/` free of circular dependencies.
- **Discovery via groups, not hard-coded node paths.** Cross-cutting
  lookups (a zombie finding the player, a weapon finding the projectile
  spawner, a zombie finding the swarm manager) use
  `get_tree().get_first_node_in_group(...)`. Nothing references another
  system by an absolute scene path or `res://` string baked into logic.

## Signal bus — `scripts/core/game_events.gd` (autoload `GameEvents`)

A `Node` autoload with no state, only signals: player health/damage/death,
zombie spawn/damage/death, population and kill counters, and weapon
fired/reload/ammo events. Any system may emit or listen; this is the one
place allowed to be depended on by everything else.

Extension point: add new signals here (e.g. `survivor_recruited`,
`quest_completed`) rather than wiring new cross-system references
directly.

## Input — `scripts/core/input_router.gd` (autoload `InputRouter`)

The single source of input for gameplay: exposes `movement_vector`,
`aim_vector`, `fire_pressed`, `reload_pressed`, `interact_pressed`,
`pause_pressed` (plus `reload_requested`/`interact_requested`/
`pause_requested` signals for the momentary ones). `Player` and
`PauseMenu` read only from here — never `Input`/`InputMap` directly, and
never from `MobileControls`.

Desktop: computed every physics frame from the project's InputMap
actions (`move_up`/`move_down`/... , `fire`, `reload`, `interact`,
`pause`) and the mouse position relative to the viewport center (an
approximation of "aim at the mouse" that stays fully decoupled from the
player's world position — see `MobileControls` below for why that
matters).

Mobile: `MobileControls` (`scripts/ui/mobile_controls.gd`) is the *only*
node that calls InputRouter's touch setters (`set_touch_movement`,
`set_touch_aim`, `request_reload`, etc.) in response to the on-screen
joysticks/buttons. InputRouter prefers touch state over
keyboard/mouse whenever a touch is active, so the two input schemes
never fight each other. This two-way decoupling (gameplay never reads
touch UI; touch UI never reads gameplay) is what let the mobile input
work land without changing `Weapon` at all and touching `Player` only at
the InputRouter call sites.

`process_mode = PROCESS_MODE_ALWAYS` on InputRouter is load-bearing: the
pause action has to keep being read while `SceneTree.paused` is true, or
nothing could ever unpause.

Extension point: a new input source (gamepad, replay playback) is a new
producer of the same six fields/signals; nothing downstream changes.

## Touch controls — `scripts/ui/mobile_controls.gd`, `virtual_joystick.gd`

`TouchJoystick` (file `virtual_joystick.gd` — named to avoid colliding
with Godot 4.7's built-in `VirtualJoystick` control, whose action-driven
design doesn't fit a continuously-polled analog vector) is a fixed-position
on-screen joystick. It does its own hit-testing and touch-index tracking
but has **no** input pipeline access of its own; `MobileControls` is the
single `_input()` listener that forwards every `InputEventScreenTouch` /
`InputEventScreenDrag` to both joysticks via `handle_touch_event()`. Each
joystick only reacts to a touch index it already owns, or an unclaimed
touch-down landing in its own catch radius — so one finger can never
steal the other joystick's finger, and a third finger tapping a button
elsewhere doesn't interfere with either.

`PlatformUtils.should_show_mobile_controls()`
(`scripts/core/platform_utils.gd`) decides visibility: true on an actual
mobile export (`OS.has_feature("mobile")`), or on desktop when the
`debug/mobile_controls/force_visible` project setting is enabled — a
dev-only escape hatch for testing touch controls without a device.

## Safe area — `scripts/ui/safe_area.gd` (`SafeArea`)

A reusable `Control` that insets its own rect to
`DisplayServer.get_display_safe_area()` (notches, rounded corners,
system bars) and re-applies on every resize/rotation. `HUD` and
`MobileControls` each parent their screen-edge content (corner labels,
joysticks, buttons) under one of these instead of directly under their
CanvasLayer's root Control. No-op (zero margins) on platforms without a
safe-area concept, so it's safe to use everywhere, not just Android.

## Damage — `scripts/core/health_component.gd` (`HealthComponent`)

A reusable `Node` component, not a base class. `Player` and `Zombie` each
own one as a child (`$HealthComponent`) and forward
`take_damage(amount, source)` to it. It owns `current_health`,
invulnerability timing, and emits `damaged` / `health_changed` / `died`.
This is the project's "damage interface": anything that can be hurt
exposes a `take_damage(amount, source)` method (`Player.take_damage`,
`Zombie.take_damage`) that projectiles and contact-damage sources call
via duck typing (`if body.has_method("take_damage")`), so combat code
never needs to know the concrete class of what it's hitting.

Extension point: a future `Survivor` actor gets damage/death for free by
adding the same component.

## Pooling — `scripts/core/object_pool.gd` (`ObjectPool`)

A generic instantiate-once/reuse-many pool used by `ProjectileManager`.
Not Godot-node-specific beyond expecting a `PackedScene`; any
frequently-spawned node type (impact effects, pickups) can reuse it.

## Combat — `scripts/combat/`

- `weapon_data.gd` (`WeaponData`, a `Resource`): pure data — damage, fire
  rate, magazine size, reload duration, projectile speed/lifetime,
  spread, automatic/semi-auto. `resources/weapons/smg.tres` is the one
  firearm in this slice. Adding a new gun is adding a new `.tres`, not
  new code.
- `weapon.gd` (`Weapon`): fire-rate cooldown, magazine/reserve ammo,
  reload timer, procedural muzzle flash. Reports every state change
  through `GameEvents` and finds its projectile source via the
  `"projectile_spawner"` group — it has no reference to `ProjectileManager`.
- `projectile.gd` / `projectile_manager.gd`: `Projectile` is an `Area2D`
  that travels in a straight line and reports hits via
  `take_damage`; `ProjectileManager` owns the `ObjectPool` of them and is
  the only node in the `"projectile_spawner"` group.

Extension point: new weapon behaviors (burst fire, shotgun spread,
explosive) are new `Weapon`-like scripts or new `WeaponData` fields plus
branching in `try_fire`; they don't require touching `Player`.

## Actors — `scripts/actors/`

- `player.gd`: reads `InputRouter` (never `Input`/`InputMap`), updates
  velocity (accel/friction) and aim rotation independently, delegates
  firing/reload to `Weapon`, forwards damage to `HealthComponent`. Aim
  direction only updates when `InputRouter.aim_vector` is non-zero and
  otherwise holds the last direction — this is what makes a centered/
  just-touched joystick (zero vector) not snap the aim to "right" before
  the first drag.
- `zombie.gd`: seeks the player's position, applies separation steering
  from `SwarmManager.get_nearby()`, deals contact damage via an `Area2D`
  "AttackArea" ticking on an interval (not per-frame overlap checks).
  Deliberately has **no** `NavigationAgent2D` and **no** per-zombie
  pathfinding — it relies on `move_and_slide()` against world collision
  and can get stuck on obstacle corners. That trade-off is intentional
  for swarm scale; see `swarm_manager.gd` below.
- `swarm_manager.gd` (`SwarmManager`): a coarse spatial hash
  (`Vector2i` cell → zombie list), rebuilt once per physics frame.
  `get_nearby(zombie, radius)` only scans the cells overlapping the
  query radius, so neighbor lookups stay cheap as zombie count grows —
  this is what makes separation steering affordable for hundreds of
  zombies instead of an O(n²) scan.
- `spawn_manager.gd` (`SpawnManager`): spawns zombies on a ring outside
  the camera's *actual on-screen* visible half-extent (read from
  `get_viewport().get_visible_rect()`, not the design-time reference
  resolution, so this stays correct as stretch/aspect changes what's
  actually visible per device), ramps population from
  `initial_population` to `max_population` on a timer, purges freed
  references every tick, and reports population/kills through
  `GameEvents`. `max_population` comes from a `PopulationProfile`
  (`LOW`/`MEDIUM`/`HIGH`/`STRESS` → 50/100/150/250); `population_profile`
  applies on desktop, `mobile_population_profile` (default `MEDIUM`)
  applies whenever `OS.has_feature("mobile")` is true, so Android never
  silently inherits the desktop-tuned 150 cap.

Extension point: `Survivor` (a future friendly/rescuable actor) would
live alongside `Zombie` here, likely sharing `HealthComponent` and its
own manager analogous to `SpawnManager`.

## World — `scripts/world/`

- `arena_builder.gd` (`ArenaBuilder`): procedurally builds pavement,
  a road grid (with center-line markings), building obstacles
  (`StaticBody2D` + `Polygon2D` + `Line2D` outline), and a perimeter
  boundary — all primitive-drawn, seeded by `random_seed` for
  reproducibility. This is the "test arena," not a real level; procedural
  city/world generation (explicitly out of scope for this slice) would
  replace or extend this builder later.
- `camera_rig.gd` (`CameraRig`): a `Camera2D` that lerps toward an
  assigned `target`. Kept separate from `Player.tscn` so the player scene
  has no camera dependency and the camera can be retargeted (e.g. a
  future spectator/cutscene camera) without touching player code.

## UI — `scripts/ui/`

`HUD`, `PauseMenu`, `DeathOverlay`, `MobileControls`, and `DebugOverlay`
are independent `CanvasLayer` scenes. `HUD` is purely reactive
(subscribes to `GameEvents`, never reads from `Player`/`SpawnManager`
directly). `PauseMenu` owns its own pause/resume state and now listens
to `InputRouter.pause_requested` instead of checking the "pause" action
itself, so a desktop key press and a mobile button tap look identical to
it. `PauseMenu` and `DeathOverlay` keep `process_mode = PROCESS_MODE_ALWAYS`
so they keep working while `SceneTree.paused` is true, rather than
routing every frame through `Main`.

`DebugOverlay` (`debug_overlay.gd`) is a read-only profiler strip (FPS,
frame/physics time, active zombies/projectiles, projectile pool
capacity, spatial-grid queries/candidates-examined-last-frame) built the
same way as `HUD` — it only reads counters other systems already expose
(`SpawnManager.active_zombie_count()`, `ProjectileManager.
active_projectile_count()`/`pool_capacity()`, `SwarmManager.
queries_last_frame`/`candidates_examined_last_frame`), never writes to
them.

## Orchestration — `scripts/core/main.gd`

`Main` finds the player (by group), hands the camera and spawn manager
their target, and connects exactly three signals: player death → open
the death overlay and pause, death overlay restart → reload the scene,
pause menu quit → quit. Restart is a full `reload_current_scene()` rather
than manual per-system resets, so every system's own `_ready()` is the
single source of truth for "what does a fresh run look like."

## Collision layers

| Layer (bit) | Value | Used by |
|---|---|---|
| 1 | 1 | World geometry (buildings, boundary) |
| 2 | 2 | Player |
| 3 | 4 | Zombies |
| 4 | 8 | Player projectiles |

Player mask = world + zombies (physically blocked by both). Zombie mask =
world + player + zombies. Projectiles mask = world + zombies (never hit
the player or each other).

## Where the excluded systems would attach

- **Settlements / world state**: would likely become sibling managers to
  `SpawnManager` under `Main`, driven by the same `GameEvents` bus.
- **Survivors**: a new actor under `scripts/actors/`, reusing
  `HealthComponent` and the group-lookup pattern.
- **Quests / economy**: new autoloads alongside `GameEvents`, or new
  signals added to it, so existing systems don't need to know they exist.
- **Crafting**: likely a new `Resource`-driven data pattern mirroring
  `WeaponData`.
- **Procedural world generation**: extends or replaces `ArenaBuilder`;
  `SpawnManager`'s camera-relative spawn-ring logic does not assume a
  fixed arena size, so it should keep working unmodified.
