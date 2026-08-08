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
	&"roof_vent", &"roof_pipe", &"roof_sign", &"roof_duct", &"roof_tank",
	# Safehouse
	&"safehouse_floor", &"safehouse_floor_alt", &"safehouse_wall", &"safehouse_wall_reinforced",
	# Phase 3B building interior floors
	&"floor_restaurant", &"floor_kitchen", &"floor_store", &"floor_clinic", &"floor_interior_plain",
]

## Actor sprite sheet layout (Phase 3A.1): one row per palette variant, one
## column per (direction, animation, frame) slot -- the full per-variant
## column sequence is fixed and shared by the generator and
## ActorSpriteLibrary alike, so neither hard-codes a raw column number.
## Directions: down (facing camera), up (facing away), side (facing
## left/right -- right is drawn, left is the same frame with flip_h).
const ACTOR_FRAME_SIZE := Vector2i(32, 40)
const ACTOR_DIRECTIONS: Array[StringName] = [&"down", &"up", &"side"]
const ACTOR_IDLE_FRAME_COUNT := 2
const ACTOR_WALK_FRAME_COUNT := 3
## Ordered (direction, anim, frame_index) column sequence -- index in this
## array IS the atlas column for that slot.
static var ACTOR_FRAME_SLOTS: Array = _build_actor_frame_slots()

static func _build_actor_frame_slots() -> Array:
	var slots: Array = []
	for direction in ACTOR_DIRECTIONS:
		for frame in range(ACTOR_IDLE_FRAME_COUNT):
			slots.append({"direction": direction, "anim": &"idle", "frame": frame})
		for frame in range(ACTOR_WALK_FRAME_COUNT):
			slots.append({"direction": direction, "anim": &"walk", "frame": frame})
	return slots

static func actor_frames_per_variant() -> int:
	return ACTOR_FRAME_SLOTS.size()

## The atlas column for one (direction, anim, frame_index) slot; -1 if no
## such slot exists.
static func actor_frame_column(direction: StringName, anim: StringName, frame_index: int) -> int:
	for i in range(ACTOR_FRAME_SLOTS.size()):
		var slot: Dictionary = ACTOR_FRAME_SLOTS[i]
		if slot["direction"] == direction and slot["anim"] == anim and slot["frame"] == frame_index:
			return i
	return -1

const PLAYER_ATLAS_PATH := "res://assets/pixel/actors/player_atlas.png"
const SURVIVOR_ATLAS_PATH := "res://assets/pixel/actors/survivor_atlas.png"
const ZOMBIE_ATLAS_PATH := "res://assets/pixel/actors/zombie_atlas.png"
const PLAYER_VARIANT_COUNT := 1
const SURVIVOR_VARIANT_COUNT := 8
const ZOMBIE_VARIANT_COUNT := 8
const SHADOW_PATH := "res://assets/pixel/actors/shadow.png"

static func env_cell(name: StringName) -> Vector2i:
	var index: int = ENV_TILE_NAMES.find(name)
	if index < 0:
		return Vector2i.ZERO
	return Vector2i(index % ENV_ATLAS_COLUMNS, index / ENV_ATLAS_COLUMNS)

static func env_atlas_size_in_cells() -> Vector2i:
	var rows: int = ceili(float(ENV_TILE_NAMES.size()) / float(ENV_ATLAS_COLUMNS))
	return Vector2i(ENV_ATLAS_COLUMNS, rows)
