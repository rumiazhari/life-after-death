# AUTOPILOT STATE — life-after-death

STATUS: OK
Project: life-after-death (Godot 4.7.1 zombie survival game)

## Current goal
Iteration 3: Kill-feed / event toasts — small on-HUD notifications for scavenge results, survivor status. Tests pass via headless TestRunner (`"../Godot_v4.7.2-stable_win64.exe" --headless --path . res://tests/TestRunner.tscn`) — judge by `=== TEST RESULTS: N passed, 0 failed ===`.

## Done
- iter 1: Added CombatFeedback overlay to HUD (damage flash, low‑HP pulse, kill hit‑marker) + headless tests in test_runner.gd tail chain.
- iter 2: Procedural audio pass — generated WAV SFX (gunshot, reload, player_hurt, zombie_hit, zombie_death) via generate_sfx.py; created AudioManager autoload with pooled AudioStreamPlayers listening to GameEvents (weapon_fired, weapon_reload_started, player_damaged, zombie_damaged, zombie_killed_by_player + voxel variants); all 193 headless tests pass.

## Backlog (top‑down, from docs/ roadmap priorities)
1. Kill-feed / event toasts — small on-HUD notifications for scavenge results, survivor status.
2. Hit-flash on zombies when damaged (white modulate pulse) for better game feel.
3. Compass / off-screen safehouse indicator.
4. Day-night ambient tint cycle tied to SimulationClock.
5. Larger roadmap items from README (quests, economy, crafting…) — too large for one iteration; split later.