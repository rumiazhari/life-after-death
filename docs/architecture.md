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

- `arena_builder.gd` (`ArenaBuilder`): procedurally builds a road grid
  (with sidewalks/curbs/markings), building obstacles
  (`StaticBody2D` + tiled roof), and a perimeter boundary, seeded by
  `random_seed` for reproducibility. This is the "test arena," not a real
  level; procedural city/world generation (explicitly out of scope for
  this slice) would replace or extend this builder later. Visuals are
  `TileMapLayer`-painted as of Phase 3A — see "Rendering / visual layer"
  below for the full writeup; the seeded layout math (arena size, road
  positions, building collision footprints) is unchanged.
- `camera_rig.gd` (`CameraRig`): a `Camera2D` that lerps toward an
  assigned `target`. Kept separate from `Player.tscn` so the player scene
  has no camera dependency and the camera can be retargeted (e.g. a
  future spectator/cutscene camera) without touching player code.

## Rendering / visual layer — Phase 3A pixel-art overhaul

Everything in this section is presentation-only: no gameplay rule
(simulation, inventory, jobs, spawning, weapon balance, zombie health,
movement speeds, collision sizes, or world dimensions) changed to add it.
See `docs/art_direction.md` for the locked art spec (tile/frame
dimensions, palette, layer order, naming conventions, and how to replace
this placeholder art later).

**Asset generation.** `tools/generate_pixel_assets.gd` is a headless
`SceneTree` script (`godot --headless --script tools/generate_pixel_assets.gd`)
that draws every PNG under `assets/pixel/` with Godot's `Image` API only —
no external tools, nothing downloaded or copied from a reference/
commercial game. Every random choice is made through a
per-asset-tag-seeded `RandomNumberGenerator` (`SEED xor tag.hash()`), so
re-running the generator reproduces byte-identical files regardless of
call order. `PixelAtlasMap` (`scripts/visuals/pixel_atlas_map.gd`) is the
single source of truth for the environment atlas's tile-name → cell
mapping and the actor atlases' frame layout; both the generator and every
consumer below read from it instead of hard-coding a raw atlas
column/row anywhere else.

**Pixel-perfect rendering.** `project.godot` sets
`rendering/textures/canvas_textures/default_texture_filter = 0` (nearest)
and `rendering/2d/snap/snap_2d_transforms_to_pixel` /
`snap_2d_vertices_to_pixel = true` project-wide, so no sprite or tile
needs a per-node filter override. The 1280x720 viewport and
`canvas_items` + `expand` stretch mode (desktop and Android) are
unchanged from Phase 0/1.

**World — `scripts/world/arena_builder.gd` (`ArenaBuilder`), `scripts/world/pixel_tileset_builder.gd` (`PixelTilesetBuilder`).**
`PixelTilesetBuilder.get_tileset()` builds (once, cached for the process)
the one `TileSet`/`TileSetAtlasSource` wrapping the generated environment
atlas; every `TileMapLayer` in the project shares this same `TileSet`.
`ArenaBuilder` paints five `TileMapLayer`s (`Ground`, `Roads`,
`Sidewalks`, `RoadMarkings`, `BuildingRoofs`) plus a purely-decorative
`Props` node, in place of the old `Polygon2D`/`Line2D` pavement/road/
building visuals — but keeps every `StaticBody2D`/`RectangleShape2D`
collider, the arena's world-space dimensions, and the building
placement/skip-chance logic byte-for-byte identical. This is enforced by
using **two independent `RandomNumberGenerator` streams**: `_rng` (the
original stream, driving building position/size/empty-lot skip chance —
untouched) and a new `_visual_rng` (seeded `random_seed xor 0x5A5AF00D`,
driving every cosmetic choice: ground/asphalt/roof tile variants,
rooftop-detail placement, prop scatter). Adding, removing, or reordering
a cosmetic random draw can therefore never shift which building a
gameplay-relevant roll lands on. Building roofs are painted as a 9-slice
(`center`/`edge_<dir>`/`corner_<dir>`) across each building's own
footprint in tile units, in one of 4 material variants (`roofA`–`roofD`).

