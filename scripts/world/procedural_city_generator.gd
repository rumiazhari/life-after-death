class_name ProceduralCityGenerator
extends RefCounted
## Deterministic semantic city generator. It owns gameplay geometry and IDs;
## ProceduralDistrict only rasterizes and instantiates this validated model.

const TILE_SIZE := 32
const ARENA_HALF_EXTENT := Vector2(1408, 1408)
const RING_CENTER := 1280.0
const SIDEWALK_DEPTH := 32.0
const MIN_BLOCK_SIZE := 384.0
const MAX_GENERATION_ATTEMPTS := 8
const GENERATED_SPAWN_RADIUS := 8.0
## A 128px room only has a 64px inner square after perimeter walls.  Once
## furniture and a 17px zombie footprint are included it is not a reliable
## spawn volume, so it stays enterable but does not advertise a spawn region.
const MIN_INDOOR_SPAWN_SPAN := 160.0
# SpawnManager checks a 13 px zombie body plus 4 px margin. Including the
# generated region's 8 px sampling radius makes every point in the region fit
# inside this deterministic 25 px obstacle/boundary clearance.
const GENERATED_SPAWN_CLEARANCE := 25.0
const PRAGUE_PLAZA_CHANCE_PERCENT := 5
const PRAGUE_COURTYARD_CHANCE_PERCENT := 6
const PRAGUE_COURTYARD_REAR_RESERVE := 192.0
## Auxiliary connectors (driveways, square branches, edge portals) must reach
## into their semantic parent carriageway by at least this much so Rect2
## overlap -- and therefore graph adjacency -- never depends on extension
## heuristics guessing a street band width.
const CONNECTOR_ROAD_OVERLAP := 32.0
## Grown exterior-zone rects populated during _make_exterior_props; consumed
## by the prop-placement guard so physical objects never land inside zones.
var _zone_clear_rects: Array[Rect2] = []

const BUILDING_ARCHETYPES := {
	&"apartment": {"minimum_size": Vector2(256, 256)},
	&"restaurant": {"minimum_size": Vector2(256, 256)},
	&"store": {"minimum_size": Vector2(256, 256)},
	&"clinic": {"minimum_size": Vector2(256, 256)},
	&"workshop": {"minimum_size": Vector2(256, 256)},
}

const PROP_TEXTURES := {
	&"bench": "res://assets/pixel/props/bench.png",
	&"tree": "res://assets/pixel/props/tree.png",
	&"dumpster": "res://assets/pixel/props/dumpster.png",
	&"crate": "res://assets/pixel/props/crate.png",
	&"car": "res://assets/pixel/props/car_sedan.png",
	&"wreck": "res://assets/pixel/props/car_wreck.png",
	&"lamp": "res://assets/pixel/props/street_lamp.png",
	&"trash": "res://assets/pixel/props/trash_bag.png",
	&"medical_cache": "res://assets/pixel/props/loot_medical.png",
	&"hydrant": "res://assets/pixel/props/hydrant.png",
	&"cone": "res://assets/pixel/props/cone.png",
	&"bollard": "res://assets/pixel/props/cone.png",
	&"sign_post": "res://assets/pixel/props/street_sign.png",
	&"tram_stop": "res://assets/pixel/props/street_sign.png",
	&"utility_box": "res://assets/pixel/props/utility_box.png",
	&"planter": "res://assets/pixel/props/planter.png",
	&"rubble": "res://assets/pixel/props/debris_small.png",
	&"sandbags": "res://assets/pixel/props/sandbags.png",
	&"pallet": "res://assets/pixel/props/pallet.png",
	&"barrel": "res://assets/pixel/props/furniture_barrel.png",
	&"barrier": "res://assets/pixel/props/road_barrier.png",
}

var _rng := RandomNumberGenerator.new()

func generate(seed_value: int) -> Dictionary:
	var failure_messages: Array[String] = []
	for attempt in range(MAX_GENERATION_ATTEMPTS):
		var attempt_seed := _attempt_seed(seed_value, attempt)
		_rng.seed = attempt_seed
		var city := _generate_attempt(seed_value, attempt, attempt_seed)
		var errors := validate(city)
		if errors.is_empty():
			city["validation_errors"] = []
			return city
		failure_messages.append("attempt %d: %s" % [attempt, "; ".join(errors)])
	return {
		"seed": seed_value,
		"generation_attempt": MAX_GENERATION_ATTEMPTS,
		"generation_error": "procedural city exhausted %d deterministic attempts" % MAX_GENERATION_ATTEMPTS,
		"validation_errors": failure_messages,
	}

## StreamingWorld asks for the same renderer-independent city model, then
## adds deterministic border contracts and a local dead-end branch.  The
## base district remains usable as a compact regression fixture.
func generate_streamed_chunk(world_seed: int, coordinate: Vector2i) -> Dictionary:
	var seed_value := ChunkEdgeContract.chunk_seed(world_seed, coordinate)
	var failure_messages: Array[String] = []
	for attempt in range(MAX_GENERATION_ATTEMPTS):
		var attempt_seed := _attempt_seed(seed_value, attempt)
		_rng.seed = attempt_seed
		var morphology := PragueRegionalPlan.morphology(world_seed, coordinate)
		var city := _generate_prague_attempt(seed_value, attempt, attempt_seed, morphology, coordinate)
		var chunk_tiles := int(ARENA_HALF_EXTENT.x * 2.0 / TILE_SIZE)
		var edge_contracts := {
			&"north": ChunkEdgeContract.edge_portals(world_seed, coordinate, ChunkEdgeContract.Side.NORTH, chunk_tiles),
			&"east": ChunkEdgeContract.edge_portals(world_seed, coordinate, ChunkEdgeContract.Side.EAST, chunk_tiles),
			&"south": ChunkEdgeContract.edge_portals(world_seed, coordinate, ChunkEdgeContract.Side.SOUTH, chunk_tiles),
			&"west": ChunkEdgeContract.edge_portals(world_seed, coordinate, ChunkEdgeContract.Side.WEST, chunk_tiles),
		}
		var roads: Array[Dictionary] = city["roads"]
		var road_by_id := _index_by_id(roads)
		_append_edge_contract_roads(roads, edge_contracts, road_by_id)
		_append_park_branch(roads, city["blocks"], seed_value, road_by_id)
		_append_building_access_branches(roads, city["buildings"], road_by_id)
		city["roads"] = roads
		city["world_seed"] = world_seed
		city["chunk_coordinate"] = coordinate
		city["edge_contracts"] = edge_contracts
		city["regional_morphology"] = morphology
		city["district_profile"] = morphology["profile"]
		city["road_topology"] = &"prague_frontage_branch_graph"
		var errors := validate(city)
		if errors.is_empty():
			city["validation_errors"] = []
			return city
		failure_messages.append("attempt %d: %s" % [attempt, "; ".join(errors)])
	return {
		"seed": seed_value,
		"world_seed": world_seed,
		"chunk_coordinate": coordinate,
		"generation_attempt": MAX_GENERATION_ATTEMPTS,
		"generation_error": "streamed Prague city exhausted %d deterministic attempts" % MAX_GENERATION_ATTEMPTS,
		"validation_errors": failure_messages,
	}

func _generate_prague_attempt(seed_value: int, attempt: int, attempt_seed: int, morphology: Dictionary, coordinate: Vector2i) -> Dictionary:
	var axes := _prague_street_axes(morphology)
	var roads := _make_roads(axes, axes)
	for road in roads:
		road["surface"] = PragueRegionalPlan.street_surface(morphology["profile"], road["kind"])
		road["tram"] = road["orientation"] == morphology["tram_axis"] and road["kind"] == &"arterial"
	var intersections := _make_intersections(axes, axes)
	var park_candidates: Array[int] = [2, 6, 7]
	var park_index := -1
	if _rare_prague_feature(seed_value, &"plaza", PRAGUE_PLAZA_CHANCE_PERCENT):
		park_index = park_candidates[_rng.randi_range(0, park_candidates.size() - 1)]
	var include_safehouse := coordinate == Vector2i.ZERO
	var blocks := _make_prague_blocks(axes, park_index, morphology, seed_value, include_safehouse)
	var parcels := _make_prague_parcels(blocks)
	var buildings := _make_buildings(seed_value, parcels, blocks, int(morphology.get("apocalypse_level", 1)))
	_apply_prague_building_style(buildings, morphology)
	var exterior_zones := _make_exterior_zones(seed_value, blocks, parcels, buildings)
	var courtyards := _make_prague_courtyards(seed_value, blocks, buildings)
	for courtyard in courtyards:
		exterior_zones.append({
			"id": courtyard["id"], "block_id": courtyard["block_id"],
			"kind": &"courtyard", "zone": courtyard["zone"], "rect": courtyard["rect"],
		})
	var props := _make_exterior_props(seed_value, blocks, buildings, exterior_zones, morphology)
	props = _filter_prague_frontage_props(props, buildings)
	var spawn_regions := _make_spawn_regions(seed_value, blocks, roads, exterior_zones, buildings, props)
	for region in spawn_regions:
		var tags: Array = region["environment_tags"]
		if not tags.has(morphology["profile"]):
			tags.append(morphology["profile"])
		region["environment_tags"] = tags
	var scavenging := _make_scavenge_points(seed_value, blocks, exterior_zones, props)
	var landmarks := _make_landmarks(seed_value, blocks, buildings, exterior_zones, props, scavenging, include_safehouse)
	props = _filter_prague_anchor_conflicts(props, scavenging, landmarks)
	var safe_block: Dictionary = blocks[0]
	var safehouse_position: Vector2 = safe_block["rect"].get_center() if include_safehouse else Vector2.ZERO
	var safehouse_entrance := safehouse_position + Vector2(0, 208) if include_safehouse else Vector2.ZERO
	var public_spaces: Array[Dictionary] = []
	if park_index >= 0:
		public_spaces.append({"id": StringName("city_%d/%s" % [seed_value, morphology["square_kind"]]), "kind": morphology["square_kind"], "block_id": blocks[park_index]["id"], "rect": blocks[park_index]["rect"]})
	return {
		"seed": seed_value,
		"attempt_seed": attempt_seed,
		"generation_attempt": attempt,
		"generation_error": "",
		"half_extent": ARENA_HALF_EXTENT,
		"roads": roads,
		"intersections": intersections,
		"blocks": blocks,
		"parcels": parcels,
		"buildings": buildings,
		"exterior_zones": exterior_zones,
		"props": props,
		"spawn_regions": spawn_regions,
		"scavenge_points": scavenging,
		"landmarks": landmarks,
		"public_spaces": public_spaces,
		"courtyards": courtyards,
		"has_safehouse": include_safehouse,
		"safehouse_position": safehouse_position,
		"safehouse_entrance": safehouse_entrance,
		"safehouse_access": _corridor_rect(safehouse_entrance, Vector2(safehouse_entrance.x, safe_block["rect"].end.y - 16.0), 48.0) if include_safehouse else Rect2(),
		"player_spawn": safehouse_position + Vector2(0, 130) if include_safehouse else Vector2.ZERO,
	}

func _prague_street_axes(morphology: Dictionary) -> Array[Dictionary]:
	var inner: Array = morphology["inner_axes"]
	var widths: Dictionary = morphology.get("street_widths", {"local": 128.0, "arterial": 192.0})
	return [
		{"center": -RING_CENTER, "width": 128.0, "kind": &"ring"},
		{"center": float(inner[0]), "width": float(widths["local"]), "kind": &"local"},
		{"center": float(inner[1]), "width": float(widths["arterial"]), "kind": &"arterial"},
		{"center": RING_CENTER, "width": 128.0, "kind": &"ring"},
	]

func _make_prague_blocks(axes: Array[Dictionary], park_index: int, morphology: Dictionary, seed_value: int, include_safehouse: bool) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	var dimension := axes.size() - 1
	for row in range(dimension):
		for col in range(dimension):
			var left := float(axes[col]["center"]) + float(axes[col]["width"]) * 0.5
			var right := float(axes[col + 1]["center"]) - float(axes[col + 1]["width"]) * 0.5
			var top := float(axes[row]["center"]) + float(axes[row]["width"]) * 0.5
			var bottom := float(axes[row + 1]["center"]) - float(axes[row + 1]["width"]) * 0.5
			# NOTE: profile street widths deliberately leave block sizes off
			# the 64 px module grid; sub-module margins become wider sidewalk,
			# and the branch appenders below always reach across that band so
			# the semantic road graph stays fully connected.
			var index := row * dimension + col
			var zone := _prague_zone_for(index, row, col, park_index, dimension, include_safehouse)
			var surface: StringName = &"grass" if zone == &"park" else (&"dirt" if zone == &"industrial" else &"concrete")
			var block_id := StringName("quarter_%02d" % index)
			blocks.append({
				"id": block_id, "index": index, "row": row, "col": col,
				"rect": Rect2(left, top, right - left, bottom - top), "zone": zone, "surface": surface,
				"district_profile": morphology["profile"],
				"frontage_road_id": StringName("road_h_%d" % (row + 1)),
				"courtyard_reserved": zone not in [&"safehouse", &"park"] and _rare_prague_feature(seed_value, block_id, PRAGUE_COURTYARD_CHANCE_PERCENT),
			})
	return blocks

func _prague_zone_for(index: int, row: int, col: int, park_index: int, dimension: int, include_safehouse: bool) -> StringName:
	if include_safehouse and index == 0:
		return &"safehouse"
	if park_index >= 0 and index == park_index:
		return &"park"
	if index == int(dimension * dimension / 2):
		return &"civic"
	if col == dimension - 1:
		return &"industrial"
	if row == 1 or col == 1:
		return &"commercial"
	return &"residential"

