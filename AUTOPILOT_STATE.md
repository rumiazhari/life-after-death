# AUTOPILOT STATE — life-after-death

STATUS: OK
Project: life-after-death (Godot 4.7.1 zombie survival game)

## Current goal
Iteration 1: HUD combat feedback overlay — damage flash on player_damaged, low‑HP warning pulse below 30%, kill‑confirm hit‑marker on zombie_killed_by_player. Tests pass via headless TestRunner (`"../Godot_v4.7.2-stable_win64.exe" --headless --path . res://tests/TestRunner.tscn`) — judge by `=== TEST RESULTS: N passed, 0 failed ===`.

## Done
- iter 1: Added CombatFeedback overlay to HUD (damage flash, low‑HP pulse, kill hit‑marker) + headless tests in test_runner.gd tail chain.

## Backlog (top‑down, from docs/ roadmap priorities)
1. Audio pass: generate/procedural SFX for gunshot, reload, zombie hit/death, player hurt (no assets exist yet; consider generating simple WAVs or runtime AudioStreamPlayer).
2. Kill‑feed / event toasts — small on‑HUD notifications for scavenge results, survivor status.
3. Hit‑flash on zombies when damaged (white modulate pulse) for better game feel.
4. Compass / off‑screen safehouse indicator.
5. Day‑night ambient tint cycle tied to SimulationClock.
6. Larger roadmap items from README (quests, economy, crafting…) — too large for one iteration; split later.