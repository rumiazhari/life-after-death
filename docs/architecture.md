# Architecture

This document describes the systems implemented in the Phase 0 / Phase 1
combat vertical slice and the Phase 2A autonomous survivor/settlement
simulation vertical slice, and where later systems (procedural world
generation, quests, economy, crafting, factions, crime, family/children,
advanced construction) are expected to attach.

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

`Survivor` (Phase 2A) got damage/death for free by adding the same
component.

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

`Survivor` (`survivor.gd`, added in Phase 2A) lives alongside `Zombie`
here, sharing `HealthComponent` and the same `Weapon`/`WeaponData`
pipeline, but has no `SpawnManager`-style manager of its own -- the
settlement's population is small and fixed for this slice, spawned
directly by `main.gd`. See "Phase 2A" below for its AI.

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
| 5 | 16 | Survivors |

Player mask = world + zombies. Zombie mask = world + player + zombies +
survivors (physically blocked by all of them). Survivor mask = world +
zombies. Projectiles mask = world + zombies (never hit the player,
survivors, or each other). Zombie's `AttackArea` (an `Area2D`, not the
body's own collision) additionally monitors player + survivor layers so
contact damage lands on either.

## Phase 2A: autonomous survivor and settlement simulation

Everything below is additive to the Phase 0/1 slice above: existing
combat, `InputRouter`, mobile controls, the zombie swarm, and scene
structure are unchanged except where noted (`Zombie` targeting and the
`AttackArea` mask, both explained under "Zombies can now threaten
survivors" below). Phase 2A.1 (below, in the Job/Reservation lifecycle
sections and "Death and restart") hardened this slice's data-integrity
guarantees -- reservation/haul-interruption edge cases and the
persistent-record/restart-reset behavior -- without changing the
observable AI/gameplay behavior described above.

### Simulation tick architecture -- `scripts/core/simulation_clock.gd` (autoload `SimulationClock`)

A `Node` autoload that is the single source of "how much game time
passed." It accumulates real `delta * speed` into a fixed
`tick_interval_seconds` step (default 0.25s) and only advances game time
in those fixed increments -- a slow frame processes more ticks in one
`_process` call (capped at `_MAX_TICKS_PER_FRAME` so a debugger-stall
frame can't spiral) rather than skipping simulated time. `speed` is a
`SimSpeed` enum (`PAUSED` / `NORMAL` / `FAST`); `real_seconds_per_game_minute`
converts real ticks to in-game minutes. Emits `sim_tick(tick_count)` every
fixed tick (what AI staggering keys off, see below), and
`minute_changed` / `hour_changed` / `day_changed` as game time rolls over
(what need decay and settlement danger recompute key off).

`SimulationClock` deliberately does **not** set
`process_mode = PROCESS_MODE_ALWAYS` (unlike `InputRouter`/`PauseMenu`),
so pausing the game (`SceneTree.paused = true`, e.g. on player death) also
pauses simulated time -- consistent with the existing pause behavior for
combat, and the reason `SurvivorAI` needs no special-casing to also
freeze correctly on pause.

### Persistent data vs. runtime nodes -- `scripts/core/world_state.gd` (autoload `WorldState`)

`WorldState` is the authoritative registry for survivors, settlements,
inventories, and jobs -- **not** the `Survivor`/`Settlement`/
`StorageContainer` nodes themselves. Each holds a plain data
`Resource`/object (`SurvivorData`, `SettlementData`, `Inventory`) and a
stable `int` id assigned by `WorldState.register_*()`; the node is a
*view* onto that data (reads/writes it, forwards physics/rendering), not
the data's owner. This is what "off-screen/reduced simulation" and (in a
later phase) save/load can build on: a survivor's data can keep existing
and being reasoned about even if its actor node is far off-screen or not
instantiated at all.

- `SurvivorData` (`scripts/survivors/survivor_data.gd`, a `Resource`):
  id, name, age, vitals (health/hunger/thirst/fatigue/morale/fear/
  infection_exposure), skills, movement speed, personality modifiers,
  current settlement/goal/action, relationships map.
- `SettlementData` (`scripts/world/settlement_data.gd`): id, name, danger
  level, member ids, storage container ids by role.
- `Inventory` (`scripts/items/inventory.gd`, `RefCounted`, see below):
  used both for a survivor's carried items and for settlement storage --
  the same class on both sides of every transfer.

