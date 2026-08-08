# Interaction and persistence system (Phase 3B, updated for Phase 3B.1)

The component framework behind every door, loot container, and salvage
prop; how the player selects and triggers one; and how the resulting
state survives being re-queried (or, eventually, reloaded).

## Framework — `scripts/interaction/`

Built around `InputRouter.interact_requested`, a signal that already
existed (Phase 0/1) but had no listener until now.

- **`InteractableComponent`** — declares "my parent (an `Area2D` on the
  Interactable layer) is something `PlayerInteractor` can act on." One
  component = one verb. A prop with two verbs (searchable *and*
  salvageable) composes two sibling `*Component` nodes under the same
  `Area2D` rather than branching inside one big script.
  `can_interact(actor)` gates eligibility (default: `enabled`);
  `interact(actor)` emits `interacted(actor)`. Callers (`PlayerInteractor`)
  are required to check `can_interact()` before calling `interact()` —
  the component itself doesn't re-check on every call, since the one
  caller in this codebase already guarantees it.
- **`PlayerInteractor`** (an `Area2D` child of `Player`, layer/mask =
  Interactable) — maintains a small **registry** of currently-overlapping
  candidate `Area2D`s via `area_entered`/`area_exited` (never a per-frame
  full-map scan). `_best_candidate()` scores by distance, with a facing
  bonus (`FACING_BONUS`, subtracted from effective distance) for anything
  within `FACING_DOT_THRESHOLD` of the player's aim — so facing a door in
  a cluttered room reliably targets that door over something merely
  nearer. Exactly one candidate is interacted with per
  `interact_requested` signal. Prunes freed nodes from its registry each
  physics frame.
- **`LootContainerComponent`** — real `Inventory`-backed (shelves,
  fridges, cabinets, cars, dumpsters). `_search(actor)` requires the
  actor expose `carried_inventory` (duck-typed, same convention as
  `HealthComponent.take_damage`), moves everything via
  `Inventory.move_all_to()`, and emits a `search` noise
  (`NoiseManager`, loudness 4). Searching an already-empty container is a
  silent no-op — the exact mechanism that prevents duplicate loot.
- **`SalvageableComponent`** — one-time `materials` yield. Disables its
  own sibling `InteractableComponent` the moment it's spent (rather than
  tracking a separate "used" flag), so a depleted prop simply stops
  appearing as a candidate at all. Emits a `salvage` noise (loudness 5).
- **`RestPointComponent`** — minimal foundation only (`last_used_tick`),
  no sleep/rest simulation implemented this pass.

## Reach vs. footprint

An interact-detection `Area2D` sized identically to a prop's own physical
collision means the player's own collision radius can never be
simultaneously *outside* the solid shape and *inside* the interact zone —
there's no valid standing position. Furniture interact areas are padded
generously beyond their physical footprint
(`BuildingShellBuilder._make_interact_area`: `collision_size +
Vector2(56, 56)`). Doors go further: a door has **two separate** `Area2D`s
— `InteractArea` (exact 30×30 footprint, used only to detect "an actor is
physically standing in the doorway," not on the Interactable layer, not
what `PlayerInteractor` sees) and `InteractReachArea` (72×72, on the
Interactable layer, what `PlayerInteractor` actually detects). Sharing
one `Area2D` for both would have forced a tradeoff between correct
door-blocking detection and comfortable interact range; splitting them
avoids it entirely.

## Doors — `scripts/world/door.gd`

Closed by default. `is_open` drives **one** `CollisionShape2D`
(`_collision.disabled = is_open`) that gates both movement and vision —
the same shape, never two flags that could desync. `toggle()` swaps the
sprite, updates the collision, persists to `WorldState`, tells
`UrbanNavigationService` to flip that door's grid cell, and (except on
the initial silent `_ready()` load) emits a `door` noise. A door refuses
to close on top of a physically-present actor
(`_block_check_area.body_entered`/`body_exited` tracking a
`_blocked_by_body` flag, checked at the top of `toggle()`) — closing is
simply skipped, safely, rather than trapping or displacing whatever's in
the doorway.

`door_id` (a stable authored `StringName`, e.g.
`"restaurant_01/door_entrance"`) is what makes state persistent: on
`_ready()`, a door with a non-empty `door_id` reads its `is_open` state
from `WorldState.get_door_open(door_id)` instead of always starting
closed, so re-entering a scene (or, later, a save/load) restores exactly
how it was left.

`Door` also emits `state_changed(is_open: bool)` (Phase 3B.1) whenever
`_apply_state()` runs — the event `BuildingVisibilityController` listens
to so opening/closing a door recomputes room-portal reveal immediately,
even while the player is stationary (see `docs/building_system.md`).

## Windows — `scripts/world/window.gd` (`class_name BuildingWindow`)

