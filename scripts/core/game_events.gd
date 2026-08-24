extends Node
## Global signal bus (autoload "GameEvents").
##
## Decouples systems that would otherwise need direct references to each
## other (HUD, SpawnManager, SwarmManager, Player, weapons). Systems emit
## through this bus instead of calling into each other directly, which keeps
## script dependencies one-directional.

signal player_health_changed(current: float, max_health: float)
signal player_damaged(amount: float)
signal player_died()
signal player_respawned()

signal zombie_spawned(zombie: Node2D)
signal zombie_damaged(zombie: Node2D, amount: float)
signal zombie_died(zombie: Node2D, death_position: Vector2)
signal zombie_killed_by_player(death_position: Vector2)

signal zombie_count_changed(active_count: int)
signal kill_count_changed(total_kills: int)

signal weapon_fired(ammo_in_magazine: int, magazine_size: int)
signal weapon_reload_started(duration: float)
signal weapon_reload_finished(ammo_in_magazine: int, reserve_ammo: int)
signal weapon_ammo_changed(ammo_in_magazine: int, reserve_ammo: int)
signal weapon_equipped(weapon_name: String, slot_index: int, slot_count: int, ammo_in_magazine: int, reserve_ammo: int, magazine_size: int)
signal environment_explosion(origin: Vector2, radius: float)
signal voxel_environment_explosion(origin: Vector3, radius: float)
signal voxel_zombie_damaged(zombie: Node3D, amount: float)
signal voxel_zombie_died(zombie: Node3D, death_position: Vector3)

signal game_paused()
signal game_resumed()
signal game_restarted()

signal survivor_spawned(survivor: Node2D)
signal survivor_died(survivor: Node2D)
signal survivor_selected(survivor: Node)

## Phase 3B: fires whenever PlayerInteractor's best candidate changes.
## Empty string means "no valid interaction target right now."
signal interact_prompt_changed(label: String)
## Emitted when a survivor group switches floors inside a multistory
## generated building (0 = ground, 1 = upper).
signal building_floor_changed(building: ProceduralBuilding, floor_index: int)