`WorldState.to_snapshot()` walks all of the above into plain
dictionaries (via each type's `to_dict()`) plus current sim time and
world flags. This is *preparation* for save/load -- nothing reads or
writes it to disk yet.

### Utility AI -- `scripts/ai/`

`UtilityAction` (`scripts/ai/utility_action.gd`) is the base class for
one candidate behavior: `score(ai) -> float`, `can_start(ai) -> bool`,
`enter/tick/exit(ai)`. `SurvivorAI` (`scripts/ai/survivor_ai.gd`, a
`Node` child of `Survivor`) holds one instance of each of the 14 actions
under `scripts/ai/actions/` (idle, wander, eat, drink, sleep,
seek_safety, flee, fight, retrieve_supplies, haul_supplies, scavenge,
treat_self, help_injured, guard) and, on each reconsideration, scores
every action and runs whichever wins -- there is no hard-coded state
machine branching on action type.

**Scoring formula.** Each action computes its own score from whatever
mix of these it needs (`scripts/ai/utility_math.gd` holds the shared
curves so every action derives them the same way):

- **urgency** -- `UtilityMath.urgency(value, threshold)`: 0 below a
  threshold, ramping 0..1 as a need (hunger/thirst/fatigue/missing
  health) gets worse. Needs that aren't a problem yet contribute nothing.
- **risk** -- `UtilityMath.risk_from_danger(danger_level, brave)`:
  settlement/point danger scaled down by the survivor's `brave`
  personality trait.
- **distance** -- `UtilityMath.distance_cost(distance, max_range)`: 0 at
  the survivor's feet, 1 at or beyond `max_range`; subtracted from
  benefit so a same-value-but-farther option scores lower.
- **expected benefit** -- action-specific (e.g. scavenging benefit scales
  with `scavenging_skill`; guarding benefit scales with `brave`/
  `diligent` and current settlement danger).
- **survivor personality** -- the four modifiers on `SurvivorData.personality`
  (`brave`, `cautious`, `diligent`, `social`) bias risk tolerance, hauling/
  guarding willingness, and help-injured willingness respectively.
- **settlement priorities** -- e.g. `ActionGuard` scores higher as
  `Settlement.danger_level()` rises; `ActionSleep`/`ActionSeekSafety`
  score against the same danger level from the other direction.
- **resource availability** -- actions that depend on stock (Eat/Drink/
  TreatSelf on carried items; RetrieveSupplies/Scavenge/Haul on
  settlement/point stock) score 0 when nothing is available, rather than
  scoring speculatively and failing at execution time.
- **interruption cost** -- `UtilityAction.interrupt_cost`: in
  `SurvivorAI._reconsider()`, a candidate must beat the *currently
  running* action's score by more than that action's `interrupt_cost` to
  take over (unless the candidate is `is_emergency` and simply scores
  higher) -- this is what stops two near-tied actions from flickering
  every reconsideration.

**Reconsideration cadence.** `SurvivorAI` reconsiders on a per-survivor
jittered timer (`base_decision_interval` ± `decision_jitter`, default
~1.1-1.9s), not every physics frame and not synchronized across
survivors -- decision cost stays flat as survivor count grows. Perception
(nearby zombies, cached on `SurvivorAI.nearby_zombies`/`nearest_zombie`)
refreshes on its own shorter, separately-jittered timer
(`base_perception_interval`, default ~0.5s) so "is anything a threat"
stays cheap and current without being recomputed every frame either.

**Emergency interrupts.** After each perception refresh,
`_check_emergency()` checks "is a zombie within `emergency_zombie_radius`"
or "is health below 25%"; if so and the current action isn't already
`is_emergency` (Flee/Fight are the only two), it zeroes the decision
timer so `_reconsider()` runs on the *next* physics frame instead of
waiting out the rest of the normal interval. This is the mechanism behind
"emergency needs and nearby threats interrupt lower-priority actions."

### Job lifecycle -- `scripts/jobs/job.gd`, `scripts/jobs/settlement_job_board.gd`

A `Job` (`RefCounted`) is one unit of settlement work: `SCAVENGE` (claim a
`ScavengePoint`), `HAUL` (move a specific reserved item stack between two
containers), `GUARD` (hold a `GuardPost`), or `HELP_INJURED` (declared for
future use -- the current `ActionHelpInjured` uses a cheaper direct claim,
see below). Status moves `AVAILABLE -> RESERVED` (`claim_job`, a survivor
committed) `-> ACTIVE` (`start_job`, the survivor is actually executing
it, e.g. arrived and working) `-> COMPLETED` / `FAILED` / `CANCELLED`.

- `SCAVENGE` and `GUARD` jobs are created once at scenario setup (one per
  `ScavengePoint` / `GuardPost`, `main.gd._setup_settlement_jobs()`) and
  are *not* removed on completion if there's still work to do:
  `ActionScavenge` calls `release_survivor()` instead of `complete_job()`
  when the point isn't yet depleted, reopening the job (`AVAILABLE`) for
  a future visit instead of retiring it after one harvest. `GUARD` jobs
  are never completed at all -- holding one just means "no higher-scoring
  action has won yet."
- `HAUL` jobs are created dynamically by
  `SettlementJobBoard._refresh_haul_jobs()` (checked once per sim tick)
  whenever general storage holds stock that belongs in food/water/medical
  storage, and complete for good once delivered.
- `SettlementJobBoard._validate_some_jobs()` target-validates a handful of
  jobs per sim tick (`jobs_validated_per_tick`, round-robin cursor, not
  the whole list every tick) and cancels any whose node target no longer
  exists (`Job.is_target_valid()` via a `WeakRef`) -- e.g. a fully-
  depleted `ScavengePoint` frees itself, and the next validation pass
  cancels any job still pointing at it.

**HAUL sub-state (`Job.haul_phase`).** `Status` alone can't tell "claimed
and traveling to pick up" from "cargo physically in the carrier's own
inventory" -- `start_job()` flips `Status` to `ACTIVE` on the very first
tick, well before pickup actually completes. `haul_phase` tracks this
separately: `AWAITING_PICKUP` (set at job creation) `-> IN_TRANSIT` (set
by `SettlementJobBoard.mark_picked_up()`, called by `ActionHaulSupplies`
right after a successful pickup transfer, which also clears the now-spent
`reservation_id`) `-> DELIVERED` (set in `complete_job()` just before the
job is removed). This is what makes interruption after pickup safe (see
"Reservation lifecycle" below): `SettlementJobBoard.release_survivor()`
refuses to reopen an `IN_TRANSIT` job even if called on it, so a survivor
that already has the cargo in hand is the only one who can ever finish
that delivery -- `get_in_transit_haul_job(survivor_id)` is how
`ActionHaulSupplies.enter()` finds and resumes it after being interrupted
mid-delivery, ahead of any fresh job/personal-carry scan.

A HAUL job's dropoff leg distinguishes a *missing* destination (container
no longer registered -- permanent, so `_tick_job()` fails the job
immediately rather than waiting forever at a stop that can never accept
the cargo) from a *full* one (transient -- the cargo stays safely with
the survivor and the dropoff retries next tick, since capacity might free
up).