func _rare_prague_feature(seed_value: int, feature_id: StringName, chance_percent: int) -> bool:
	var mixed := int((seed_value ^ String(feature_id).hash() ^ 0x6D2B79F5) & 0x7FFFFFFF)
	return posmod(mixed, 100) < chance_percent

func _make_prague_parcels(blocks: Array[Dictionary]) -> Array[Dictionary]:
	var parcels: Array[Dictionary] = []
	for block in blocks:
		if block["zone"] in [&"safehouse", &"park"]:
			continue
		var buildable: Rect2 = (block["rect"] as Rect2).grow(-SIDEWALK_DEPTH)
		# Prague street walls are continuous: every full-size quarter receives
		# two attached lots. Only a deliberately reserved courtyard inserts a
		# two-cell passage; ordinary party-wall buildings have no open lot gap.
		var courtyard_reserved := bool(block.get("courtyard_reserved", false))
		var passage_width := 64.0 if courtyard_reserved else 0.0
		var lot_count := 2 if buildable.size.x - passage_width >= 512.0 else 1
		if lot_count == 1:
			courtyard_reserved = false
			passage_width = 0.0
		var total_modules := maxi(floori((buildable.size.x - passage_width) / 64.0), 4)
		var base_modules := floori(float(total_modules) / float(lot_count))
		var extra_modules := total_modules % lot_count
		var lot_widths: Array[float] = []
		for lot_index in range(lot_count):
			lot_widths.append(float((base_modules + (1 if lot_index < extra_modules else 0)) * 64))
		var used_width := passage_width
		for width in lot_widths:
			used_width += width
		var frontage_x := buildable.position.x + (buildable.size.x - used_width) * 0.5
		var lot_x := frontage_x
		for lot_index in range(lot_count):
			var lot_width: float = lot_widths[lot_index]
			var lot_rect := Rect2(Vector2(lot_x, buildable.position.y), Vector2(lot_width, buildable.size.y))
			parcels.append({
				"id": StringName("%s/frontage_%02d" % [String(block["id"]), lot_index]),
				"block_id": block["id"], "zone": block["zone"], "rect": lot_rect,
				"frontage": &"south", "frontage_road_id": block["frontage_road_id"],
				"lot_index": lot_index, "attached_frontage": true,
				"courtyard_reserved": courtyard_reserved,
				"building_id": &"", "entrance_position": Vector2.ZERO,
				"approach_position": Vector2.ZERO, "access_corridor": Rect2(),
			})
			lot_x += lot_width + passage_width
	return parcels

func _apply_prague_building_style(buildings: Array[Dictionary], morphology: Dictionary) -> void:
	var palette: Array = morphology["roof_palette"]
	var profile: StringName = morphology["profile"]
	var storey_range: Vector2i = morphology.get("storey_range", Vector2i(3, 5))
	var apocalypse_level := int(morphology.get("apocalypse_level", 1))
	for building in buildings:
		var index := posmod(String(building["id"]).hash(), palette.size())
		building["interior"]["roof_material"] = palette[index]
		building["district_profile"] = profile
		building["street_wall"] = true
		building["roof_shape"] = &"pitched_ridge"
		var archetype: StringName = building["archetype"]
		# Profile massing bands keep dense Prague cores at a genuinely urban
		# 4-6 storey read while hillside/industrial quarters stay lower and
		# more varied. Workshops never grow past four floors anywhere.
		var storey_lo := storey_range.x
		var storey_hi := storey_range.y
		if archetype == &"workshop":
			storey_hi = mini(storey_hi, 4)
			storey_lo = mini(storey_lo, storey_hi)
		building["storeys"] = storey_lo + posmod(String(building["id"]).hash() >> 3, storey_hi - storey_lo + 1)
		building["apocalypse_level"] = apocalypse_level
		var facade_style: StringName = &"painted_plaster"
		var wall_texture := "res://assets/pixel/props/wall_plaster.png"
		if profile == &"industrial_transition" or archetype == &"workshop":
			facade_style = &"masonry_industrial"
			wall_texture = "res://assets/pixel/props/wall_brick.png"
		elif archetype in [&"store", &"restaurant"]:
			facade_style = &"active_shopfront"
			wall_texture = "res://assets/pixel/props/wall_shopfront.png"
		elif profile == &"inner_city" and index % 3 == 0:
			facade_style = &"exposed_brick_infill"
			wall_texture = "res://assets/pixel/props/wall_brick.png"
		elif profile == &"historic_core" and index % 4 == 0:
			facade_style = &"exposed_brick_infill"
			wall_texture = "res://assets/pixel/props/wall_brick.png"
		building["facade_style"] = facade_style
		building["interior"]["wall_texture"] = wall_texture
		building["exterior"] = BuildingExteriorRenderer.make_prague_spec(building)

func _filter_prague_frontage_props(props: Array[Dictionary], buildings: Array[Dictionary]) -> Array[Dictionary]:
	var accepted: Array[Dictionary] = []
	for prop in props:
		var prop_rect := Rect2((prop["position"] as Vector2) - (prop["size"] as Vector2) * 0.5, prop["size"])
		var blocked := false
		for building in buildings:
			if _intersects_enterable_footprint(prop_rect, building) or prop_rect.intersects(building["access_corridor"]):
				blocked = true
				break
		if not blocked:
			accepted.append(prop)
	return accepted

## Dressing props yield to semantic anchors: any prop whose clearance footprint
## swallows a scavenge point or landmark position is dropped deterministically.
## The anchors are gameplay-critical navigation/loot targets; debris is not.
func _filter_prague_anchor_conflicts(props: Array[Dictionary], scavenge_points: Array[Dictionary], landmarks: Array[Dictionary]) -> Array[Dictionary]:
	var anchor_positions: Array[Vector2] = []
	for point in scavenge_points:
		anchor_positions.append(point["position"])
	for landmark in landmarks:
		if landmark.get("position", Vector2.ZERO) != Vector2.ZERO:
			anchor_positions.append(landmark["position"])
	var accepted: Array[Dictionary] = []
	for prop in props:
		var prop_rect := Rect2((prop["position"] as Vector2) - (prop["size"] as Vector2) * 0.5, prop["size"]).grow(16.0)
		var blocked := false
		for position in anchor_positions:
			if prop_rect.has_point(position):
				blocked = true
				break
		if not blocked:
			accepted.append(prop)
	return accepted

func _make_prague_courtyards(seed_value: int, blocks: Array[Dictionary], buildings: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var buildings_by_block: Dictionary = {}
	for building in buildings:
		if not buildings_by_block.has(building["block_id"]):
			buildings_by_block[building["block_id"]] = []
		buildings_by_block[building["block_id"]].append(building)
	for block in blocks:
		if not bool(block.get("courtyard_reserved", false)):
			continue
		var local_buildings: Array = buildings_by_block.get(block["id"], [])
		if local_buildings.size() < 2:
			continue
		local_buildings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["footprint"] as Rect2).position.x < (b["footprint"] as Rect2).position.x)
		var left: Dictionary = local_buildings[0]
		var right: Dictionary = local_buildings[1]
		var left_footprint: Rect2 = left["footprint"]
		var right_footprint: Rect2 = right["footprint"]
		var passage_left := left_footprint.end.x
		var passage_right := right_footprint.position.x
		if passage_right - passage_left < 64.0:
			continue
		var block_inner := (block["rect"] as Rect2).grow(-SIDEWALK_DEPTH - 32.0)
		var building_top := minf(left_footprint.position.y, right_footprint.position.y)
		var court_bottom := building_top - 32.0
		var court_rect := Rect2(block_inner.position, Vector2(block_inner.size.x, court_bottom - block_inner.position.y))
		if court_rect.size.x < 160.0 or court_rect.size.y < 128.0:
			continue
		var passage_center := (passage_left + passage_right) * 0.5
		var access_y := court_rect.end.y - 32.0
		var access := Rect2(passage_center - 32.0, access_y, 64.0, (block["rect"] as Rect2).end.y - access_y)
		result.append({
			"id": StringName("city_%d/%s/courtyard" % [seed_value, String(block["id"])]),
			"block_id": block["id"], "zone": block["zone"], "rect": court_rect,
			"access_corridor": access, "passage_width": 64.0,
			"environment_tags": [block["zone"], &"courtyard", &"passage"],
		})
	return result

func _generate_attempt(seed_value: int, attempt: int, attempt_seed: int) -> Dictionary:
	var x_axes := _street_axes()
	var y_axes := _street_axes()
	var roads := _make_roads(x_axes, y_axes)
	var intersections := _make_intersections(x_axes, y_axes)
	var park_candidates: Array[int] = [2, 8, 11, 14]
	var park_index: int = int(park_candidates[_rng.randi_range(0, park_candidates.size() - 1)])
	var blocks := _make_blocks(x_axes, y_axes, park_index)
	var parcels := _make_parcels(blocks)
	var buildings := _make_buildings(seed_value, parcels, blocks)
	var exterior_zones := _make_exterior_zones(seed_value, blocks, parcels, buildings)
	# The compact regression district keeps legacy fixed axes; give its
	# dressing pass a matching default morphology.
	var props := _make_exterior_props(seed_value, blocks, buildings, exterior_zones, {
		"profile": &"inner_city",
		"tram_axis": &"horizontal",
		"apocalypse_level": 1,
	})
	# Profile/apocalypse dressing scatters deterministic debris anywhere in a
	# quarter; the same frontage-clearance filter the streamed Prague path
	# applies keeps those props off building shells and access corridors so
	# the compact district still validates without weakening its invariants.
	props = _filter_prague_frontage_props(props, buildings)
	var spawn_regions := _make_spawn_regions(seed_value, blocks, roads, exterior_zones, buildings, props)
	var scavenging := _make_scavenge_points(seed_value, blocks, exterior_zones, props)
	var landmarks := _make_landmarks(seed_value, blocks, buildings, exterior_zones, props, scavenging)
	props = _filter_prague_anchor_conflicts(props, scavenging, landmarks)
	var safe_block: Dictionary = blocks[0]
	var safehouse_position: Vector2 = safe_block["rect"].get_center()
	var safehouse_entrance := safehouse_position + Vector2(0, 208)
	return {
		"seed": seed_value,
		"attempt_seed": attempt_seed,
		"generation_attempt": attempt,
		"generation_error": "",
		"half_extent": ARENA_HALF_EXTENT,
		"roads": roads,
		"intersections": intersections,
		"blocks": blocks,
		"parcels": parcels,
		"buildings": buildings,
		"exterior_zones": exterior_zones,
		"props": props,
		"spawn_regions": spawn_regions,
		"scavenge_points": scavenging,
		"landmarks": landmarks,
		"safehouse_position": safehouse_position,
		"safehouse_entrance": safehouse_entrance,
		"safehouse_access": _corridor_rect(safehouse_entrance, Vector2(safehouse_entrance.x, safe_block["rect"].end.y - 16.0), 48.0),
		"player_spawn": safehouse_position + Vector2(0, 130),
	}

func _attempt_seed(seed_value: int, attempt: int) -> int:
	if attempt == 0:
		return seed_value & 0x7FFFFFFF
	return int((seed_value ^ (attempt * 0x9E3779B9) ^ 0x51A7C05) & 0x7FFFFFFF)

func _append_edge_contract_roads(roads: Array[Dictionary], contracts: Dictionary, road_by_id: Dictionary = {}) -> void:
	var half := ARENA_HALF_EXTENT
	var serial := 0
	for side_name in [&"north", &"east", &"south", &"west"]:
		var parent_rect := _edge_parent_ring_rect(side_name, road_by_id)
		for portal_variant in contracts[side_name]:
			var portal: Dictionary = portal_variant
			var lane := -half.y + float(portal["lane_tile"] * TILE_SIZE) + TILE_SIZE * 0.5
			var width: float = portal["width"]
			var rect: Rect2
			var orientation: StringName
			if side_name == &"east" or side_name == &"west":
				orientation = &"horizontal"
				var x0: float
				var x1: float
				if side_name == &"east":
					x1 = half.x
					x0 = x1 - _edge_connector_reach(parent_rect, half.x)
				else:
					x0 = -half.x
					x1 = x0 + _edge_connector_reach(parent_rect, half.x)
				rect = Rect2(x0, lane - width * 0.5, x1 - x0, width)
			else:
				orientation = &"vertical"
				var x_lane := -half.x + float(portal["lane_tile"] * TILE_SIZE) + TILE_SIZE * 0.5
				var y0: float
				var y1: float
				if side_name == &"south":
					y1 = half.y
					y0 = y1 - _edge_connector_reach(parent_rect, half.y)
				else:
					y0 = -half.y
					y1 = y0 + _edge_connector_reach(parent_rect, half.y)
				rect = Rect2(x_lane - width * 0.5, y0, width, y1 - y0)
			roads.append({
				"id": StringName("road_contract_%s_%02d" % [String(side_name), serial]),
				"orientation": orientation,
				"kind": portal["kind"],
				"surface": portal.get("surface", &"asphalt"),
				"tram": bool(portal.get("tram", false)),
				"portal_id": portal.get("portal_id", &""),
				"rect": rect,
				"edge_contract": side_name,
			})
			serial += 1

