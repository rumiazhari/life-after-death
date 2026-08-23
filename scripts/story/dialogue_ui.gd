class_name DialogueUI
extends CanvasLayer
## Bottom-screen presentation for DialogueController: speaker name, body
## text, and choice buttons. Builds its own (minimal) Control tree so no
## scene file is required. Input is intentionally NOT consumed globally --
## Main/routes call advance()/choose() from their own input handling.

const PANEL_COLOR := Color(0.07, 0.07, 0.1, 0.92)
const BORDER_COLOR := Color(0.55, 0.53, 0.63)

var controller: DialogueController = null

var _root: Control
var _speaker_label: Label
var _text_label: Label
var _choices_box: VBoxContainer

func _ready() -> void:
	layer = 20
	_build_tree()
	_visible_ui(false)

func bind(target: DialogueController) -> void:
	if controller != null and controller.line_started.is_connected(_on_line_started):
		controller.line_started.disconnect(_on_line_started)
		controller.choices_available.disconnect(_on_choices_available)
		controller.dialogue_finished.disconnect(_on_dialogue_finished)
	controller = target
	if controller == null:
		return
	controller.line_started.connect(_on_line_started)
	controller.choices_available.connect(_on_choices_available)
	controller.dialogue_finished.connect(_on_dialogue_finished)

func _build_tree() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 80.0
	panel.offset_right = -80.0
	panel.offset_top = -190.0
	panel.offset_bottom = -24.0
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "Content"
	panel.add_child(vbox)

	_speaker_label = Label.new()
	_speaker_label.name = "Speaker"
	_speaker_label.add_theme_font_size_override("font_size", 15)
	_speaker_label.add_theme_color_override("font_color", Color8(226, 214, 166))
	vbox.add_child(_speaker_label)

	_text_label = Label.new()
	_text_label.name = "Text"
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.add_theme_font_size_override("font_size", 17)
	_text_label.custom_minimum_size = Vector2(0, 52)
	vbox.add_child(_text_label)

	_choices_box = VBoxContainer.new()
	_choices_box.name = "Choices"
	vbox.add_child(_choices_box)

	_visible_ui(false)

func _visible_ui(value: bool) -> void:
	_root.visible = value

func _on_line_started(_id: StringName, index: int, speaker: StringName, text: String) -> void:
	_clear_choices()
	_speaker_label.text = "%s (%d/%d)" % [String(speaker).capitalize(), index + 1, _line_count(_id)]
	_text_label.text = text
	_visible_ui(true)

func _line_count(id: StringName) -> int:
	var entry := DialogueDatabase.get_entry(id)
	return (entry.get("lines", []) as Array).size()

func _on_choices_available(_id: StringName, options: Array) -> void:
	_clear_choices()
	for i in range(options.size()):
		var option: Dictionary = options[i]
		var button := Button.new()
		button.text = String(option["text"])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var index := i
		button.pressed.connect(func() -> void:
			if controller != null:
				controller.choose(index))
		_choices_box.add_child(button)
	_visible_ui(true)

func _clear_choices() -> void:
	for child in _choices_box.get_children():
		child.queue_free()

func _on_dialogue_finished(_id: StringName) -> void:
	_visible_ui(false)

## Test/automation hook: current visible line text.
func displayed_text() -> String:
	return _text_label.text

func displayed_choice_texts() -> Array[String]:
	var result: Array[String] = []
	for child in _choices_box.get_children():
		if child is Button:
			result.append((child as Button).text)
	return result