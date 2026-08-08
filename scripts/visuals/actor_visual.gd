class_name ActorVisual
extends AnimatedSprite2D
## Sprite-based replacement for the old Polygon2D BodyVisual, shared by
## Player/Survivor/Zombie. Reads its frames from the ActorSpriteLibrary
## autoload (one SpriteFrames resource per actor type, shared across every
## instance of that type) and exposes update_from_velocity() so each
## actor's own _physics_process can drive facing/pose -- this node never
## reads or writes gameplay state itself, only presentation.
##
## Damage-flash code in player.gd/survivor.gd/zombie.gd keeps working
## unchanged: it only ever sets/tweens `modulate`, a CanvasItem property
## every one of Polygon2D/Sprite2D/AnimatedSprite2D shares.

@export var actor_type: StringName = &"player"
@export var variant: int = 0

func _ready() -> void:
	sprite_frames = ActorSpriteLibrary.get_frames(actor_type)
	play(_animation_name(false))

## velocity: the owning CharacterBody2D's current velocity, read-only.
func update_from_velocity(velocity: Vector2) -> void:
	if absf(velocity.x) > 4.0:
		flip_h = velocity.x < 0.0
	var target := _animation_name(velocity.length() > 4.0)
	if animation != target:
		play(target)

func _animation_name(moving: bool) -> String:
	return "%s_%d" % [("walk" if moving else "idle"), variant]
