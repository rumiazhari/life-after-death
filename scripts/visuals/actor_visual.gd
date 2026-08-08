class_name ActorVisual
extends AnimatedSprite2D
## Sprite-based replacement for the old Polygon2D BodyVisual, shared by
## Player/Survivor/Zombie. Reads its frames from the ActorSpriteLibrary
## autoload (one shared SpriteFrames resource per actor type, not
## duplicated per instance) and exposes update_from_velocity() so each
## actor's own _physics_process can drive facing/pose without the visual
## layer touching any gameplay state itself.
##
## Direction is chosen from velocity, not rotation (actor bodies never
## rotate -- only WeaponPivot does, for aim, entirely independent of
## this): horizontal dominance -> "side" (mirrored via flip_h for left),
## vertical-positive (moving down the screen) -> "down", vertical-negative
## -> "up". The last direction is retained while stationary instead of
## resetting, so a character doesn't visibly snap to face "down" the
## instant it stops.
##
## Damage-flash code in player.gd/survivor.gd/zombie.gd keeps working
## unchanged: it only ever sets/tweens `modulate`, a CanvasItem property
## every one of Polygon2D/Sprite2D/AnimatedSprite2D shares.

const MOVING_SPEED_THRESHOLD := 4.0

@export var actor_type: StringName = &"player"
@export var variant: int = 0

var _direction: StringName = &"down"

func _ready() -> void:
	sprite_frames = ActorSpriteLibrary.get_frames(actor_type)
	play(_animation_name(&"idle"))

## velocity: the owning CharacterBody2D's current velocity, read-only.
func update_from_velocity(velocity: Vector2) -> void:
	var moving: bool = velocity.length() > MOVING_SPEED_THRESHOLD
	if moving:
		_direction = _direction_from_velocity(velocity)
		if _direction == &"side":
			flip_h = velocity.x < 0.0
	var target := _animation_name(&"walk" if moving else &"idle")
	if animation != target:
		play(target)

func _direction_from_velocity(velocity: Vector2) -> StringName:
	if absf(velocity.x) >= absf(velocity.y):
		return &"side"
	return &"down" if velocity.y > 0.0 else &"up"

func _animation_name(anim: StringName) -> String:
	return "%s_%s_%d" % [_direction, anim, variant]