### Reservation lifecycle -- `scripts/items/inventory.gd`

`Inventory.reserve(item_id, amount) -> reservation_id` claims stock
without moving it; `get_available()` (count minus reserved) is what a new
claim actually sees, so two survivors evaluating the same tick can't both
commit to the same last unit. A reservation resolves one of two ways:

- `confirm_reserved_transfer(reservation_id, to)` -- atomically moves the
  reserved stack into another `Inventory` and clears the reservation in
  one call (used when a survivor actually arrives and picks something up
  in HAUL/SCAVENGE/RETRIEVE_SUPPLIES actions). If the destination can't
  fit it, the reservation is deliberately left intact rather than cleared
  -- the caller (e.g. `ActionRetrieveSupplies.tick()`) checks
  `has_reservation()` afterward and either retries next tick (still
  present -- a transient capacity issue) or stops (already gone -- the
  source depleted, which this method releases on the caller's behalf).
  Every caller of `confirm_reserved_transfer` is required to handle both
  outcomes this way; clearing a local reservation id after an
  unchecked/failed call is exactly how a reservation used to get orphaned
  (fixed in Phase 2A.1 for `ActionRetrieveSupplies`, which previously
  cleared its id unconditionally on return).
- `release_reservation(reservation_id)` -- drops the claim without moving
  anything; safe to call on an id that's already been resolved. Called
  from every action's `exit()` when interrupted (via
  `current_action.exit(self)` in both the normal per-frame interruption
  path and `SurvivorAI.stop()` on death) and from
  `SettlementJobBoard.cancel_job()`/`fail_job()` -- this is what
  guarantees a dead or interrupted survivor never leaves a reservation
  permanently stuck. A HAUL job's own `reservation_id` is a special case:
  it's cleared (set to 0) the moment pickup succeeds
  (`SettlementJobBoard.mark_picked_up()`), since from that point the
  cargo is tracked by `haul_phase`/`carrier_survivor_id` instead (see
  "Job lifecycle" above) -- there is nothing left on the *source*
  container to reserve or release once the items have physically left it.

`Inventory.transfer_item(from, to, item_id, amount)` is the unconditional
(non-reservation) atomic move, used for a survivor depositing its own
carried stock (which nothing else could be racing for) and for the
player using the same storage.

