# Building system (Phase 3B, updated for Phase 3B.1)

How an enterable building is authored, how roof/interior visibility works,
and the door/window/room identity rules everything else (persistence,
navigation, perception) depends on.

## Archetypes implemented

Ground floor only. All 5 of the spec's requested archetypes now exist
(Apartment/Workshop added in Phase 3B.1):

| Archetype | Scene | Rooms |
|---|---|---|
| Restaurant/café | `scenes/world/buildings/Restaurant01.tscn` | Dining Room, Kitchen, Pantry (+ an outdoor patio, not a Room) |
| Convenience store | `scenes/world/buildings/ConvenienceStore01.tscn` | Retail Floor, Back Room |
| Clinic/pharmacy | `scenes/world/buildings/Clinic01.tscn` | Waiting Area, Exam Room, Medical Storage |
| Apartment/residential | `scenes/world/buildings/Apartment01.tscn` | Lobby, Living Room, Kitchen, Bedroom, Bathroom (shotgun layout -- see below) |
| Workshop/warehouse | `scenes/world/buildings/Workshop01.tscn` | Loading Bay (service entrance), Work Floor (main entrance), Storage, Office |

Apartment01 and Workshop01 both use a **row layout**: rooms in a straight
line, divided by simple full-height/full-width vertical partitions (the
same `BuildingShellBuilder.build_partition` call repeated N times), rather
than a 2D grid of partitions. This was a deliberate authoring-simplicity
choice — a grid needs partitions to intersect cleanly at corners, which is
easy to get subtly wrong by hand; a row never has that problem, at the
cost of a less "realistic" floor plan. Apartment01 reuses `bed.png` (from
the Phase 3A safehouse sleep-spot art) for its bedroom and
`medical_cabinet.png` as a generic dresser/storage stand-in; Workshop01
reuses `crate.png`/`pallet.png` (from the safehouse's own storage art) for
its loading bay and storage room.

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

**Phase 3B.1: a real bounded room-portal graph**, replacing the earlier
"current room + any room sharing an open door" rule:

- The room currently containing the player → always fully revealed
  (`Color(1,1,1,1)`).
- A `Door` (open) or `BuildingWindow` (intact, not boarded) connects two
  `Room`s (`Room.doors`/`Room.windows`, hand-authored per building — see
  "Room/door/prop id convention" above). Starting from the player's
  current room, a neighboring room reveals only if its connecting portal
  is currently open/intact, **inside the player's current view cone**
  (`view_cone_degrees`, default 120°; aim direction preferred, recent
  movement direction as a fallback — see `_player_view_direction()`), and
  a raycast from the player to the portal is unobstructed (so a portal on
  the far side of another wall never counts — "walls block reveal").
- From each such revealed room, **one further hop** is allowed
  (`MAX_PORTAL_DEPTH = 2`) through another open/intact, line-of-sight-clear
  portal — "look through one room into the next," not an unbounded chain.
  The second hop only re-checks line of sight, not the view cone, since
  the player is already looking "through" the first portal.
- Every room outside that revealed set → fully **hidden**
  (`Color(1,1,1,0)`), not merely dimmed.
- The roof hides for the whole building while the player is anywhere
  inside it, and restores the instant they leave every room.

**The line-of-sight raycast uses the Vision layer only (32), deliberately
not `World | Vision` together** — real walls/closed doors/boarded windows
all carry the Vision bit alongside World, so they still correctly block
reveal, but an *intact* window carries World (still physically solid,
blocking movement) and never Vision, so it does **not** block this
raycast: "intact windows allow visual reveal but not movement." A
`World | Vision` mask (the one every other line-of-sight check in this
codebase uses, e.g. `ZombiePerceptionComponent`/`SpawnManager`) would
incorrectly treat every intact window as opaque.

**Scope still limited by the roof being building-wide, not per-room:**
reveal is only computed while the player is inside the building. Seeing
*into* a room through an exterior window from *outside* would need the
roof itself to be segmented per-room (a per-room cutout, not a single
`.visible` toggle for the whole `TileMapLayer`) — out of scope this pass.
Every `BuildingWindow` in the current 5 buildings only borders the
exterior (none connect two interior rooms), so the window-portal code
path never actually fires for any of them today; it's exercised directly
by a synthetic two-room test fixture instead, ready for a future building
authored with a real interior-facing window.

**Updates on room enter/exit (event-driven) and any door in the scene
changing state** (`Door.state_changed`, a new signal — event-driven, so
"opening or closing a door immediately recalculates visibility even when
the player is stationary" holds), plus a low-frequency timer
(`view_recheck_interval`, default 0.2s, **only running while the player
is actually inside that specific building** via `set_physics_process`)
to pick up aim/movement direction changes without raycasting every
physics frame for every building in the district.

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

- All 5 requested archetypes now exist (see above).
- Room reveal doesn't segment the roof per-room, so a window can't yet
  reveal a room's interior to a player standing *outside* the building
  (see "Scope still limited..." above).
- No partial-dim "previously seen but not currently visible" state — a
  room is always either fully revealed or fully hidden, never dimmed.
- No upper floors, no basements — ground floor only, per the spec's
  explicit "do not add" list.
- `UrbanNavigationService` is wired into both `Zombie` and `Survivor`
  movement now (Phase 3B.1 — see `docs/perception_system.md`), sharing
  the same per-frame request budget.

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
   `scripts/world/district_builder.gd`, re-run
   `godot --headless --path . --script tools/bake_district.gd` to bake it
   into the committed `UrbanDistrict01.tscn` (Phase 3B.1 — see
   `docs/urban_map_design.md` "Baked, not runtime-built"), and update the
   `DistrictLayoutChecksum` baseline test to match.
