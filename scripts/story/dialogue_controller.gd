class_name DialogueController
extends Node
## Drives one conversation at a time from DialogueDatabase: start() shows the
## first line, advance() steps through lines, and when lines run out the
## entry's choices are presented; choose(index) applies the chosen effects
## (WorldState world flag) and either jumps to the branch target or finishes.
## Pure logic -- presentation lives in DialogueUI.

signal line_started(dialogue_id: StringName, index: int, speaker: StringName, text: String)
signal choices_available(dialogue_id: StringName, options: Array)
signal dialogue_finished(dialogue_id: StringName)

var active_id: StringName = &""
var line_index := -1
var _choices_presented := false

func is_active() -> bool:
	return active_id != &""

func start(dialogue_id: StringName) -> bool:
	var entry := DialogueDatabase.get_entry(dialogue_id)
	if entry.is_empty():
		return false
	active_id = dialogue_id
	line_index = -1
	_choices_presented = false
	return advance()

## Steps to the next line. Returns true while a line was shown; when lines
## run out it presents choices (once) or finishes, and returns false.
func advance() -> bool:
	if not is_active():
		return false
	var entry := DialogueDatabase.get_entry(active_id)
	var lines: Array = entry["lines"]
	if line_index + 1 < lines.size():
		line_index += 1
		line_started.emit(active_id, line_index, entry["speaker"], String(lines[line_index]))
		return true
	return _finish_or_present(entry)

func _finish_or_present(entry: Dictionary) -> bool:
	if not _choices_presented:
		var choices: Array = entry["choices"]
		if not choices.is_empty():
			_choices_presented = true
			choices_available.emit(active_id, choices.duplicate(true))
			return false
	_finish()
	return false

func choose(choice_index: int) -> bool:
	if not is_active():
		return false
	var entry := DialogueDatabase.get_entry(active_id)
	var choices: Array = entry["choices"]
	if choice_index < 0 or choice_index >= choices.size():
		return false
	var choice: Dictionary = choices[choice_index]
	var flag: StringName = choice["set_flag"]
	if flag != &"":
		WorldState.world_flags[flag] = true
	var next: StringName = choice["next"]
	if next != &"" and DialogueDatabase.has(next):
		active_id = next
		line_index = -1
		_choices_presented = false
		return advance()
	_finish()
	return false

func cancel() -> void:
	if is_active():
		var id := active_id
		active_id = &""
		line_index = -1
		_choices_presented = false
		dialogue_finished.emit(id)

func _finish() -> void:
	var id := active_id
	active_id = &""
	line_index = -1
	_choices_presented = false
	dialogue_finished.emit(id)
