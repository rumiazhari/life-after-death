extends Node
## Deterministic visual QA capture for the projected Prague building system.
## Produces exterior and interior PNGs from the production Main scene.

const OUTPUT_DIR := "res://docs/screenshots/projected-buildings"

func _ready() -> void:
	call_deferred("_capture")

func _capture() -> void:
	print("PROJECTED_CAPTURE_START")
	var packed: PackedScene = load("res://scenes/main/Main.tscn")
	var main := packed.instantiate()
	get_tree().root.add_child(main)
	for _i in range(12):
		await get_tree().process_frame
		await get_tree().physics_frame
	var world := main.get_node("World") as StreamingWorld
	var district := world.get_chunk(Vector2i.ZERO)
	if district == null or not district.generation_succeeded:
		push_error("Projected-building capture could not resolve the origin Prague chunk")
		get_tree().quit(2)
		return
	var buildings := district.get_node("Buildings").get_children()
	if buildings.is_empty():
		push_error("Projected-building capture found no runtime building")
		get_tree().quit(3)
		return
	var target := _select_target(buildings)
	var player := main.get_node("EntityContainer/Player") as Player
	var bounds: Rect2 = target.specification["interior"]["footprint_bounds"]
	player.global_position = target.global_position + Vector2(0.0, bounds.end.y + 40.0)
	(main.get_node("CameraRig") as CameraRig).set_target(player)
	for _i in range(6):
		await get_tree().process_frame
		await get_tree().physics_frame
	await _save_frame("prague-facade-exterior.png")

	var first_room: Dictionary = target.specification["interior"]["rooms"][0]
	player.global_position = target.global_position + (first_room["rect"] as Rect2).get_center()
	(main.get_node("CameraRig") as CameraRig).set_target(player)
	for _i in range(6):
		await get_tree().process_frame
		await get_tree().physics_frame
	await _save_frame("prague-facade-interior.png")

	var settlement := main.get_node("Settlement") as Settlement
	player.global_position = settlement.global_position + Vector2(0.0, 282.0)
	(main.get_node("CameraRig") as CameraRig).set_target(player)
	for _i in range(6):
		await get_tree().process_frame
		await get_tree().physics_frame
	await _save_frame("prague-safehouse-gatehouse.png")
	get_tree().quit(0)

func _select_target(buildings: Array) -> ProceduralBuilding:
	for building in buildings:
		if building is ProceduralBuilding and building.specification.get("facade_style", &"") == &"active_shopfront":
			return building
	return buildings[0] as ProceduralBuilding

func _save_frame(file_name: String) -> void:
	await get_tree().process_frame
	var absolute_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(absolute_dir.path_join(file_name))
	if error != OK:
		push_error("Failed to save projected-building QA capture %s: %s" % [file_name, error_string(error)])
	else:
		print("PROJECTED_CAPTURE_SAVED ", absolute_dir.path_join(file_name))
