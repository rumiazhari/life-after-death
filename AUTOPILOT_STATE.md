# AUTOPILOT STATE — life-after-death

STATUS: OK
Project: life-after-death (Godot 4.7.1 zombie survival game)

## Current goal
Iteration 7: Backlog item #2 — Day-night ambient tint cycle tied to SimulationClock.

## Done
- iter 1: Added CombatFeedback overlay to HUD (damage flash, low‑HP pulse, kill hit‑marker) + headless tests in test_runner.gd tail chain.
- iter 2: Procedural audio pass — generated WAV SFX (gunshot, reload, player_hurt, zombie_hit, zombie_death) via generate_sfx.py; created AudioManager autoload with pooled AudioStreamPlayers listening to GameEvents (weapon_fired, weapon_reload_started, player_damaged, zombie_damaged, zombie_killed_by_player + voxel variants); all 193 headless tests pass.
- iter 3: kill-feed / event toasts — scavenge emits scavenge_completed + event_toast on-hud notification
- iter 4: Voxel-zombie hit-flash — per-instance duplicated StandardMaterial3D in VoxelZombie3D._ready() (scene sub-resource is shared), `_flash_hit()` snaps albedo to white and tweens back over 0.12s, re-hit restarts tween. Two new headless tests (`voxel_zombie_hit_flash_engages_and_recovers`, `voxel_zombie_hit_flash_is_isolated_per_instance`); suite green 195/0. `.autopilot.lock` untracked + gitignored (machine-local runtime state).
- iter 5: Stabilized flaky `procedural_runtime_generation_profile` — added comprehensive actor-group hygiene (zombies, survivors, player, settlement, spawn_manager, swarm_manager, attackable) to fixture setup so leaked live actors from earlier tests no longer pollute physics/nav sampling; fixed stale HUD API `Label.set_default_font_size()` → `add_theme_font_size_override("font_size", 16)`. Suite green 195/0.
- iter 6: Compass / off-screen safehouse indicator — new `scripts/ui/safehouse_compass.gd` (presentation-only widget): HUD feeds it settlement screen pos via `get_viewport().get_canvas_transform()` + world distance each frame; marker clamps to a 56px viewport inset along the bearing, arrow rotates to true bearing, metre readout at 20px/m (documented approximation), hides while target is inside the inset. Wired into HUD._ready/_process with group polling (player/settlement) and freed-node guards. First run exposed an inverted clamp comparison (t>=1 ⇔ on-screen) caught by the new tests. Two headless tests (`safehouse_compass_offscreen_clamping_and_readout`, `hud_builds_safehouse_compass_and_tolerates_missing_targets`); suite green 197/0.

## Backlog (top‑down)
1. Day-night ambient tint cycle tied to SimulationClock.
2. Larger roadmap items from README (quests, economy, crafting…) — too large for one iteration; split later.
