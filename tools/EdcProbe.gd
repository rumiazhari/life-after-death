extends Node

func _ready() -> void:
	var script: Script = load("res://scripts/combat/environment_damage_component.gd")
	print("reload errors follow:")
	var err: int = script.reload()
	print("reload result=", err)
	get_tree().quit(0)
