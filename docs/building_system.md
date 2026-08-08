# Building system (Phase 3B)

How an enterable building is authored, how roof/interior visibility works,
and the door/window/room identity rules everything else (persistence,
navigation, perception) depends on.

## Archetypes implemented

Ground floor only, 3 of the spec's 5 requested archetypes:

| Archetype | Scene | Rooms |
|---|---|---|
| Restaurant/café | `scenes/world/buildings/Restaurant01.tscn` | Dining Room, Kitchen, Pantry (+ an outdoor patio, not a Room) |
| Convenience store | `scenes/world/buildings/ConvenienceStore01.tscn` | Retail Floor, Back Room |
| Clinic/pharmacy | `scenes/world/buildings/Clinic01.tscn` | Waiting Area, Exam Room, Medical Storage |

**Not implemented this pass:** Apartment/residential, Workshop/office/
warehouse. Both would follow the exact same authoring pattern below —
they were cut for scope, not because the architecture doesn't support
them.

## Authoring pattern

Every building script (`scripts/world/buildings/*.gd`) extends
`BuildingVisibilityController` and follows the same shape:

1. Set `building_id`, `roof_node_path`, `rooms_container_path` in
   `_ready()`, before calling `super._ready()`.
2. `_build_shell()` — perimeter walls (with door-sized gaps),
   interior partition walls (with their own door gaps), a painted roof
   (`BuildingShellBuilder.paint_roof`, a 9-slice reusing the district's
   own roof-material tiles under a building-specific letter), and floor
   fill per room (`BuildingShellBuilder.fill_floor`, tiled from the
   shared environment atlas — not a standalone texture file). Then
   furniture: `add_loot_furniture` (searchable, Inventory-backed),
   `add_salvage_prop` (one-time materials yield), `add_physical_prop`
   (obstacle only).
3. `_link_doors_to_rooms()` — assigns each hand-authored `Room.doors`
   array so `BuildingVisibilityController` knows which doors border which
   rooms.
4. `super._ready()` — `BuildingVisibilityController._ready()` finds the
   roof node and every `Room` child, wires each room's
   `body_entered`/`body_exited`, and applies the initial (outside) state.

Rooms, doors, and windows are **hand-authored directly in the `.tscn`**
(not built by the shell-builder), since their identity, exact position,
and door-adjacency graph are meaningful authored data a script shouldn't
silently redecide on every load.

`BuildingShellBuilder` (`scripts/world/building_shell_builder.gd`, a
`RefCounted` of static helpers) is the shared plumbing every building
calls — walls/floor/roof/furniture construction is one reusable routine,
not duplicated per building. All of its construction happens **before**
`add_child()` is ever called on the resulting subtree: Godot readies
children bottom-up (before their parent), so setting a child component's
`@export` var *after* `add_child()` from the parent's own `_ready()`
races that child's own `_ready()` if it reads the var synchronously.
Building the whole configured subtree first sidesteps that entirely.

## Room/door/prop id convention

Stable, human-readable `StringName` ids, never node references or
auto-incrementing ints: `"<building_id>/<local_name>"` — e.g.
`"convenience_store_01/shelf_0"`, `"restaurant_01/door_entrance"`,
`"clinic_01/cabinet_1"`. These are what `WorldState`'s persistent
dictionaries key on (see `docs/interaction_system.md`) and what
`UrbanNavigationService.register_door()` keys its door-cell map on. A
building's rooms additionally carry `room_id` (unique within that
building only, e.g. `"retail_floor"`) and `building_id`.

## Roof and interior visibility — `scripts/world/building_visibility_controller.gd`

`BuildingVisibilityController` (a `Node2D`, one per building, extended by
each building script) never touches collision — only `modulate` on each
`Room` (a `Room` **is** the `CanvasItem` being dimmed; it holds its own
floor/furniture as direct children, no separate "Visual" wrapper node)
and `.visible` on the roof `TileMapLayer`. Fading can therefore never
change what blocks movement — a fully-verified property
(`tests/test_runner.gd::_test_building_roof_hides_and_room_reveals_on_enter_restores_on_exit`
never observes a collision change across enter/exit).

