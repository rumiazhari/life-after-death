class_name PragueRegionalPlan
extends RefCounted
## Deterministic regional style field for the streamed city.  The plan is
## intentionally renderer-independent: it selects morphology, street surface,
## transit and roof vocabulary from world seed + a coarse coordinate cell.

const PROFILE_CELL_SIZE := 4
const PROFILES: Array[StringName] = [
	&"historic_core",
	&"inner_city",
	&"hillside_residential",
	&"industrial_transition",
]

static func profile_for(world_seed: int, coordinate: Vector2i) -> StringName:
	var region := Vector2i(
		floori(float(coordinate.x) / PROFILE_CELL_SIZE),
		floori(float(coordinate.y) / PROFILE_CELL_SIZE)
	)
	var mixed := ChunkEdgeContract.chunk_seed(world_seed ^ 0x4A1F39B, region)
	return PROFILES[posmod(mixed, PROFILES.size())]

static func morphology(world_seed: int, coordinate: Vector2i) -> Dictionary:
	var profile := profile_for(world_seed, coordinate)
	var rng := RandomNumberGenerator.new()
	rng.seed = ChunkEdgeContract.chunk_seed(world_seed ^ 0x2C9277B, coordinate)
	# Center/width parity keeps every resulting quarter boundary on the 64 px
	# building module grid while still allowing asymmetric district spacing.
	var inner_a := -448.0 + float(rng.randi_range(-2, 1) * 64)
	var inner_b := 480.0 + float(rng.randi_range(-1, 2) * 64)
	match profile:
		&"historic_core":
			inner_a -= 128.0
			inner_b += 64.0
		&"hillside_residential":
			inner_a += 64.0
			inner_b += 128.0
		&"industrial_transition":
			inner_a -= 64.0
			inner_b += 128.0
	return {
		"profile": profile,
		"inner_axes": [inner_a, inner_b],
		"tram_axis": &"horizontal" if posmod(rng.randi(), 2) == 0 else &"vertical",
		"square_kind": &"market_square" if profile in [&"historic_core", &"inner_city"] else &"neighborhood_square",
		"local_surface": &"cobble" if profile != &"industrial_transition" else &"stone_setts",
		"roof_palette": _roof_palette(profile),
	}

static func street_surface(profile: StringName, street_kind: StringName) -> StringName:
	if street_kind in [&"ring", &"arterial"]:
		return &"asphalt"
	if profile == &"industrial_transition":
		return &"stone_setts"
	return &"cobble"

static func _roof_palette(profile: StringName) -> Array[String]:
	match profile:
		&"historic_core": return ["A", "A", "C", "B"]
		&"inner_city": return ["A", "A", "B", "C"]
		&"hillside_residential": return ["A", "C", "D"]
		_: return ["B", "D", "A"]
