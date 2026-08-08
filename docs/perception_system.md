# Perception, navigation, and noise (Phase 3B)

Removing zombie omniscience, the bounded perception state machine that
replaced it, the shared navigation grid it falls back on, and the
centralized noise/hearing system both zombies and survivors read from.

## What existed before

`Zombie._find_nearest_attackable()` (Phase 2A) scanned the whole
`"attackable"` group every retarget tick and picked the nearest member —
**no maximum range**. The player (and, within a fixed radius, survivors)
was targetable from anywhere on the map. The task spec was explicit:
"Remove this behavior."

## `ZombiePerceptionComponent` — `scripts/ai/zombie_perception_component.gd`

A `Node` child of `Zombie` (`$Perception`), owns all targeting decisions —
`Zombie` itself never scans the `"attackable"` group or decides who to
chase; it only asks `perception.state`/`perception.target`/
`perception.last_known_position` each physics frame (see
`Zombie._seek_current_goal()`).

**State machine:** `IDLE → SUSPICIOUS → CHASE → ATTACK`, with
`INVESTIGATE` (hearing-triggered) and `SEARCH → RETURN_TO_IDLE` on losing
a target. Losing sight/sound is never a permanent memory — `SEARCH` times
out to `RETURN_TO_IDLE` after `search_duration` (default 4s), clearing
`target`.

**Vision detection**, cheapest check first so the expensive one runs
least often:

1. Squared-distance filter against `vision_distance` (default 260px) —
   free.
2. Facing-relative view-cone filter (`vision_cone_degrees`, default
   100°, dot-product against `facing`) — free, only for candidates that
   passed (1).
3. A single raycast (`World | Vision` mask) — the only per-candidate cost
   that touches the physics server, only for candidates that passed (1)
   and (2). The `"attackable"` group is always small (player + ≤4
   survivors this slice), so even this per-tick scan itself stays cheap.

**Suspicion, not instant aggro.** A visible candidate raises `_suspicion`
by `suspicion_buildup` (1.5) each perception tick; only once it crosses
`suspicion_threshold` (2.0) — i.e. after roughly 2 consecutive sightings —
does the state promote to `CHASE`/`ATTACK`. A single frame of visibility
enters `SUSPICIOUS`, not `CHASE`. Suspicion decays (`suspicion_decay`,
0.6/tick) when nothing is visible.

