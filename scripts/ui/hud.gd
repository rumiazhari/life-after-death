class_name HUD
extends CanvasLayer
## Read-only display driven entirely by GameEvents signals -- the HUD never
## reaches into Player/SpawnManager/Weapon directly.

@onready var health_label: Label = $Root/SafeArea/TopLeft/HealthLabel
@onready var ammo_label: Label = $Root/SafeArea/TopLeft/AmmoLabel
@onready var reload_label: Label = $Root/SafeArea/TopLeft/ReloadLabel
@onready var zombie_count_label: Label = $Root/SafeArea/TopRight/ZombieCountLabel
@onready var kills_label: Label = $Root/SafeArea/TopRight/KillsLabel
@onready var fps_label: Label = $Root/SafeArea/TopRight/FPSLabel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.player_health_changed.connect(_on_health_changed)
	GameEvents.weapon_ammo_changed.connect(_on_ammo_changed)
	GameEvents.weapon_reload_started.connect(_on_reload_started)
	GameEvents.weapon_reload_finished.connect(_on_reload_finished)
	GameEvents.zombie_count_changed.connect(_on_zombie_count_changed)
	GameEvents.kill_count_changed.connect(_on_kill_count_changed)
	reload_label.visible = false
	kills_label.text = "Kills: 0"
	zombie_count_label.text = "Zombies: 0"

func _process(_delta: float) -> void:
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

func _on_health_changed(current: float, max_health: float) -> void:
	health_label.text = "HP: %d / %d" % [int(ceil(current)), int(max_health)]

func _on_ammo_changed(ammo_in_magazine: int, reserve_ammo: int) -> void:
	ammo_label.text = "Ammo: %d / %d" % [ammo_in_magazine, reserve_ammo]

func _on_reload_started(_duration: float) -> void:
	reload_label.visible = true
	reload_label.text = "Reloading..."

func _on_reload_finished(_ammo_in_magazine: int, _reserve_ammo: int) -> void:
	reload_label.visible = false

func _on_zombie_count_changed(active_count: int) -> void:
	zombie_count_label.text = "Zombies: %d" % active_count

func _on_kill_count_changed(total_kills: int) -> void:
	kills_label.text = "Kills: %d" % total_kills
