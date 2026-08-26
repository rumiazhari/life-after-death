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

const SAFEHOUSE_COMPASS_SCRIPT: GDScript = preload("res://scripts/ui/safehouse_compass.gd")

var _known_magazine_size: int = 1
var has_player: bool = false
var floor_label: Label
var safehouse_compass: Control

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
	has_player = get_tree().get_first_node_in_group("player") != null
	# Add floor indicator label dynamically
	var floor_dbg := Label.new()
	floor_dbg.name = "floor_label"
	floor_dbg.add_theme_font_size_override("font_size", 16)
	floor_dbg.position = Vector2(10, get_viewport().get_visible_rect().size.y - 30)
	add_child(floor_dbg)
	floor_label = floor_dbg
	# Off-screen safehouse indicator (see safehouse_compass.gd); fed from
	# _process like the floor label -- read-only group polling, no direct
	# coupling to Settlement.
	safehouse_compass = SAFEHOUSE_COMPASS_SCRIPT.new()
	safehouse_compass.name = "SafehouseCompass"
	add_child(safehouse_compass)

func _process(_delta: float) -> void:
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	var player: Node2D = get_tree().get_first_node_in_group("player")
	if player != null and has_player:
		floor_label.text = "Floor: %d" % player.current_floor
	_update_safehouse_compass()

func _update_safehouse_compass() -> void:
	if safehouse_compass == null or not is_instance_valid(safehouse_compass):
		return
	var player: Node2D = get_tree().get_first_node_in_group("player")
	var settlement: Node2D = get_tree().get_first_node_in_group("settlement")
	if player == null or settlement == null \
			or not is_instance_valid(player) or not is_instance_valid(settlement):
		safehouse_compass.visible = false
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var target_screen: Vector2 = get_viewport().get_canvas_transform() * settlement.global_position
	safehouse_compass.update_indicator(
		target_screen,
		viewport_size,
		settlement.global_position.distance_to(player.global_position))

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
