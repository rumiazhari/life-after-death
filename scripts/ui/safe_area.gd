class_name SafeArea
extends Control
## Insets its own rect to the platform's safe area (notches, rounded
## corners, system status/gesture bars) and re-applies it whenever the
## window resizes or rotates. Reusable: any CanvasLayer's screen-edge
## content (HUD corners, mobile joysticks/buttons) should be parented
## under one of these instead of directly under the layer's root Control,
## so it naturally insets rather than being drawn under a notch.
##
## No-op (zero margins) on platforms without a safe-area concept, so this
## is safe to use on desktop too.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.size_changed.connect(_apply_safe_area)
	_apply_safe_area()

func _apply_safe_area() -> void:
	var window_size: Vector2 = DisplayServer.window_get_size()
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	var full_area: Rect2i = DisplayServer.screen_get_usable_rect()
	if safe_area.size == Vector2i.ZERO or full_area.size == Vector2i.ZERO:
		return
	if safe_area == full_area:
		offset_left = 0.0
		offset_top = 0.0
		offset_right = 0.0
		offset_bottom = 0.0
		return

	var canvas_size: Vector2 = get_viewport_rect().size
	var scale: Vector2 = canvas_size / window_size

	offset_left = float(safe_area.position.x - full_area.position.x) * scale.x
	offset_top = float(safe_area.position.y - full_area.position.y) * scale.y
	offset_right = -float((full_area.position.x + full_area.size.x) - (safe_area.position.x + safe_area.size.x)) * scale.x
	offset_bottom = -float((full_area.position.y + full_area.size.y) - (safe_area.position.y + safe_area.size.y)) * scale.y