**Capacity-aware scavenging.** `ScavengePoint.harvest(max_amount)` takes
the amount to remove as a parameter rather than always removing a full
yield -- `ActionScavenge.tick()` computes `Inventory.max_fit(item_id)`
(how many units the survivor's carried inventory has room for, without
mutating anything) *before* calling `harvest()`, so a survivor with a
nearly-full inventory only takes what actually fits and leaves the rest
at the point instead of it being removed from the world and then
discarded for lack of room. `harvest(0)` removes nothing.

### Death and restart

**Death is permanent but the record isn't deleted.** `Survivor._on_died()`
sets `SurvivorData.is_dead = true`, removes the survivor from its
settlement's *living* roster (`SettlementData.member_ids`), and leaves
the `SurvivorData` itself registered in `WorldState.survivors` -- it is
**not** erased, so it still appears in `WorldState.to_snapshot()` and its
id is never reused within the same run.
`WorldState.is_survivor_alive(id)` / `get_living_survivors()` are the
explicit "excludes the dead" queries other systems should use instead of
assuming every registered id is alive. `WorldState.unregister_survivor()`
still exists for a deliberate purge, but nothing calls it on natural
death anymore.

`SurvivorAI.stop()` (called once, from `_on_died()`) resolves every claim
the dying survivor held, in order: `current_action.exit(self)` first --
the same release path a live interruption would take, which correctly
leaves an `IN_TRANSIT` HAUL job alone (see "Job lifecycle") -- then
`SettlementJobBoard.release_survivor_permanently(id)`, which is the one
difference from a normal interruption: any HAUL job still `IN_TRANSIT`
for this survivor is `fail_job()`-ed outright (its cargo was in the now-
gone carried inventory and can never be delivered) rather than being
reopened for a different survivor to walk to an already-emptied pickup
point, and every other job the dead survivor held (an `AWAITING_PICKUP`
haul, a scavenge/guard claim) is released normally since those
reservations/claims are still genuinely available to someone else.

**Restart resets both simulation autoloads.** `SimulationClock` and
`WorldState` are autoloads and survive
`SceneTree.reload_current_scene()` (only the scene tree is torn down and
rebuilt) -- without an explicit reset, a restarted run would inherit the
previous run's time-of-day, speed, and every dead survivor/completed
job/id counter ever produced. `Main._restart_game()` calls
`WorldState.reset()` and `SimulationClock.reset()` synchronously *before*
`reload_current_scene()`, so by the time the new scene's
`Settlement`/`StorageContainer`/`Survivor` nodes register themselves the
registries are already empty and id generators already back at 1.
`SimulationClock.reset()` also restores `speed` to `NORMAL`.
`total_game_minutes()` is `(game_day - 1) * 1440 + ...` -- day 1, 00:00
evaluates to exactly zero, since `game_day` is 1-based.

Selection UI state (`SurvivorInspector._selected`) needs no explicit
reset: it's an ordinary scene node, destroyed and recreated fresh by the
same `reload_current_scene()` call. Signal connections between an
autoload and a scene-local node (e.g. `SettlementJobBoard` to
`SimulationClock.sim_tick`, `SurvivorAI` to
`SimulationClock.minute_changed`) also need no manual bookkeeping on
restart: Godot disconnects a signal automatically when either endpoint is
freed, and every such receiver here is scene-local.

### Active vs. off-screen simulation

`Survivor` carries a `VisibleOnScreenNotifier2D`
(`is_on_screen`, toggled by its `screen_entered`/`screen_exited`
signals). `SurvivorAI` multiplies both its decision and perception
intervals by `offscreen_slowdown` (default 3x) whenever `is_on_screen` is
false, so an off-screen survivor still reconsiders and perceives threats,
just far less often -- proportionally cheaper instead of a separate coarse
simulation path. Physics movement itself (`move_and_slide()`) is not
throttled; at four survivors this is cheap regardless of screen state, and
throttling it would risk a survivor's position silently drifting out of
sync with its last-seen collision state.

### Zombies can now threaten survivors

`Zombie._seek_target()` used to always target the single "player" group
node. It now periodically (`retarget_interval`, jittered, not every
frame) picks the nearest node in the new `"attackable"` group, which
`Player` and `Survivor` both join -- so zombies can converge on whichever
is closer/most exposed instead of ignoring survivors entirely. The
swarm/separation steering itself, and `Zombie` having no
`NavigationAgent2D`, are unchanged. `Zombie.AttackArea`'s
`_on_attack_area_body_entered` also switched from an `is_in_group("player")`
check to the project's own documented duck-typing convention
(`has_method("take_damage")`), matching how `HealthComponent` is already
described as this project's "damage interface."

