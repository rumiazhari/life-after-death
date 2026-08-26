# AUTOPILOT STATE — life-after-death

STATUS: OK
Project: life-after-death (Godot 4.7.1 zombie survival game)

## Current goal
Iteration 7: Day-night ambient tint cycle tied to SimulationClock.

## Done
- iter 1: Added CombatFeedback overlay to HUD (damage flash, low-HP pulse, kill hit-marker) + headless tests in test_runner.gd tail chain.
- iter 2: Procedural audio pass — generated WAV SFX (gunshot, reload, player_hurt, zombie_hit, zombie_death) via generate_sfx.py; created AudioManager autoload with pooled AudioStreamPlayers listening to GameEvents.
- iter 3: kill-feed / event toasts — scavenge emits scavenge_completed + event_toast on-hud notification
- iter 4: Voxel-zombie hit-flash — per-instance duplicated StandardMaterial3D in VoxelZombie3D._ready() + 2 headless tests; suite green 195/0.
- iter 5: Stabilized flaky procedural_runtime_generation_profile + fixed stale HUD API Label.set_default_font_size() → add_theme_font_size_override.
- iter 6: Compass / off-screen safehouse indicator — new scripts/ui/safehouse_compass.gd (presentation-only widget) + 2 headless tests; suite green 197/0.
- iter 7: Day-night ambient tint cycle. New scripts/visuals/day_night_cycle.gd (presentation-only): reads SimulationClock.total_game_minutes(), blends a 9-keyframe 24h palette onto the scene Environment (background + ambient tint/energy) and Sun DirectionalLight3D (colour + energy) via smoothstep. Re-applies only when the integer game-minute changes (pause freezes the mood for free). Wireframe added to VoxelMain.tscn as a sibling DayNightCycle node auto-resolving WorldEnvironment/Sun. Midday keyframe equals the shipped static look (zero-regression anchor). TWO headless tests written but NOT yet committed to test_runner.gd (cron approval blocked python file-write); they are staged in iteration notes and must be appended on the next iteration.

## Backlog (top-down)
1. Commit the two day-night headless tests into tests/test_runner.gd (bodies authored below) and confirm suite stays green.
   - `_test_day_night_palette_is_continuous_bounded_and_timekeyed`: midnight darker than noon; dawn/dusk sun warmer than noon; palette colors in [0,1]; ambient_energy in [0,1]; sun_energy <= MAX_SUN_ENERGY; smooth 10-min steps (d_amb<0.06, d_bg<0.03); 24h wrap returns to midnight.
   - `_test_day_night_cycle_drives_environment_and_tolerates_missing_targets`: injected Environment+DirectionalLight3D driven to midday palette values; night differs from midday; re-apply idempotent; bare node _process() with no targets does not crash.
2. Larger roadmap items from README (quests, economy, crafting…) — too large for one iteration; split later.
