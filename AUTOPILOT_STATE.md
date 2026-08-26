# AUTOPILOT STATE — life-after-death

STATUS: OK
Project: life-after-death (Godot 4.7.1 zombie survival game)

## Current goal
Iteration 5: Stabilize `procedural_runtime_generation_profile` — it intermittently fails ("seed 2147483646 spawn region exterior_07 must contain a full-footprint-valid candidate"), observed twice on 2026-08-26 including once on PRISTINE HEAD (so not caused by autopilot changes). Suspect wall-clock/frame-budget-dependent retry logic in spawn-candidate search. Also one-line drive-by available: `scripts/ui/hud.gd:40` calls nonexistent `Label.set_default_font_size()` (stale API, script error on every HUD._ready) → replace with `add_theme_font_size_override("font_size", 16)`.

## Done
- iter 1: Added CombatFeedback overlay to HUD (damage flash, low‑HP pulse, kill hit‑marker) + headless tests in test_runner.gd tail chain.
- iter 2: Procedural audio pass — generated WAV SFX (gunshot, reload, player_hurt, zombie_hit, zombie_death) via generate_sfx.py; created AudioManager autoload with pooled AudioStreamPlayers listening to GameEvents (weapon_fired, weapon_reload_started, player_damaged, zombie_damaged, zombie_killed_by_player + voxel variants); all 193 headless tests pass.
- iter 3: kill-feed / event toasts — scavenge emits scavenge_completed + event_toast on-hud notification
- iter 4: Voxel-zombie hit-flash — per-instance duplicated StandardMaterial3D in VoxelZombie3D._ready() (scene sub-resource is shared), `_flash_hit()` snaps albedo to white and tweens back over 0.12s, re-hit restarts tween. Two new headless tests (`voxel_zombie_hit_flash_engages_and_recovers`, `voxel_zombie_hit_flash_is_isolated_per_instance`); suite green 195/0. `.autopilot.lock` untracked + gitignored (machine-local runtime state).

## Backlog (top‑down)
1. Stabilize procedural_runtime_generation_profile (flaky red; see Current goal) + fix hud.gd:40 stale Label API.
2. Compass / off-screen safehouse indicator.
3. Day-night ambient tint cycle tied to SimulationClock.
4. Larger roadmap items from README (quests, economy, crafting…) — too large for one iteration; split later.