## The bordering ring road a given chunk edge must connect back to.
func _edge_parent_ring_rect(side_name: StringName, road_by_id: Dictionary) -> Rect2:
	var want_horizontal := side_name in [&"north", &"south"]
	var pick_minimum := side_name in [&"north", &"west"]
	var best_rect := Rect2()
	var best_center := INF if pick_minimum else -INF
	for id in road_by_id:
		var road: Dictionary = road_by_id[id]
		if road.get("kind", &"") != &"ring":
			continue
		var horizontal: bool = road["orientation"] == &"horizontal"
		if horizontal != want_horizontal:
			continue
		var rect: Rect2 = road["rect"]
		var center := rect.get_center().y if horizontal else rect.get_center().x
		if (pick_minimum and center < best_center) or (not pick_minimum and center > best_center):
			best_center = center
			best_rect = rect
	return best_rect

## How far inward from a chunk edge a contract portal must run so its inner
## end overlaps the parent ring carriageway by CONNECTOR_ROAD_OVERLAP past the
## carriageway centerline. Derived from the actual ring Rect2; falls back to
## the historical one-band reach only when no ring road exists to measure.
func _edge_connector_reach(parent_rect: Rect2, edge: float) -> float:
	if parent_rect.size == Vector2.ZERO:
		return 128.0
	var parent_center := parent_rect.get_center().x if parent_rect.size.x < parent_rect.size.y else parent_rect.get_center().y
	return maxf(absf(edge - parent_center) + CONNECTOR_ROAD_OVERLAP, TILE_SIZE + CONNECTOR_ROAD_OVERLAP)

func _append_park_branch(roads: Array[Dictionary], blocks: Array[Dictionary], seed_value: int, road_by_id: Dictionary = {}) -> void:
	var park: Dictionary = {}
	for block in blocks:
		if block["zone"] == &"park":
			park = block
			break
	if park.is_empty():
		return
	var rect: Rect2 = park["rect"]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x2F6E2B1
	var width := 64.0
	var branch_rect: Rect2
	var cross_rect: Rect2
	var orientation: StringName
	if rng.randi_range(0, 1) == 0:
		orientation = &"vertical"
		var x := rect.position.x + 96.0 + float(rng.randi_range(0, maxi(int((rect.size.x - 192.0) / TILE_SIZE), 0)) * TILE_SIZE)
		# The branch runs north across the sidewalk band into its semantic
		# parent street (the collector bordering this quarter's row); its end
		# is snapped onto that road's centerline so graph adjacency never
		# depends on guessing how wide the band between block and carriageway
		# is for the active profile.
		var parent_y := _parent_axis_center(road_by_id, StringName("road_h_%d" % int(park["row"])), rect.position.y - 128.0)
		branch_rect = Rect2(x - width * 0.5, parent_y, width, rect.position.y + rect.size.y * 0.58 - parent_y)
		var cross_y := branch_rect.end.y - width
		cross_rect = Rect2(rect.position.x + 64.0, cross_y, rect.size.x - 128.0, width)
	else:
		orientation = &"horizontal"
		var y := rect.position.y + 96.0 + float(rng.randi_range(0, maxi(int((rect.size.y - 192.0) / TILE_SIZE), 0)) * TILE_SIZE)
		var parent_x := _parent_axis_center(road_by_id, StringName("road_v_%d" % int(park["col"])), rect.position.x - 128.0)
		branch_rect = Rect2(parent_x, y - width * 0.5, rect.position.x + rect.size.x * 0.58 - parent_x, width)
		var cross_x := branch_rect.end.x - width
		cross_rect = Rect2(cross_x, rect.position.y + 64.0, width, rect.size.y - 128.0)
	roads.append({
		"id": &"road_park_branch",
		"orientation": orientation,
		"kind": &"local",
		"surface": &"cobble",
		"tram": false,
		"rect": branch_rect,
		"topology": &"square_access_branch",
	})
	roads.append({
		"id": &"road_square_crosslane",
		"orientation": &"horizontal" if orientation == &"vertical" else &"vertical",
		"kind": &"pedestrian_passage",
		"surface": &"cobble",
		"tram": false,
		"rect": cross_rect,
		"topology": &"dogleg_square_lane",
	})

## Centerline of a semantic parent road on its running axis, or the supplied
## deterministic fallback when that axis record is unavailable.
func _parent_axis_center(road_by_id: Dictionary, road_id: StringName, fallback: float) -> float:
	var road: Dictionary = road_by_id.get(road_id, {})
	if road.is_empty():
		return fallback
	var rect: Rect2 = road["rect"]
	if road["orientation"] == &"horizontal":
		return rect.get_center().y
	return rect.get_center().x

## Every generated building gets a narrow, unmarked access drive from its
## entrance to the collector it fronts.  These are actual road rectangles in
## the semantic graph (not painted decoration), so streamed districts read as
## a hierarchy of arterial grid, local branch, and building approach rather
## than a field of isolated boxes on a grid.
func _append_building_access_branches(roads: Array[Dictionary], buildings: Array[Dictionary], road_by_id: Dictionary = {}) -> void:
	for building in buildings:
		var corridor: Rect2 = building["access_corridor"]
		if corridor.size.y < TILE_SIZE * 2.0:
			continue
		var width := maxf(corridor.size.x, TILE_SIZE * 2.0)
		# The drive ends on its declared frontage collector's centerline, so
		# the semantic branch always physically intersects the exact road it
		# claims to join — whatever width that profile gives it — instead of
		# relying on a fixed extension length to luck across the band.
		var end_y := _parent_axis_center(road_by_id, building.get("frontage_road_id", &""), corridor.end.y + TILE_SIZE * 4.0)
		var height := maxf(end_y - corridor.position.y, corridor.size.y + TILE_SIZE)
		var rect := Rect2(corridor.get_center().x - width * 0.5, corridor.position.y, width, height)
		roads.append({
			"id": StringName("road_branch_%s" % String(building["id"]).replace("/", "_")),
			"orientation": &"vertical",
			"kind": &"driveway",
			"surface": &"stone_setts",
			"tram": false,
			"rect": rect,
		})

func _street_axes() -> Array[Dictionary]:
	var inner_negative := -640.0 + float(_rng.randi_range(-2, 2) * TILE_SIZE)
	var inner_positive := 640.0 + float(_rng.randi_range(-2, 2) * TILE_SIZE)
	return [
		{"center": -RING_CENTER, "width": 128.0, "kind": &"ring"},
		{"center": inner_negative, "width": 128.0, "kind": &"secondary"},
		{"center": 0.0, "width": 192.0, "kind": &"arterial"},
		{"center": inner_positive, "width": 128.0, "kind": &"secondary"},
		{"center": RING_CENTER, "width": 128.0, "kind": &"ring"},
	]

func _make_roads(x_axes: Array[Dictionary], y_axes: Array[Dictionary]) -> Array[Dictionary]:
	var roads: Array[Dictionary] = []
	for i in range(y_axes.size()):
		var axis: Dictionary = y_axes[i]
		roads.append({
			"id": StringName("road_h_%d" % i), "orientation": &"horizontal", "kind": axis["kind"],
			"rect": Rect2(-ARENA_HALF_EXTENT.x, axis["center"] - axis["width"] * 0.5, ARENA_HALF_EXTENT.x * 2.0, axis["width"]),
		})
	for i in range(x_axes.size()):
		var axis: Dictionary = x_axes[i]
		roads.append({
			"id": StringName("road_v_%d" % i), "orientation": &"vertical", "kind": axis["kind"],
			"rect": Rect2(axis["center"] - axis["width"] * 0.5, -ARENA_HALF_EXTENT.y, axis["width"], ARENA_HALF_EXTENT.y * 2.0),
		})
	return roads