**Staggered low-frequency updates**, not every physics frame:
`update_interval` (default 0.35s) ± a per-instance jitter drawn from a
**private** `_gameplay_rng` (seeded via `rng_seed`, same RNG-isolation
contract as `Zombie`/`SpawnManager` from Phase 3A.1 — see
`tests/test_runner.gd`'s `cosmetic_rng_does_not_affect_*` tests). With
hundreds of zombies, staggering means the raycast-eligible subset in any
one frame is small.

## Hearing — `scripts/core/noise_manager.gd` (autoload `NoiseManager`)

One shared signal (`noise_emitted`) and a small bounded ring buffer
(`MAX_RECENT = 32`), not one `Area2D` per sound. `emit_noise(position,
loudness, category, source)` records `{position, loudness, category,
tick}`; `recent_noises_near(listener_position, hearing_radius,
within_ticks)` filters by both recency (sim ticks, not real time) and an
`effective_radius = min(loudness * 20.0, hearing_radius)` — a louder
sound reaches farther, up to the listener's own hearing cap. A zombie
only checks hearing while `IDLE`/`RETURN_TO_IDLE` (vision already owns
`SUSPICIOUS`/`CHASE`/`ATTACK`); a qualifying noise promotes straight to
`INVESTIGATE` with the noise's position as a **lead to search**, never a
permanent exact target. One noise event never alerts the whole
population — only zombies whose own `hearing_radius` check against that
specific noise's `effective_radius` passes react at all, and even then
each reacts independently, on its own next perception tick.

Noise categories in use: `door` (a door's `noise_loudness`, default 8 —
default excluded from the initial silent `_ready()` load, only emitted on
an actual open/close), `search` (loot container, loudness 4), `salvage`
(loudness 5), `gunshot` (`Weapon.try_fire()`, loudness 20 — loud and
far-reaching, but still only *nearby* zombies react, since
`effective_radius` is still capped by each listener's own
`hearing_radius`).

## Navigation — `scripts/world/urban_navigation_service.gd` (autoload `UrbanNavigationService`)

One shared `AStarGrid2D`, built **once** from the district's static
World-layer collision (`build(half_extent)`, called from
`DistrictBuilder._ready()`'s end) — not a `NavigationAgent2D` per zombie
doing its own unrestricted pathfinding every frame.

- `is_direct_path_clear(from, to)` — a single raycast, the cheap
  preferred check; callers try this first.
- `find_path(from, to)` — only when blocked, and budget-capped
  (`MAX_REQUESTS_PER_FRAME = 8`, reset every physics frame) so a burst of
  simultaneous requests (a whole swarm losing line of sight at once)
  can never spike one frame's cost. Returns an empty path on budget
  exhaustion, an out-of-bounds request, or before `build()` has run —
  callers must treat all three as "fall back to direct steering," never
  as an error.
- Door-aware: `register_door(door_id, world_position)` records a door's
  grid cell once; `mark_door_open`/`mark_door_closed` (called by `Door`
  itself, from `toggle()`) flip that one cell's solidity, so a
  since-closed door invalidates a previously-valid route and a
  newly-opened one immediately becomes available. Closed doors block
  zombie pathing (door destruction/breaking is explicitly out of scope
  this phase).

`Zombie._seek_point()` is the integration point: it steers directly
toward its current goal by default, and only consults
`UrbanNavigationService` on a 1-second recheck timer
(`NAV_RECHECK_INTERVAL`) when the direct line is actually blocked —
caching whatever path it gets and following its waypoints until either
arrival or the next recheck finds a clear direct line again. This keeps
navigation a **fallback**, not a per-frame cost, for every zombie.

**Not wired into `Survivor` movement this pass** — a deliberate scope
decision (see `docs/building_system.md` "Known limitations") to avoid
destabilizing the existing, well-tested `SurvivorAI`/`UtilityAction`
movement system this late in the phase.

**Debug visualization:** off by default. `ZombiePerceptionComponent.
debug_draw_enabled` is a **per-instance** flag (not `static` — an earlier
draft had this as a shared class-level flag, which made every zombie in
a swarm draw overlapping cones the instant any one of them was flagged
for debugging; fixed to an instance var). Set it on one target zombie
(`zombie.perception.debug_draw_enabled = true`) to draw its vision
cone (green when it has a target, amber otherwise), a line + dot to
`last_known_position`, and its current state as text — see
`docs/screenshots/phase-3b/zombie-perception-debug.png`.

## Survivor local threat response — `scripts/ai/survivor_ai.gd`

`SurvivorAI._refresh_perception()` already computed `nearby_zombies`/
`nearest_zombie` within `perception_radius` (420px) from Phase 2A. Phase
3B adds one filter: a zombie beyond `emergency_zombie_radius` (160px,
the same "close enough to always react regardless" safety margin used
elsewhere) is excluded if a wall blocks line of sight
(`_blocked_by_wall`, a `World | Vision` raycast — the identical mask
`ZombiePerceptionComponent` itself raycasts against, so "can this zombie
plausibly see/be seen" means the same thing on both sides). A zombie
*within* the emergency radius always counts, wall or not — a point-blank
threat is never filtered out on a technicality. This is what stops a
survivor from reacting to a zombie it "shouldn't know about" behind a
wall while still reacting instantly to one that's right on top of it.

`_check_emergency()` (unchanged from Phase 2A) still zeroes the decision
timer when `nearest_zombie_distance <= emergency_zombie_radius` — Phase
3B's filter changes *which* zombies can ever reach that check, not the
check itself.

## Collision layers (full table, all systems)

| Layer (bit) | Value | Used by |
|---|---|---|
| 1 | 1 | World geometry (buildings, boundary, closed doors, walls) |
| 2 | 2 | Player |
| 3 | 4 | Zombies |
| 4 | 8 | Player projectiles |
| 5 | 16 | Survivors |
| 6 | 32 | Vision (walls, closed doors, boarded windows — raycast-only, never a movement blocker on its own) |
| 7 | 64 | Interactable (doors' reach area, loot/salvage props' reach area) |

Zombie perception raycasts `World | Vision` (1\|32). `UrbanNavigationService`'s
grid solidity check uses `World` (1) only — a boarded window with no
physical body would block sight but not pathing (none currently exist:
every `BuildingWindow` is physically solid regardless of boarded state).
`PlayerInteractor` masks `Interactable` (64) only.

## Known limitations

- No perception/raycast/nav-request-rate telemetry counters were added to
  `DebugOverlay` this pass — the Phase 3B performance report (see the
  completion report) measures these via a temporary in-session profiling
  probe instead of a permanent on-screen readout.
- Zombie hearing and vision share one state machine's promotion path but
  don't compose (e.g. a *quiet* nearby noise plus a *marginal* sighting
  don't add up toward suspicion together) — each is evaluated
  independently against the same state.
- `UrbanNavigationService` is Zombie-only; see `docs/building_system.md`.