### Settlement -- `scripts/world/`

`Settlement` (`settlement.gd`) collects its own `StorageContainer`
(`storage_container.gd`, role "general"/"food"/"water"/"medical", each
wrapping its own registered `Inventory`), `SleepSpot`
(`sleep_spot.gd`, single-occupant claim), and `GuardPost`
(`guard_post.gd`, a job-board target) children by walking its own
subtree in `_ready()` -- direct ownership, not a cross-cutting lookup, so
this is one of the few places that doesn't use group-based discovery.
`danger_level()` recomputes periodically (staggered on `sim_tick`, not
every tick) from how many zombies are within `danger_check_radius`.
`ScavengePoint` (`scavenge_point.gd`) is a standalone depleting resource
node, scattered directly in `Main.tscn` rather than owned by the
settlement, since scavenging happens away from home.

### Items -- `scripts/items/`

`ItemData` (a `Resource`, mirroring `WeaponData`'s pattern) defines one
item type; `resources/items/*.tres` are the five required instances
(food_ration, water_bottle, medical_supplies, ammunition, materials).
`ItemDatabase` (autoload) loads every `.tres` under `resources/items/`
once at startup and is the only place item stats are looked up by id --
adding a new item is a new `.tres`, not new code. (`ammunition` is
defined but not yet wired to `Weapon`'s reload, which still uses its own
internal `reserve_ammo` counter -- see Known limitations.)

### Observability

`SurvivorInspector` (`scripts/ui/survivor_inspector.gd`,
`scenes/ui/SurvivorInspector.tscn`) is a read-only panel, purely reactive
to `GameEvents.survivor_selected` like `HUD` is to its own signals --
never writes back to the survivor. Selection is a right-click nearest-
survivor pick handled in `main.gd._try_select_survivor()` (kept off the
existing left-click "fire" binding on purpose), which just emits
`GameEvents.survivor_selected`; nothing about selecting a survivor can
command it. `DebugOverlay` gained a second line of counters: survivor
count, decisions/s and actions-evaluated/s (both accumulated over a
rolling ~1s window -- an instantaneous per-frame rate would read ~0 most
frames since individual reconsiderations are sparse relative to 60fps),
average decision time, job board counts by status, and total inventory
reservations across every registered container.

### Extension points

- **Settlement construction**: `StorageContainer`/`SleepSpot`/`GuardPost`
  are already placeable primitives; a build system would add new ones at
  runtime (reserving `materials` via the same `Inventory` reservation
  path) rather than needing new placement infrastructure.
- **Factions / crime**: `SettlementData.member_ids` and
  `SurvivorData.relationships` (currently unused) are the natural anchors
  -- faction standing and crime consequences would read/write those
  rather than needing new per-survivor state.
- **Economy**: `Inventory`/`ItemData` already model stock and transfer;
  a market would be a new job type (`Job.Type.TRADE`) reusing the same
  reservation-then-confirm pattern as `HAUL`.
- **Family / children**: `SurvivorData.relationships` plus a new "age
  survivor over time" hook off `SimulationClock.day_changed`.
- **Consequential quests**: new `GameEvents` signals (matching the
  existing "extend the bus, don't add direct references" rule) fired
  from job completion/failure or settlement danger crossing a threshold.
- **Save/load**: `WorldState.to_snapshot()` already produces the
  serializable shape; wiring it to `ResourceSaver`/`FileAccess` is the
  remaining step, plus a matching load path that reconstructs runtime
  nodes (`Survivor`, `StorageContainer`, ...) from restored `WorldState`
  data instead of the other way around.

## Where the remaining excluded systems would attach

Settlements, world state, and survivors are implemented as of Phase 2A
(see above); their extension points are listed there. Still excluded:

- **Quests / economy / crafting**: see the Phase 2A extension points
  above (new job types, new `GameEvents` signals, a `Resource`-driven
  recipe pattern mirroring `WeaponData`/`ItemData`).
- **Procedural world generation**: extends or replaces `ArenaBuilder`;
  `SpawnManager`'s camera-relative spawn-ring logic does not assume a
  fixed arena size, so it should keep working unmodified. `Settlement`
  and `ScavengePoint` placement is currently hand-authored in
  `Main.tscn`; a generator would need to place these too, or query
  `ArenaBuilder` for valid non-building positions.
- **Android export / graphical polish**: unchanged from Phase 0/1 (see
  Mobile / Android in the README).