func _make_intersections(x_axes: Array[Dictionary], y_axes: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in range(y_axes.size()):
		for col in range(x_axes.size()):
			result.append({
				"id": StringName("intersection_%d_%d" % [row, col]),
				"position": Vector2(x_axes[col]["center"], y_axes[row]["center"]),
				"road_ids": [StringName("road_h_%d" % row), StringName("road_v_%d" % col)],
				"kind": &"signalized" if row == 2 or col == 2 else &"local",
			})
	return result

func _make_blocks(x_axes: Array[Dictionary], y_axes: Array[Dictionary], park_index: int) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	for row in range(4):
		for col in range(4):
			var left := float(x_axes[col]["center"]) + float(x_axes[col]["width"]) * 0.5
			var right := float(x_axes[col + 1]["center"]) - float(x_axes[col + 1]["width"]) * 0.5
			var top := float(y_axes[row]["center"]) + float(y_axes[row]["width"]) * 0.5
			var bottom := float(y_axes[row + 1]["center"]) - float(y_axes[row + 1]["width"]) * 0.5
			var index := row * 4 + col
			var zone := _zone_for(index, row, col, park_index)
			var surface: StringName = &"grass" if zone == &"park" else (&"dirt" if zone == &"industrial" else &"concrete")
			blocks.append({
				"id": StringName("block_%02d" % index), "index": index, "row": row, "col": col,
				"rect": Rect2(left, top, right - left, bottom - top), "zone": zone, "surface": surface,
				"frontage_road_id": StringName("road_h_%d" % (row + 1)),
			})
	return blocks

func _zone_for(index: int, row: int, col: int, park_index: int) -> StringName:
	if index == 0:
		return &"safehouse"
	if index == park_index:
		return &"park"
	if index == 4:
		return &"civic"
	if row in [1, 2] and col in [1, 2]:
		return &"commercial"
	if col == 3:
		return &"industrial"
	return &"residential"

func _make_parcels(blocks: Array[Dictionary]) -> Array[Dictionary]:
	var parcels: Array[Dictionary] = []
	for block in blocks:
		if block["zone"] in [&"safehouse", &"park"]:
			continue
		var rect: Rect2 = (block["rect"] as Rect2).grow(-SIDEWALK_DEPTH)
		parcels.append({
			"id": StringName("%s/parcel_0" % String(block["id"])),
			"block_id": block["id"],
			"zone": block["zone"],
			"rect": rect,
			"frontage": &"south",
			"frontage_road_id": block["frontage_road_id"],
			"building_id": &"",
			"entrance_position": Vector2.ZERO,
			"approach_position": Vector2.ZERO,
			"access_corridor": Rect2(),
		})
	return parcels

func _make_buildings(seed_value: int, parcels: Array[Dictionary], blocks: Array[Dictionary], apocalypse_level: int = 1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var block_by_id := _index_by_id(blocks)
	for parcel_index in range(parcels.size()):
		var parcel: Dictionary = parcels[parcel_index]
		var block: Dictionary = block_by_id[parcel["block_id"]]
		var archetype: StringName = _archetype_for_zone(block["zone"])
		var size: Vector2 = _building_size(archetype, parcel["rect"])
		var parcel_rect: Rect2 = parcel["rect"]
		var lot_index := int(parcel.get("lot_index", 0))
		var attached_frontage := bool(parcel.get("attached_frontage", false))
		if attached_frontage:
			size.x = maxf(floorf(parcel_rect.size.x / 64.0) * 64.0, BUILDING_ARCHETYPES[archetype]["minimum_size"].x)
			var rear_reserve := PRAGUE_COURTYARD_REAR_RESERVE if bool(parcel.get("courtyard_reserved", false)) else 0.0
			var dense_depth := floorf((parcel_rect.size.y - rear_reserve) / 64.0) * 64.0
			size.y = maxf(dense_depth, BUILDING_ARCHETYPES[archetype]["minimum_size"].y)
		var stable_id: StringName = StringName("city_%d/%s/%s_%d" % [seed_value, String(block["id"]), String(archetype), lot_index])
		var layout_seed: int
		if attached_frontage:
			layout_seed = int((seed_value ^ (int(block["index"]) + 1) * 0x45D9F3B ^ (lot_index + 1) * 0x119DE1F3 ^ String(archetype).hash()) & 0x7FFFFFFF)
		else:
			layout_seed = int((seed_value ^ (int(block["index"]) + 1) * 0x45D9F3B ^ String(archetype).hash()) & 0x7FFFFFFF)
		var building_generator := ProceduralBuildingGenerator.new()
		var interior: Dictionary = building_generator.generate(stable_id, archetype, size, layout_seed, true, apocalypse_level)
		var local_bounds: Rect2 = interior["footprint_bounds"]
		var footprint_y := parcel_rect.end.y - local_bounds.size.y if attached_frontage else parcel_rect.position.y
		var footprint := Rect2(parcel_rect.get_center().x - local_bounds.size.x * 0.5, footprint_y, local_bounds.size.x, local_bounds.size.y)
		# A compound form is only retained when its entire, enterable footprint
		# fits the parcel. Falling back to the same seed's rectangular plan keeps
		# invalid wings from becoming a generation retry or a blocked entrance.
		if not parcel_rect.encloses(footprint):
			interior = building_generator.generate(stable_id, archetype, size, layout_seed, false, apocalypse_level)
			local_bounds = interior["footprint_bounds"]
			footprint_y = parcel_rect.end.y - local_bounds.size.y if attached_frontage else parcel_rect.position.y
			footprint = Rect2(parcel_rect.get_center().x - local_bounds.size.x * 0.5, footprint_y, local_bounds.size.x, local_bounds.size.y)
		var position: Vector2 = footprint.position - local_bounds.position
		var entrance_local: Vector2 = Vector2.ZERO
		for door in interior["doors"]:
			if bool(door["exterior"]) and not bool(door.get("service", false)):
				entrance_local = door["position"]
				break
		var entrance_world := position + entrance_local
		var approach := Vector2(entrance_world.x, (block["rect"] as Rect2).end.y - TILE_SIZE * 0.5)
		var building := {
			"id": stable_id,
			"block_id": block["id"],
			"parcel_id": parcel["id"],
			"zone": block["zone"],
			"archetype": archetype,
			"frontage_road_id": parcel["frontage_road_id"],
			"position": position,
			"rotation": 0.0,
			"size": footprint.size,
			"form": interior["form"],
			"footprint": footprint,
			"entrance_position": entrance_world,
			"approach_position": approach,
			"access_corridor": _corridor_rect(entrance_world, approach, 48.0),
			"courtyard_reserved": bool(parcel.get("courtyard_reserved", false)),
			"interior": interior,
		}
		building["exterior"] = BuildingExteriorRenderer.make_prague_spec(building)
		result.append(building)
		parcel["building_id"] = stable_id
		parcel["entrance_position"] = entrance_world
		parcel["approach_position"] = approach
		parcel["access_corridor"] = building["access_corridor"]
		parcels[parcel_index] = parcel
	return result

func _building_size(archetype: StringName, parcel_rect: Rect2) -> Vector2:
	var minimum: Vector2 = BUILDING_ARCHETYPES[archetype]["minimum_size"]
	var maximum_width := floorf(parcel_rect.size.x / 64.0) * 64.0
	var maximum_height := floorf((parcel_rect.size.y - 64.0) / 64.0) * 64.0
	var width := minimum.x
	var height := minimum.y
	if maximum_width >= minimum.x + 64.0 and _rng.randf() < 0.65:
		width = minimum.x + 64.0
	if maximum_height >= minimum.y + 64.0 and _rng.randf() < 0.5:
		height = minimum.y + 64.0
	width = minf(width, maximum_width)
	height = minf(height, maximum_height)
	return Vector2(maxf(width, minimum.x), maxf(height, minimum.y))

func _archetype_for_zone(zone: StringName) -> StringName:
	match zone:
		&"residential": return &"apartment"
		&"commercial": return [&"store", &"restaurant"][_rng.randi_range(0, 1)]
		&"industrial": return &"workshop"
		&"civic": return &"clinic"
	return &"store"

func _make_exterior_zones(seed_value: int, blocks: Array[Dictionary], parcels: Array[Dictionary], buildings: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var building_by_parcel: Dictionary = {}
	for building in buildings:
		building_by_parcel[building["parcel_id"]] = building
	for block in blocks:
		if block["zone"] == &"park":
			result.append({
				"id": StringName("city_%d/%s/public_park" % [seed_value, String(block["id"])]),
				"block_id": block["id"], "kind": &"park", "zone": block["zone"],
				"rect": (block["rect"] as Rect2).grow(-SIDEWALK_DEPTH),
			})
		elif block["zone"] == &"safehouse":
			result.append({
				"id": StringName("city_%d/%s/safehouse_yard" % [seed_value, String(block["id"])]),
				"block_id": block["id"], "kind": &"safehouse_yard", "zone": block["zone"],
				"rect": (block["rect"] as Rect2).grow(-SIDEWALK_DEPTH),
			})
	for parcel in parcels:
		var building: Dictionary = building_by_parcel.get(parcel["id"], {})
		if building.is_empty():
			continue
		var parcel_rect: Rect2 = parcel["rect"]
		var footprint: Rect2 = building["footprint"]
		var gap := Rect2(parcel_rect.position.x, footprint.end.y, parcel_rect.size.x, parcel_rect.end.y - footprint.end.y)
		if gap.size.y < 32.0:
			continue
		var corridor: Rect2 = building["access_corridor"]
		var left_width := maxf(corridor.position.x - parcel_rect.position.x, 0.0)
		var right_x := corridor.end.x
		var right_width := maxf(parcel_rect.end.x - right_x, 0.0)
		var parking_on_left := left_width >= right_width
		var parking_width := left_width if parking_on_left else right_width
		var parking_x := parcel_rect.position.x if parking_on_left else right_x
		if parcel["zone"] in [&"commercial", &"civic", &"industrial"] and parking_width >= 64.0:
			result.append({
				"id": StringName("city_%d/%s/parking" % [seed_value, String(parcel["block_id"])]),
				"block_id": parcel["block_id"], "parcel_id": parcel["id"], "kind": &"parking", "zone": parcel["zone"],
				"rect": Rect2(parking_x, gap.position.y, parking_width, gap.size.y),
			})
		var alley_width := right_width if parking_on_left else left_width
		var alley_x := right_x if parking_on_left else parcel_rect.position.x
		if alley_width >= 32.0:
			result.append({
				"id": StringName("city_%d/%s/alley" % [seed_value, String(parcel["block_id"])]),
				"block_id": parcel["block_id"], "parcel_id": parcel["id"], "kind": &"alley", "zone": parcel["zone"],
				"rect": Rect2(alley_x, gap.position.y, alley_width, gap.size.y),
			})
	return result

func _make_exterior_props(seed_value: int, blocks: Array[Dictionary], buildings: Array[Dictionary], exterior_zones: Array[Dictionary], morphology: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var serial_by_block: Dictionary = {}
	var zones_by_block: Dictionary = {}
	for zone in exterior_zones:
		if not zones_by_block.has(zone["block_id"]):
			zones_by_block[zone["block_id"]] = []
		zones_by_block[zone["block_id"]].append(zone)
	var building_by_block: Dictionary = {}
	for building in buildings:
		building_by_block[building["block_id"]] = building
	var apocalypse := int(morphology.get("apocalypse_level", 1))
	_zone_clear_rects.clear()
	for zone_entry in exterior_zones:
		_zone_clear_rects.append((zone_entry["rect"] as Rect2).grow(GENERATED_SPAWN_CLEARANCE))
	for block in blocks:
		var block_id: StringName = block["id"]
		serial_by_block[block_id] = 0
		var rect: Rect2 = block["rect"]
		var local_zones: Array = zones_by_block.get(block_id, [])
		for exterior in local_zones:
			var zone_rect: Rect2 = exterior["rect"]
			match exterior["kind"]:
				&"park":
					# A pocket park reads as planted, not decorated: a small
					# deterministic grove plus seats facing the green.
					var grove_seed := _hash_scatter(seed_value, block, 11)
					for tree_index in range(3 + grove_seed % 3):
						var angle := TAU * float(tree_index) / 5.0 + float(grove_seed % 10) * 0.1
						var grove_position: Vector2 = zone_rect.get_center() + Vector2(cos(angle), sin(angle)) * 72.0
						_append_tree(result, serial_by_block, seed_value, block, grove_position)
					_append_prop(result, serial_by_block, seed_value, block, &"bench", &"public", zone_rect.get_center() + Vector2(64, 32))
					_append_prop(result, serial_by_block, seed_value, block, &"bench", &"public", zone_rect.get_center() + Vector2(-88, 40))
				&"courtyard":
					_append_tree(result, serial_by_block, seed_value, block, zone_rect.get_center() + Vector2(-80, -40))
					_append_prop(result, serial_by_block, seed_value, block, &"bench", &"public", zone_rect.get_center() + Vector2(72, 40))
				&"parking":
					var wreck_chance := 0.55 if block["zone"] == &"industrial" else (0.3 if apocalypse >= 1 else 0.0)
					var car_kind: StringName = &"wreck" if _rng.randf() < wreck_chance else &"car"
					_append_prop(result, serial_by_block, seed_value, block, car_kind, &"parking", zone_rect.get_center())
					if block["zone"] == &"civic":
						_append_prop(result, serial_by_block, seed_value, block, &"medical_cache", &"medical", zone_rect.get_center() + Vector2(0, 16))
				&"alley":
					var alley_kind: StringName = &"dumpster" if block["zone"] in [&"commercial", &"civic"] else (&"crate" if block["zone"] == &"industrial" else &"trash")
					_append_prop(result, serial_by_block, seed_value, block, alley_kind, &"alley", zone_rect.get_center())
					if apocalypse >= 1 or block["zone"] in [&"commercial", &"industrial"]:
						var bag_x: float = clampf(zone_rect.get_center().x + zone_rect.size.x * 0.5 + 16.0, rect.position.x + 20.0, rect.end.x - 20.0)
						_append_prop(result, serial_by_block, seed_value, block, &"trash", &"alley", Vector2(bag_x, zone_rect.get_center().y + 8.0))
		if block["zone"] == &"residential" and building_by_block.has(block_id):
			var building: Dictionary = building_by_block[block_id]
			var position: Vector2 = building["approach_position"] + Vector2(72.0 if _rng.randi_range(0, 1) == 0 else -72.0, -24.0)
			_append_tree(result, serial_by_block, seed_value, block, position)
		elif block["zone"] == &"industrial":
			_append_prop(result, serial_by_block, seed_value, block, &"cone", &"service", Vector2(rect.end.x - 48.0, rect.end.y - 48.0))
		_make_street_composition(result, serial_by_block, seed_value, block, building_by_block.get(block_id, {}), rect, morphology, local_zones)
	# Post-pass: guarantee every exterior-zone spawn region retains at least
	# one full-footprint-clear cell by removing composition props that crowd
	# it. Zone-internal functional props (dumpsters, cars) are never removed.
	_validate_exterior_zone_spawns(result, exterior_zones, blocks)
	return result

## For each exterior zone that will host a spawn region, verifies a clear
## cell still exists after ALL dressing passes. If not, removes the nearest
## non-functional composition props until one does.
func _validate_exterior_zone_spawns(props: Array[Dictionary], exterior_zones: Array[Dictionary], _blocks: Array[Dictionary]) -> void:
	for zone_variant in exterior_zones:
		var zone: Dictionary = zone_variant
		if zone["kind"] not in [&"parking", &"alley"]:
			continue
		var zone_rect: Rect2 = zone["rect"]
		var inset := zone_rect.grow(-ProceduralCityGenerator.GENERATED_SPAWN_CLEARANCE + 0.001)
		if inset.size.x <= 0.0 or inset.size.y <= 0.0:
			continue
		# Check if any cell in the inset is clear of all prop footprints.
		var has_clear := false
		for prop_variant in props:
			var p: Dictionary = prop_variant
			if p["zone"] != zone["zone"] or String(p["id"]).get_base_dir() != String(zone["id"]).get_base_dir():
				continue
			var pr := Rect2(p["position"] - p["size"] * 0.5, p["size"])
			if not inset.intersects(pr.grow(ProceduralCityGenerator.GENERATED_SPAWN_CLEARANCE)):
				has_clear = true
				break
		if has_clear:
			continue
		# Too crowded: remove composition props overlapping the zone.
		var removed := 0
		var cleaned: Array[Dictionary] = []
		for i in range(props.size()):
			var p: Dictionary = props[i]
			var pr2 := Rect2(p["position"] - p["size"] * 0.5, p["size"])
			var in_zone := zone_rect.grow(4.0).intersects(pr2)
			var is_functional: bool = p.get("interaction", &"") == &"loot" or p.get("kind", &"") in [&"dumpster", &"car", &"wreck", &"medical_cache"]
			if in_zone and not is_functional and removed < 4:
				removed += 1
				continue
			cleaned.append(p)
		if removed > 0:
			props.clear()
			props.append_array(cleaned)

## Composed street dressing for one urban quarter: lamps following the
## sidewalk rhythm, tree lines on residential/commercial frontages, benches
## and bins grouped by land use, wrecks and rubble only where the regional
## apocalypse level earns them. Everything is deterministic from the seed and
## keeps the pedestrian band, door approaches and road connectivity clear --
## collisions stay on the sidewalk, tall visuals may overlap the roadway.
func _make_street_composition(output: Array[Dictionary], serials: Dictionary, seed_value: int, block: Dictionary, building: Dictionary, rect: Rect2, morphology: Dictionary, local_zones: Array) -> void:
	var profile: StringName = morphology["profile"]
	var apocalypse := int(morphology.get("apocalypse_level", 1))
	var zone: StringName = block["zone"]
	var center_x := rect.get_center().x

	# Exterior-zone footprints (grown by spawn clearance) are no-prop zones:
	# semantic spawn regions sample full zombie footprints inside them.
	var zone_clear_rects: Array[Rect2] = []
	for zr in local_zones:
		zone_clear_rects.append((zr["rect"] as Rect2).grow(ProceduralCityGenerator.GENERATED_SPAWN_CLEARANCE))

	# --- lamp spacing follows the sidewalk ---
	var lamp_positions: Array[float] = []
	var lamp_x := rect.position.x + 144.0
	while lamp_x <= rect.end.x - 96.0:
		if absf(lamp_x - center_x) >= 56.0:
			lamp_positions.append(lamp_x)
		lamp_x += 288.0
	for lamp_position in lamp_positions:
		_append_lamp(output, serials, seed_value, block, Vector2(lamp_position, rect.end.y - 16.0), apocalypse)

	# --- tree-lined frontages (never on industrial yards) ---
	var tree_density: float = {&"historic_core": 0.45, &"inner_city": 0.7, &"hillside_residential": 0.85, &"industrial_transition": 0.2}.get(profile, 0.5)
	var tree_x := rect.position.x + 96.0
	while tree_x <= rect.end.x - 64.0:
		var near_lamp := false
		for lamp_position in lamp_positions:
			if absf(tree_x - lamp_position) < 48.0:
				near_lamp = true
				break
		var tree_roll := float(_hash_scatter(seed_value, block, 500 + int(tree_x)) % 100)
		if not near_lamp and absf(tree_x - center_x) >= 72.0 and tree_roll < tree_density * 100.0:
			_append_tree(output, serials, seed_value, block, Vector2(tree_x, rect.end.y - 16.0))
		tree_x += 192.0

	# --- benches where people actually sit: fronts and greens ---
	if zone == &"commercial" and float(_hash_scatter(seed_value, block, 61) % 100) < 35.0:
		var side := 1.0 if _hash_scatter(seed_value, block, 62) % 2 == 0 else -1.0
		_append_prop(output, serials, seed_value, block, &"bench", &"frontage", Vector2(center_x + side * 128.0, rect.end.y - 16.0))

	# --- garbage gathers around commerce and service doors ---
	if zone in [&"commercial", &"civic"]:
		var bags := 1 + int(_hash_scatter(seed_value, block, 71) % (2 if apocalypse >= 1 else 1))
		for bag_index in range(bags):
			var side := 1.0 if bag_index % 2 == 0 else -1.0
			_append_prop(output, serials, seed_value, block, &"trash", &"frontage", Vector2(center_x + side * (152.0 + float(bag_index) * 20.0), rect.end.y - 14.0))

	# --- rubble belongs to visibly damaged buildings ---
	if apocalypse >= 1 and not building.is_empty():
		var rubble_count := apocalypse
		for rubble_index in range(rubble_count):
			var side := 1.0 if rubble_index % 2 == 0 else -1.0
			var footprint: Rect2 = building["footprint"]
			var rubble_x: float = clampf(footprint.get_center().x + side * (footprint.size.x * 0.5 + 28.0), rect.position.x + 32.0, rect.end.x - 32.0)
			_append_prop(output, serials, seed_value, block, &"rubble", &"damage", Vector2(rubble_x, footprint.get_center().y + 24.0))
			if apocalypse >= 2:
				_append_prop(output, serials, seed_value, block, &"trash", &"damage", Vector2(rubble_x - side * 24.0, footprint.get_center().y + 40.0))

	# --- low-key per-profile sidewalk character (kept off the south anchor) ---
	var slots := clampi(int(rect.size.x / 320.0), 1, 4)
	for i in range(slots):
		var slot_x := rect.position.x + 120.0 + float(i) * ((rect.size.x - 240.0) / float(maxi(slots, 1)))
		if absf(slot_x - center_x) < 56.0:
			continue
		match profile:
			&"historic_core":
				var historic_kind: StringName = [&"bollard", &"planter"][i % 2]
				_append_prop(output, serials, seed_value, block, historic_kind, &"sidewalk", Vector2(slot_x, rect.end.y - 16.0))
			&"inner_city":
				if i % 2 == 0:
					_append_prop(output, serials, seed_value, block, &"utility_box", &"service", Vector2(slot_x, rect.position.y + 16.0))
			&"hillside_residential":
				if i % 2 == 0:
					_append_prop(output, serials, seed_value, block, &"planter", &"sidewalk", Vector2(slot_x, rect.end.y - 16.0))
			&"industrial_transition":
				var industrial_kind: StringName = [&"pallet", &"crate"][i % 2]
				_append_prop(output, serials, seed_value, block, industrial_kind, &"yard_edge", Vector2(slot_x, rect.position.y + 16.0))

	# --- destructible street cover: crates/barrels/barriers on sidewalks ---
	# Every block gets at least one piece of cover; higher apocalypse adds
	# more, denser as the world rots. Kind and slot come from hash scatter
	# so the same world seed always breeds the same barricade layout.
	var cover_rolls := 1 + apocalypse
	# Guaranteed first piece (deterministic kind/slot per block) so cover is
	# a reliable street feature, not a rare dice roll.
	var guaranteed_kind: StringName = [&"crate", &"barrel", &"barrier"][_hash_scatter(seed_value, block, 650) % 3]
	var guaranteed_span := maxi(int(rect.size.x - 176.0), 1)
	var guaranteed_x := rect.position.x + 88.0 + float(_hash_scatter(seed_value, block, 680) % guaranteed_span)
	_append_cover_prop(output, serials, seed_value, block, guaranteed_kind, Vector2(guaranteed_x, rect.end.y - 16.0))
	for cover_index in range(1, cover_rolls):
		if float(_hash_scatter(seed_value, block, 600 + cover_index) % 100) >= 45.0 + float(apocalypse) * 15.0:
			continue
		var cover_kind: StringName = [&"crate", &"barrel", &"barrier"][_hash_scatter(seed_value, block, 650 + cover_index) % 3]
		var cover_span := maxi(int(rect.size.x - 176.0), 1)
		var cover_x := rect.position.x + 88.0 + float(_hash_scatter(seed_value, block, 680 + cover_index) % cover_span)
		_append_cover_prop(output, serials, seed_value, block, cover_kind, Vector2(cover_x, rect.end.y - 16.0))

	# Tram stop group beside whichever block edge the tram axis runs along.
	var tram_axis: StringName = morphology["tram_axis"]
	if profile in [&"historic_core", &"inner_city"] and _rng.randf() < 0.6:
		var stop_position: Vector2 = rect.get_center()
		if tram_axis == &"horizontal":
			stop_position = Vector2(rect.position.x + 128.0, rect.end.y - 16.0)
		else:
			stop_position = Vector2(rect.end.x - 16.0, rect.position.y + 128.0)
		_append_prop(output, serials, seed_value, block, &"tram_stop", &"transit", stop_position)
		_append_prop(output, serials, seed_value, block, &"bench", &"transit", stop_position + Vector2(52.0, 6.0))
		_append_prop(output, serials, seed_value, block, &"trash", &"transit", stop_position + Vector2(-40.0, 10.0))
	# Apocalypse scatter and barricades: denser chaos only where earned.
	if apocalypse >= 1:
		var scatter_count := apocalypse * 2
		for i in range(scatter_count):
			var scatter_x := rect.position.x + 64.0 + float(int(_hash_scatter(seed_value, block, i)) % maxi(int(rect.size.x - 128.0), 1))
			var scatter_y := rect.position.y + 64.0 + float(int(_hash_scatter(seed_value, block, i + 97)) % maxi(maxi(int(rect.size.y - 160.0), 1), 1))
			var scatter_kind: StringName = &"rubble" if i % 2 == 0 else &"trash"
			_append_prop(output, serials, seed_value, block, scatter_kind, &"debris", Vector2(scatter_x, scatter_y))
		if apocalypse >= 1 and float(_hash_scatter(seed_value, block, 91) % 100) < 50.0:
			var corner: Vector2 = Vector2(rect.position.x + 40.0, rect.end.y - 40.0)
			_append_prop(output, serials, seed_value, block, &"sandbags", &"barricade", corner)
		if apocalypse >= 2 and zone in [&"residential", &"safehouse"]:
			# Survivor-held streets barricade their approaches.
			_append_prop(output, serials, seed_value, block, &"sandbags", &"barricade", Vector2(center_x + 96.0, rect.end.y - 24.0))
			_append_prop(output, serials, seed_value, block, &"sandbags", &"barricade", Vector2(center_x - 104.0, rect.end.y - 24.0))

func _lamp_state(apocalypse: int, hash_value: int) -> StringName:
	var roll := hash_value % 100
	match apocalypse:
		0:
			return &"dead" if roll >= 85 else &"steady"
		1:
			if roll < 45:
				return &"steady"
			return &"flicker" if roll < 65 else &"dead"
		_:
			if roll < 15:
				return &"steady"
			return &"flicker" if roll < 40 else &"dead"

## Keeps any physical street object out of exterior-zone spawn-clearance
## footprints AND the semantic frontage anchor zone.
func _frontage_cleared_position(block: Dictionary, position: Vector2, footprint_half_width: float) -> Vector2:
	var rect: Rect2 = block["rect"]
	var center_x := rect.get_center().x
	var minimum := 56.0 + footprint_half_width
	# South-band frontage anchor protection.
	if position.y >= rect.end.y - 48.0 and absf(position.x - center_x) < minimum:
		var side := 1.0 if position.x >= center_x else -1.0
		position.x = center_x + side * (minimum + 16.0)
	# Exterior-zone clearance.
	for zr in _zone_clear_rects:
		if zr.has_point(position):
			return Vector2(zr.position.x - footprint_half_width - 20.0, position.y)
	return position

func _append_lamp(output: Array[Dictionary], serials: Dictionary, seed_value: int, block: Dictionary, position: Vector2, apocalypse: int) -> void:
	position = _frontage_cleared_position(block, position, 5.0)
	var state_hash := _hash_scatter(seed_value, block, 300 + int(position.x))
	var mode := _lamp_state(apocalypse, state_hash)
	var damaged := mode == &"dead" and apocalypse >= 1 and state_hash % 3 == 0
	output.append({
		"id": _prop_id(serials, seed_value, block),
		"block_id": block["id"], "zone": block["zone"], "kind": &"lamp",
		"placement_role": &"sidewalk", "position": position,
		"texture": PROP_TEXTURES[&"lamp"], "size": Vector2(10, 10),
		"visual_size": Vector2(20, 84), "procedural_kind": &"lamp",
		"variant": state_hash % 4, "damaged": damaged, "light_mode": mode,
		"yield": 1, "minimum_damage_class": EnvironmentDamage.DamageClass.SMALL_ARMS,
		"interaction": &"salvage", "items": {},
	})

func _append_tree(output: Array[Dictionary], serials: Dictionary, seed_value: int, block: Dictionary, position: Vector2) -> void:
	position = _frontage_cleared_position(block, position, 12.0)
	var tree_hash := _hash_scatter(seed_value, block, 400 + int(position.x) * 7 + int(position.y))
	var damaged := tree_hash % 100 < 12
	var spread := 80.0 + float(tree_hash % 4) * 12.0
	output.append({
		"id": _prop_id(serials, seed_value, block),
		"block_id": block["id"], "zone": block["zone"], "kind": &"tree",
		"placement_role": &"street_tree", "position": position,
		"texture": PROP_TEXTURES[&"tree"], "size": Vector2(24, 24),
		"visual_size": Vector2(spread, spread * 1.2), "procedural_kind": &"tree",
		"variant": tree_hash % 3, "damaged": damaged,
		"yield": 1, "minimum_damage_class": EnvironmentDamage.DamageClass.SMALL_ARMS,
		"interaction": &"salvage", "items": {},
	})

## Destructible street-level COVER prop: crates, barrels and road barriers
## that read as real protection, not dressing. Unlike plain props these carry
## explicit combat tuning -- a microcell integrity grid so gunfire chews
## progressive holes, an elevated durability pool, and a shatter debris set
## drawn from the prop's own texture -- while durability/destroyed state
## persists through the same WorldState prop flags wall breaches use.
func _append_cover_prop(output: Array[Dictionary], serials: Dictionary, seed_value: int, block: Dictionary, kind: StringName, position: Vector2) -> void:
	position = _frontage_cleared_position(block, position, _prop_size(kind).x * 0.5)
	var block_id: StringName = block["id"]
	var serial: int = serials.get(block_id, 0)
	serials[block_id] = serial + 1
	var durability := 34.0
	var cells := 2
	match kind:
		&"barrel":
			durability = 46.0
			cells = 3
		&"barrier":
			durability = 58.0
			cells = 2
	output.append({
		"id": StringName("city_%d/%s/exterior_%02d" % [seed_value, String(block_id), serial]),
		"block_id": block_id, "zone": block["zone"], "kind": kind,
		"placement_role": &"cover", "position": position,
		"texture": PROP_TEXTURES[kind], "size": _prop_size(kind),
		"yield": 2, "minimum_damage_class": EnvironmentDamage.DamageClass.SMALL_ARMS,
		"interaction": &"salvage", "items": {},
		"max_durability": durability, "sub_cells": cells,
		"debris_count": 4 if kind == &"barrier" else 3,
		"debris_texture": PROP_TEXTURES[kind],
	})
	_apply_street_object_dimensions(output[len(output) - 1])

func _prop_id(serials: Dictionary, seed_value: int, block: Dictionary) -> StringName:
	var block_id: StringName = block["id"]
	var serial: int = serials.get(block_id, 0)
	serials[block_id] = serial + 1
	return StringName("city_%d/%s/exterior_%02d" % [seed_value, String(block_id), serial])

func _hash_scatter(seed_value: int, block: Dictionary, index: int) -> int:
	return abs(int((seed_value ^ String(block["id"]).hash() ^ (index + 1) * 2654435761) & 0x7FFFFFFF))

func _append_prop(output: Array[Dictionary], serials: Dictionary, seed_value: int, block: Dictionary, kind: StringName, placement_role: StringName, position: Vector2) -> void:
	var block_id: StringName = block["id"]
	position = _frontage_cleared_position(block, position, _prop_size(kind).x * 0.5)
	var serial: int = serials.get(block_id, 0)
	serials[block_id] = serial + 1
	var impact_class := EnvironmentDamage.DamageClass.HEAVY if kind in [&"car", &"wreck"] else EnvironmentDamage.DamageClass.SMALL_ARMS
	var interaction: StringName = &"loot" if kind in [&"dumpster", &"medical_cache", &"car"] else &"salvage"
	var items: Dictionary = {}
	if kind == &"dumpster":
		items = {"materials": 2, "food_ration": 1}
	elif kind == &"medical_cache":
		items = {"medical_supplies": 3}
	elif kind == &"car":
		# Authored intact sedans are searchable trunks with two materials; the
		# civic/depot variant additionally carries one medical supply. The zone
		# makes that variation deterministic without consuming another RNG draw.
		items = {"materials": 2}
		if block["zone"] == &"civic":
			items["medical_supplies"] = 1
	var record := {
		"id": StringName("city_%d/%s/exterior_%02d" % [seed_value, String(block_id), serial]),
		"block_id": block_id, "zone": block["zone"], "kind": kind, "placement_role": placement_role,
		"position": position, "texture": PROP_TEXTURES[kind], "size": _prop_size(kind),
		"yield": 3 if impact_class == EnvironmentDamage.DamageClass.HEAVY else 1,
		"minimum_damage_class": impact_class, "interaction": interaction, "items": items,
	}
	_apply_street_object_dimensions(record)
	output.append(record)

## Per-kind street-object dimensions. `size` is the PHYSICAL collision
## footprint (validators and spawn clearance measure against it); visual_size
## is how much world space the drawn object occupies, which may be far larger
## (tall lamp posts, wide benches) without ever blocking more of the street.
func _apply_street_object_dimensions(record: Dictionary) -> void:
	match record["kind"]:
		&"bench":
			record["visual_size"] = Vector2(60, 24)
		&"bollard":
			record["visual_size"] = Vector2(12, 22)
		&"planter":
			record["visual_size"] = Vector2(28, 20)
		&"tram_stop":
			record["visual_size"] = Vector2(28, 60)
		&"sign_post":
			record["visual_size"] = Vector2(16, 46)
		&"utility_box":
			record["visual_size"] = Vector2(30, 36)
		&"dumpster":
			record["visual_size"] = Vector2(44, 32)
		&"trash":
			record["visual_size"] = Vector2(20, 16)
		&"pallet":
			record["visual_size"] = Vector2(34, 22)
		&"sandbags":
			record["visual_size"] = Vector2(40, 20)
		&"rubble":
			record["visual_size"] = Vector2(32, 16)
		&"car", &"wreck":
			record["visual_size"] = Vector2(62, 34)
		&"crate":
			record["visual_size"] = Vector2(30, 26)
		&"barrel":
			record["visual_size"] = Vector2(24, 30)
		&"barrier":
			record["visual_size"] = Vector2(46, 22)
		_:
			pass

func _prop_size(kind: StringName) -> Vector2:
	match kind:
		&"tree": return Vector2(24, 24)
		&"bench": return Vector2(56, 18)
		&"dumpster": return Vector2(40, 26)
		&"crate": return Vector2(24, 20)
		&"car", &"wreck": return Vector2(58, 28)
		&"lamp", &"hydrant", &"cone", &"bollard": return Vector2(10, 10)
		&"medical_cache": return Vector2(20, 20)
		&"tram_stop": return Vector2(20, 26)
		&"sign_post": return Vector2(12, 22)
		&"utility_box": return Vector2(28, 20)
		&"planter": return Vector2(24, 16)
		&"rubble": return Vector2(24, 14)
		&"sandbags": return Vector2(36, 16)
		&"pallet": return Vector2(32, 24)
		&"barrel": return Vector2(20, 20)
		&"barrier": return Vector2(40, 18)
	return Vector2(16, 16)

func _make_spawn_regions(seed_value: int, blocks: Array[Dictionary], _roads: Array[Dictionary], exterior_zones: Array[Dictionary], buildings: Array[Dictionary], props: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var edge_points := [
		Vector2(-1120, -1280), Vector2(0, -1280), Vector2(1120, -1280),
		Vector2(-1280, 0), Vector2(1280, 0),
		Vector2(-1120, 1280), Vector2(0, 1280), Vector2(1120, 1280),
	]
	for i in range(edge_points.size()):
		result.append({
			"id": StringName("city_%d/spawn/edge_%d" % [seed_value, i]), "position": edge_points[i],
			"radius": 48.0, "category": &"road_edge", "environment_tags": [&"road", &"perimeter"],
			"initial_weight": 0.6, "replenishment_weight": 3.0,
			"allow_initial": true, "allow_replenishment": true, "indoor": false, "reachable": true,
		})
	# The perimeter is not enough for a city-scale population: each compact
	# room/parking anchor intentionally has a tight collision-safe radius.
	# Add spaced anchors along every connected carriageway so replenishment can
	# reach the configured 250 cap without ever falling back outside the
	# semantic road environment.
	var corridor_offsets: Array[float] = [-1120.0, -896.0, -672.0, -448.0, -224.0, 0.0, 224.0, 448.0, 672.0, 896.0, 1120.0]
	var seen_corridors: Dictionary = {}
	var corridor_serial := 0
	for road in _roads:
		var road_rect: Rect2 = road["rect"]
		for offset in corridor_offsets:
			var position: Vector2 = Vector2(offset, road_rect.get_center().y) if road["orientation"] == &"horizontal" else Vector2(road_rect.get_center().x, offset)
			if seen_corridors.has(position):
				continue
			seen_corridors[position] = true
			result.append({
				"id": StringName("city_%d/spawn/road_corridor_%02d" % [seed_value, corridor_serial]),
				"position": position, "radius": 48.0, "category": &"road_corridor",
				"environment_tags": [&"road", road["kind"]],
				"initial_weight": 0.45, "replenishment_weight": 1.8,
				"allow_initial": true, "allow_replenishment": true, "indoor": false, "reachable": true,
			})
			corridor_serial += 1
	var serial := 0
	for exterior in exterior_zones:
		if exterior["zone"] == &"safehouse":
			continue
		var kind: StringName = exterior["kind"]
		var zone: StringName = exterior["zone"]
		var weight: float = {&"park": 1.4, &"residential": 1.0, &"commercial": 2.4, &"civic": 1.8, &"industrial": 2.8}.get(zone, 1.0)
		if kind == &"alley":
			weight *= 1.35
		elif kind == &"parking":
			weight *= 1.2
		var rect: Rect2 = exterior["rect"]
		var spawn_position: Variant = _clear_exterior_spawn_position(rect, props, buildings)
		# A 32 px alley occupied by a dumpster can remain a semantic alley, but
		# it must not advertise a zombie spawn region with no body-sized cell.
		if spawn_position == null:
			continue
		result.append({
			"id": StringName("city_%d/spawn/exterior_%02d" % [seed_value, serial]),
			"position": spawn_position, "radius": GENERATED_SPAWN_RADIUS,
			"category": StringName("exterior_%s_%s" % [String(zone), String(kind)]),
			"environment_tags": [zone, kind],
			"initial_weight": weight, "replenishment_weight": weight * (1.2 if kind in [&"alley", &"parking"] else 0.65),
			"allow_initial": true, "allow_replenishment": kind != &"park", "indoor": false, "reachable": true,
			"exterior_id": exterior["id"],
		})
		serial += 1
	# Quiet residential frontages still receive low-weight initial regions
	# even when a narrow parcel produced no separate alley record.
	for block in blocks:
		if block["zone"] != &"residential":
			continue
		var rect: Rect2 = block["rect"]
		result.append({
			"id": StringName("city_%d/spawn/%s_frontage" % [seed_value, String(block["id"])]),
			"position": Vector2(rect.get_center().x, rect.end.y - 18.0), "radius": 12.0,
			"category": &"exterior_residential_frontage", "environment_tags": [&"residential", &"sidewalk"],
			"initial_weight": 0.8, "replenishment_weight": 0.35,
			"allow_initial": true, "allow_replenishment": true, "indoor": false, "reachable": true,
		})
	for building in buildings:
		var zone: StringName = building["zone"]
		var base_weight: float = {&"commercial": 2.4, &"industrial": 2.8, &"civic": 1.8, &"residential": 1.2}.get(zone, 1.0)
		for room in building["interior"]["rooms"]:
			var room_rect: Rect2 = room["rect"]
			if room_rect.size.x < MIN_INDOOR_SPAWN_SPAN or room_rect.size.y < MIN_INDOOR_SPAWN_SPAN:
				continue
			var spawn_position: Variant = _clear_indoor_spawn_position(building, room)
			# A reachable room can be furnished densely enough that it has no
			# body-sized standing cell. It remains traversable gameplay space but
			# must not become a zombie spawn region until one exists.
			if spawn_position == null:
				continue
			result.append({
				"id": StringName("%s/spawn/%s" % [String(building["id"]), String(room["id"])]),
				"position": spawn_position,
				"radius": GENERATED_SPAWN_RADIUS,
				"category": StringName("interior_%s_%s" % [String(zone), String(room["role"])]),
				"environment_tags": [zone, &"interior", room["role"]],
				"initial_weight": base_weight,
				"replenishment_weight": base_weight * (0.18 if zone in [&"residential", &"civic"] else 0.35),
				"allow_initial": true,
				"allow_replenishment": zone in [&"commercial", &"industrial"],
				"indoor": true,
				"reachable": bool(room.get("required", true)),
				"building_id": building["id"],
				"room_id": room["id"],
			})
	return result

func _make_scavenge_points(seed_value: int, blocks: Array[Dictionary], exterior_zones: Array[Dictionary], props: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var zones_by_block: Dictionary = {}
	for zone in exterior_zones:
		if zone["kind"] in [&"alley", &"parking"]:
			zones_by_block[zone["block_id"]] = zone
	for block in blocks:
		var zone: StringName = block["zone"]
		if zone in [&"safehouse", &"park"] or int(block["index"]) % 2 != 0:
			continue
		var item: StringName = &"materials"
		if zone == &"commercial": item = &"food_ration"
		elif zone == &"civic": item = &"medical_supplies"
		var rect: Rect2 = block["rect"]
		var position := _navigation_sample(Vector2(rect.end.x - 80.0, rect.end.y - 56.0))
		var exterior_id: StringName = &""
		if zones_by_block.has(block["id"]):
			var exterior: Dictionary = zones_by_block[block["id"]]
			position = _clear_exterior_position(exterior["rect"], props)
			exterior_id = exterior["id"]
		result.append({
			"id": StringName("city_%d/%s/scavenge" % [seed_value, String(block["id"])]),
			"position": position, "item_id": item, "yield": 3, "stock": 9,
			"danger": 55.0 if zone == &"industrial" else 30.0, "exterior_id": exterior_id,
		})
	return result

func _make_landmarks(seed_value: int, blocks: Array[Dictionary], buildings: Array[Dictionary], exterior_zones: Array[Dictionary], props: Array[Dictionary], scavenge_points: Array[Dictionary], include_safehouse: bool = true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for building in buildings:
		result.append({
			"id": StringName("%s/landmark_entrance" % String(building["id"])),
			"kind": building["archetype"], "position": building["approach_position"], "reachable": true,
		})
	for exterior in exterior_zones:
		if exterior["kind"] in [&"park", &"parking", &"alley"]:
			var exterior_rect: Rect2 = exterior["rect"]
			var occupied: Array[Vector2] = []
			for point in scavenge_points:
				if point.get("exterior_id", &"") == exterior["id"]:
					occupied.append(point["position"])
			var landmark_position := _clear_exterior_position(exterior_rect, props, occupied)
			result.append({
				"id": StringName("%s/landmark" % String(exterior["id"])),
				"kind": exterior["kind"], "position": landmark_position, "reachable": true,
				"exterior_id": exterior["id"],
			})
	if include_safehouse:
		var safe_block: Dictionary = blocks[0]
		result.append({
			"id": StringName("city_%d/safehouse/entrance" % seed_value), "kind": &"safehouse",
			"position": safe_block["rect"].get_center() + Vector2(0, 208), "reachable": true,
		})
	return result

func _clear_exterior_position(rect: Rect2, props: Array[Dictionary], occupied: Array[Vector2] = []) -> Vector2:
	var inset := rect.grow(-16.0)
	if inset.size.x <= 0.0 or inset.size.y <= 0.0:
		inset = rect
	var candidates: Array[Vector2] = [
		inset.get_center(),
		Vector2(inset.position.x, inset.end.y),
		Vector2(inset.end.x, inset.end.y),
		inset.position,
		Vector2(inset.end.x, inset.position.y),
		Vector2(inset.position.x + inset.size.x * 0.25, inset.position.y + inset.size.y * 0.75),
		Vector2(inset.position.x + inset.size.x * 0.75, inset.position.y + inset.size.y * 0.75),
	]
	var seen: Dictionary = {}
	for candidate in candidates:
		var sample := _navigation_sample(candidate)
		if seen.has(sample):
			continue
		seen[sample] = true
		if rect.has_point(sample) and _exterior_sample_is_clear(sample, props, occupied):
			return sample
	var first_cell := Vector2i(floori((rect.position.x + ARENA_HALF_EXTENT.x) / TILE_SIZE), floori((rect.position.y + ARENA_HALF_EXTENT.y) / TILE_SIZE))
	var last_cell := Vector2i(floori((rect.end.x - 0.001 + ARENA_HALF_EXTENT.x) / TILE_SIZE), floori((rect.end.y - 0.001 + ARENA_HALF_EXTENT.y) / TILE_SIZE))
	for y in range(first_cell.y, last_cell.y + 1):
		for x in range(first_cell.x, last_cell.x + 1):
			var sample := -ARENA_HALF_EXTENT + Vector2(x * TILE_SIZE + TILE_SIZE * 0.5, y * TILE_SIZE + TILE_SIZE * 0.5)
			if rect.has_point(sample) and _exterior_sample_is_clear(sample, props, occupied):
				return sample
	# Relaxed pass: dense dressing can legitimately cover every cell of a
	# narrow alley/parking zone. Prefer an anchor-clear cell anyway; the prop
	# half of the conflict is resolved afterwards by
	# _filter_prague_anchor_conflicts, which yields props to semantic anchors.
	for y in range(first_cell.y, last_cell.y + 1):
		for x in range(first_cell.x, last_cell.x + 1):
			var sample := -ARENA_HALF_EXTENT + Vector2(x * TILE_SIZE + TILE_SIZE * 0.5, y * TILE_SIZE + TILE_SIZE * 0.5)
			if not rect.has_point(sample):
				continue
			var anchor_clear := true
			for other in occupied:
				if sample.distance_squared_to(other) < TILE_SIZE * TILE_SIZE:
					anchor_clear = false
					break
			if anchor_clear:
				return sample
	return _navigation_sample(rect.get_center())

func _clear_exterior_spawn_position(rect: Rect2, props: Array[Dictionary], buildings: Array[Dictionary]) -> Variant:
	var inset := rect.grow(-GENERATED_SPAWN_CLEARANCE + 0.001)
	if inset.size.x <= 0.0 or inset.size.y <= 0.0:
		return null
	var candidates: Array[Vector2] = [
		inset.get_center(),
		inset.position,
		Vector2(inset.end.x, inset.position.y),
		Vector2(inset.position.x, inset.end.y),
		inset.end,
		Vector2(inset.position.x + inset.size.x * 0.25, inset.position.y + inset.size.y * 0.75),
		Vector2(inset.position.x + inset.size.x * 0.75, inset.position.y + inset.size.y * 0.75),
	]
	var seen: Dictionary = {}
	for candidate in candidates:
		var vertex := _navigation_vertex(candidate)
		if seen.has(vertex):
			continue
		seen[vertex] = true
		if inset.has_point(vertex) and _exterior_spawn_sample_is_clear(vertex, props, buildings):
			return vertex
	var first_vertex := Vector2i(
		ceili((inset.position.x + ARENA_HALF_EXTENT.x) / TILE_SIZE),
		ceili((inset.position.y + ARENA_HALF_EXTENT.y) / TILE_SIZE)
	)
	var last_vertex := Vector2i(
		floori((inset.end.x + ARENA_HALF_EXTENT.x) / TILE_SIZE),
		floori((inset.end.y + ARENA_HALF_EXTENT.y) / TILE_SIZE)
	)
	for y in range(first_vertex.y, last_vertex.y + 1):
		for x in range(first_vertex.x, last_vertex.x + 1):
			var vertex := -ARENA_HALF_EXTENT + Vector2(x * TILE_SIZE, y * TILE_SIZE)
			if inset.has_point(vertex) and _exterior_spawn_sample_is_clear(vertex, props, buildings):
				return vertex
	return null

func _clear_indoor_spawn_position(building: Dictionary, room: Dictionary) -> Variant:
	var room_rect: Rect2 = room["rect"]
	var inset := room_rect.grow(-GENERATED_SPAWN_CLEARANCE + 0.001)
	if inset.size.x <= 0.0 or inset.size.y <= 0.0:
		return null
	var building_position: Vector2 = building["position"]
	var candidates: Array[Vector2] = [
		inset.get_center(), inset.position, Vector2(inset.end.x, inset.position.y),
		Vector2(inset.position.x, inset.end.y), inset.end,
	]
	var seen: Dictionary = {}
	for candidate in candidates:
		var world_sample := _navigation_sample(building_position + candidate)
		var local_sample := world_sample - building_position
		if seen.has(local_sample):
			continue
		seen[local_sample] = true
		if inset.has_point(local_sample) and _interior_spawn_sample_is_clear(local_sample, room["id"], building["interior"]["furniture"]):
			return world_sample
	var world_inset := Rect2(building_position + inset.position, inset.size)
	var first_cell := Vector2i(floori((world_inset.position.x + ARENA_HALF_EXTENT.x) / TILE_SIZE), floori((world_inset.position.y + ARENA_HALF_EXTENT.y) / TILE_SIZE))
	var last_cell := Vector2i(floori((world_inset.end.x - 0.001 + ARENA_HALF_EXTENT.x) / TILE_SIZE), floori((world_inset.end.y - 0.001 + ARENA_HALF_EXTENT.y) / TILE_SIZE))
	for y in range(first_cell.y, last_cell.y + 1):
		for x in range(first_cell.x, last_cell.x + 1):
			var world_sample := -ARENA_HALF_EXTENT + Vector2(x * TILE_SIZE + TILE_SIZE * 0.5, y * TILE_SIZE + TILE_SIZE * 0.5)
			var local_sample := world_sample - building_position
			if inset.has_point(local_sample) and _interior_spawn_sample_is_clear(local_sample, room["id"], building["interior"]["furniture"]):
				return world_sample
	return null

func _interior_spawn_sample_is_clear(local_position: Vector2, room_id: StringName, furniture: Array) -> bool:
	for item in furniture:
		if item["room_id"] == room_id and (item["collision_rect"] as Rect2).grow(GENERATED_SPAWN_CLEARANCE).has_point(local_position):
			return false
	return true

## `building["footprint"]` is intentionally the bounding rect used by
## parcels, parking, and broad-phase building overlap checks. Compound forms
## leave one quadrant empty, however, so interaction props are checked against
## the actual union of perimeter rectangles instead of that bounding rect.
func _intersects_enterable_footprint(world_rect: Rect2, building: Dictionary) -> bool:
	var building_position: Vector2 = building["position"]
	var interior: Dictionary = building["interior"]
	var perimeter_rects: Array = interior.get("perimeter_rects", [])
	for local_rect_variant in perimeter_rects:
		var local_rect: Rect2 = local_rect_variant
		var actual_rect: Rect2 = Rect2(building_position + local_rect.position, local_rect.size)
		if world_rect.intersects(actual_rect):
			return true
	if not perimeter_rects.is_empty():
		return false
	return world_rect.intersects(building["footprint"])

func _navigation_sample(position: Vector2) -> Vector2:
	var cell := Vector2i(
		floori((position.x + ARENA_HALF_EXTENT.x) / TILE_SIZE),
		floori((position.y + ARENA_HALF_EXTENT.y) / TILE_SIZE)
	)
	return -ARENA_HALF_EXTENT + Vector2(cell.x * TILE_SIZE + TILE_SIZE * 0.5, cell.y * TILE_SIZE + TILE_SIZE * 0.5)

func _navigation_vertex(position: Vector2) -> Vector2:
	var vertex := Vector2i(
		roundi((position.x + ARENA_HALF_EXTENT.x) / TILE_SIZE),
		roundi((position.y + ARENA_HALF_EXTENT.y) / TILE_SIZE)
	)
	return -ARENA_HALF_EXTENT + Vector2(vertex.x * TILE_SIZE, vertex.y * TILE_SIZE)

func _exterior_spawn_sample_is_clear(position: Vector2, props: Array[Dictionary], buildings: Array[Dictionary] = []) -> bool:
	for prop in props:
		var prop_rect := Rect2((prop["position"] as Vector2) - (prop["size"] as Vector2) * 0.5, prop["size"])
		if prop_rect.grow(GENERATED_SPAWN_CLEARANCE).has_point(position):
			return false
	# Runtime navigation blocks full cells touched by a building shell. Keep an
	# additional half-cell beyond actor-plus-region clearance so a semantic
	# anchor never lands on the blocked corner cell beside an exterior wall.
	var shell_clearance := GENERATED_SPAWN_CLEARANCE + TILE_SIZE * 0.5
	for building in buildings:
		if (building["footprint"] as Rect2).grow(shell_clearance).has_point(position):
			return false
	return true

func _exterior_sample_is_clear(position: Vector2, props: Array[Dictionary], occupied: Array[Vector2] = []) -> bool:
	for prop in props:
		var prop_rect := Rect2((prop["position"] as Vector2) - (prop["size"] as Vector2) * 0.5, prop["size"]).grow(16.0)
		if prop_rect.has_point(position):
			return false
	for other in occupied:
		if position.distance_squared_to(other) < TILE_SIZE * TILE_SIZE:
			return false
	return true

func _corridor_rect(from: Vector2, to: Vector2, width: float) -> Rect2:
	var x := minf(from.x, to.x) - width * 0.5
	var y := minf(from.y, to.y) - width * 0.5
	return Rect2(x, y, absf(to.x - from.x) + width, absf(to.y - from.y) + width)

func _index_by_id(items: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for item in items:
		result[item["id"]] = item
	return result

func validate(city: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not String(city.get("generation_error", "")).is_empty():
		errors.append(String(city["generation_error"]))
		for diagnostic in city.get("validation_errors", []):
			var detail := String(diagnostic)
			if not detail.is_empty() and not errors.has(detail):
				errors.append(detail)
		return errors
	var roads: Array = city.get("roads", [])
	var blocks: Array = city.get("blocks", [])
	var parcels: Array = city.get("parcels", [])
	var buildings: Array = city.get("buildings", [])
	var streamed := city.has("chunk_coordinate")
	if not streamed and roads.size() != 10:
		errors.append("city must contain five horizontal and five vertical roads")
	if streamed and roads.size() < 12:
		errors.append("streamed chunk must contain connected regional streets, edge contracts, and frontage branches")
	if not streamed and blocks.size() != 16:
		errors.append("city must contain sixteen generated blocks")
	if streamed and blocks.size() < 7:
		errors.append("streamed Prague chunk must contain a complete urban-quarter set")
	_validate_road_connectivity(roads, errors)
	var ids: Dictionary = {}
	for road in roads:
		_register_id(road["id"], ids, errors)
	for intersection in city.get("intersections", []):
		_register_id(intersection["id"], ids, errors)
	var block_by_id: Dictionary = {}
	for block in blocks:
		_register_id(block["id"], ids, errors)
		block_by_id[block["id"]] = block
		var rect: Rect2 = block["rect"]
		if rect.size.x < MIN_BLOCK_SIZE or rect.size.y < MIN_BLOCK_SIZE:
			errors.append("%s is too small for a navigable parcel" % String(block["id"]))
	var parcel_by_id: Dictionary = {}
	for parcel in parcels:
		_register_id(parcel["id"], ids, errors)
		parcel_by_id[parcel["id"]] = parcel
		var block: Dictionary = block_by_id.get(parcel["block_id"], {})
		if block.is_empty() or not (block["rect"] as Rect2).grow(-SIDEWALK_DEPTH + 0.01).encloses(parcel["rect"]):
			errors.append("parcel %s leaves its block buildable inset" % String(parcel["id"]))
	for i in range(parcels.size()):
		for j in range(i + 1, parcels.size()):
			if (parcels[i]["rect"] as Rect2).intersects(parcels[j]["rect"]):
				errors.append("parcels %s and %s overlap" % [String(parcels[i]["id"]), String(parcels[j]["id"])])
	for i in range(buildings.size()):
		var building: Dictionary = buildings[i]
		_register_id(building["id"], ids, errors)
		var parcel: Dictionary = parcel_by_id.get(building["parcel_id"], {})
		if parcel.is_empty() or not (parcel["rect"] as Rect2).encloses(building["footprint"]):
			errors.append("%s does not fit its generated parcel" % String(building["id"]))
		if not (block_by_id[building["block_id"]]["rect"] as Rect2).has_point(building["approach_position"]):
			errors.append("%s approach leaves its block" % String(building["id"]))
		if not (building["access_corridor"] as Rect2).has_point(building["entrance_position"]):
			errors.append("%s entrance is disconnected from its approach" % String(building["id"]))
		var interior_errors := ProceduralBuildingGenerator.new().validate(building["interior"])
		for interior_error in interior_errors:
			errors.append("%s: %s" % [String(building["id"]), interior_error])
		var exterior_errors := BuildingExteriorRenderer.validate(building)
		for exterior_error in exterior_errors:
			errors.append("%s: %s" % [String(building["id"]), exterior_error])
		for room in building["interior"]["rooms"]:
			_register_id(room["stable_id"], ids, errors)
		for door in building["interior"]["doors"]:
			_register_id(door["id"], ids, errors)
		for window in building["interior"]["windows"]:
			_register_id(window["id"], ids, errors)
		for furniture in building["interior"]["furniture"]:
			_register_id(furniture["id"], ids, errors)
		for j in range(i + 1, buildings.size()):
			if (building["footprint"] as Rect2).intersects(buildings[j]["footprint"]):
				errors.append("buildings %s and %s overlap" % [String(building["id"]), String(buildings[j]["id"])])
	for courtyard in city.get("courtyards", []):
		var owner_block: Dictionary = block_by_id.get(courtyard["block_id"], {})
		var court_rect: Rect2 = courtyard["rect"]
		var passage: Rect2 = courtyard["access_corridor"]
		if owner_block.is_empty() or not (owner_block["rect"] as Rect2).encloses(court_rect):
			errors.append("courtyard %s leaves its urban quarter" % String(courtyard["id"]))
		if float(courtyard.get("passage_width", 0.0)) < 64.0 or not passage.intersects(court_rect):
			errors.append("courtyard %s has no two-cell street passage" % String(courtyard["id"]))
		for building in buildings:
			if building["block_id"] == courtyard["block_id"] and passage.intersects(building["footprint"]):
				errors.append("courtyard %s passage is blocked by %s" % [String(courtyard["id"]), String(building["id"])])
	for prop in city.get("props", []):
		_register_id(prop["id"], ids, errors)
		var prop_rect := Rect2((prop["position"] as Vector2) - (prop["size"] as Vector2) * 0.5, prop["size"])
		for building in buildings:
			if _intersects_enterable_footprint(prop_rect, building) or prop_rect.intersects(building["access_corridor"]):
				errors.append("prop %s blocks building %s" % [String(prop["id"]), String(building["id"])])
	var exterior_by_id: Dictionary = {}
	for exterior in city.get("exterior_zones", []):
		_register_id(exterior["id"], ids, errors)
		exterior_by_id[exterior["id"]] = exterior
	for region in city.get("spawn_regions", []):
		_register_id(region["id"], ids, errors)
		if not bool(region.get("reachable", false)):
			errors.append("spawn region %s is not accessibility-approved" % String(region["id"]))
		if bool(region.get("indoor", false)):
			var owner: Dictionary = {}
			for building in buildings:
				if building["id"] == region.get("building_id", &""):
					owner = building
					break
			if owner.is_empty():
				errors.append("indoor spawn region %s has no generated building" % String(region["id"]))
			else:
				var local_position: Vector2 = (region["position"] as Vector2) - (owner["position"] as Vector2)
				var owner_room: Dictionary = {}
				for room in owner["interior"]["rooms"]:
					if room["id"] == region.get("room_id", &"") and (room["rect"] as Rect2).has_point(local_position):
						owner_room = room
						break
				if owner_room.is_empty():
					errors.append("indoor spawn region %s leaves its reachable room" % String(region["id"]))
				else:
					var spawn_inset := (owner_room["rect"] as Rect2).grow(-GENERATED_SPAWN_CLEARANCE + 0.001)
					if not spawn_inset.has_point(local_position):
						errors.append("indoor spawn region %s lacks actor clearance from room walls" % String(region["id"]))
					if not (region["position"] as Vector2).is_equal_approx(_navigation_sample(region["position"])):
						errors.append("indoor spawn region %s is not aligned to a navigation sample" % String(region["id"]))
					if float(region.get("radius", 0.0)) > GENERATED_SPAWN_RADIUS:
						errors.append("indoor spawn region %s exceeds its validated sampling radius" % String(region["id"]))
					for furniture in owner["interior"]["furniture"]:
						if furniture["room_id"] == owner_room["id"] and (furniture["collision_rect"] as Rect2).grow(GENERATED_SPAWN_CLEARANCE).has_point(local_position):
							errors.append("indoor spawn region %s overlaps furniture clearance" % String(region["id"]))
		elif region.has("exterior_id"):
			var owner_exterior: Dictionary = exterior_by_id.get(region["exterior_id"], {})
			var region_position: Vector2 = region["position"]
			if owner_exterior.is_empty():
				errors.append("exterior spawn region %s has no generated exterior" % String(region["id"]))
			else:
				var spawn_inset := (owner_exterior["rect"] as Rect2).grow(-GENERATED_SPAWN_CLEARANCE + 0.001)
				if not spawn_inset.has_point(region_position):
					errors.append("exterior spawn region %s lacks actor clearance from zone boundaries" % String(region["id"]))
			if not region_position.is_equal_approx(_navigation_vertex(region_position)):
				errors.append("exterior spawn region %s is not aligned to a navigation-cell vertex" % String(region["id"]))
			if float(region.get("radius", 0.0)) > GENERATED_SPAWN_RADIUS:
				errors.append("exterior spawn region %s exceeds its validated sampling radius" % String(region["id"]))
			if not _exterior_spawn_sample_is_clear(region_position, city.get("props", []), city.get("buildings", [])):
				errors.append("exterior spawn region %s overlaps prop or building-shell clearance" % String(region["id"]))
	for point in city.get("scavenge_points", []):
		_register_id(point["id"], ids, errors)
		if not (point["position"] as Vector2).is_equal_approx(_navigation_sample(point["position"])):
			errors.append("scavenge point %s is not aligned to a navigation sample" % String(point["id"]))
		if point.get("exterior_id", &"") != &"":
			var owner_exterior: Dictionary = {}
			for exterior in city.get("exterior_zones", []):
				if exterior["id"] == point["exterior_id"]:
					owner_exterior = exterior
					break
			if owner_exterior.is_empty() or not (owner_exterior["rect"] as Rect2).has_point(point["position"]):
				errors.append("scavenge point %s leaves its exterior zone" % String(point["id"]))
		for prop in city.get("props", []):
			var prop_rect := Rect2((prop["position"] as Vector2) - (prop["size"] as Vector2) * 0.5, prop["size"]).grow(16.0)
			if prop_rect.has_point(point["position"]):
				errors.append("scavenge point %s overlaps prop %s" % [String(point["id"]), String(prop["id"])])
	for landmark in city.get("landmarks", []):
		_register_id(landmark["id"], ids, errors)
		if landmark.has("exterior_id") and not (landmark["position"] as Vector2).is_equal_approx(_navigation_sample(landmark["position"])):
			errors.append("landmark %s is not aligned to a navigation sample" % String(landmark["id"]))
		if landmark.has("exterior_id"):
			var owner_exterior: Dictionary = {}
			for exterior in city.get("exterior_zones", []):
				if exterior["id"] == landmark["exterior_id"]:
					owner_exterior = exterior
					break
			if owner_exterior.is_empty() or not (owner_exterior["rect"] as Rect2).has_point(landmark["position"]):
				errors.append("landmark %s leaves its exterior zone" % String(landmark["id"]))
		for prop in city.get("props", []):
			var prop_rect := Rect2((prop["position"] as Vector2) - (prop["size"] as Vector2) * 0.5, prop["size"]).grow(16.0)
			if prop_rect.has_point(landmark["position"]):
				errors.append("landmark %s overlaps prop %s" % [String(landmark["id"]), String(prop["id"])])
		if landmark.has("exterior_id"):
			for point in city.get("scavenge_points", []):
				if point.get("exterior_id", &"") == landmark["exterior_id"] and (landmark["position"] as Vector2).distance_squared_to(point["position"]) < TILE_SIZE * TILE_SIZE:
					errors.append("landmark %s overlaps scavenge point %s" % [String(landmark["id"]), String(point["id"])])
	if bool(city.get("has_safehouse", true)):
		if not (blocks[0]["rect"] as Rect2).has_point(city["safehouse_entrance"]):
			errors.append("safehouse entrance is isolated from its generated block")
		if not (city["safehouse_access"] as Rect2).has_point(city["safehouse_entrance"]):
			errors.append("safehouse access corridor does not contain its entrance")
	return errors

func _validate_road_connectivity(roads: Array, errors: Array[String]) -> void:
	if roads.is_empty():
		errors.append("road graph is empty")
		return
	var adjacency: Dictionary = {}
	var road_by_id: Dictionary = {}
	for road in roads:
		adjacency[road["id"]] = []
		road_by_id[road["id"]] = road
	for i in range(roads.size()):
		for j in range(i + 1, roads.size()):
			if (roads[i]["rect"] as Rect2).intersects(roads[j]["rect"]):
				adjacency[roads[i]["id"]].append(roads[j]["id"])
				adjacency[roads[j]["id"]].append(roads[i]["id"])
	# Label whole components so a failure names every stranded road instead of
	# only reporting that *some* street is unreachable.
	var component_of: Dictionary = {}
	var component_sizes: Array[int] = []
	for road in roads:
		var root: StringName = road["id"]
		if component_of.has(root):
			continue
		var size := 0
		var queue: Array = [root]
		while not queue.is_empty():
			var current: StringName = queue.pop_front()
			if component_of.has(current):
				continue
			component_of[current] = component_sizes.size()
			size += 1
			for neighbor in adjacency[current]:
				if not component_of.has(neighbor):
					queue.append(neighbor)
		component_sizes.append(size)
	if component_sizes.size() <= 1:
		return
	var largest: int = component_sizes.max()
	for road in roads:
		var id: StringName = road["id"]
		var component := int(component_of[id])
		if component_sizes[component] == largest:
			continue
		errors.append("disconnected road %s kind=%s orientation=%s rect=%s component=%d/%d size=%d adjacency=%d" % [
			String(id), String(road.get("kind", &"?")), String(road.get("orientation", &"?")),
			str(road["rect"]), component + 1, component_sizes.size(), component_sizes[component], (adjacency[id] as Array).size(),
		])
	errors.append("road hierarchy has %d disconnected components (sizes %s); largest is %d of %d roads" % [
		component_sizes.size(), str(component_sizes), largest, roads.size(),
	])

func _register_id(id: StringName, ids: Dictionary, errors: Array[String]) -> void:
	if id == &"":
		errors.append("generated stable id is empty")
	elif ids.has(id):
		errors.append("duplicate stable id %s" % String(id))
	else:
		ids[id] = true

## Structural fingerprint deliberately excludes the seed literal and stable
## IDs, so a different-seed test only passes when geometry/content changes.
func signature(city: Dictionary) -> String:
	var parts: Array[String] = []
	for road in city.get("roads", []):
		parts.append("road:%s:%s:%s:%s:%s" % [String(road["orientation"]), String(road["kind"]), String(road.get("surface", &"asphalt")), str(road.get("tram", false)), str(road["rect"])])
	for intersection in city.get("intersections", []):
		parts.append("intersection:%s:%s" % [String(intersection["kind"]), str(intersection["position"])])
	for block in city.get("blocks", []):
		parts.append("block:%s:%s:%s" % [String(block["zone"]), String(block["surface"]), str(block["rect"])])
	for parcel in city.get("parcels", []):
		parts.append("parcel:%s:%s:%s:%s:%s:%s" % [String(parcel["zone"]), String(parcel["frontage"]), str(parcel["rect"]), str(parcel["entrance_position"]), str(parcel["approach_position"]), str(parcel["access_corridor"])])
	for building in city.get("buildings", []):
		parts.append("building:%s:%s:%s:%s:%s:%s:%s:%s:%s" % [String(building["archetype"]), String(building.get("facade_style", &"")), String(building.get("roof_shape", &"")), str(building["position"]), str(building["size"]), str(building["footprint"]), str(building["entrance_position"]), str(building["approach_position"]), str(building["access_corridor"])])
		var exterior: Dictionary = building.get("exterior", {})
		parts.append("projected_exterior:%s:%s:%s:%s:%s:%s" % [str(exterior.get("projection_height_tiles", 0)), str(exterior.get("visual_storeys", 0)), String(exterior.get("facade_style", &"")), String(exterior.get("roof_profile", &"")), str(exterior.get("entrance_positions", [])), str(exterior.get("window_positions", []))])
		var interior: Dictionary = building["interior"]
		parts.append("layout:%s:%s:%s:%s:%s" % [String(interior["layout"]), str(interior["mirrored"]), str(interior["size"]), String(interior["roof_material"]), String(interior["wall_texture"])])
		for room in interior["rooms"]:
			parts.append("room:%s:%s:%s:%s" % [String(room["role"]), str(room["rect"]), String(room["floor_tile"]), str(room["required"])])
		for door in interior["doors"]:
			parts.append("door:%s:%s:%s:%s:%s:%s" % [str(door["position"]), str(door["rotation"]), String(door["room_a"]), String(door["room_b"]), str(door["exterior"]), str(door["service"])])
		for partition in interior["partitions"]:
			parts.append("partition:%s:%s:%s" % [str(partition["from"]), str(partition["to"]), str(partition["gaps"])])
		for window in interior["windows"]:
			parts.append("window:%s:%s:%s:%s" % [str(window["position"]), str(window["rotation"]), String(window["room_id"]), str(window["boarded"])])
		for clearance in interior["clearance_rects"]:
			parts.append("clearance:%s:%s" % [String(clearance["room_id"]), str(clearance["rect"])])
		for furniture in interior["furniture"]:
			parts.append("furniture:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s" % [String(furniture["room_id"]), String(furniture["kind"]), String(furniture["mode"]), str(furniture["position"]), str(furniture["size"]), str(furniture["collision_rect"]), str(furniture["clearance_rect"]), str(furniture["items"]), str(furniture["yield"]), str(furniture["minimum_damage_class"])])
	for exterior in city.get("exterior_zones", []):
		parts.append("exterior:%s:%s:%s" % [String(exterior["zone"]), String(exterior["kind"]), str(exterior["rect"])])
	for prop in city.get("props", []):
		parts.append("prop:%s:%s:%s:%s:%s:%s:%s:%s" % [String(prop["kind"]), String(prop["placement_role"]), str(prop["position"]), str(prop["size"]), String(prop["interaction"]), str(prop["items"]), str(prop["yield"]), str(prop["minimum_damage_class"])])
	for region in city.get("spawn_regions", []):
		parts.append("spawn:%s:%s:%s:%s:%s:%s:%s:%s:%s" % [String(region["category"]), str(region["position"]), str(region["radius"]), str(region["environment_tags"]), str(region["initial_weight"]), str(region["replenishment_weight"]), str(region["allow_initial"]), str(region["allow_replenishment"]), str(region["indoor"])])
	for point in city.get("scavenge_points", []):
		parts.append("scavenge:%s:%s:%s:%s:%s" % [String(point["item_id"]), str(point["position"]), str(point["yield"]), str(point["stock"]), str(point["danger"])])
	for landmark in city.get("landmarks", []):
		parts.append("landmark:%s:%s:%s" % [String(landmark["kind"]), str(landmark["position"]), str(landmark["reachable"])])
	for courtyard in city.get("courtyards", []):
		parts.append("courtyard:%s:%s:%s" % [str(courtyard["rect"]), str(courtyard["access_corridor"]), str(courtyard["passage_width"])])
	parts.append("district:%s" % String(city.get("district_profile", &"finite_regression")))
	parts.append("safehouse:%s:%s:%s:%s" % [str(city.get("safehouse_position", Vector2.ZERO)), str(city.get("safehouse_entrance", Vector2.ZERO)), str(city.get("safehouse_access", Rect2())), str(city.get("player_spawn", Vector2.ZERO))])
	return "|".join(parts)
