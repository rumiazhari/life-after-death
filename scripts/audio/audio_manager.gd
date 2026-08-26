@tool
extends Node
## AudioManager (autoload "AudioManager")
##
## Central audio playback for SFX. Listens to GameEvents and plays
## appropriate procedural sounds. Keeps a pool of AudioStreamPlayer
## instances for overlapping sounds without manual management.

var _sfx_pool: Array[AudioStreamPlayer] = []
const MAX_POOL_SIZE := 32

## Preloaded sound resources (loaded once at startup)
@export var gunshot_sound: AudioStreamWAV
@export var reload_sound: AudioStreamWAV
@export var player_hurt_sound: AudioStreamWAV
@export var zombie_hit_sound: AudioStreamWAV
@export var zombie_death_sound: AudioStreamWAV

## Volume multipliers (tweakable in inspector)
@export var master_volume: float = 1.0
@export var sfx_volume: float = 0.8
@export var gunshot_volume: float = 1.0
@export var reload_volume: float = 0.7
@export var player_hurt_volume: float = 1.0
@export var zombie_hit_volume: float = 0.9
@export var zombie_death_volume: float = 1.0

func _ready() -> void:
	# Load sounds at runtime (preload fails in headless)
	gunshot_sound = load("res://assets/audio/sfx/gunshot.wav")
	reload_sound = load("res://assets/audio/sfx/reload.wav")
	player_hurt_sound = load("res://assets/audio/sfx/player_hurt.wav")
	zombie_hit_sound = load("res://assets/audio/sfx/zombie_hit.wav")
	zombie_death_sound = load("res://assets/audio/sfx/zombie_death.wav")
	
	# Pre-warm pool
	for i in range(8):
		_get_player()
	# Connect to GameEvents
	GameEvents.weapon_fired.connect(_on_weapon_fired)
	GameEvents.weapon_reload_started.connect(_on_weapon_reload_started)
	GameEvents.player_damaged.connect(_on_player_damaged)
	GameEvents.zombie_damaged.connect(_on_zombie_damaged)
	GameEvents.zombie_killed_by_player.connect(_on_zombie_killed_by_player)
	# Also listen for voxel variants if needed
	GameEvents.voxel_zombie_damaged.connect(_on_voxel_zombie_damaged)
	GameEvents.voxel_zombie_died.connect(_on_voxel_zombie_died)

func _get_player() -> AudioStreamPlayer:
	var player: AudioStreamPlayer
	if _sfx_pool.is_empty():
		player = AudioStreamPlayer.new()
		player.name = "SFX_Player_%d" % _sfx_pool.size()
		add_child(player)
	else:
		player = _sfx_pool.pop_front()
	return player

func _release_player(player: AudioStreamPlayer) -> void:
	if _sfx_pool.size() < MAX_POOL_SIZE:
		player.stream = null
		_sfx_pool.append(player)
	else:
		player.queue_free()

func _play_sound(stream: AudioStreamWAV, volume_db: float = 0.0, pitch_scale: float = 1.0, position: Vector2 = Vector2.ZERO) -> void:
	if stream == null:
		return
	var player := _get_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	# For 2D positional audio we'd need AudioStreamPlayer2D; keep simple for now
	player.play()
	# Release back to pool when finished (with a small delay)
	var tween := create_tween()
	tween.tween_callback(_release_player.bind(player)).set_delay(stream.get_length() / pitch_scale + 0.1)

func _on_weapon_fired(ammo_in_magazine: int, magazine_size: int) -> void:
	_play_sound(gunshot_sound, linear_to_db(sfx_volume * gunshot_volume * master_volume), randf_range(0.95, 1.05))

func _on_weapon_reload_started(duration: float) -> void:
	_play_sound(reload_sound, linear_to_db(sfx_volume * reload_volume * master_volume))

func _on_player_damaged(amount: float) -> void:
	_play_sound(player_hurt_sound, linear_to_db(sfx_volume * player_hurt_volume * master_volume))

func _on_zombie_damaged(zombie: Node2D, amount: float) -> void:
	# Pitch varies slightly per hit for variety
	_play_sound(zombie_hit_sound, linear_to_db(sfx_volume * zombie_hit_volume * master_volume), randf_range(0.9, 1.1))

func _on_zombie_killed_by_player(death_position: Vector2) -> void:
	_play_sound(zombie_death_sound, linear_to_db(sfx_volume * zombie_death_volume * master_volume), randf_range(0.85, 1.0))

func _on_voxel_zombie_damaged(zombie: Node3D, amount: float) -> void:
	_play_sound(zombie_hit_sound, linear_to_db(sfx_volume * zombie_hit_volume * master_volume), randf_range(0.9, 1.1))

func _on_voxel_zombie_died(zombie: Node3D, death_position: Vector3) -> void:
	_play_sound(zombie_death_sound, linear_to_db(sfx_volume * zombie_death_volume * master_volume), randf_range(0.85, 1.0))