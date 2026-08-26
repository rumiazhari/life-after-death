# AUTOPILOT STATE — life-after-death

STATUS: OK
Project: life-after-death (Godot 4.7.1 zombie survival game)

## Current goal
Iteration 8: add a HUD game-clock readout (Day N HH:MM + Dawn/Day/Dusk/Night
phase) — presentation-only widget fed by SimulationClock via HUD, + 2 headless
tests. Fold in backlog #1 (.uid sidecars + Main.tscn metadata cleanup).

## Done
- iter 1: Added CombatFeedback overlay to HUD (damage flash, low-HP pulse, kill hit-marker) + headless tests in test_runner.gd tail chain.
- iter 2: Procedural audio pass — generated WAV SFX (gunshot, reload, player_hurt, zombie_hit, zombie_death) via generate_sfx.py; created AudioManager autoload with pooled AudioStreamPlayers listening to GameEvents.
- iter 3: kill-feed / event toasts — scavenge emits scavenge_completed + event_toast on-hud notification
- iter 4: Voxel-zombie hit-flash — per-instance duplicated StandardMaterial3D in VoxelZombie3D._ready() + 2 headless tests; suite green 195/0.
- iter 5: Stabilized flaky procedural_runtime_generation_profile + fixed stale HUD API Label.set_default_font_size() → add_theme_font_size_override.
- iter 6: Compass / off-screen safehouse indicator — new scripts/ui/safehouse_compass.gd (presentation-only widget) + 2 headless tests; suite green 197/0.
- iter 7: Day-night ambient tint cycle. New scripts/visuals/day_night_cycle.gd (presentation-only): reads SimulationClock.total_game_minutes(), blends a 9-keyframe 24h palette onto the scene Environment (background + ambient tint/energy) and Sun DirectionalLight3D (colour + energy) via smoothstep. Re-applies only when the integer game-minute changes (pause freezes the mood for free). Wired into VoxelMain.tscn as a sibling DayNightCycle node auto-resolving WorldEnvironment/Sun. Midday keyframe equals the shipped static look (zero-regression anchor). + 2 headless tests (palette continuity/bounds/time-keying; drives Environment + tolerates missing targets). Suite green 199/0. Committed as 3c2c920 + 9bed990, pushed to origin/master.
- iter 8: HUD game-clock readout. New scripts/ui/game_clock_label.gd (presentation-only Label): HUD pushes SimulationClock game_day/hour/minute each frame; formatter shows "Day N  HH:MM  <phase>" with Dawn/Day/Dusk/Night suffix. Positioned at top-left under the floor label. + 2 headless tests (HUD builds GameClockLabel; phase_suffix boundaries + out-of-range wrap). Also folded in backlog #1: committed the 3 leftover .uid sidecars (audio_manager/combat_feedback/safehouse_compass) and the benign Main.tscn metadata cleanup (unique_ids, uid= on script ext_resources, dropped an unused ScavengePoint ext_resource decl).

## Backlog (top-down)
1. Player-visible polish candidates (freedom scope): weather/vignette tied to SimulationClock; low-health screen desaturation in CombatFeedback; footstep/ambient audio loops. Split one per iteration.
2. Larger roadmap items from README (quests, economy, crafting…) — too large for one iteration; split later.

## ⭐ USER DIRECTIVE (2026-08-26 evening) — 2.5D VERTICAL TRAVERSABILITY + DESTRUCTION
North-star direction (supersedes backlog ordering after current slice lands):

1. 2.5D TOP-DOWN WITH VERTICAL PLAY, ring-bell-style: multi-storey buildings
   where EVERY floor is enterable/usable — stairs work, floors are playable,
   roofs accessible. Verticality must matter for gameplay (escape routes,
   sightlines, loot upstairs).
2. DESTRUCTIBLE CITY: buildings, props, and structures damageable/destructible
   in the top-down 2.5D view (walls breachable with explosive class as today,
   extend to props/furniture/cover; destruction persists in world state).
3. LOGICAL PROCEDURAL INTERIORS: apartment blocks (bedrooms/dining/kitchen/
   toilet per unit), office buildings (workstations/meeting rooms), shops,
   workshops, schools, universities — plausible floor plans, neat placement,
   generated deterministically.
4. Keep the voxel contract/performance budget docs authoritative for renderer
   decisions; keep headless TestRunner green before every commit.
