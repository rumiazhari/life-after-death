class_name VoxelChunk
extends StaticBody3D

const MATERIAL_REGISTRY := preload("res://scripts/voxel/voxel_material_registry.gd")

## One merged mesh and one collision body for a dictionary of integer voxels.
## Material IDs are positive; a missing coordinate is empty space.

const FACE_NORMALS: Array[Vector3] = [
	Vector3.LEFT, Vector3.RIGHT, Vector3.DOWN,
	Vector3.UP, Vector3.FORWARD, Vector3.BACK,
]
static var FACE_CORNERS: Array[PackedVector3Array] = [
	PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)]),
	PackedVector3Array([Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1)]),
	PackedVector3Array([Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)]),
	PackedVector3Array([Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)]),
	PackedVector3Array([Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)]),
	PackedVector3Array([Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)]),
]
static var QUAD_INDICES := PackedInt32Array([0, 1, 2, 0, 2, 3])
const FACE_TINTS: Array[Color] = [
	Color(0.72, 0.72, 0.72), Color(0.90, 0.90, 0.90), Color(0.62, 0.62, 0.62),
	Color.WHITE, Color(0.78, 0.78, 0.78), Color(0.94, 0.94, 0.94),
]

@export var voxel_size := 1.0
@export var generate_collision := true

var voxels: Dictionary = {}
var materials: Array[Material] = []
var rebuild_count := 0
var last_rebuild_usec := 0
var last_visible_faces := 0
var last_vertex_count := 0

@onready var mesh_instance: MeshInstance3D = $Mesh
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func configure(voxel_data: Dictionary, material_data: Array[Material]) -> void:
	voxels = voxel_data.duplicate()
	materials = material_data.duplicate()
	if is_node_ready():
		rebuild()


func configure_from_chunk_data(chunk_data) -> void:
	configure(chunk_data.cells, MATERIAL_REGISTRY.create_render_materials())


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	var started_at := Time.get_ticks_usec()
	var merged_mesh := ArrayMesh.new()
	var surfaces: Dictionary = {}
	last_visible_faces = 0
	last_vertex_count = 0
	for raw_cell in voxels:
		var cell: Vector3i = raw_cell
		var material_id := int(voxels[cell])
		if material_id <= 0 or material_id > materials.size():
			continue
		var surface: SurfaceTool = surfaces.get(material_id)
		if surface == null:
			surface = SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surfaces[material_id] = surface
		for face_index in range(FACE_NORMALS.size()):
			if voxels.has(cell + Vector3i(FACE_NORMALS[face_index])):
				continue
			_append_face(surface, cell, face_index)
			last_visible_faces += 1
			last_vertex_count += 6
	var material_ids: Array = surfaces.keys()
	material_ids.sort()
	for material_id_variant in material_ids:
		var material_id: int = material_id_variant
		var surface: SurfaceTool = surfaces[material_id]
		surface.set_material(materials[material_id - 1])
		surface.commit(merged_mesh)
	mesh_instance.mesh = merged_mesh
	collision_shape.shape = merged_mesh.create_trimesh_shape() if generate_collision and merged_mesh.get_surface_count() > 0 else null
	rebuild_count += 1
	last_rebuild_usec = Time.get_ticks_usec() - started_at


func visible_face_count() -> int:
	if rebuild_count > 0:
		return last_visible_faces
	var count := 0
	for raw_cell in voxels:
		var cell: Vector3i = raw_cell
		for normal in FACE_NORMALS:
			if not voxels.has(cell + Vector3i(normal)):
				count += 1
	return count


func set_collision_enabled(enabled: bool) -> void:
	if generate_collision == enabled:
		return
	generate_collision = enabled
	if not is_node_ready():
		return
	if not enabled:
		collision_shape.shape = null
		return
	var current_mesh: ArrayMesh = mesh_instance.mesh
	collision_shape.shape = current_mesh.create_trimesh_shape() if current_mesh != null and current_mesh.get_surface_count() > 0 else null


func build_metrics() -> Dictionary:
	return {
		"rebuild_count": rebuild_count,
		"rebuild_usec": last_rebuild_usec,
		"voxel_count": voxels.size(),
		"visible_faces": last_visible_faces,
		"vertex_count": last_vertex_count,
		"surface_count": mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 0,
		"collision_enabled": generate_collision,
	}


func _append_face(surface: SurfaceTool, cell: Vector3i, face_index: int) -> void:
	var origin := Vector3(cell) * voxel_size
	var corners := FACE_CORNERS[face_index]
	var uvs := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	for index in QUAD_INDICES:
		surface.set_normal(FACE_NORMALS[face_index])
		surface.set_color(FACE_TINTS[face_index])
		surface.set_uv(uvs[index])
		surface.add_vertex(origin + corners[index] * voxel_size)
