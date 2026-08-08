class_name PlayerInteractor
extends Area2D
## Nearest-candidate interaction picker for the player. Never scans every
## prop in the map: candidates are only ever the InteractableComponents
## whose owning Area2D is currently overlapping this Area2D (collision
## layer 64, "Interactable" -- see docs/interaction_system.md for the full
## layer table), added/removed via area_entered/area_exited. Selection
## prefers the candidate roughly in the player's aim direction over a
## strictly-nearer one behind them, so facing a door in a cluttered room
## reliably targets that door.

const LAYER_INTERACTABLE := 64
const FACING_DOT_THRESHOLD := 0.3 ## candidate must be within ~107 degrees of aim to get the facing bonus
const FACING_BONUS := 40.0 ## world units subtracted from effective distance when facing

var _candidate_areas: Array[Area2D] = []
var _player: Node2D
var _last_prompt: String = ""

func _ready() -> void:
	collision_layer = 0
	collision_mask = LAYER_INTERACTABLE
	_player = get_parent()
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	InputRouter.interact_requested.connect(_on_interact_requested)

func _physics_process(_delta: float) -> void:
	_prune_invalid()
	var best: InteractableComponent = _best_candidate()
	var label: String = best.interact_label if best else ""
	if label != _last_prompt:
		_last_prompt = label
		GameEvents.interact_prompt_changed.emit(label)

func _on_area_entered(area: Area2D) -> void:
	if _get_component(area) and area not in _candidate_areas:
		_candidate_areas.append(area)

func _on_area_exited(area: Area2D) -> void:
	_candidate_areas.erase(area)

func _prune_invalid() -> void:
	var i: int = _candidate_areas.size() - 1
	while i >= 0:
		if not is_instance_valid(_candidate_areas[i]):
			_candidate_areas.remove_at(i)
		i -= 1

func _get_component(area: Area2D) -> InteractableComponent:
	return area.get_node_or_null("InteractableComponent")

func _best_candidate() -> InteractableComponent:
	var best_comp: InteractableComponent = null
	var best_score: float = INF
	var aim: Vector2 = _player.aim_direction if "aim_direction" in _player else Vector2.RIGHT
	for area in _candidate_areas:
		if not is_instance_valid(area):
			continue
		var comp: InteractableComponent = _get_component(area)
		if comp == null or not comp.can_interact(_player):
			continue
		var offset: Vector2 = area.global_position - _player.global_position
		var dist: float = offset.length()
		var score: float = dist
		if dist > 0.01 and aim.dot(offset / dist) >= FACING_DOT_THRESHOLD:
			score -= FACING_BONUS
		if score < best_score:
			best_score = score
			best_comp = comp
	return best_comp

func _on_interact_requested() -> void:
	var best: InteractableComponent = _best_candidate()
	if best:
		best.interact(_player)
