class_name PlatformUtils
extends RefCounted
## Static helpers for platform/touch-input detection, shared by
## MobileControls and anything else that needs to know whether the
## on-screen touch controls should be shown.

const FORCE_MOBILE_SETTING := "debug/mobile_controls/force_visible"

## True on an actual mobile export, or on desktop/editor when the
## "debug/mobile_controls/force_visible" project setting is enabled --
## a development toggle for testing touch controls without a device.
static func should_show_mobile_controls() -> bool:
	if OS.has_feature("mobile"):
		return true
	return bool(ProjectSettings.get_setting(FORCE_MOBILE_SETTING, false))