**This is a deliberately simplified subset** of the full spec's
room-portal-graph / aim-cone reveal:

- The room currently containing the player → fully revealed
  (`Color(1,1,1,1)`).
- A room sharing a currently-**open** door with the current room → also
  revealed.
- Every other room in the same building → fully **hidden**
  (`Color(1,1,1,0)`), not merely dimmed.
- The roof hides for the whole building while the player is anywhere
  inside it, and restores the instant they leave every room.

What the full spec asked for and this doesn't implement: no aim-direction
/ view-cone-based reveal (a room is either fully revealed or fully
hidden, never "revealed because you're facing that way"), no
raycast-per-portal check, no partial dim state for "seen but not
currently occupied." Detection of "am I still inside any room" uses
`Area2D.get_overlapping_bodies()` (`_find_room_still_containing_player()`)
rather than a cached portal graph, since with at most 2–3 rooms per
building this is cheap and needed no further optimization this pass.

**Reveal state only recomputes on room enter/exit** (`_on_room_body_entered`/
`_on_room_body_exited`), not on a door's own state change. Opening a door
while standing still in a room does not retroactively reveal a
newly-connected room until the player next enters/exits a room — this is
a known limitation of the simplified subset (the full portal-graph
version would re-evaluate reveal state on every door toggle too). See
`tests/test_runner.gd::_test_building_adjacent_room_reveals_through_open_door`
for the exact tested contract: the door must be opened *before* the
player enters, not after.

## Doors and windows

See `docs/interaction_system.md` "Doors and windows" for the full
door/window contract (state, collision, interaction, persistence). In
short: a `Door` is closed by default, blocks movement + vision while
closed, and its physical `CollisionShape2D` is the single thing gating
both (no separate vision-only flag to desync). A `BuildingWindow` always
blocks movement; vision blocking is authored per-instance
(`is_boarded`).

## Collision layers this system adds

See `docs/interaction_system.md`'s collision layer table (the
authoritative list) — this system's walls/doors/windows use `World` (1)
and `Vision` (32); doors' larger `InteractReachArea` uses `Interactable`
(64).

## Known limitations

- Only 3 of 5 requested archetypes (see above).
- Simplified room-reveal (see above) — no view-cone/aim-direction reveal,
  no partial-dim "previously seen" state, reveal doesn't react to a door
  toggling while the player is stationary.
- No upper floors, no basements — ground floor only, per the spec's
  explicit "do not add" list.
- `UrbanNavigationService` is wired into `Zombie` movement (see
  `docs/perception_system.md`) but **not** into `Survivor` movement this
  pass — survivors don't yet path through building doors on their own;
  this was deliberately deferred as lower-risk (avoids destabilizing the
  existing, well-tested `SurvivorAI`/`UtilityAction` movement system this
  late in the pass).

## Authoring another building

1. New scene under `scenes/world/buildings/`, new script under
   `scripts/world/buildings/` extending `BuildingVisibilityController`.
2. Author `Rooms/<RoomName>` (`Room`, with `room_id`/`building_id`) and
   `Doors/<DoorName>` (`Door.tscn` instances, with a stable `door_id`)
   directly in the `.tscn`.
3. `_build_shell()` using `BuildingShellBuilder`'s static helpers for
   walls/floor/roof/furniture, matching an existing building script for
   the exact call shape.
4. `_link_doors_to_rooms()` assigning each `Room.doors` array.
5. Add its `BUILDING_SCENES`/`BUILDING_POSITIONS` entry in
   `scripts/world/district_builder.gd` and update the
   `DistrictLayoutChecksum` baseline test if committing a layout change.
