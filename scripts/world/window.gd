class_name BuildingWindow
extends Node2D
## Always blocks movement. Vision blocking depends on authored state:
## intact glass lets the BuildingVisibilityController's room reveal see
## through it (also usable later as a reduced-detection sightline for
## zombie perception); boarded fully blocks vision like a wall. State is
## authored per-instance. Intact glass accepts small-arms damage; boarded
## windows require heavy damage. Destruction removes the complete collider and
## persists through EnvironmentDamageComponent's stable object id.

const INTACT_TEXTURE := preload("res://assets/pixel/props/window_intact.png")
const BOARDED_TEXTURE := preload("res://assets/pixel/props/window_boarded.png")

const LAYER_WORLD := 1
const LAYER_VISION := 32

@export var window_id: StringName = &""
@export var is_boarded: bool = false

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision_body: StaticBody2D = $CollisionBody

func _ready() -> void:
	add_to_group("windows")
	_sprite.texture = BOARDED_TEXTURE if is_boarded else INTACT_TEXTURE
	_collision_body.collision_layer = LAYER_WORLD | (LAYER_VISION if is_boarded else 0)
	_collision_body.collision_mask = 0
	var damage := EnvironmentDamageComponent.new()
	damage.name = "EnvironmentDamageComponent"
	damage.object_id = StringName("%s/structure" % String(window_id))
	damage.minimum_damage_class = EnvironmentDamage.DamageClass.HEAVY if is_boarded else EnvironmentDamage.DamageClass.SMALL_ARMS
	damage.max_durability = 45.0 if is_boarded else 18.0
	damage.affected_size = Vector2(30, 12)
	damage.destroy_target = self
	_collision_body.add_child(damage)

## Whether a raycast may pass through this window for room-reveal / vision
## purposes. Boarded windows never do; intact ones do.
func blocks_vision() -> bool:
	return is_boarded
