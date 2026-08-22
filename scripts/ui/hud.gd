class_name HUD
extends CanvasLayer
## Read-only display driven entirely by GameEvents signals -- the HUD never
## reaches into Player/SpawnManager/Weapon directly.

@onready var health_label: Label = $Root/SafeArea/TopLeftPanel/TopLeft/HealthRow/HealthLabel
@onready var health_bar: ProgressBar = $Root/SafeArea/TopLeftPanel/TopLeft/HealthBar
@onready var weapon_label: Label = $Root/SafeArea/TopLeftPanel/TopLeft/WeaponLabel
@onready var ammo_label: Label = $Root/SafeArea/TopLeftPanel/TopLeft/AmmoRow/AmmoLabel
@onready var ammo_bar: ProgressBar = $Root/SafeArea/TopLeftPanel/TopLeft/AmmoBar
@onready var reload_label: Label = $Root/SafeArea/TopLeftPanel/TopLeft/ReloadLabel
@onready var zombie_count_label: Label = $Root/SafeArea/TopRightPanel/TopRight/ZombieRow/ZombieCountLabel
@onready var kills_label: Label = $Root/SafeArea/TopRightPanel/TopRight/KillsRow/KillsLabel
@onready var fps_label: Label = $Root/SafeArea/TopRightPanel/TopRight/FPSLabel
@onready var interact_prompt_panel: PanelContainer = $Root/SafeArea/InteractPromptPanel
@onready var interact_prompt_label: Label = $Root/SafeArea/InteractPromptPanel/InteractPromptLabel

var _known_magazine_size: int = 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.player_health_changed.connect(_on_health_changed)
	GameEvents.weapon_equipped.connect(_on_weapon_equipped)
	GameEvents.weapon_ammo_changed.connect(_on_ammo_changed)
	GameEvents.weapon_reload_started.connect(_on_reload_started)
	GameEvents.weapon_reload_finished.connect(_on_reload_finished)
	GameEvents.zombie_count_changed.connect(_on_zombie_count_changed)
	GameEvents.kill_count_changed.connect(_on_kill_count_changed)
	GameEvents.interact_prompt_changed.connect(_on_interact_prompt_changed)
	reload_label.visible = false
	kills_label.text = "Kills: 0"
	zombie_count_label.text = "Zombies: 0"
	interact_prompt_panel.visible = false

func _process(_delta: float) -> void:
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

func _on_health_changed(current: float, max_health: float) -> void:
	health_label.text = "HP: %d / %d" % [int(ceil(current)), int(max_health)]
	health_bar.max_value = max_health
	health_bar.value = current

func _on_ammo_changed(ammo_in_magazine: int, reserve_ammo: int) -> void:
	ammo_label.text = "Ammo: %d / %d" % [ammo_in_magazine, reserve_ammo]
	# Magazine fill, not total ammo including reserve -- "how close to
	# needing a reload" is the at-a-glance question a bar should answer.
	# weapon_ammo_changed doesn't carry magazine_size, so infer it as the
	# highest ammo_in_magazine ever observed (a full/just-reloaded
	# magazine) rather than reaching into Player/Weapon directly.
	_known_magazine_size = maxi(_known_magazine_size, ammo_in_magazine)
	ammo_bar.max_value = _known_magazine_size
	ammo_bar.value = ammo_in_magazine

func _on_weapon_equipped(weapon_name: String, slot_index: int, slot_count: int, ammo_in_magazine: int, reserve_ammo: int, magazine_size: int) -> void:
	weapon_label.text = "Weapon %d/%d: %s" % [slot_index + 1, slot_count, weapon_name]
	_known_magazine_size = maxi(magazine_size, 1)
	ammo_label.text = "Ammo: %d / %d" % [ammo_in_magazine, reserve_ammo]
	ammo_bar.max_value = _known_magazine_size
	ammo_bar.value = ammo_in_magazine
	reload_label.visible = false

func _on_reload_started(_duration: float) -> void:
	reload_label.visible = true
	reload_label.text = "Reloading..."

func _on_reload_finished(_ammo_in_magazine: int, _reserve_ammo: int) -> void:
	reload_label.visible = false

func _on_zombie_count_changed(active_count: int) -> void:
	zombie_count_label.text = "Zombies: %d" % active_count

func _on_kill_count_changed(total_kills: int) -> void:
	kills_label.text = "Kills: %d" % total_kills

func _on_interact_prompt_changed(label: String) -> void:
	interact_prompt_panel.visible = not label.is_empty()
	interact_prompt_label.text = label
