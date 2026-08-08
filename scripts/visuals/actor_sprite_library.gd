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

func _build_frames(actor_type: StringName) -> SpriteFrames:
	var atlas_path: String = _atlas_paths.get(actor_type, PixelAtlasMap.PLAYER_ATLAS_PATH)
	var texture: Texture2D = load(atlas_path)
	var variant_count: int = get_variant_count(actor_type)
	var fs: Vector2i = PixelAtlasMap.ACTOR_FRAME_SIZE
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for v in range(variant_count):
		for frame_idx in range(PixelAtlasMap.ACTOR_FRAME_NAMES.size()):
			var anim_name := "%s_%d" % [PixelAtlasMap.ACTOR_FRAME_NAMES[frame_idx], v]
			frames.add_animation(anim_name)
			frames.set_animation_loop(anim_name, true)
			frames.set_animation_speed(anim_name, 4.0)
			var atlas_tex := AtlasTexture.new()
			atlas_tex.atlas = texture
			atlas_tex.region = Rect2(Vector2(frame_idx * fs.x, v * fs.y), Vector2(fs.x, fs.y))
			frames.add_frame(anim_name, atlas_tex)
	return frames
