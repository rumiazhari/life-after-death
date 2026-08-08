class_name PixelAtlasMap
extends RefCounted
## Canonical layout for the generated pixel-art atlases -- the single
## source of truth both tools/generate_pixel_assets.gd (which draws each
## named cell at the position this file assigns it) and every consumer
## that paints/places tiles or frames by name (ArenaBuilder, Settlement,
## ActorSpriteLibrary) read from, so nothing ever hard-codes a raw atlas
## column/row anywhere else. See docs/art_direction.md for the full
## rationale.

const TILE_SIZE := 32
const ENV_ATLAS_COLUMNS := 10
const ENV_ATLAS_PATH := "res://assets/pixel/environment/environment_atlas.png"

## Ordered once, here, and nowhere else -- both the generator and any
## consumer derive a name's (column, row) from its index in this array,
## so adding a new tile is adding one line, not editing two places that
## could drift out of sync.
const ENV_TILE_NAMES: Array[StringName] = [
	# Roads / asphalt
	&"asphalt_0", &"asphalt_1", &"asphalt_2", &"asphalt_3",
	# Sidewalks
	&"sidewalk_0", &"sidewalk_1",
	# Curbs (straight + corners)
	&"curb_top", &"curb_bottom", &"curb_left", &"curb_right",
	&"curb_corner_tl", &"curb_corner_tr", &"curb_corner_bl", &"curb_corner_br",
	# Road markings
	&"crosswalk", &"road_dash_h", &"road_dash_v", &"road_solid_h", &"road_solid_v",
	# Ground variety
	&"concrete", &"grass", &"dirt", &"cracked_ground",
	# Roof variant A (brick red)
	&"roofA_center", &"roofA_edge_top", &"roofA_edge_bottom", &"roofA_edge_left", &"roofA_edge_right",
	&"roofA_corner_tl", &"roofA_corner_tr", &"roofA_corner_bl", &"roofA_corner_br",
	# Roof variant B (slate blue)
	&"roofB_center", &"roofB_edge_top", &"roofB_edge_bottom", &"roofB_edge_left", &"roofB_edge_right",
	&"roofB_corner_tl", &"roofB_corner_tr", &"roofB_corner_bl", &"roofB_corner_br",
	# Roof variant C (tan)
	&"roofC_center", &"roofC_edge_top", &"roofC_edge_bottom", &"roofC_edge_left", &"roofC_edge_right",
	&"roofC_corner_tl", &"roofC_corner_tr", &"roofC_corner_bl", &"roofC_corner_br",
	# Roof variant D (green patina)
	&"roofD_center", &"roofD_edge_top", &"roofD_edge_bottom", &"roofD_edge_left", &"roofD_edge_right",
	&"roofD_corner_tl", &"roofD_corner_tr", &"roofD_corner_bl", &"roofD_corner_br",
	# Rooftop details
	&"roof_vent", &"roof_pipe", &"roof_sign",
	# Safehouse
	&"safehouse_floor", &"safehouse_floor_alt", &"safehouse_wall", &"safehouse_wall_reinforced",
]

## Actor sprite sheet layout: one row per palette variant, one column per
## animation frame. Kept separate per actor type since each has a
## different variant count.
const ACTOR_FRAME_SIZE := Vector2i(32, 40)
const ACTOR_FRAME_NAMES: Array[StringName] = [&"idle", &"walk"]
const PLAYER_ATLAS_PATH := "res://assets/pixel/actors/player_atlas.png"
const SURVIVOR_ATLAS_PATH := "res://assets/pixel/actors/survivor_atlas.png"
const ZOMBIE_ATLAS_PATH := "res://assets/pixel/actors/zombie_atlas.png"
const PLAYER_VARIANT_COUNT := 1
const SURVIVOR_VARIANT_COUNT := 4
const ZOMBIE_VARIANT_COUNT := 4
const SHADOW_PATH := "res://assets/pixel/actors/shadow.png"

static func env_cell(name: StringName) -> Vector2i:
	var index: int = ENV_TILE_NAMES.find(name)
	if index < 0:
		return Vector2i.ZERO
	return Vector2i(index % ENV_ATLAS_COLUMNS, index / ENV_ATLAS_COLUMNS)

static func env_atlas_size_in_cells() -> Vector2i:
	var rows: int = ceili(float(ENV_TILE_NAMES.size()) / float(ENV_ATLAS_COLUMNS))
	return Vector2i(ENV_ATLAS_COLUMNS, rows)
