class_name ProceduralDistrict
extends Node2D
## Runtime renderer for ProceduralCityGenerator's semantic model. Generation
## completes before Main starts population/survivor systems; collision is then
## sampled once into UrbanNavigationService.

signal generation_completed(seed_value: int)
signal generation_failed(seed_value: int, errors: Array[String])

const TS := PixelAtlasMap.TILE_SIZE
const WORLD_LAYER := 1

@export var city_seed: int = -1
@export var boundary_thickness: float = 40.0
## StreamingWorld sets these before the chunk enters the tree.  Keeping the
## existing district renderer as a chunk renderer makes the migration
## incremental: semantic generation and building construction stay identical
## while ownership/lifetime move to the streamed world.
@export var seed_override: int = -1
@export var stream_world_seed: int = -1
@export var chunk_coordinate: Vector2i = Vector2i.ZERO
@export var streamed_chunk: bool = false
@export var defer_navigation: bool = false
@export var build_boundaries: bool = true

var city_model: Dictionary = {}
var resolved_seed: int = 0
var generation_complete: bool = false
var generation_succeeded: bool = false
var generation_duration_ms: int = 0
var generation_errors: Array[String] = []
var _visual_rng := RandomNumberGenerator.new()
var _ground_layer: TileMapLayer
var _roads_layer: TileMapLayer
var _sidewalks_layer: TileMapLayer
var _markings_layer: TileMapLayer
var _external_nodes: Array[Node] = []

func _ready() -> void:
	var started_at := Time.get_ticks_msec()
	resolved_seed = ChunkEdgeContract.chunk_seed(stream_world_seed, chunk_coordinate) if streamed_chunk and stream_world_seed >= 0 else (seed_override if seed_override >= 0 else _resolve_seed())
	var generator := _create_generator()
	city_model = generator.generate_streamed_chunk(stream_world_seed, chunk_coordinate) if streamed_chunk and stream_world_seed >= 0 else generator.generate(resolved_seed)
	var errors := generator.validate(city_model)
	if not errors.is_empty():
		generation_errors.assign(errors)
		for error in errors:
			_report_generation_error(error)
		generation_complete = true
		generation_succeeded = false
		generation_duration_ms = Time.get_ticks_msec() - started_at
		generation_failed.emit(resolved_seed, errors)
		generation_completed.emit(resolved_seed)
		return
	_visual_rng.seed = resolved_seed ^ 0x51A7C05
	_build_tile_layers()
	_paint_ground_and_blocks()
	_paint_roads()
	_paint_exterior_zones()
	_paint_markings()
	if build_boundaries:
		_build_boundary()
	_build_buildings()
	_build_exterior_props()
	_build_scavenge_points()
	_build_spawn_regions()
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Settlement is a sibling of this world node. Position it before the
	# physics-point navigation sample so its physical safehouse shell is
	# represented at this seed's generated location, not Main.tscn's default.
	var settlement := get_tree().get_first_node_in_group("settlement") as Node2D
	if settlement and not streamed_chunk:
		settlement.global_position = get_safehouse_position()
	await get_tree().physics_frame
	if not defer_navigation:
		UrbanNavigationService.build_rect(Rect2(global_position - city_model["half_extent"], city_model["half_extent"] * 2.0))
		register_doors_with_navigation()
	generation_complete = true
	generation_succeeded = true
	generation_duration_ms = Time.get_ticks_msec() - started_at
	generation_completed.emit(resolved_seed)

func _create_generator() -> ProceduralCityGenerator:
	return ProceduralCityGenerator.new()

func _report_generation_error(error: String) -> void:
	push_error("Procedural city validation: %s" % error)

func _resolve_seed() -> int:
	if city_seed >= 0:
		WorldState.world_flags[&"city_seed"] = city_seed
		return city_seed
	if WorldState.world_flags.has(&"city_seed"):
		return int(WorldState.world_flags[&"city_seed"])
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var generated := rng.randi_range(1, 0x7FFFFFFF)
	WorldState.world_flags[&"city_seed"] = generated
	return generated

