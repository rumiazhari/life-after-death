class_name BuildingExteriorRenderer
extends RefCounted
## Projects a validated top-down footprint into a camera-facing Prague
## elevation. All generated nodes are visual-only; physical walls, rooms,
## portals and navigation continue to use the undisplaced semantic footprint.

const TILE_SIZE := 32.0

static func make_prague_spec(building: Dictionary) -> Dictionary:
	var interior: Dictionary = building.get("interior", {})
	var requested_storeys := int(building.get("storeys", 3))
	var visual_storeys := clampi(requested_storeys, 2, 6)
	return {
		"projection_height_tiles": visual_storeys,
		"visual_storeys": visual_storeys,
		"facade_style": building.get("facade_style", &"painted_plaster"),
		"roof_profile": building.get("roof_shape", &"pitched_ridge"),
		"apocalypse_level": int(building.get("apocalypse_level", 0)),
		"frontage_edge": &"south",
		"street_wall": bool(building.get("street_wall", false)),
		"decoration_seed": int((String(building.get("id", &"building")).hash() ^ 0x50A6E) & 0x7fffffff),
		"entrance_positions": _south_entrances(interior),
		"window_positions": _south_windows(interior),
	}

static func build(parent: BuildingVisibilityController, building: Dictionary, interior: Dictionary) -> Dictionary:
	var exterior: Dictionary = building.get("exterior", make_prague_spec(building))
	var perimeter_rects: Array = interior.get("perimeter_rects", [Rect2(-interior["half_extent"], interior["half_extent"] * 2.0)])
	var spans := south_facade_spans(perimeter_rects)
	var projection_height := float(clampi(int(exterior.get("projection_height_tiles", 3)), 2, 6)) * TILE_SIZE
	var anchor_y := _southern_anchor(spans)

	var roof := TileMapLayer.new()
	roof.name = "Roof"
	roof.tile_set = PixelTilesetBuilder.get_tileset()
	roof.position.y = -projection_height
	roof.z_index = 5
	parent.add_child(roof)
	if perimeter_rects.size() == 1:
		BuildingShellBuilder.paint_roof(roof, interior["half_extent"], interior["roof_material"])
	else:
		BuildingShellBuilder.paint_compound_roof(roof, perimeter_rects, interior["roof_material"])

	var facade := BuildingFacadeVisual.new()
	facade.name = "ProjectedFacade"
	facade.z_index = 0
	parent.add_child(facade)
	facade.configure({
		"facade_spans": spans,
		"facade_style": exterior.get("facade_style", building.get("facade_style", &"painted_plaster")),
		"archetype": building.get("archetype", &"apartment"),
		"visual_storeys": int(exterior.get("visual_storeys", 3)),
		"projection_height": projection_height,
		"anchor_y": anchor_y,
		"entrance_positions": exterior.get("entrance_positions", _south_entrances(interior)),
		"window_positions": exterior.get("window_positions", _south_windows(interior)),
		"decoration_seed": int(exterior.get("decoration_seed", String(building.get("id", &"building")).hash())),
		"occluder_footprints": perimeter_rects,
		"apocalypse_level": int(exterior.get("apocalypse_level", building.get("apocalypse_level", 0))),
		"roof_profile": StringName(exterior.get("roof_profile", &"pitched_ridge")),
	})
	# Roof and facade occlude together: one shared world-space fade material
	# (see BuildingFacadeVisual) so a single uniform update drives both.
	roof.material = facade.occlusion_material()
	parent.register_exterior_cover(facade)
	return {"roof": roof, "facade": facade, "spans": spans, "projection_height": projection_height}

static func build_authored(
	parent: BuildingVisibilityController,
	half_extent: Vector2,
	roof_material: String,
	style: StringName,
	archetype_name: StringName,
	visual_storeys: int,
	entrances: Array[Vector2],
	windows: Array[Vector2] = []
) -> Dictionary:
	var interior := {
		"half_extent": half_extent,
		"perimeter_rects": [Rect2(-half_extent, half_extent * 2.0)],
		"roof_material": roof_material,
		"doors": [],
		"windows": [],
	}
	var building := {
		"id": parent.building_id,
		"archetype": archetype_name,
		"facade_style": style,
		"exterior": {
			"projection_height_tiles": clampi(visual_storeys, 2, 6),
			"visual_storeys": clampi(visual_storeys, 2, 6),
			"facade_style": style,
			"roof_profile": &"pitched_ridge",
			"frontage_edge": &"south",
			"decoration_seed": int((String(parent.building_id).hash() ^ 0x50A6E) & 0x7fffffff),
			"entrance_positions": entrances,
			"window_positions": windows,
		},
	}
	return build(parent, building, interior)

