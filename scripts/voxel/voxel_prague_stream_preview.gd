extends Node3D

const CITY_GENERATOR := preload("res://scripts/world/procedural_city_generator.gd")
const VOXELIZER := preload("res://scripts/voxel/semantic_voxelizer.gd")
const MATERIALS := preload("res://scripts/voxel/voxel_material_registry.gd")
const COORDINATES := preload("res://scripts/voxel/voxel_coordinates.gd")

@export var world_seed := 20260822

var _capture_path := ""
var _capture_frames := 0
var profile_metrics: Dictionary = {}


func _ready() -> void:
	WorldState.reset()
	var generator = CITY_GENERATOR.new()
	var voxelizer = VOXELIZER.new()
	var total_objects := 0
	var total_voxels := 0
	var total_faces := 0
	var maximum_build_usec := 0
	for coordinate in [Vector2i.ZERO, Vector2i.RIGHT]:
		var city: Dictionary = generator.generate_streamed_chunk(world_seed, coordinate)
		var world = voxelizer.voxelize_chunk(city, world_seed, coordinate)
		var renderer: VoxelChunk = $OriginChunk if coordinate == Vector2i.ZERO else $EastChunk
		renderer.position = Vector3(coordinate.x * COORDINATES.CHUNK_CELLS, 0, coordinate.y * COORDINATES.CHUNK_CELLS)
		renderer.configure_from_chunk_data(world.get_chunk(coordinate))
		total_objects += world.stable_objects.size()
		var metrics: Dictionary = renderer.build_metrics()
		total_voxels += int(metrics.voxel_count)
		total_faces += int(metrics.visible_faces)
		maximum_build_usec = maxi(maximum_build_usec, int(metrics.rebuild_usec))
	profile_metrics = {
		"chunks": 2,
		"voxels": total_voxels,
		"visible_faces": total_faces,
		"stable_objects": total_objects,
		"maximum_build_usec": maximum_build_usec,
	}
	$CanvasLayer/Panel/Label.text = "PRAGUE VOXEL STREAM  •  2 chunks  •  %s voxels  •  %s faces  •  %d objects" % [_grouped(total_voxels), _grouped(total_faces), total_objects]
	_parse_capture_argument()


func _process(_delta: float) -> void:
	if _capture_path.is_empty():
		return
	_capture_frames += 1
	if _capture_frames < 8:
		return
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("VOXEL_PRAGUE_CAPTURE requires a rendering display driver")
		get_tree().quit(1)
		return
	var result := image.save_png(_capture_path)
	print("VOXEL_PRAGUE_CAPTURE path=%s result=%s" % [_capture_path, error_string(result)])
	get_tree().quit(0 if result == OK else 1)


func _parse_capture_argument() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prague-voxel="):
			_capture_path = argument.trim_prefix("--capture-prague-voxel=")


func _grouped(value: int) -> String:
	var digits := str(value)
	var result := ""
	while digits.length() > 3:
		result = "," + digits.right(3) + result
		digits = digits.left(digits.length() - 3)
	return digits + result
