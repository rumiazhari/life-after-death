class_name SurvivorInspector
extends CanvasLayer
## Read-only survivor inspection panel. Selection happens in Main (a
## right-click nearest-survivor pick, kept separate from the left-click
## "fire" binding) which emits GameEvents.survivor_selected; this panel only
## displays whatever the currently selected survivor's SurvivorAI/
## SurvivorData already expose -- it never writes back, so inspecting a
## survivor can never accidentally command one (see phase objective: the
## player does not directly issue survivor orders in this slice).

@onready var panel: Panel = $Panel
@onready var label: Label = $Panel/Label

var _selected: Survivor = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.survivor_selected.connect(_on_survivor_selected)
	GameEvents.survivor_died.connect(_on_survivor_died)
	panel.visible = false

func _process(_delta: float) -> void:
	if _selected == null or not is_instance_valid(_selected):
		return
	label.text = _build_text(_selected)

func _on_survivor_selected(survivor: Node2D) -> void:
	_selected = survivor as Survivor
	panel.visible = _selected != null

func _on_survivor_died(survivor: Node2D) -> void:
	if survivor == _selected:
		_selected = null
		panel.visible = false

func _build_text(survivor: Survivor) -> String:
	var data: SurvivorData = survivor.data
	var ai: SurvivorAI = survivor.ai
	if data == null:
		return ""
	var lines: Array[String] = []
	lines.append("%s (age %d)" % [data.survivor_name, data.age])
	lines.append("HP %d/%d  Fear %d  Morale %d" % [int(data.health), int(data.max_health), int(data.fear), int(data.morale)])
	lines.append("Hunger %d  Thirst %d  Fatigue %d  Infection %d" % [int(data.hunger), int(data.thirst), int(data.fatigue), int(data.infection_exposure)])
	lines.append("Goal: %s" % data.current_goal)
	lines.append("Action: %s" % data.current_action)
	lines.append("Target: %s" % ai.reserved_target_description)
	lines.append("Scores:")
	var score_keys: Array = ai.last_scores.keys()
	score_keys.sort()
	for key in score_keys:
		lines.append("  %s: %.2f" % [key, ai.last_scores[key]])
	lines.append("Carried:")
	var inv: Inventory = survivor.carried_inventory
	var any_items: bool = false
	for item_id in ItemDatabase.all_item_ids():
		var count: int = inv.get_count(item_id)
		if count > 0:
			any_items = true
			lines.append("  %s x%d" % [item_id, count])
	if not any_items:
		lines.append("  (empty)")
	return "\n".join(lines)
