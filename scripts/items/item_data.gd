class_name ItemData
extends Resource
## Data-driven item definition. One resource instance = one item type,
## mirroring the WeaponData pattern in scripts/combat/weapon_data.gd.
## Adding a new item is adding a new .tres under resources/items/, not code.

enum Category { FOOD, WATER, MEDICAL, AMMO, MATERIAL }

@export var item_id: StringName = &""
@export var display_name: String = "Item"
@export var category: Category = Category.MATERIAL
@export var weight_per_unit: float = 1.0
@export var max_stack: int = 99
## How much this single unit restores when consumed (hunger/thirst points
## for FOOD/WATER, health points for MEDICAL). Unused for AMMO/MATERIAL.
@export var restore_amount: float = 0.0