Named `BuildingWindow`, not `Window` — Godot's own `Window` class (an OS
window) already owns that name. Always physically solid (blocks
movement) regardless of state. Vision blocking is authored per-instance
via `is_boarded`: intact lets a room-reveal/perception raycast pass,
boarded blocks it exactly like a wall. No breaking/climbing gameplay this
pass — `is_boarded` is set once at authoring time, not toggled by any
interaction.

## Persistent world-prop state — `scripts/core/world_state.gd`

Three `Dictionary`s, all keyed by the same kind of stable authored
`StringName` id used throughout (never a scene-node reference, never an
auto-incrementing int — a node reference goes stale the instant a scene
reloads, and an auto-incrementing id would assign a *different* number to
"the same" shelf on a second run):

- `door_states: StringName -> bool`
- `prop_states: StringName -> Dictionary` (arbitrary flags, e.g.
  `{"salvaged": true}`)
- `prop_containers: StringName -> Inventory`

`get_or_create_prop_container(prop_id, capacity_weight, initial_items)`
is the load-bearing one: it registers an `Inventory` **once** per
`prop_id` and returns that *same instance* on every later call, ignoring
`initial_items` after the first registration. This is what makes
depletion durable — the second time anything asks for a shelf's
inventory, it gets back the already-searched (possibly empty) one, not a
freshly reseeded one. `WorldState.reset()` clears all three dictionaries
alongside its Phase 2A ones, restoring a clean new-game state.

**Snapshot serialization and restore (Phase 3B.1).**
`WorldState.to_snapshot()` now includes all three dictionaries:
`door_states` and `prop_states` copied directly (already plain
`StringName`/`bool`/`Dictionary` data), `prop_containers` converted via
each `Inventory.to_dict()` (`{capacity_weight, counts}`) since an
`Inventory` object itself isn't snapshot-safe data.
`WorldState.restore_phase_3b_state(snapshot)` is the matching read path
-- **idempotent** (each of the three dictionaries is fully replaced, not
merged, so restoring the same snapshot twice in a row is identical to
restoring it once: no duplicate registrations, no doubled loot) and
exact (a depleted/empty container restores as still empty, not
resurrected). Deliberately scoped to just these three -- survivors/
settlements/containers/jobs/drops remain snapshot-*only* preparation for
a future save/load system (see `docs/architecture.md`'s
`WorldState.to_snapshot()` note); reconstructing their live runtime nodes
is a separate, larger undertaking this pass doesn't attempt. `WorldState.reset()`
still fully clears all three afterward regardless of whether a restore
ever happened.

## Minimal HUD — `scenes/ui/HUD.tscn`, `scripts/ui/hud.gd`

`InteractPromptPanel` (bottom-center, initially hidden) shows the current
best candidate's `interact_label` (`"Search"`, `"Open Door"`, `"Salvage"`,
...), driven by `GameEvents.interact_prompt_changed` — emitted by
`PlayerInteractor` only when the label actually changes, keeping this
consistent with the rest of the HUD's "purely reactive to `GameEvents`"
rule rather than a bespoke local signal.

## Android

`MobileControls`' existing `InteractButton` already called
`InputRouter.request_interact()` (bound but inert before this phase,
since nothing consumed `interact_requested`) — no touch-input code
changed; `PlayerInteractor`'s `_on_interact_requested()` is the first
thing that ever actually listens.

## What every major prop declares

| Prop | Systemic participation |
|---|---|
| Shelves / fridges / medical cabinets | `LootContainerComponent`, deterministic starting contents |
| Wrecked/salvage cars, dumpsters | `LootContainerComponent` (dumpster) or `SalvageableComponent` (wreck) |
| Sedan (street) | `LootContainerComponent` (trunk-style loot, no driving) |
| Doors | physical + vision block while closed, interactable, noise on toggle |
| Windows | physical always, vision block per authored state |
| Tables / chairs / counters / benches / trees / planters | physical obstacle only (`add_physical_prop`) — no salvage/search yet, see Known limitations |

## Known limitations

- Tables/chairs/counters/trees are physical-obstacle-only —
  cover/vision-blocker/salvage-metadata participation for these (as the
  full spec describes) wasn't implemented; they exist and block movement
  but declare no further systemic role.
- No `VisionBlockerComponent`/`NoiseEmitterComponent`/`WorldPropData`
  resource as distinct classes — vision blocking is expressed directly
  via collision layer (walls/doors/windows), and noise emission is a
  direct `NoiseManager.emit_noise()` call at each interaction site rather
  than a reusable per-prop component. Functionally equivalent for what's
  implemented; less uniform than the full spec's component list.
- `CoverComponent` not implemented — no prop currently offers a
  cover-while-fighting mechanic.
- No inspect-with-no-mechanical-use interaction exists yet (every
  interactable prop currently does something).
- Persistence is in-memory only (`WorldState`, an autoload) — nothing
  reads/writes it to disk, consistent with the rest of the project's
  "prepared for save/load, not wired to it yet" state (see
  `docs/architecture.md`'s `WorldState.to_snapshot()` note).
