# AUTOPILOT STATE — life-after-death

STATUS: OK
Project: life-after-death (Godot 4.7.1 zombie survival game)

## Current goal
Iteration 8 (next): pick a small player-visible improvement from the backlog
(listed below). Iteration 7 is COMPLETE and committed (suite green 199/0).

## Done
- iter 1: Added CombatFeedback overlay to HUD (damage flash, low-HP pulse, kill hit-marker) + headless tests in test_runner.gd tail chain.
- iter 2: Procedural audio pass — generated WAV SFX (gunshot, reload, player_hurt, zombie_hit, zombie_death) via generate_sfx.py; created AudioManager autoload with pooled AudioStreamPlayers listening to GameEvents.
- iter 3: kill-feed / event toasts — scavenge emits scavenge_completed + event_toast on-hud notification
- iter 4: Voxel-zombie hit-flash — per-instance duplicated StandardMaterial3D in VoxelZombie3D._ready() + 2 headless tests; suite green 195/0.
- iter 5: Stabilized flaky procedural_runtime_generation_profile + fixed stale HUD API Label.set_default_font_size() → add_theme_font_size_override.
- iter 6: Compass / off-screen safehouse indicator — new scripts/ui/safehouse_compass.gd (presentation-only widget) + 2 headless tests; suite green 197/0.
- iter 7: Day-night ambient tint cycle. New scripts/visuals/day_night_cycle.gd (presentation-only): reads SimulationClock.total_game_minutes(), blends a 9-keyframe 24h palette onto the scene Environment (background + ambient tint/energy) and Sun DirectionalLight3D (colour + energy) via smoothstep. Re-applies only when the integer game-minute changes (pause freezes the mood for free). Wired into VoxelMain.tscn as a sibling DayNightCycle node auto-resolving WorldEnvironment/Sun. Midday keyframe equals the shipped static look (zero-regression anchor). + 2 headless tests (palette continuity/bounds/time-keying; drives Environment + tolerates missing targets). Suite green 199/0. Committed as 3c2c920 + 9bed990, pushed to origin/master.

## Backlog (top-down)
1. Commit the 3 leftover .uid sidecars from prior iterations (audio_manager.gd.uid [iter2], combat_feedback.gd.uid [iter1], safehouse_compass.gd.uid [iter6]) — they were generated but never staged; add on the next run.
2. Player-visible polish candidates (freedom scope): weather/vignette tied to SimulationClock; HUD clock widget showing game day/hour; low-health screen desaturation in CombatFeedback; footstep/ambient audio loops. Split one per iteration.
3. Larger roadmap items from README (quests, economy, crafting…) — too large for one iteration; split later.