func get_arena_size() -> Vector2:
	return city_model.get("half_extent", ProceduralCityGenerator.ARENA_HALF_EXTENT)

func get_player_spawn() -> Vector2:
	return to_global(city_model.get("player_spawn", Vector2.ZERO))

func get_safehouse_position() -> Vector2:
	return to_global(city_model.get("safehouse_position", Vector2(-976, -976)))

func _build_tile_layers() -> void:
	var tileset := PixelTilesetBuilder.get_tileset()
	_ground_layer = _make_layer("Ground", -10, tileset)
	_roads_layer = _make_layer("Roads", -9, tileset)
	_sidewalks_layer = _make_layer("Sidewalks", -8, tileset)
	_markings_layer = _make_layer("RoadMarkings", -7, tileset)

func _make_layer(layer_name: String, layer_z: int, tileset: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.z_index = layer_z
	layer.tile_set = tileset
	$GroundLayers.add_child(layer)
	return layer

func _paint_ground_and_blocks() -> void:
	var half: Vector2 = city_model["half_extent"]
	var min_cell := Vector2i(floori(-half.x / TS), floori(-half.y / TS))
	var max_cell := Vector2i(ceili(half.x / TS) - 1, ceili(half.y / TS) - 1)
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			PixelTilesetBuilder.paint(_ground_layer, Vector2i(x, y), _ground_variant(&"concrete"))
	var public_block_ids: Dictionary = {}
	for public_space in city_model.get("public_spaces", []):
		public_block_ids[public_space["block_id"]] = true
	for block in city_model["blocks"]:
		var rect: Rect2 = block["rect"]
		var inner := rect.grow(-ProceduralCityGenerator.SIDEWALK_DEPTH)
		for cell in _cells_of(rect):
			var center := Vector2(cell.x * TS + TS * 0.5, cell.y * TS + TS * 0.5)
			if inner.has_point(center):
				var ground_tile: StringName = &"plaza_pavers" if public_block_ids.has(block["id"]) else _ground_variant(block["surface"])
				PixelTilesetBuilder.paint(_ground_layer, cell, ground_tile)
			else:
				PixelTilesetBuilder.paint(_sidewalks_layer, cell, &"sidewalk_1" if _visual_rng.randf() < 0.18 else &"sidewalk_0")

func _paint_roads() -> void:
	for road in city_model["roads"]:
		for cell in _cells_of(road["rect"]):
			var surface: StringName = road.get("surface", &"asphalt")
			var tile: StringName
			match surface:
				&"cobble": tile = &"cobble_1" if _visual_rng.randf() < 0.22 else &"cobble_0"
				&"stone_setts": tile = &"stone_setts"
				_: tile = StringName("asphalt_%d" % _visual_rng.randi_range(0, 3))
			PixelTilesetBuilder.paint(_roads_layer, cell, tile)
			if bool(road.get("tram", false)):
				PixelTilesetBuilder.paint(_markings_layer, cell, &"tram_h" if road["orientation"] == &"horizontal" else &"tram_v")

func _paint_exterior_zones() -> void:
	for exterior in city_model["exterior_zones"]:
		var kind: StringName = exterior["kind"]
		var rect: Rect2 = exterior["rect"]
		match kind:
			&"parking":
				for cell in _cells_of(rect):
					PixelTilesetBuilder.paint(_roads_layer, cell, &"asphalt_2")
				var bounds := _cell_bounds(rect)
				for x in range(bounds[0].x + 1, bounds[1].x, 3):
					for y in range(bounds[0].y, bounds[1].y + 1):
						PixelTilesetBuilder.paint(_markings_layer, Vector2i(x, y), &"road_solid_v")
			&"alley":
				for cell in _cells_of(rect):
					PixelTilesetBuilder.paint(_ground_layer, cell, &"cracked_ground" if _visual_rng.randf() < 0.45 else &"concrete")
			&"courtyard":
				for cell in _cells_of(rect):
					PixelTilesetBuilder.paint(_ground_layer, cell, &"plaza_pavers" if _visual_rng.randf() < 0.82 else &"cobble_1")

func _paint_markings() -> void:
	for road in city_model["roads"]:
		if road.get("kind", &"") == &"driveway" or road.get("surface", &"asphalt") != &"asphalt" or bool(road.get("tram", false)):
			continue
		var rect: Rect2 = road["rect"]
		if road["orientation"] == &"horizontal":
			var y := floori(rect.get_center().y / TS)
			var from_x := floori(rect.position.x / TS)
			var to_x := ceili(rect.end.x / TS) - 1
			for x in range(from_x, to_x + 1, 3):
				PixelTilesetBuilder.paint(_markings_layer, Vector2i(x, y), &"road_dash_h")
		else:
			var x := floori(rect.get_center().x / TS)
			var from_y := floori(rect.position.y / TS)
			var to_y := ceili(rect.end.y / TS) - 1
			for y in range(from_y, to_y + 1, 3):
				PixelTilesetBuilder.paint(_markings_layer, Vector2i(x, y), &"road_dash_v")

func _ground_variant(surface: StringName) -> StringName:
	if surface == &"concrete" and _visual_rng.randf() < 0.12:
		return &"cracked_ground"
	return surface

func _cells_of(rect: Rect2) -> Array[Vector2i]:
	var output: Array[Vector2i] = []
	var x0 := floori(rect.position.x / TS)
	var y0 := floori(rect.position.y / TS)
	var x1 := ceili(rect.end.x / TS) - 1
	var y1 := ceili(rect.end.y / TS) - 1
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			output.append(Vector2i(x, y))
	return output

func _cell_bounds(rect: Rect2) -> Array[Vector2i]:
	return [
		Vector2i(floori(rect.position.x / TS), floori(rect.position.y / TS)),
		Vector2i(ceili(rect.end.x / TS) - 1, ceili(rect.end.y / TS) - 1),
	]

func _build_boundary() -> void:
	var half: Vector2 = city_model["half_extent"]
	_make_boundary_wall(Vector2(0, -half.y), Vector2(half.x * 2.0, boundary_thickness))
	_make_boundary_wall(Vector2(0, half.y), Vector2(half.x * 2.0, boundary_thickness))
	_make_boundary_wall(Vector2(-half.x, 0), Vector2(boundary_thickness, half.y * 2.0))
	_make_boundary_wall(Vector2(half.x, 0), Vector2(boundary_thickness, half.y * 2.0))

func _make_boundary_wall(center: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = center
	body.collision_layer = WORLD_LAYER | 32
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	$Boundaries.add_child(body)

func _build_buildings() -> void:
	var sort_parent := get_tree().get_first_node_in_group("entity_container") as Node2D
	for spec in city_model["buildings"]:
		var instance := ProceduralBuilding.new()
		instance.configure(spec)
		instance.position = spec["position"]
		$Buildings.add_child(instance)
		if sort_parent != null:
			var facade := instance.attach_exterior_sort_parent(sort_parent)
			if facade != null:
				facade.add_to_group("projected_building_facade")
				_external_nodes.append(facade)

func _build_exterior_props() -> void:
	# Generated street objects share Main/EntityContainer with actors and
	# scavenging sites so its y_sort_enabled ordering can place a character
	# behind or in front of them by world Y. Standalone district fixtures keep
	# the local StreetProps fallback because they have no dynamic-world sibling.
	var prop_parent: Node2D = get_tree().get_first_node_in_group("entity_container") as Node2D
	if prop_parent == null:
		prop_parent = $StreetProps
	for spec in city_model["props"]:
		var first_new_child: int = prop_parent.get_child_count()
		var local_position: Vector2 = prop_parent.to_local(to_global(spec["position"]))
		if spec.has("visual_size") or spec.has("procedural_kind"):
			# Composed street object: independent visual dimensions,
			# collision footprint, base anchor and optional light.
			BuildingShellBuilder.add_street_object(prop_parent, local_position, spec)
		elif spec["interaction"] == &"loot":
			BuildingShellBuilder.add_loot_furniture(
				prop_parent, local_position, load(spec["texture"]), spec["size"], spec["id"], 80.0,
				spec["items"], "Search", spec["minimum_damage_class"]
			)
		else:
			BuildingShellBuilder.add_physical_prop(
				prop_parent, local_position, load(spec["texture"]), spec["size"], spec["id"],
				spec["yield"], spec["minimum_damage_class"]
			)
		if prop_parent.get_child_count() > first_new_child:
			var prop := prop_parent.get_child(first_new_child)
			prop.add_to_group("generated_street_prop")
			_external_nodes.append(prop)

func _build_scavenge_points() -> void:
	var dynamic_world := get_tree().get_first_node_in_group("entity_container")
	if dynamic_world == null:
		return
	var scene: PackedScene = load("res://scenes/world/ScavengePoint.tscn")
	for spec in city_model["scavenge_points"]:
		var instance: ScavengePoint = scene.instantiate()
		instance.name = String(spec["id"]).replace("/", "_")
		instance.point_id = spec["id"]
		instance.item_id = spec["item_id"]
		instance.yield_per_scavenge = spec["yield"]
		instance.remaining_stock = spec["stock"]
		instance.danger = spec["danger"]
		dynamic_world.add_child(instance)
		instance.global_position = to_global(spec["position"])
		_external_nodes.append(instance)

func _build_spawn_regions() -> void:
	for spec in city_model["spawn_regions"]:
		var marker := SpawnRegion.new()
		marker.name = String(spec["id"]).replace("/", "_")
		marker.region_id = spec["id"]
		marker.radius = spec["radius"]
		marker.category = spec["category"]
		marker.environment_tags.assign(spec["environment_tags"])
		marker.initial_weight = spec["initial_weight"]
		marker.replenishment_weight = spec["replenishment_weight"]
		marker.allow_initial = spec["allow_initial"]
		marker.allow_replenishment = spec["allow_replenishment"]
		marker.is_indoor = spec["indoor"]
		marker.is_reachable = spec["reachable"]
		marker.position = spec["position"]
		$SpawnRegions.add_child(marker)

func register_doors_with_navigation() -> void:
	for door_node in get_tree().get_nodes_in_group("doors"):
		var door := door_node as Door
		if door and is_ancestor_of(door):
			# Register the carved bay, not the raw semantic point: Door
			# children and the wall carve both center on
			# position + (aperture - tile) / 2 (see
			# ProceduralBuildingGenerator.door_bay_rect), so navigation must
			# agree or open doors route actors into intact wall cells.
			var bay_center := door.global_position + (door.aperture_size - Vector2(32.0, 32.0)) * 0.5
			UrbanNavigationService.register_door(door.door_id, bay_center, door.aperture_size)
			if door.is_open:
				UrbanNavigationService.mark_door_open(door.door_id)
			else:
				UrbanNavigationService.mark_door_closed(door.door_id)

func chunk_world_rect() -> Rect2:
	var half: Vector2 = city_model.get("half_extent", ProceduralCityGenerator.ARENA_HALF_EXTENT)
	return Rect2(global_position - half, half * 2.0)

func _exit_tree() -> void:
	# Props and scavenge points are intentionally reparented into Main's
	# shared Y-sorted entity layer.  A streamed chunk must still own their
	# lifetime, otherwise walking indefinitely leaks every previous chunk.
	for node in _external_nodes:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.queue_free()
	_external_nodes.clear()
