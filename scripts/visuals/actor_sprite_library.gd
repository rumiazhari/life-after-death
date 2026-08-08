extends Node
## Autoload. Builds (once) the shared SpriteFrames resource for each actor
## type from the generated pixel atlases, so every Player/Survivor/Zombie
## instance references the SAME SpriteFrames object instead of each
## constructing/duplicating its own -- required to stay cheap at up to 250
## concurrent zombies. Frame layout (frame size, animation names, variant
## counts) is read entirely from PixelAtlasMap so this file never
## hard-codes atlas geometry itself.

var _frames_by_type: Dictionary = {} ## StringName -> SpriteFrames
var _variant_counts: Dictionary = {
	&"player": PixelAtlasMap.PLAYER_VARIANT_COUNT,
	&"survivor": PixelAtlasMap.SURVIVOR_VARIANT_COUNT,
	&"zombie": PixelAtlasMap.ZOMBIE_VARIANT_COUNT,
}
var _atlas_paths: Dictionary = {
	&"player": PixelAtlasMap.PLAYER_ATLAS_PATH,
	&"survivor": PixelAtlasMap.SURVIVOR_ATLAS_PATH,
	&"zombie": PixelAtlasMap.ZOMBIE_ATLAS_PATH,
}

func get_frames(actor_type: StringName) -> SpriteFrames:
	if not _frames_by_type.has(actor_type):
		_frames_by_type[actor_type] = _build_frames(actor_type)
	return _frames_by_type[actor_type]

func get_variant_count(actor_type: StringName) -> int:
	return _variant_counts.get(actor_type, 1)

## Deterministic per-instance variant pick (no runtime RNG needed) -- callers
## pass a stable per-actor number (e.g. a data id) so the same actor always
## gets the same cosmetic variant across a session.
func variant_for(actor_type: StringName, stable_key: int) -> int:
	var count: int = get_variant_count(actor_type)
	return posmod(stable_key, count)

## Builds one animation per (variant, direction, idle|walk) combination --
## e.g. "down_idle_0", "side_walk_3" -- each with its 2 (idle) or 3 (walk)
## frames sourced from the atlas column PixelAtlasMap.actor_frame_column()
## assigns that slot. "side" covers both left/right: ActorVisual flips the
## sprite horizontally rather than this library doubling the animation set.
func _build_frames(actor_type: StringName) -> SpriteFrames:
	var atlas_path: String = _atlas_paths.get(actor_type, PixelAtlasMap.PLAYER_ATLAS_PATH)
	var texture: Texture2D = load(atlas_path)
	var variant_count: int = get_variant_count(actor_type)
	var fs: Vector2i = PixelAtlasMap.ACTOR_FRAME_SIZE
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for v in range(variant_count):
		for direction in PixelAtlasMap.ACTOR_DIRECTIONS:
			_add_animation(frames, texture, fs, v, direction, &"idle", PixelAtlasMap.ACTOR_IDLE_FRAME_COUNT, 2.0)
			_add_animation(frames, texture, fs, v, direction, &"walk", PixelAtlasMap.ACTOR_WALK_FRAME_COUNT, 6.0)
	return frames

func _add_animation(frames: SpriteFrames, texture: Texture2D, fs: Vector2i, variant: int, direction: StringName, anim: StringName, frame_count: int, fps: float) -> void:
	var anim_name := "%s_%s_%d" % [direction, anim, variant]
	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, true)
	frames.set_animation_speed(anim_name, fps)
	for frame_idx in range(frame_count):
		var col: int = PixelAtlasMap.actor_frame_column(direction, anim, frame_idx)
		var atlas_tex := AtlasTexture.new()
		atlas_tex.atlas = texture
		atlas_tex.region = Rect2(Vector2(col * fs.x, variant * fs.y), Vector2(fs.x, fs.y))
		frames.add_frame(anim_name, atlas_tex)