static func south_facade_spans(perimeter_rects: Array) -> Array[Rect2]:
	var occupied: Dictionary = {}
	for rect_variant in perimeter_rects:
		var rect: Rect2 = rect_variant
		var first := Vector2i(floori(rect.position.x / TILE_SIZE), floori(rect.position.y / TILE_SIZE))
		var last := Vector2i(ceili(rect.end.x / TILE_SIZE) - 1, ceili(rect.end.y / TILE_SIZE) - 1)
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				occupied[Vector2i(x, y)] = true
	var boundary_by_row: Dictionary = {}
	for cell_variant in occupied.keys():
		var cell: Vector2i = cell_variant
		if occupied.has(cell + Vector2i.DOWN):
			continue
		if not boundary_by_row.has(cell.y):
			boundary_by_row[cell.y] = []
		boundary_by_row[cell.y].append(cell.x)
	var spans: Array[Rect2] = []
	var rows: Array = boundary_by_row.keys()
	rows.sort()
	for row_variant in rows:
		var row := int(row_variant)
		var columns: Array = boundary_by_row[row]
		columns.sort()
		var run_start := int(columns[0])
		var previous := run_start
		for column_index in range(1, columns.size()):
			var column := int(columns[column_index])
			if column != previous + 1:
				spans.append(Rect2(Vector2(run_start * TILE_SIZE, (row + 1) * TILE_SIZE), Vector2((previous - run_start + 1) * TILE_SIZE, 0.0)))
				run_start = column
			previous = column
		spans.append(Rect2(Vector2(run_start * TILE_SIZE, (row + 1) * TILE_SIZE), Vector2((previous - run_start + 1) * TILE_SIZE, 0.0)))
	return spans

static func validate(building: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var interior: Dictionary = building.get("interior", {})
	var exterior: Dictionary = building.get("exterior", {})
	if exterior.is_empty():
		errors.append("missing projected exterior specification")
		return errors
	var projection_tiles := int(exterior.get("projection_height_tiles", 0))
	if projection_tiles < 2 or projection_tiles > 6:
		errors.append("projection height must remain between two and six tiles")
	if exterior.get("frontage_edge", &"") != &"south":
		errors.append("Prague fixed-camera frontage must face south")
	var spans := south_facade_spans(interior.get("perimeter_rects", []))
	if spans.is_empty():
		errors.append("compound footprint has no visible south facade span")
	var semantic_entrances := _south_entrances(interior)
	var visual_entrances: Array = exterior.get("entrance_positions", [])
	for entrance in semantic_entrances:
		var matched := false
		for visual in visual_entrances:
			if (visual as Vector2).is_equal_approx(entrance):
				matched = true
				break
		if not matched:
			errors.append("projected facade omits semantic entrance at %s" % str(entrance))
			continue
		if not _position_has_span(entrance, spans):
			errors.append("semantic entrance at %s is not supported by a south facade span" % str(entrance))
	return errors

static func _south_entrances(interior: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for door in interior.get("doors", []):
		if bool(door.get("exterior", false)) and not bool(door.get("service", false)) and is_equal_approx(float(door.get("rotation", 0.0)), 0.0):
			result.append(door["position"])
	return result

static func _south_windows(interior: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for window in interior.get("windows", []):
		if is_equal_approx(float(window.get("rotation", 0.0)), 0.0) and float((window["position"] as Vector2).y) > 0.0:
			result.append(window["position"])
	return result

static func _position_has_span(position: Vector2, spans: Array[Rect2]) -> bool:
	for span in spans:
		if position.x >= span.position.x and position.x <= span.end.x and absf(position.y + TILE_SIZE * 0.5 - span.end.y) <= 1.0:
			return true
	return false

static func _southern_anchor(spans: Array[Rect2]) -> float:
	var result := 0.0
	for span in spans:
		result = maxf(result, span.end.y)
	return result