**Safehouse — `scripts/world/safehouse_interior_builder.gd` (`SafehouseInteriorBuilder`).**
A presentation-only companion node (`Safehouse.tscn`'s `Interior` child)
that paints the safehouse's floor and perimeter-wall `TileMapLayer`s at
`_ready()`, leaving a tile-wide gap in the south wall aligned with the
existing `Entrance` node. Every functional node (`StorageGeneral/Food/
Water/Medical`, `SleepSpot1-4`, `GuardPostLeft/Right`, `Entrance`) kept
its exact name, script, and position — only each one's `Visual` child
changed from a flat-color `Polygon2D` to a `Sprite2D` using a
category-specific texture (crate / ration-box / bottle-crate / medical
case for storage, a bed sprite for sleep spots, a sandbag-and-post sprite
for guard posts). `Settlement`'s own logic (`settlement.gd`) was not
touched.

**Actors — `scripts/visuals/actor_visual.gd` (`ActorVisual`), `scripts/visuals/actor_sprite_library.gd` (`ActorSpriteLibrary`, autoload).**
`ActorSpriteLibrary` builds one shared `SpriteFrames` resource per actor
type (`player`/`survivor`/`zombie`) from that type's atlas — every
instance of a type references the *same* `SpriteFrames` object rather
than each constructing/duplicating its own, which is what keeps hundreds
of concurrent zombies cheap. Each variant gets two 1-frame animations
(`idle_<n>`, `walk_<n>`) instead of a multi-frame walk cycle — a
deliberate simplification (see "Known simplifications" in
`docs/art_direction.md`). `ActorVisual` (an `AnimatedSprite2D` subclass)
replaces the old `BodyVisual` `Polygon2D` in `Player.tscn`/
`Survivor.tscn`/`Zombie.tscn` under the same node name; its
`update_from_velocity(velocity)` (called once per physics tick from each
actor's own script) only sets `flip_h` and picks between the idle/walk
animation — it never reads or writes movement/gameplay state. Damage
flash in `player.gd`/`survivor.gd`/`zombie.gd` needed no logic change:
it only ever tweens `modulate`, a `CanvasItem` property every one of
`Polygon2D`/`AnimatedSprite2D` shares, so only each script's `body_visual`
type annotation changed. A `Shadow` `Sprite2D` sibling (one shared
`shadow.png`) was added per actor, drawn beneath the body sprite. Variant
assignment is deterministic, not random: survivors use
`ActorSpriteLibrary.variant_for(&"survivor", data.id)` (stable per
survivor id), zombies use one `randi()` pick at spawn (purely cosmetic,
doesn't affect any gameplay-relevant RNG stream since `Zombie` has none).

**Combat — `scripts/combat/blood_decal_manager.gd` (`BloodDecalManager`).**
`Projectile.tscn`'s `Visual` and `Player.tscn`/`Survivor.tscn`'s
`MuzzleFlash` swapped from `Polygon2D` to `Sprite2D` using generated
textures; `weapon.gd`'s `muzzle_flash` type annotation is the only script
change (still just `.visible` toggles). `BloodDecalManager` (a plain
`Node2D` child of `Main`) listens to the existing `GameEvents.zombie_died`
signal and drops one blood-decal sprite per death, capped at `MAX_DECALS`
(40) via a ring buffer — once the cap is reached, the *oldest* sprite is
repositioned and reused instead of a new node being created, so decal
count can never grow unbounded regardless of how many zombies die in a
run. A restart's `reload_current_scene()` frees this node (and its pooled
children) along with everything else, so no separate reset hook is
needed.

**Scavenge points and world drops — `scripts/world/scavenge_point.gd`, `scripts/world/world_drop_visual_manager.gd` (`WorldDropVisualManager`).**
`ScavengePoint._ready()` now also picks a category-specific texture
(food/water/medical/materials) for its `Visual` `Sprite2D` from
`item_id`, purely additive to its existing harvest logic. `WorldState`
gained one new signal, `drop_registered(drop: WorldDrop)`, emitted from
`register_drop()` right after the drop is added to `WorldState.drops` —
`WorldDropVisualManager` subscribes to it (plus a one-time scan of
whatever drops already existed at `_ready()`) instead of scanning every
frame, and adds one loot-bag `Sprite2D` per drop, tinted by
`WorldDrop.reason` (`death`/`haul_stalled`/`storage_destroyed`) so the
three causes read as visually distinct without three separate textures.
It never reads or mutates `WorldDrop`/`Inventory` data and adds no
looting mechanic — `WorldDrop` itself is unchanged.

**UI — `resources/theme/pixel_theme.tres`.** Applied project-wide via
`project.godot`'s `gui/theme/custom`, so `HUD`/`PauseMenu`/`DeathOverlay`/
`MobileControls`/`SurvivorInspector`/`DebugOverlay` all picked up dark
semi-opaque `StyleBoxFlat` panels, a light 2px border, and an
outlined/drop-shadowed font (Godot's built-in font — no external/
unlicensed font file) without per-scene styling code. `HUD.tscn`'s
`TopLeft`/`TopRight` groups were each wrapped in a `PanelContainer` (and
gained small category-icon `TextureRect`s next to the health/ammo/
zombie-count/kills labels); `hud.gd`'s `@onready` paths were updated to
match, and that is the only script change this required — every signal
this HUD reacts to (`GameEvents.player_health_changed`, etc.) is
unchanged.

**Performance.** No per-actor shader materials, no per-actor lights, no
`NavigationAgent2D` additions, no per-frame environment reconstruction or
world-drop scanning, no per-zombie procedural texture generation at
runtime. All generated art is produced once (by the offline generator)
and loaded as ordinary shared `Texture2D`/`SpriteFrames` resources before
gameplay begins. See the Phase 3A validation report for measured FPS/
node-count/draw-call numbers across the 50/100/150/250 zombie population
profiles.

## Phase 3A.1: pixel-art quality, animation, depth, and rendering correctness pass

Additive to Phase 3A above -- same generator, same `TileMapLayer` city, same
`ActorSpriteLibrary`/shared-`SpriteFrames` design, same gameplay dimensions
and collision. This pass replaced the block-figure actor art with layered
character designs, added real 3-directional multi-frame animation, fixed
two rendering-correctness bugs (cosmetic/gameplay RNG bleed, double pixel
snapping), and added native Y-sort depth ordering.

**RNG isolation -- `scripts/visuals/cosmetic_rng.gd` (autoload `CosmeticRng`).**
Before this pass, `Zombie` picked its visual variant and `BloodDecalManager`
picked its decal texture/rotation via Godot's bare global `randf()`/`randi()`
-- the SAME implicit stream `SpawnManager` used for spawn-position angles and
`Zombie` used for retarget-timing jitter. Since nothing partitioned cosmetic
draws from gameplay draws, toggling a visual feature on/off (or just
reordering unrelated cosmetic code) could silently shift spawn positions and
AI timing on a given run. Fix: `CosmeticRng` is now the one shared stream
every purely-visual choice draws from, and `Zombie`/`SpawnManager` each got
their own private `_gameplay_rng` (`RandomNumberGenerator`, OS-randomized by
default, or seeded via a `rng_seed` export for tests) for their
gameplay-relevant draws. `tests/test_runner.gd`'s
`cosmetic_rng_does_not_affect_zombie_retarget_timing` /
`_does_not_affect_spawn_positions` prove this by seeding two runs identically
with heavy `CosmeticRng` consumption interleaved and asserting identical
gameplay output. Survivor variant selection was never affected -- it was
already deterministic (`ActorSpriteLibrary.variant_for(&"survivor", data.id)`),
per this same "prefer a derived id over RNG" principle.

**Pixel-stable camera -- `scripts/world/camera_rig.gd`.** The project no
longer enables `rendering/2d/snap/snap_2d_vertices_to_pixel` alongside
`snap_2d_transforms_to_pixel` (Godot's own guidance is against combining
both). Transform snapping alone rounds every sprite's own transform to the
pixel grid, but a smoothly-lerping `CameraRig` still drifts through
fractional positions every frame, which reads as the whole world "swimming"
relative to camera even though no individual sprite is wrong. `CameraRig` now
keeps its smooth follow as a private `_logical_position` (unrounded, updated
every frame via the same lerp as before) and only ever writes a
pixel-grid-rounded value (`_snap_to_pixel()`, which accounts for `zoom` so it
still works at non-1x zoom) to its actual `global_position` --
the rendered value always lands on a whole pixel, the logical target never
loses precision to rounding error accumulating frame over frame.

**Actor art -- `tools/generate_pixel_assets.gd` `SURVIVOR_SPECS` / `ZOMBIE_SPECS` / `PLAYER_SPEC`.**
Replaced the single parametrized `_draw_humanoid()` (skin/shirt/pants
palette-swap over one fixed rectangle skeleton) with a spec-driven system:
each of 8 survivor combinations and 8 zombie combinations is a hand-authored
`Dictionary` (skin tone, hair style + color, garment style + color/accent,
posture) drawn by a shared skeleton (`_draw_front_back_actor()` /
`_draw_side_actor()`) that composes separately-outlined head/hair/torso/
arm/leg parts instead of one flat rectangle block. Hair styles
(`short`/`long`/`bald`/`cap`/`hood`/`bandana`/`buzzed`/`afro` for survivors;
`patchy`/`matted`/`bald` for zombies) are silhouette-breaking, not palette
swaps -- each occupies a different region around the head. Garment
`top_style` (`jacket`/`coat`/`work`/`medical`/`plain`) adds a
style-specific silhouette/accent detail (shoulder patches, a longer hem, a
tool pouch, a cross badge) on top of the shared torso block. Zombies add a
torn-clothing notch (an irregular skin-colored patch breaking the torso
outline) and pick one of two posture families (`upright` / `hunched`, the
latter offsetting the whole skeleton down and shortening the torso) so they
read as zombies by silhouette and posture, never by skin tone alone. The
player gets its own near-black `outline_color` (vs. the shared
`PALETTE.outline` every survivor/zombie uses) and a gold accent trim,
deliberately higher-contrast so it reads as "the player" without relying on
the jacket being blue.

**Directional animation -- `scripts/visuals/pixel_atlas_map.gd` (`ACTOR_FRAME_SLOTS`), `actor_sprite_library.gd`, `actor_visual.gd`.**
Each actor atlas row (one per variant) is now a fixed 15-column sequence:
`(down, up, side) x (idle x2 frames, walk x3 frames)`, generated from
`PixelAtlasMap.ACTOR_FRAME_SLOTS` so the generator and
`ActorSpriteLibrary._build_frames()` read the same layout instead of either
hard-coding column numbers. `ActorSpriteLibrary` builds one animation per
`(direction, idle|walk)` per variant (e.g. `"side_walk_3"`), still one shared
`SpriteFrames` resource per actor *type*, not per instance. `ActorVisual`
picks direction from velocity every `update_from_velocity()` call --
horizontal-dominant -> `"side"` (mirrored via `flip_h` for facing left, so
there is no separate left-facing frame set), vertical-positive (moving down
the screen) -> `"down"`, vertical-negative -> `"up"` -- and only updates
`_direction` while actually moving above a small speed threshold, so a
stopped actor keeps facing whichever way it was last walking instead of
snapping to a default. Zombie "walk" is the same 3-frame slot as human walk,
reusing the shared skeleton's own hunched-posture/torn-clothing rendering to
read as a shuffle rather than needing a separate animation track.

**Y-sort depth ordering -- `EntityContainer` (`Main.tscn`, `y_sort_enabled = true`).**
Player, every spawned Zombie, every spawned Survivor, `ScavengePoint`
instances, and "volumetric" scattered props (crates/trash bags/sandbags/
pallets from `ArenaBuilder._scatter_props()`) are now all direct children of
the same `EntityContainer` node (survivors moved here from a separate
non-sorted `SurvivorContainer`, which was removed; `WorldDropVisualManager`
parents its loot-bag sprites here too instead of under itself) with no
per-node `z_index` override, so Godot's native y-sort orders them by feet
position -- an actor south of a crate draws in front of it, one to the north
draws behind, and a zombie swarm sorts consistently without any manual
per-frame sort script. Two deliberate exceptions stay on fixed z-index bands
outside y-sort, both because they should never occlusion-sort against
actors: "flush" ground-level decoration (loose debris, drain covers, in
`ArenaBuilder`'s own `GroundProps` container) stays permanently beneath
actors, and `BuildingRoofs` (z=5) stays permanently above them, matching the
original Phase 3A layer-order design. An actor's `Shadow` sprite needs no
y-sort participation of its own -- it's a child *of* that actor node, so it
always draws immediately beneath its own owner regardless of how the owner
sorts against everything else.

**Hit-effect manager -- `scripts/combat/hit_effect_manager.gd` (`HitEffectManager`).**
A brief blood-impact flash on every zombie hit (not just on death), separate
from `BloodDecalManager`'s persistent capped decals. `GameEvents.zombie_damaged`
(previously declared but never emitted) is now emitted from
`Zombie._on_damaged()`; `HitEffectManager` pre-allocates a fixed pool of 16
`Sprite2D`s in `_ready()` (never grows) and reuses them round-robin, tweening
each flash's alpha out over ~0.12s -- a hit during a 250-zombie swarm never
allocates a node.

**UI -- `resources/theme/pixel_theme.tres`, `scenes/ui/HUD.tscn`.** `HUD`
gained an actual `HealthBar`/`AmmoBar` (`ProgressBar`, per-instance
`StyleBoxFlat` fill colors so health reads red and ammo reads amber without
touching the shared theme) alongside the existing exact-number labels, and
`ReloadLabel` got a distinct amber font color. The ammo bar tracks magazine
fill specifically (not magazine+reserve combined) since "how close to
needing a reload" is the more useful at-a-glance signal; since
`weapon_ammo_changed` doesn't carry `magazine_size`, `HUD` infers it as the
highest `ammo_in_magazine` value it has observed rather than reaching into
`Player`/`Weapon` directly, preserving the existing "HUD is purely reactive
to `GameEvents`" rule.

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

The player remains targetable at any distance, preserving the original
Phase 0/1 pressure/tuning exactly. Survivors are only targetable within
`Zombie.survivor_detection_radius` (default 500px, picked against
`SurvivorAI.perception_radius` of 420 -- a zombie notices somewhat
farther than a survivor does) -- `_find_nearest_attackable()` skips any
candidate in the `"survivors"` group beyond that range. Without this, a
zombie could be pulled clear across the map toward a lone survivor
scavenging far from the action, which reads as omniscient rather than a
swarm reacting to what's actually nearby; since zombies still spawn
camera-relative to the player (see `SpawnManager` above), this doesn't
reduce pressure on the player, only on distant unaccompanied survivors.

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

## Phase 3B: fixed urban district, enterable buildings, interaction, perception

Everything below is additive to Phase 0/1/2A above. The single biggest
change: **the world is no longer runtime-generated.**
`scripts/world/arena_builder.gd` (`ArenaBuilder`) is kept, untouched, as
an optional/unused test-and-performance scene, but `Main.tscn`'s `World`
node now instances `scenes/world/maps/UrbanDistrict01.tscn`
(`DistrictBuilder`) — one fixed, hand-authored urban district with a
committed layout checksum test guarding against accidental drift. See
`docs/urban_map_design.md` for the full layout writeup.

**Enterable buildings.** Three archetypes (Restaurant, Convenience Store,
Clinic — ground floor only) share one authoring pattern
(`BuildingVisibilityController` base + `BuildingShellBuilder` static
helpers for walls/floor/roof/furniture). Roof visibility and interior
room reveal are Project-Zomboid-style but deliberately simplified: current
room fully revealed, a room sharing a currently-open door also revealed,
everything else fully hidden — never a raycast/view-cone-based partial
reveal. See `docs/building_system.md`.

**Doors and windows** (`scripts/world/door.gd`, `scripts/world/window.gd`)
are reusable, stateful, and collision-driven: one `CollisionShape2D`
gates both movement and vision for a door, so fading/animation can never
desync the two. Both carry a stable authored id used for persistence.

**Systemic interaction** (`scripts/interaction/`) is built on
`InputRouter.interact_requested` (a signal that existed since Phase 0/1
but had no listener until now): `PlayerInteractor` picks the nearest,
facing-preferred candidate from a small overlap-tracked registry (never a
per-frame full-map scan); `InteractableComponent` /
`LootContainerComponent` / `SalvageableComponent` / `RestPointComponent`
are composable one-verb-each building blocks rather than one large
per-prop script. See `docs/interaction_system.md`.

**Persistent world-prop state** lives in three new `WorldState`
dictionaries (`door_states`, `prop_states`, `prop_containers`), keyed by
stable authored `StringName` ids — never a scene-node reference or an
auto-incrementing int, so re-querying a shelf's inventory (or, later, a
reloaded scene) resolves to the *same* record rather than a fresh one.

**Zombie perception was rebuilt from scratch.** The old
`Zombie._find_nearest_attackable()` (nearest member of `"attackable"`,
unlimited range) is gone. `ZombiePerceptionComponent`
(`scripts/ai/zombie_perception_component.gd`) is a bounded state machine
(`IDLE/SUSPICIOUS/INVESTIGATE/CHASE/ATTACK/SEARCH/RETURN_TO_IDLE`) driven
by a cheap distance/cone pre-filter before an expensive raycast, staggered
per-instance updates, and a suspicion-buildup delay before committing to
a chase. A centralized `NoiseManager` autoload (bounded ring buffer, no
per-sound `Area2D`) feeds hearing into the same state machine. A shared
`UrbanNavigationService` (`AStarGrid2D`, built once from static
collision, budget-capped path requests) is Zombie's pathfinding fallback
for when direct steering is blocked — not wired into `Survivor` movement
this pass. `SurvivorAI`'s existing local-perception radius gained one
filter: a zombie beyond the emergency safety margin and behind a wall no
longer counts as a locally-perceived threat. See
`docs/perception_system.md` for the full state machine, hearing model,
navigation grid, and the extended collision-layer table (adds Vision=32
and Interactable=64 to the Phase 0/1 table above).

**Spawn regions** (`scripts/world/spawn_region.gd`, `SpawnRegion`) are
authored `Node2D`s (map-edge streets, the service alley, concealed
exterior corners) that `SpawnManager` is expected to draw from using its
own private gameplay RNG — never inside the safehouse, never using any
RNG stream but the caller's own (same cosmetic/gameplay RNG isolation
rule as Phase 3A.1's `CosmeticRng`).

**Known limitations** (see each doc's own "Known limitations" section for
the full list): only 3 of 5 requested building archetypes; simplified
(non-portal-graph) room reveal; navigation is Zombie-only; several
Section-13-style street/interior art items (van/truck, bicycles, vending
machines, shopping carts, apartment/workshop-specific fixtures) were not
generated this pass; no perception/nav telemetry counters were added to
`DebugOverlay` (performance was measured via a temporary profiling probe
instead).

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
