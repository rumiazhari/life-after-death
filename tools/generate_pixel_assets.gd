extends SceneTree
## Deterministic pixel-art asset generator for Phase 3A. Run headless via:
##   godot --headless --script tools/generate_pixel_assets.gd
## Draws every PNG under assets/pixel/ using only the Image API (no
## external tools, no downloaded/copied art). Every random choice is made
## with a RandomNumberGenerator seeded from SEED xor a per-asset tag, so
## running this script twice byte-for-byte reproduces the same files --
## see docs/art_direction.md for the locked spec this implements.

## Preloaded directly (rather than relying on the global class_name cache)
## since this script runs via --script before the project has ever been
## opened/imported, so PixelAtlasMap's class_name registration may not
## exist yet.
const PixelAtlasMap = preload("res://scripts/visuals/pixel_atlas_map.gd")

const SEED := 20260808

const PALETTE := {
	"asphalt_dark": Color8(56, 56, 62),
	"asphalt_mid": Color8(68, 68, 74),
	"asphalt_light": Color8(80, 80, 86),
	"sidewalk_light": Color8(172, 168, 154),
	"sidewalk_mid": Color8(152, 148, 134),
	"curb": Color8(118, 114, 102),
	"curb_dark": Color8(90, 86, 76),
	"line_yellow": Color8(226, 194, 66),
	"line_white": Color8(230, 230, 222),
	"grass": Color8(92, 142, 72),
	"grass_dark": Color8(70, 116, 54),
	"dirt": Color8(122, 94, 62),
	"concrete": Color8(148, 144, 136),
	"crack": Color8(40, 38, 36),
	"roofA": Color8(150, 70, 60), "roofA_dark": Color8(112, 50, 44),
	"roofB": Color8(90, 110, 130), "roofB_dark": Color8(64, 80, 98),
	"roofC": Color8(150, 138, 96), "roofC_dark": Color8(112, 102, 66),
	"roofD": Color8(100, 140, 110), "roofD_dark": Color8(72, 106, 82),
	"metal": Color8(150, 150, 158),
	"metal_dark": Color8(104, 104, 112),
	"safehouse_floor": Color8(122, 110, 94),
	"safehouse_floor_alt": Color8(112, 100, 84),
	"safehouse_wall": Color8(96, 82, 66),
	"safehouse_wall_dark": Color8(70, 58, 46),
	"wood": Color8(150, 110, 66),
	"wood_dark": Color8(108, 78, 44),
	"outline": Color8(26, 22, 20),
	"player_skin": Color8(224, 180, 142),
	"player_shirt": Color8(58, 96, 150),
	"player_pants": Color8(52, 58, 72),
	"survivor_skin": Color8(214, 172, 136),
	"zombie_skin": Color8(108, 132, 98),
	"zombie_skin_dark": Color8(78, 100, 72),
	"zombie_clothes": Color8(90, 84, 70),
	"blood": Color8(140, 20, 20),
	"blood_dark": Color8(96, 12, 12),
	"food": Color8(196, 150, 60),
	"water": Color8(80, 150, 196),
	"medical": Color8(210, 70, 70),
	"materials": Color8(150, 150, 158),
	"cone_orange": Color8(224, 120, 40),
	"ui_panel": Color8(20, 20, 26, 220),
	"ui_border": Color8(140, 136, 160),
	"ui_health": Color8(184, 60, 56),
	"ui_ammo": Color8(206, 182, 78),
	# Phase 3B building interiors/exteriors
	"floor_restaurant_a": Color8(150, 120, 90), "floor_restaurant_b": Color8(130, 102, 76),
	"floor_kitchen_a": Color8(170, 172, 176), "floor_kitchen_b": Color8(148, 150, 154),
	"floor_store_a": Color8(140, 138, 132), "floor_store_b": Color8(120, 118, 114),
	"floor_clinic_a": Color8(224, 228, 226), "floor_clinic_b": Color8(202, 208, 208),
	"floor_plain_a": Color8(120, 108, 96), "floor_plain_b": Color8(104, 94, 82),
	"wall_brick": Color8(140, 74, 62), "wall_brick_dark": Color8(104, 52, 44),
	"wall_concrete": Color8(150, 148, 142), "wall_concrete_dark": Color8(118, 116, 110),
	"wall_plaster": Color8(210, 202, 184), "wall_plaster_dark": Color8(180, 170, 150),
	"wall_shopfront": Color8(90, 110, 128), "wall_shopfront_dark": Color8(64, 82, 98),
	"wall_interior": Color8(196, 188, 172), "wall_interior_dark": Color8(168, 158, 140),
	"door_wood": Color8(128, 86, 50), "door_wood_dark": Color8(92, 60, 34),
	"door_metal": Color8(140, 144, 152), "door_metal_dark": Color8(100, 104, 112),
	"glass": Color8(150, 190, 210, 200), "glass_dark": Color8(100, 140, 165, 220),
	"furniture_wood": Color8(150, 108, 64), "furniture_wood_dark": Color8(110, 76, 42),
	"furniture_metal": Color8(160, 162, 168), "furniture_metal_dark": Color8(112, 114, 120),
	"fridge_white": Color8(220, 224, 224), "fridge_dark": Color8(180, 186, 188),
	"car_red": Color8(160, 54, 48), "car_red_dark": Color8(110, 34, 30),
	"car_rust": Color8(126, 96, 66), "car_rust_dark": Color8(88, 64, 42),
	"tree_trunk": Color8(96, 68, 44), "tree_leaves": Color8(78, 122, 60), "tree_leaves_dark": Color8(58, 96, 44),
	"bench_wood": Color8(140, 100, 60),
}

const ROOF_COLORS := {
	"A": ["roofA", "roofA_dark"],
	"B": ["roofB", "roofB_dark"],
	"C": ["roofC", "roofC_dark"],
	"D": ["roofD", "roofD_dark"],
}

## Eight hand-authored survivor combinations (hair style + color, skin
## tone, garment style + color, bottom/shoe color) -- silhouette-distinct,
## not just a palette swap of one base shape. Index order is what
## ActorSpriteLibrary.variant_for(&"survivor", data.id) maps named
## survivors onto, so this order is what gives each of the four a stable
## recognizable appearance across a run.
const SURVIVOR_SPECS := [
	{"skin": Color8(224, 180, 142), "hair_style": "short", "hair_color": Color8(60, 42, 30),
		"top_style": "jacket", "top_color": Color8(150, 70, 60), "accent_color": Color8(112, 50, 44),
		"bottom_color": Color8(60, 64, 78), "shoe_color": Color8(40, 36, 32)},
	{"skin": Color8(196, 148, 112), "hair_style": "long", "hair_color": Color8(24, 20, 18),
		"top_style": "coat", "top_color": Color8(90, 110, 130), "accent_color": Color8(64, 80, 98),
		"bottom_color": Color8(70, 62, 50), "shoe_color": Color8(48, 42, 36)},
	{"skin": Color8(120, 86, 60), "hair_style": "bald", "hair_color": Color8(0, 0, 0, 0),
		"top_style": "work", "top_color": Color8(110, 120, 84), "accent_color": Color8(80, 70, 40),
		"bottom_color": Color8(64, 58, 48), "shoe_color": Color8(40, 36, 32)},
	{"skin": Color8(236, 198, 164), "hair_style": "cap", "hair_color": Color8(150, 138, 96),
		"top_style": "plain", "top_color": Color8(100, 140, 110), "accent_color": Color8(72, 106, 82),
		"bottom_color": Color8(56, 58, 72), "shoe_color": Color8(40, 36, 32)},
	{"skin": Color8(150, 104, 72), "hair_style": "hood", "hair_color": Color8(64, 60, 74),
		"top_style": "jacket", "top_color": Color8(64, 60, 74), "accent_color": Color8(150, 138, 96),
		"bottom_color": Color8(50, 48, 44), "shoe_color": Color8(30, 28, 26)},
	{"skin": Color8(214, 172, 136), "hair_style": "bandana", "hair_color": Color8(180, 60, 56),
		"top_style": "medical", "top_color": Color8(224, 222, 214), "accent_color": Color8(184, 60, 56),
		"bottom_color": Color8(200, 198, 190), "shoe_color": Color8(60, 58, 54)},
	{"skin": Color8(96, 68, 48), "hair_style": "buzzed", "hair_color": Color8(30, 26, 22),
		"top_style": "work", "top_color": Color8(150, 110, 66), "accent_color": Color8(100, 72, 40),
		"bottom_color": Color8(58, 54, 46), "shoe_color": Color8(36, 32, 28)},
	{"skin": Color8(228, 188, 150), "hair_style": "afro", "hair_color": Color8(40, 30, 24),
		"top_style": "coat", "top_color": Color8(150, 138, 96), "accent_color": Color8(112, 102, 66),
		"bottom_color": Color8(62, 58, 50), "shoe_color": Color8(40, 36, 32)},
]

## Stronger (near-black, higher-contrast) outline than the shared
## PALETTE.outline every survivor/zombie uses, plus a gold accent trim --
## both are cheap, reliable "this one is the player" cues that don't
## depend on the viewer noticing the jacket is blue.
const PLAYER_SPEC := {
	"skin": Color8(224, 180, 142), "hair_style": "short", "hair_color": Color8(40, 30, 24),
	"top_style": "jacket", "top_color": Color8(48, 78, 120), "accent_color": Color8(206, 182, 78),
	"bottom_color": Color8(40, 44, 54), "shoe_color": Color8(26, 24, 22),
	"outline_color": Color8(8, 6, 6),
}

## Eight zombie combinations across two silhouette families (upright vs
## hunched) so zombies read as distinct even before color is considered --
## never relying on skin tone alone. hair_style "patchy"/"matted" implies
## torn/uneven remnants; "bald" implies bare/wounded scalp.
const ZOMBIE_SPECS := [
	{"skin": Color8(108, 132, 98), "posture": "upright", "top_color": Color8(90, 84, 70),
		"bottom_color": Color8(80, 76, 64), "hair_style": "patchy", "hair_color": Color8(40, 38, 32)},
	{"skin": Color8(96, 120, 140), "posture": "hunched", "top_color": Color8(70, 72, 84),
		"bottom_color": Color8(60, 60, 68), "hair_style": "bald", "hair_color": Color8(0, 0, 0, 0)},
	{"skin": Color8(140, 120, 90), "posture": "upright", "top_color": Color8(110, 90, 70),
		"bottom_color": Color8(90, 74, 58), "hair_style": "matted", "hair_color": Color8(50, 40, 30)},
	{"skin": Color8(120, 100, 130), "posture": "hunched", "top_color": Color8(100, 80, 110),
		"bottom_color": Color8(70, 60, 80), "hair_style": "patchy", "hair_color": Color8(30, 26, 34)},
	{"skin": Color8(100, 128, 92), "posture": "hunched", "top_color": Color8(84, 78, 64),
		"bottom_color": Color8(70, 66, 56), "hair_style": "bald", "hair_color": Color8(0, 0, 0, 0)},
	{"skin": Color8(108, 132, 150), "posture": "upright", "top_color": Color8(78, 86, 96),
		"bottom_color": Color8(64, 70, 80), "hair_style": "matted", "hair_color": Color8(20, 20, 24)},
	{"skin": Color8(150, 128, 96), "posture": "hunched", "top_color": Color8(120, 96, 74),
		"bottom_color": Color8(96, 78, 60), "hair_style": "patchy", "hair_color": Color8(60, 48, 36)},
	{"skin": Color8(128, 108, 138), "posture": "upright", "top_color": Color8(104, 84, 112),
		"bottom_color": Color8(80, 66, 86), "hair_style": "bald", "hair_color": Color8(0, 0, 0, 0)},
]

func _initialize() -> void:
	print("=== Phase 3A pixel asset generator ===")
	_ensure_dirs()
	_generate_environment_atlas()
	_generate_props()
	_generate_actor_atlases()
	_generate_effects()
	_generate_ui()
	print("=== Done ===")
	quit()

func _ensure_dirs() -> void:
	for d in [
		"res://assets/pixel/environment",
		"res://assets/pixel/actors",
		"res://assets/pixel/props",
		"res://assets/pixel/effects",
		"res://assets/pixel/ui",
	]:
		DirAccess.make_dir_recursive_absolute(d)

# ---------------------------------------------------------------------------
# Generic helpers
# ---------------------------------------------------------------------------

func _new_image(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img

func _save(img: Image, path: String) -> void:
	var err := img.save_png(path)
	if err != OK:
		push_error("Failed to save %s: %d" % [path, err])
	else:
		print("  wrote %s (%dx%d)" % [path, img.get_width(), img.get_height()])

func _outline_rect(img: Image, rect: Rect2i, color: Color, thickness: int = 1) -> void:
	img.fill_rect(Rect2i(rect.position, Vector2i(rect.size.x, thickness)), color)
	img.fill_rect(Rect2i(Vector2i(rect.position.x, rect.position.y + rect.size.y - thickness), Vector2i(rect.size.x, thickness)), color)
	img.fill_rect(Rect2i(rect.position, Vector2i(thickness, rect.size.y)), color)
	img.fill_rect(Rect2i(Vector2i(rect.position.x + rect.size.x - thickness, rect.position.y), Vector2i(thickness, rect.size.y)), color)

func _speckle(img: Image, rect: Rect2i, color: Color, density: float, rng: RandomNumberGenerator) -> void:
	var count := int(rect.size.x * rect.size.y * density)
	for i in range(count):
		var x := rect.position.x + rng.randi_range(0, rect.size.x - 1)
		var y := rect.position.y + rng.randi_range(0, rect.size.y - 1)
		img.set_pixel(x, y, color)

func _rng_for(tag: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED ^ tag.hash()
	return rng

func _local(rect: Rect2i, lx: int, ly: int, lw: int, lh: int) -> Rect2i:
	return Rect2i(rect.position + Vector2i(lx, ly), Vector2i(lw, lh))

# ---------------------------------------------------------------------------
# Section 1: environment tile atlas
# ---------------------------------------------------------------------------

func _generate_environment_atlas() -> void:
	var cells: Vector2i = PixelAtlasMap.env_atlas_size_in_cells()
	var img := _new_image(cells.x * PixelAtlasMap.TILE_SIZE, cells.y * PixelAtlasMap.TILE_SIZE)
	for i in range(PixelAtlasMap.ENV_TILE_NAMES.size()):
		var tile_name: StringName = PixelAtlasMap.ENV_TILE_NAMES[i]
		var cell := Vector2i(i % PixelAtlasMap.ENV_ATLAS_COLUMNS, i / PixelAtlasMap.ENV_ATLAS_COLUMNS)
		var rect := Rect2i(cell * PixelAtlasMap.TILE_SIZE, Vector2i(PixelAtlasMap.TILE_SIZE, PixelAtlasMap.TILE_SIZE))
		_draw_env_tile(img, rect, tile_name)
	_save(img, PixelAtlasMap.ENV_ATLAS_PATH)

func _draw_env_tile(img: Image, rect: Rect2i, tile_name: StringName) -> void:
	var s := String(tile_name)
	var rng := _rng_for(s)
	if s.begins_with("asphalt_"):
		_draw_asphalt(img, rect, rng, s)
	elif s.begins_with("sidewalk_"):
		_draw_sidewalk(img, rect, rng)
	elif s.begins_with("curb_corner"):
		_draw_curb_corner(img, rect, s)
	elif s.begins_with("curb_"):
		_draw_curb(img, rect, s)
	elif s == "crosswalk":
		_draw_crosswalk(img, rect)
	elif s.begins_with("road_dash"):
		_draw_road_dash(img, rect, s.ends_with("_v"))
	elif s.begins_with("road_solid"):
		_draw_road_solid(img, rect, s.ends_with("_v"))
	elif s == "concrete":
		_draw_concrete(img, rect, rng)
	elif s == "grass":
		_draw_grass(img, rect, rng)
	elif s == "dirt":
		_draw_dirt(img, rect, rng)
	elif s == "cracked_ground":
		_draw_cracked_ground(img, rect, rng)
	elif s == "roof_vent":
		_draw_roof_vent(img, rect)
	elif s == "roof_pipe":
		_draw_roof_pipe(img, rect)
	elif s == "roof_sign":
		_draw_roof_sign(img, rect)
	elif s == "roof_duct":
		_draw_roof_duct(img, rect)
	elif s == "roof_tank":
		_draw_roof_tank(img, rect)
	elif s.begins_with("roof"):
		_draw_roof_tile(img, rect, s, rng)
	elif s.begins_with("safehouse_"):
		_draw_safehouse_tile(img, rect, s, rng)
	elif s.begins_with("floor_"):
		_draw_building_floor(img, rect, s, rng)

func _draw_asphalt(img: Image, rect: Rect2i, rng: RandomNumberGenerator, tile_name: String) -> void:
	img.fill_rect(rect, PALETTE.asphalt_mid)
	# Fine base grain on every variant.
	_speckle(img, rect, PALETTE.asphalt_dark, 0.10, rng)
	_speckle(img, rect, PALETTE.asphalt_light, 0.07, rng)
	match tile_name:
		"asphalt_2":
			# Patched resurfacing rectangle, slightly lighter/newer asphalt.
			var patch := _local(rect, rng.randi_range(2, 10), rng.randi_range(2, 10), 16, 14)
			img.fill_rect(patch, PALETTE.asphalt_light)
			_speckle(img, patch, PALETTE.asphalt_dark, 0.08, rng)
			_outline_rect(img, patch, PALETTE.asphalt_dark, 1)
		"asphalt_3":
			# A cracked-asphalt fissure, like cracked_ground but on asphalt.
			var x := rng.randi_range(6, 24)
			for y in range(32):
				img.set_pixel(rect.position.x + x, rect.position.y + y, PALETTE.crack)
				if rng.randf() < 0.35:
					img.set_pixel(rect.position.x + x + 1, rect.position.y + y, PALETTE.crack)
				x = clampi(x + rng.randi_range(-1, 1), 2, 29)
		_:
			pass

func _draw_sidewalk(img: Image, rect: Rect2i, rng: RandomNumberGenerator) -> void:
	img.fill_rect(rect, PALETTE.sidewalk_light)
	for gx in range(8, 32, 8):
		img.fill_rect(_local(rect, gx, 0, 1, 32), PALETTE.sidewalk_mid)
	for gy in range(8, 32, 8):
		img.fill_rect(_local(rect, 0, gy, 32, 1), PALETTE.sidewalk_mid)
	# Finer expansion-joint seam detail within each slab.
	img.fill_rect(_local(rect, 3, 3, 26, 1), PALETTE.sidewalk_mid)
	img.fill_rect(_local(rect, 3, 3, 1, 26), PALETTE.sidewalk_mid)
	_speckle(img, rect, PALETTE.sidewalk_mid, 0.03, rng)
	_speckle(img, rect, PALETTE.curb, 0.01, rng)

func _draw_curb(img: Image, rect: Rect2i, name: String) -> void:
	img.fill_rect(rect, PALETTE.sidewalk_light)
	if name == "curb_top":
		img.fill_rect(_local(rect, 0, 0, 32, 8), PALETTE.curb)
		img.fill_rect(_local(rect, 0, 0, 32, 1), PALETTE.sidewalk_light.lightened(0.15)) # highlight lip
		img.fill_rect(_local(rect, 0, 6, 32, 2), PALETTE.curb_dark) # dark gutter edge
	elif name == "curb_bottom":
		img.fill_rect(_local(rect, 0, 24, 32, 8), PALETTE.curb)
		img.fill_rect(_local(rect, 0, 24, 32, 2), PALETTE.curb_dark)
		img.fill_rect(_local(rect, 0, 31, 32, 1), PALETTE.sidewalk_light.lightened(0.15))
	elif name == "curb_left":
		img.fill_rect(_local(rect, 0, 0, 8, 32), PALETTE.curb)
		img.fill_rect(_local(rect, 0, 0, 1, 32), PALETTE.sidewalk_light.lightened(0.15))
		img.fill_rect(_local(rect, 6, 0, 2, 32), PALETTE.curb_dark)
	elif name == "curb_right":
		img.fill_rect(_local(rect, 24, 0, 8, 32), PALETTE.curb)
		img.fill_rect(_local(rect, 24, 0, 2, 32), PALETTE.curb_dark)
		img.fill_rect(_local(rect, 31, 0, 1, 32), PALETTE.sidewalk_light.lightened(0.15))

func _draw_curb_corner(img: Image, rect: Rect2i, name: String) -> void:
	img.fill_rect(rect, PALETTE.sidewalk_light)
	if name == "curb_corner_tl":
		img.fill_rect(_local(rect, 0, 0, 32, 8), PALETTE.curb)
		img.fill_rect(_local(rect, 0, 0, 8, 32), PALETTE.curb)
	elif name == "curb_corner_tr":
		img.fill_rect(_local(rect, 0, 0, 32, 8), PALETTE.curb)
		img.fill_rect(_local(rect, 24, 0, 8, 32), PALETTE.curb)
	elif name == "curb_corner_bl":
		img.fill_rect(_local(rect, 0, 24, 32, 8), PALETTE.curb)
		img.fill_rect(_local(rect, 0, 0, 8, 32), PALETTE.curb)
	elif name == "curb_corner_br":
		img.fill_rect(_local(rect, 0, 24, 32, 8), PALETTE.curb)
		img.fill_rect(_local(rect, 24, 0, 8, 32), PALETTE.curb)

func _draw_crosswalk(img: Image, rect: Rect2i) -> void:
	img.fill_rect(rect, PALETTE.asphalt_mid)
	var rng := _rng_for("crosswalk_wear")
	for lx in range(2, 30, 8):
		var stripe := _local(rect, lx, 2, 5, 28)
		img.fill_rect(stripe, PALETTE.line_white)
		_outline_rect(img, stripe, PALETTE.asphalt_dark, 1)
		# Worn/faded patches breaking up an otherwise perfectly flat stripe.
		for i in range(4):
			img.set_pixel(stripe.position.x + rng.randi_range(0, 4), stripe.position.y + rng.randi_range(0, 27), PALETTE.asphalt_light)

func _draw_road_dash(img: Image, rect: Rect2i, vertical: bool) -> void:
	img.fill_rect(rect, PALETTE.asphalt_mid)
	if vertical:
		img.fill_rect(_local(rect, 14, 4, 4, 10), PALETTE.line_yellow)
		img.fill_rect(_local(rect, 14, 18, 4, 10), PALETTE.line_yellow)
	else:
		img.fill_rect(_local(rect, 4, 14, 10, 4), PALETTE.line_yellow)
		img.fill_rect(_local(rect, 18, 14, 10, 4), PALETTE.line_yellow)

func _draw_road_solid(img: Image, rect: Rect2i, vertical: bool) -> void:
	img.fill_rect(rect, PALETTE.asphalt_mid)
	if vertical:
		img.fill_rect(_local(rect, 14, 0, 4, 32), PALETTE.line_yellow)
	else:
		img.fill_rect(_local(rect, 0, 14, 32, 4), PALETTE.line_yellow)

func _draw_concrete(img: Image, rect: Rect2i, rng: RandomNumberGenerator) -> void:
	img.fill_rect(rect, PALETTE.concrete)
	_speckle(img, rect, PALETTE.sidewalk_mid, 0.05, rng)
	_speckle(img, rect, PALETTE.curb_dark, 0.02, rng)

func _draw_grass(img: Image, rect: Rect2i, rng: RandomNumberGenerator) -> void:
	img.fill_rect(rect, PALETTE.grass)
	_speckle(img, rect, PALETTE.grass_dark, 0.12, rng)
	# Weed tufts -- a few short vertical blades, not just uniform speckle.
	for i in range(3):
		var tx: int = rng.randi_range(2, 29)
		var ty: int = rng.randi_range(4, 27)
		img.set_pixel(rect.position.x + tx, rect.position.y + ty, PALETTE.grass_dark)
		img.set_pixel(rect.position.x + tx, rect.position.y + ty - 1, PALETTE.grass_dark)
		img.set_pixel(rect.position.x + tx + 1, rect.position.y + ty - 2, PALETTE.grass_dark)

func _draw_dirt(img: Image, rect: Rect2i, rng: RandomNumberGenerator) -> void:
	img.fill_rect(rect, PALETTE.dirt)
	_speckle(img, rect, PALETTE.crack, 0.05, rng)
	_speckle(img, rect, PALETTE.grass_dark, 0.03, rng)

func _draw_cracked_ground(img: Image, rect: Rect2i, rng: RandomNumberGenerator) -> void:
	img.fill_rect(rect, PALETTE.concrete)
	var x := rng.randi_range(4, 10)
	for y in range(32):
		img.set_pixel(rect.position.x + x, rect.position.y + y, PALETTE.crack)
		x = clampi(x + rng.randi_range(-1, 1), 1, 30)
	_speckle(img, rect, PALETTE.sidewalk_mid, 0.04, rng)

func _draw_roof_tile(img: Image, rect: Rect2i, name: String, rng: RandomNumberGenerator) -> void:
	var letter := name.substr(4, 1)
	var colors: Array = ROOF_COLORS[letter]
	var base: Color = PALETTE[colors[0]]
	var dark: Color = PALETTE[colors[1]]
	img.fill_rect(rect, base)
	var part := name.substr(6)
	match part:
		"center":
			for gy in range(6, 32, 8):
				img.fill_rect(_local(rect, 0, gy, 32, 1), dark)
			# Occasional weathering/damage patch -- a rustier discolored panel.
			if rng.randf() < 0.3:
				var patch := _local(rect, rng.randi_range(4, 16), rng.randi_range(4, 16), 10, 8)
				img.fill_rect(patch, dark.darkened(0.2))
		"edge_top":
			for gy in range(6, 32, 8):
				img.fill_rect(_local(rect, 0, gy, 32, 1), dark)
			img.fill_rect(_local(rect, 0, 0, 32, 4), dark)
		"edge_bottom":
			for gy in range(6, 32, 8):
				img.fill_rect(_local(rect, 0, gy, 32, 1), dark)
			img.fill_rect(_local(rect, 0, 28, 32, 4), dark)
		"edge_left":
			for gy in range(6, 32, 8):
				img.fill_rect(_local(rect, 0, gy, 32, 1), dark)
			img.fill_rect(_local(rect, 0, 0, 4, 32), dark)
		"edge_right":
			for gy in range(6, 32, 8):
				img.fill_rect(_local(rect, 0, gy, 32, 1), dark)
			img.fill_rect(_local(rect, 28, 0, 4, 32), dark)
		"corner_tl":
			img.fill_rect(_local(rect, 0, 0, 32, 4), dark)
			img.fill_rect(_local(rect, 0, 0, 4, 32), dark)
		"corner_tr":
			img.fill_rect(_local(rect, 0, 0, 32, 4), dark)
			img.fill_rect(_local(rect, 28, 0, 4, 32), dark)
		"corner_bl":
			img.fill_rect(_local(rect, 0, 28, 32, 4), dark)
			img.fill_rect(_local(rect, 0, 0, 4, 32), dark)
		"corner_br":
			img.fill_rect(_local(rect, 0, 28, 32, 4), dark)
			img.fill_rect(_local(rect, 28, 0, 4, 32), dark)

func _draw_roof_vent(img: Image, rect: Rect2i) -> void:
	img.fill_rect(_local(rect, 10, 10, 12, 12), PALETTE.metal)
	_outline_rect(img, _local(rect, 10, 10, 12, 12), PALETTE.outline)
	img.fill_rect(_local(rect, 13, 6, 6, 6), PALETTE.metal_dark)

func _draw_roof_pipe(img: Image, rect: Rect2i) -> void:
	img.fill_rect(_local(rect, 13, 4, 6, 24), PALETTE.metal_dark)
	_outline_rect(img, _local(rect, 13, 4, 6, 24), PALETTE.outline)

func _draw_roof_sign(img: Image, rect: Rect2i) -> void:
	img.fill_rect(_local(rect, 4, 12, 24, 10), PALETTE.metal)
	_outline_rect(img, _local(rect, 4, 12, 24, 10), PALETTE.outline)
	img.fill_rect(_local(rect, 8, 15, 16, 2), PALETTE.line_white)
	img.fill_rect(_local(rect, 4, 22, 3, 8), PALETTE.metal_dark)
	img.fill_rect(_local(rect, 25, 22, 3, 8), PALETTE.metal_dark)

func _draw_roof_duct(img: Image, rect: Rect2i) -> void:
	# A horizontal HVAC duct run with ribbed seams.
	img.fill_rect(_local(rect, 2, 12, 28, 8), PALETTE.metal)
	_outline_rect(img, _local(rect, 2, 12, 28, 8), PALETTE.outline)
	for x in range(6, 28, 6):
		img.fill_rect(_local(rect, x, 12, 1, 8), PALETTE.metal_dark)
	img.fill_rect(_local(rect, 2, 12, 28, 2), PALETTE.metal_dark)

func _draw_roof_tank(img: Image, rect: Rect2i) -> void:
	# A cylindrical rooftop water tank on a support frame.
	img.fill_rect(_local(rect, 8, 6, 16, 18), PALETTE.metal)
	_outline_rect(img, _local(rect, 8, 6, 16, 18), PALETTE.outline)
	img.fill_rect(_local(rect, 8, 6, 16, 3), PALETTE.metal_dark) # domed cap
	img.fill_rect(_local(rect, 8, 20, 16, 2), PALETTE.metal_dark) # base band
	img.fill_rect(_local(rect, 9, 26, 2, 5), PALETTE.wood_dark) # legs
	img.fill_rect(_local(rect, 21, 26, 2, 5), PALETTE.wood_dark)

func _draw_safehouse_tile(img: Image, rect: Rect2i, name: String, rng: RandomNumberGenerator) -> void:
	match name:
		"safehouse_floor":
			img.fill_rect(rect, PALETTE.safehouse_floor)
			for gx in range(0, 32, 16):
				img.fill_rect(_local(rect, gx, 0, 1, 32), PALETTE.safehouse_floor_alt)
			_speckle(img, rect, PALETTE.safehouse_floor_alt, 0.04, rng)
		"safehouse_floor_alt":
			img.fill_rect(rect, PALETTE.safehouse_floor_alt)
			for gy in range(0, 32, 16):
				img.fill_rect(_local(rect, 0, gy, 32, 1), PALETTE.safehouse_floor)
			_speckle(img, rect, PALETTE.safehouse_floor, 0.04, rng)
		"safehouse_wall":
			img.fill_rect(rect, PALETTE.safehouse_wall)
			for gy in range(0, 32, 8):
				img.fill_rect(_local(rect, 0, gy, 32, 1), PALETTE.safehouse_wall_dark)
			for row in range(4):
				var offset: int = 8 if row % 2 == 0 else 0
				for gx in range(offset, 32, 16):
					img.fill_rect(_local(rect, gx, row * 8, 1, 8), PALETTE.safehouse_wall_dark)
		"safehouse_wall_reinforced":
			img.fill_rect(rect, PALETTE.safehouse_wall_dark)
			img.fill_rect(_local(rect, 2, 2, 28, 28), PALETTE.metal_dark)
			_outline_rect(img, _local(rect, 2, 2, 28, 28), PALETTE.metal)
			img.fill_rect(_local(rect, 6, 6, 6, 6), PALETTE.metal)
			img.fill_rect(_local(rect, 20, 20, 6, 6), PALETTE.metal)

func _draw_building_floor(img: Image, rect: Rect2i, name: String, rng: RandomNumberGenerator) -> void:
	match name:
		"floor_restaurant":
			# Checkered dining-room tile.
			for gx in range(0, 32, 8):
				for gy in range(0, 32, 8):
					var checker: bool = ((gx / 8) + (gy / 8)) % 2 == 0
					img.fill_rect(_local(rect, gx, gy, 8, 8), PALETTE.floor_restaurant_a if checker else PALETTE.floor_restaurant_b)
		"floor_kitchen":
			img.fill_rect(rect, PALETTE.floor_kitchen_a)
			for gx in range(0, 32, 8):
				img.fill_rect(_local(rect, gx, 0, 1, 32), PALETTE.floor_kitchen_b)
			for gy in range(0, 32, 8):
				img.fill_rect(_local(rect, 0, gy, 32, 1), PALETTE.floor_kitchen_b)
			_speckle(img, rect, PALETTE.floor_kitchen_b, 0.03, rng)
		"floor_store":
			img.fill_rect(rect, PALETTE.floor_store_a)
			for gx in range(0, 32, 16):
				img.fill_rect(_local(rect, gx, 0, 1, 32), PALETTE.floor_store_b)
			_speckle(img, rect, PALETTE.floor_store_b, 0.05, rng)
		"floor_clinic":
			img.fill_rect(rect, PALETTE.floor_clinic_a)
			for gx in range(0, 32, 16):
				img.fill_rect(_local(rect, gx, 0, 1, 32), PALETTE.floor_clinic_b)
			for gy in range(0, 32, 16):
				img.fill_rect(_local(rect, 0, gy, 32, 1), PALETTE.floor_clinic_b)
		"floor_interior_plain":
			img.fill_rect(rect, PALETTE.floor_plain_a)
			for gx in range(0, 32, 16):
				img.fill_rect(_local(rect, gx, 0, 1, 32), PALETTE.floor_plain_b)
			_speckle(img, rect, PALETTE.floor_plain_b, 0.04, rng)

# ---------------------------------------------------------------------------
# Section 1: props
# ---------------------------------------------------------------------------

func _generate_props() -> void:
	_save(_draw_crate(), "res://assets/pixel/props/crate.png")
	_save(_draw_pallet(), "res://assets/pixel/props/pallet.png")
	_save(_draw_dumpster(), "res://assets/pixel/props/dumpster.png")
	_save(_draw_trash_bag(), "res://assets/pixel/props/trash_bag.png")
	_save(_draw_cone(), "res://assets/pixel/props/cone.png")
	_save(_draw_road_barrier(), "res://assets/pixel/props/road_barrier.png")
	_save(_draw_sandbags(), "res://assets/pixel/props/sandbags.png")
	_save(_draw_debris_small(), "res://assets/pixel/props/debris_small.png")
	_save(_draw_street_lamp(), "res://assets/pixel/props/street_lamp.png")
	_save(_draw_hydrant(), "res://assets/pixel/props/hydrant.png")
	_save(_draw_drain_cover(), "res://assets/pixel/props/drain_cover.png")
	_save(_draw_boarded_window(), "res://assets/pixel/props/boarded_window.png")
	_save(_draw_bed(), "res://assets/pixel/props/bed.png")
	_save(_draw_guard_post(), "res://assets/pixel/props/guard_post.png")
	_save(_draw_loot_bag(), "res://assets/pixel/props/loot_bag.png")
	_save(_draw_loot_food(), "res://assets/pixel/props/loot_food.png")
	_save(_draw_loot_water(), "res://assets/pixel/props/loot_water.png")
	_save(_draw_loot_materials(), "res://assets/pixel/props/loot_materials.png")
	_save(_draw_loot_medical(), "res://assets/pixel/props/loot_medical.png")
	# Phase 3B: building walls, doors, windows, furniture, street dressing
	_save(_draw_wall_segment(PALETTE.wall_brick, PALETTE.wall_brick_dark, "brick"), "res://assets/pixel/props/wall_brick.png")
	_save(_draw_wall_segment(PALETTE.wall_concrete, PALETTE.wall_concrete_dark, "concrete"), "res://assets/pixel/props/wall_concrete.png")
	_save(_draw_wall_segment(PALETTE.wall_plaster, PALETTE.wall_plaster_dark, "plaster"), "res://assets/pixel/props/wall_plaster.png")
	_save(_draw_wall_segment(PALETTE.wall_shopfront, PALETTE.wall_shopfront_dark, "shopfront"), "res://assets/pixel/props/wall_shopfront.png")
	_save(_draw_interior_wall(), "res://assets/pixel/props/wall_interior.png")
	_save(_draw_door(false), "res://assets/pixel/props/door_closed.png")
	_save(_draw_door(true), "res://assets/pixel/props/door_open.png")
	_save(_draw_window(false), "res://assets/pixel/props/window_intact.png")
	_save(_draw_window(true), "res://assets/pixel/props/window_boarded.png")
	_save(_draw_table(), "res://assets/pixel/props/table.png")
	_save(_draw_chair(), "res://assets/pixel/props/chair.png")
	_save(_draw_counter(), "res://assets/pixel/props/counter.png")
	_save(_draw_shelf(), "res://assets/pixel/props/shelf.png")
	_save(_draw_fridge(), "res://assets/pixel/props/fridge.png")
	_save(_draw_medical_cabinet(), "res://assets/pixel/props/medical_cabinet.png")
	_save(_draw_bench(), "res://assets/pixel/props/bench.png")
	_save(_draw_utility_box(), "res://assets/pixel/props/utility_box.png")
	_save(_draw_street_sign(), "res://assets/pixel/props/street_sign.png")
	_save(_draw_car(false), "res://assets/pixel/props/car_sedan.png")
	_save(_draw_car(true), "res://assets/pixel/props/car_wreck.png")
	_save(_draw_tree(), "res://assets/pixel/props/tree.png")
	_save(_draw_planter(), "res://assets/pixel/props/planter.png")

func _draw_crate() -> Image:
	var img := _new_image(24, 24)
	img.fill_rect(Rect2i(1, 1, 22, 22), PALETTE.wood)
	# Individual plank seams, not a flat fill.
	for x in range(1, 23, 5):
		img.fill_rect(Rect2i(x, 1, 1, 22), PALETTE.wood_dark)
	img.fill_rect(Rect2i(1, 11, 22, 1), PALETTE.wood_dark)
	_outline_rect(img, Rect2i(1, 1, 22, 22), PALETTE.outline)
	# Metal corner reinforcement brackets.
	for corner in [Vector2i(0, 0), Vector2i(19, 0), Vector2i(0, 19), Vector2i(19, 19)]:
		img.fill_rect(Rect2i(corner, Vector2i(5, 5)), PALETTE.metal)
		_outline_rect(img, Rect2i(corner, Vector2i(5, 5)), PALETTE.outline)
	return img

func _draw_pallet() -> Image:
	var img := _new_image(32, 20)
	for x in range(0, 32, 6):
		img.fill_rect(Rect2i(x, 3, 4, 14), PALETTE.wood)
		_outline_rect(img, Rect2i(x, 3, 4, 14), PALETTE.wood_dark, 1)
	img.fill_rect(Rect2i(0, 0, 32, 4), PALETTE.wood_dark)
	img.fill_rect(Rect2i(0, 16, 32, 4), PALETTE.wood_dark)
	_outline_rect(img, Rect2i(0, 0, 32, 4), PALETTE.outline)
	_outline_rect(img, Rect2i(0, 16, 32, 4), PALETTE.outline)
	return img

func _draw_dumpster() -> Image:
	var img := _new_image(40, 30)
	img.fill_rect(Rect2i(2, 8, 36, 18), PALETTE.metal_dark)
	_outline_rect(img, Rect2i(2, 8, 36, 18), PALETTE.outline)
	img.fill_rect(Rect2i(4, 10, 32, 2), PALETTE.metal) # side rib
	img.fill_rect(Rect2i(4, 16, 32, 2), PALETTE.metal)
	# Hinged lid, slightly ajar.
	img.fill_rect(Rect2i(0, 2, 40, 7), PALETTE.metal)
	_outline_rect(img, Rect2i(0, 2, 40, 7), PALETTE.outline)
	img.fill_rect(Rect2i(2, 7, 36, 2), PALETTE.metal_dark)
	# Casters.
	for wx in [5, 33]:
		img.fill_rect(Rect2i(wx, 26, 5, 4), PALETTE.outline)
		img.set_pixel(wx + 2, 27, PALETTE.metal)
	return img

func _draw_trash_bag() -> Image:
	var img := _new_image(16, 14)
	# Irregular lumpy silhouette instead of a flat rectangle.
	img.fill_rect(Rect2i(3, 6, 10, 7), PALETTE.zombie_clothes)
	img.fill_rect(Rect2i(2, 8, 3, 4), PALETTE.zombie_clothes)
	img.fill_rect(Rect2i(12, 7, 2, 5), PALETTE.zombie_clothes)
	img.fill_rect(Rect2i(6, 2, 5, 5), PALETTE.zombie_clothes)
	_outline_rect(img, Rect2i(3, 6, 10, 7), PALETTE.outline)
	_outline_rect(img, Rect2i(6, 2, 5, 5), PALETTE.outline)
	img.fill_rect(Rect2i(7, 1, 3, 2), PALETTE.crack) # tied knot
	return img

func _draw_cone() -> Image:
	var img := _new_image(14, 18)
	img.fill_rect(Rect2i(1, 14, 12, 4), PALETTE.outline)
	img.fill_rect(Rect2i(2, 15, 10, 2), PALETTE.wood_dark)
	img.fill_rect(Rect2i(4, 0, 6, 14), PALETTE.cone_orange)
	img.fill_rect(Rect2i(3, 6, 8, 2), PALETTE.line_white)
	img.fill_rect(Rect2i(3, 10, 8, 2), PALETTE.line_white)
	_outline_rect(img, Rect2i(3, 0, 8, 18), PALETTE.outline)
	return img

func _draw_road_barrier() -> Image:
	var img := _new_image(36, 24)
	# A-frame legs.
	img.fill_rect(Rect2i(2, 14, 3, 10), PALETTE.outline)
	img.fill_rect(Rect2i(31, 14, 3, 10), PALETTE.outline)
	img.fill_rect(Rect2i(2, 22, 8, 2), PALETTE.outline)
	img.fill_rect(Rect2i(26, 22, 8, 2), PALETTE.outline)
	# Striped beam.
	img.fill_rect(Rect2i(0, 4, 36, 12), PALETTE.cone_orange)
	for x in range(0, 36, 8):
		img.fill_rect(Rect2i(x, 4, 4, 12), PALETTE.line_white)
	_outline_rect(img, Rect2i(0, 4, 36, 12), PALETTE.outline)
	return img

func _draw_sandbags() -> Image:
	var img := _new_image(32, 18)
	# Individual overlapping bags, back row first so the front row occludes.
	for i in range(3):
		var rect := Rect2i(3 + i * 9, 0, 10, 8)
		img.fill_rect(rect, PALETTE.dirt)
		img.fill_rect(Rect2i(rect.position + Vector2i(1, 1), Vector2i(rect.size.x - 2, 2)), PALETTE.grass_dark)
		_outline_rect(img, rect, PALETTE.outline)
	for i in range(4):
		var rect := Rect2i(i * 8, 8, 10, 10)
		img.fill_rect(rect, PALETTE.dirt)
		img.fill_rect(Rect2i(rect.position + Vector2i(1, 1), Vector2i(rect.size.x - 2, 2)), PALETTE.grass_dark)
		_outline_rect(img, rect, PALETTE.outline)
	return img

func _draw_debris_small() -> Image:
	var img := _new_image(12, 8)
	var rng := _rng_for("debris_small")
	for i in range(6):
		img.set_pixel(rng.randi_range(0, 11), rng.randi_range(0, 7), PALETTE.concrete)
	img.fill_rect(Rect2i(2, 3, 5, 3), PALETTE.concrete)
	_outline_rect(img, Rect2i(2, 3, 5, 3), PALETTE.outline)
	return img

func _draw_street_lamp() -> Image:
	var img := _new_image(12, 48)
	img.fill_rect(Rect2i(5, 10, 2, 36), PALETTE.metal_dark)
	img.fill_rect(Rect2i(2, 0, 8, 12), PALETTE.metal)
	_outline_rect(img, Rect2i(2, 0, 8, 12), PALETTE.outline)
	img.fill_rect(Rect2i(4, 2, 4, 6), PALETTE.line_yellow)
	img.fill_rect(Rect2i(2, 44, 8, 4), PALETTE.metal_dark)
	return img

func _draw_hydrant() -> Image:
	var img := _new_image(14, 20)
	img.fill_rect(Rect2i(3, 4, 8, 14), PALETTE.medical)
	_outline_rect(img, Rect2i(3, 4, 8, 14), PALETTE.outline)
	img.fill_rect(Rect2i(1, 8, 3, 4), PALETTE.medical)
	img.fill_rect(Rect2i(10, 8, 3, 4), PALETTE.medical)
	img.fill_rect(Rect2i(4, 0, 6, 5), PALETTE.medical)
	_outline_rect(img, Rect2i(4, 0, 6, 5), PALETTE.outline)
	return img

func _draw_drain_cover() -> Image:
	var img := _new_image(20, 20)
	img.fill_rect(Rect2i(1, 1, 18, 18), PALETTE.metal_dark)
	_outline_rect(img, Rect2i(1, 1, 18, 18), PALETTE.outline)
	for x in range(4, 17, 4):
		img.fill_rect(Rect2i(x, 3, 2, 14), PALETTE.metal)
	return img

func _draw_boarded_window() -> Image:
	var img := _new_image(24, 28)
	img.fill_rect(Rect2i(0, 0, 24, 28), PALETTE.safehouse_wall_dark)
	_outline_rect(img, Rect2i(0, 0, 24, 28), PALETTE.outline)
	# Cross-nailed planks at slight angles, not three identical bars.
	for data in [[2, 3, 0], [1, 11, 1], [2, 19, -1]]:
		var y: int = data[1]
		img.fill_rect(Rect2i(data[0], y, 20, 4), PALETTE.wood)
		_outline_rect(img, Rect2i(data[0], y, 20, 4), PALETTE.wood_dark)
		img.set_pixel(4, y + 1, PALETTE.metal)
		img.set_pixel(18, y + 2, PALETTE.metal)
	return img

func _draw_bed() -> Image:
	var img := _new_image(28, 18)
	img.fill_rect(Rect2i(0, 2, 28, 16), PALETTE.wood_dark)
	_outline_rect(img, Rect2i(0, 2, 28, 16), PALETTE.outline)
	img.fill_rect(Rect2i(0, 0, 3, 18), PALETTE.wood) # headboard
	_outline_rect(img, Rect2i(0, 0, 3, 18), PALETTE.outline)
	img.fill_rect(Rect2i(3, 4, 23, 12), PALETTE.sidewalk_light) # mattress
	img.fill_rect(Rect2i(3, 4, 23, 6), PALETTE.player_shirt) # blanket
	for x in range(5, 24, 5):
		img.fill_rect(Rect2i(x, 5, 1, 4), PALETTE.roofB_dark) # blanket fold lines
	img.fill_rect(Rect2i(4, 5, 7, 5), PALETTE.sidewalk_light) # pillow
	_outline_rect(img, Rect2i(4, 5, 7, 5), PALETTE.curb_dark)
	return img

func _draw_guard_post() -> Image:
	var img := _new_image(30, 24)
	# Sandbag barricade base.
	for i in range(3):
		var rect := Rect2i(i * 10, 12, 10, 8)
		img.fill_rect(rect, PALETTE.dirt)
		img.fill_rect(Rect2i(rect.position + Vector2i(1, 1), Vector2i(rect.size.x - 2, 2)), PALETTE.grass_dark)
		_outline_rect(img, rect, PALETTE.outline)
	# Lookout posts with a crossbar.
	img.fill_rect(Rect2i(3, 0, 3, 14), PALETTE.wood)
	img.fill_rect(Rect2i(24, 0, 3, 14), PALETTE.wood)
	img.fill_rect(Rect2i(3, 3, 24, 3), PALETTE.wood_dark)
	_outline_rect(img, Rect2i(3, 0, 3, 14), PALETTE.outline)
	_outline_rect(img, Rect2i(24, 0, 3, 14), PALETTE.outline)
	return img

func _draw_loot_bag() -> Image:
	var img := _new_image(18, 16)
	img.fill_rect(Rect2i(2, 6, 14, 9), PALETTE.wood_dark)
	img.fill_rect(Rect2i(1, 8, 2, 5), PALETTE.wood_dark)
	img.fill_rect(Rect2i(15, 8, 2, 5), PALETTE.wood_dark)
	_outline_rect(img, Rect2i(2, 6, 14, 9), PALETTE.outline)
	img.fill_rect(Rect2i(6, 2, 6, 5), PALETTE.wood_dark) # tied neck
	_outline_rect(img, Rect2i(6, 2, 6, 5), PALETTE.outline)
	img.fill_rect(Rect2i(5, 4, 8, 2), PALETTE.crack) # tie strap
	# Carry strap.
	img.fill_rect(Rect2i(3, 0, 2, 4), PALETTE.crack)
	img.fill_rect(Rect2i(13, 0, 2, 4), PALETTE.crack)
	return img

func _draw_loot_food() -> Image:
	var img := _new_image(20, 16)
	img.fill_rect(Rect2i(1, 4, 18, 12), PALETTE.food)
	_outline_rect(img, Rect2i(1, 4, 18, 12), PALETTE.outline)
	img.fill_rect(Rect2i(1, 4, 18, 3), PALETTE.wood)
	img.fill_rect(Rect2i(5, 8, 10, 5), PALETTE.wood_dark) # label
	_outline_rect(img, Rect2i(5, 8, 10, 5), PALETTE.outline)
	img.fill_rect(Rect2i(7, 10, 6, 1), PALETTE.sidewalk_light)
	return img

func _draw_loot_water() -> Image:
	var img := _new_image(20, 16)
	img.fill_rect(Rect2i(2, 2, 16, 12), PALETTE.wood)
	for x in range(2, 18, 5):
		img.fill_rect(Rect2i(x, 2, 1, 12), PALETTE.wood_dark)
	_outline_rect(img, Rect2i(2, 2, 16, 12), PALETTE.outline)
	for bx in [4, 9, 14]:
		img.fill_rect(Rect2i(bx, 3, 3, 9), PALETTE.water)
		img.fill_rect(Rect2i(bx, 1, 3, 2), PALETTE.sidewalk_light) # cap
		_outline_rect(img, Rect2i(bx, 3, 3, 9), PALETTE.outline)
	return img

func _draw_loot_materials() -> Image:
	var img := _new_image(20, 16)
	var rng := _rng_for("loot_materials")
	var colors := [PALETTE.materials, PALETTE.metal_dark, PALETTE.wood, PALETTE.wood_dark]
	for i in range(6):
		var w := rng.randi_range(5, 9)
		var h := rng.randi_range(3, 6)
		var x := rng.randi_range(0, 20 - w)
		var y := rng.randi_range(3, 16 - h)
		var color: Color = colors[rng.randi_range(0, colors.size() - 1)]
		img.fill_rect(Rect2i(x, y, w, h), color)
		_outline_rect(img, Rect2i(x, y, w, h), PALETTE.outline)
	return img

func _draw_loot_medical() -> Image:
	var img := _new_image(20, 16)
	img.fill_rect(Rect2i(2, 3, 16, 11), PALETTE.sidewalk_light)
	_outline_rect(img, Rect2i(2, 3, 16, 11), PALETTE.outline)
	img.fill_rect(Rect2i(2, 3, 16, 2), PALETTE.curb_dark) # lid seam
	img.fill_rect(Rect2i(8, 1, 4, 3), PALETTE.curb_dark) # handle
	_outline_rect(img, Rect2i(8, 1, 4, 3), PALETTE.outline)
	img.fill_rect(Rect2i(8, 7, 4, 6), PALETTE.medical)
	img.fill_rect(Rect2i(6, 9, 8, 2), PALETTE.medical)
	return img

# ---------------------------------------------------------------------------
# Section 1 (Phase 3B): building walls, doors, windows, furniture, streets
# ---------------------------------------------------------------------------

## One 32x32 wall segment, tiled edge-to-edge by BuildingBase along a
## building's authored perimeter. Doors/windows are the same footprint so
## they can drop into any wall-run cell.
func _draw_wall_segment(base: Color, dark: Color, style: String) -> Image:
	var img := _new_image(32, 32)
	img.fill_rect(Rect2i(0, 0, 32, 32), base)
	match style:
		"brick":
			for row in range(8):
				var offset: int = 8 if row % 2 == 0 else 0
				img.fill_rect(Rect2i(0, row * 4, 32, 1), dark)
				for gx in range(offset, 32, 16):
					img.fill_rect(Rect2i(gx, row * 4, 1, 4), dark)
		"concrete":
			for gx in range(0, 32, 10):
				img.fill_rect(Rect2i(gx, 0, 1, 32), dark)
			img.fill_rect(Rect2i(0, 15, 32, 2), dark)
		"plaster":
			img.fill_rect(Rect2i(0, 24, 32, 4), dark) # baseboard
			img.fill_rect(Rect2i(0, 22, 32, 1), dark.lightened(0.1))
		"shopfront":
			img.fill_rect(Rect2i(0, 20, 32, 12), dark)
			img.fill_rect(Rect2i(2, 2, 28, 16), PALETTE.glass)
			_outline_rect(img, Rect2i(2, 2, 28, 16), PALETTE.outline)
		_:
			pass
	_outline_rect(img, Rect2i(0, 0, 32, 32), PALETTE.outline)
	return img

func _draw_interior_wall() -> Image:
	var img := _new_image(32, 32)
	img.fill_rect(Rect2i(0, 0, 32, 32), PALETTE.wall_interior)
	img.fill_rect(Rect2i(0, 26, 32, 6), PALETTE.wall_interior_dark)
	_outline_rect(img, Rect2i(0, 0, 32, 32), PALETTE.outline)
	return img

func _draw_door(open: bool) -> Image:
	var img := _new_image(32, 32)
	if open:
		# Swung open against the wall to one side -- the doorway itself
		# reads as open floor space.
		img.fill_rect(Rect2i(0, 0, 8, 32), PALETTE.door_wood)
		_outline_rect(img, Rect2i(0, 0, 8, 32), PALETTE.outline)
		img.fill_rect(Rect2i(2, 4, 4, 24), PALETTE.door_wood_dark)
	else:
		img.fill_rect(Rect2i(2, 0, 28, 32), PALETTE.door_wood)
		_outline_rect(img, Rect2i(2, 0, 28, 32), PALETTE.outline)
		img.fill_rect(Rect2i(2, 14, 28, 2), PALETTE.door_wood_dark)
		img.fill_rect(Rect2i(24, 15, 3, 3), PALETTE.metal) # handle
	return img

func _draw_window(boarded: bool) -> Image:
	var img := _new_image(32, 32)
	img.fill_rect(Rect2i(2, 8, 28, 16), PALETTE.wall_interior_dark)
	_outline_rect(img, Rect2i(2, 8, 28, 16), PALETTE.outline)
	if boarded:
		for gy in [10, 17, 24]:
			img.fill_rect(Rect2i(3, gy, 26, 4), PALETTE.wood)
			_outline_rect(img, Rect2i(3, gy, 26, 4), PALETTE.wood_dark)
	else:
		img.fill_rect(Rect2i(4, 10, 24, 12), PALETTE.glass)
		img.fill_rect(Rect2i(15, 10, 2, 12), PALETTE.glass_dark)
		_outline_rect(img, Rect2i(4, 10, 24, 12), PALETTE.outline)
	return img

func _draw_table() -> Image:
	var img := _new_image(32, 20)
	img.fill_rect(Rect2i(1, 2, 30, 16), PALETTE.furniture_wood)
	_outline_rect(img, Rect2i(1, 2, 30, 16), PALETTE.outline)
	img.fill_rect(Rect2i(1, 2, 30, 3), PALETTE.furniture_wood_dark)
	for lx in [3, 27]:
		img.fill_rect(Rect2i(lx, 16, 2, 4), PALETTE.furniture_wood_dark)
	return img

func _draw_chair() -> Image:
	var img := _new_image(14, 16)
	img.fill_rect(Rect2i(1, 4, 12, 10), PALETTE.furniture_wood)
	_outline_rect(img, Rect2i(1, 4, 12, 10), PALETTE.outline)
	img.fill_rect(Rect2i(1, 0, 12, 4), PALETTE.furniture_wood_dark) # backrest
	_outline_rect(img, Rect2i(1, 0, 12, 4), PALETTE.outline)
	return img

func _draw_counter() -> Image:
	var img := _new_image(48, 20)
	img.fill_rect(Rect2i(0, 2, 48, 18), PALETTE.furniture_wood_dark)
	_outline_rect(img, Rect2i(0, 2, 48, 18), PALETTE.outline)
	img.fill_rect(Rect2i(0, 0, 48, 4), PALETTE.furniture_metal)
	_outline_rect(img, Rect2i(0, 0, 48, 4), PALETTE.outline)
	for gx in range(4, 48, 12):
		img.fill_rect(Rect2i(gx, 8, 8, 10), PALETTE.furniture_wood)
		_outline_rect(img, Rect2i(gx, 8, 8, 10), PALETTE.furniture_metal_dark)
	return img

func _draw_shelf() -> Image:
	var img := _new_image(28, 12)
	img.fill_rect(Rect2i(0, 0, 28, 12), PALETTE.furniture_metal)
	_outline_rect(img, Rect2i(0, 0, 28, 12), PALETTE.outline)
	img.fill_rect(Rect2i(0, 4, 28, 1), PALETTE.furniture_metal_dark)
	img.fill_rect(Rect2i(0, 8, 28, 1), PALETTE.furniture_metal_dark)
	var rng := _rng_for("shelf_goods")
	var goods := [PALETTE.food, PALETTE.water, PALETTE.materials, PALETTE.medical]
	for gx in range(2, 26, 4):
		img.fill_rect(Rect2i(gx, 1, 3, 3), goods[rng.randi_range(0, goods.size() - 1)])
		img.fill_rect(Rect2i(gx, 5, 3, 3), goods[rng.randi_range(0, goods.size() - 1)])
	return img

func _draw_fridge() -> Image:
	var img := _new_image(20, 24)
	img.fill_rect(Rect2i(1, 1, 18, 22), PALETTE.fridge_white)
	_outline_rect(img, Rect2i(1, 1, 18, 22), PALETTE.outline)
	img.fill_rect(Rect2i(1, 11, 18, 2), PALETTE.fridge_dark)
	img.fill_rect(Rect2i(16, 3, 2, 6), PALETTE.fridge_dark) # handle
	img.fill_rect(Rect2i(16, 14, 2, 6), PALETTE.fridge_dark)
	return img

func _draw_medical_cabinet() -> Image:
	var img := _new_image(20, 24)
	img.fill_rect(Rect2i(1, 1, 18, 22), PALETTE.sidewalk_light)
	_outline_rect(img, Rect2i(1, 1, 18, 22), PALETTE.outline)
	img.fill_rect(Rect2i(8, 5, 4, 4), PALETTE.medical)
	img.fill_rect(Rect2i(6, 7, 8, 2), PALETTE.medical)
	img.fill_rect(Rect2i(3, 15, 14, 1), PALETTE.curb_dark)
	img.fill_rect(Rect2i(3, 19, 14, 1), PALETTE.curb_dark)
	return img

func _draw_bench() -> Image:
	var img := _new_image(32, 12)
	img.fill_rect(Rect2i(0, 2, 32, 6), PALETTE.bench_wood)
	_outline_rect(img, Rect2i(0, 2, 32, 6), PALETTE.outline)
	for lx in [2, 28]:
		img.fill_rect(Rect2i(lx, 8, 2, 4), PALETTE.outline)
	for gx in range(2, 30, 6):
		img.fill_rect(Rect2i(gx, 2, 1, 6), PALETTE.wood_dark)
	return img

func _draw_utility_box() -> Image:
	var img := _new_image(16, 20)
	img.fill_rect(Rect2i(1, 1, 14, 18), PALETTE.metal_dark)
	_outline_rect(img, Rect2i(1, 1, 14, 18), PALETTE.outline)
	img.fill_rect(Rect2i(3, 4, 10, 3), PALETTE.line_yellow)
	img.fill_rect(Rect2i(3, 9, 10, 1), PALETTE.metal)
	img.fill_rect(Rect2i(3, 13, 10, 1), PALETTE.metal)
	return img

func _draw_street_sign() -> Image:
	var img := _new_image(20, 36)
	img.fill_rect(Rect2i(9, 8, 2, 28), PALETTE.metal_dark)
	img.fill_rect(Rect2i(1, 0, 18, 8), PALETTE.line_white)
	_outline_rect(img, Rect2i(1, 0, 18, 8), PALETTE.outline)
	img.fill_rect(Rect2i(3, 3, 14, 2), PALETTE.outline)
	return img

func _draw_car(wrecked: bool) -> Image:
	var img := _new_image(28, 48)
	var body_color: Color = PALETTE.car_rust if wrecked else PALETTE.car_red
	var dark: Color = PALETTE.car_rust_dark if wrecked else PALETTE.car_red_dark
	img.fill_rect(Rect2i(2, 2, 24, 44), body_color)
	_outline_rect(img, Rect2i(2, 2, 24, 44), PALETTE.outline)
	img.fill_rect(Rect2i(4, 8, 20, 12), dark) # windshield/cabin band
	img.fill_rect(Rect2i(4, 28, 20, 10), dark)
	if not wrecked:
		img.fill_rect(Rect2i(4, 8, 20, 12), PALETTE.glass)
	img.fill_rect(Rect2i(2, 4, 24, 2), dark)
	img.fill_rect(Rect2i(2, 42, 24, 2), dark)
	if wrecked:
		img.fill_rect(Rect2i(10, 18, 8, 6), PALETTE.crack)
		img.fill_rect(Rect2i(6, 24, 4, 3), PALETTE.outline)
	return img

func _draw_tree() -> Image:
	var img := _new_image(32, 32)
	img.fill_rect(Rect2i(14, 20, 4, 10), PALETTE.tree_trunk)
	_outline_rect(img, Rect2i(14, 20, 4, 10), PALETTE.outline)
	var rng := _rng_for("tree_canopy")
	for i in range(3):
		var r := 10 - i * 2
		var cx := 16 + rng.randi_range(-2, 2)
		var cy := 14 - i * 4
		for y in range(-r, r):
			for x in range(-r, r):
				if x * x + y * y <= r * r and cx + x >= 0 and cx + x < 32 and cy + y >= 0 and cy + y < 32:
					img.set_pixel(cx + x, cy + y, PALETTE.tree_leaves if (x + y) % 3 != 0 else PALETTE.tree_leaves_dark)
	return img

func _draw_planter() -> Image:
	var img := _new_image(24, 16)
	img.fill_rect(Rect2i(1, 6, 22, 9), PALETTE.wood_dark)
	_outline_rect(img, Rect2i(1, 6, 22, 9), PALETTE.outline)
	img.fill_rect(Rect2i(2, 1, 20, 7), PALETTE.grass)
	_speckle(img, Rect2i(2, 1, 20, 7), PALETTE.grass_dark, 0.2, _rng_for("planter_leaves"))
	return img

# ---------------------------------------------------------------------------
# Section 1: actor atlases
# ---------------------------------------------------------------------------

func _generate_actor_atlases() -> void:
	_generate_actor_atlas(PixelAtlasMap.PLAYER_ATLAS_PATH, [PLAYER_SPEC], false)
	_generate_actor_atlas(PixelAtlasMap.SURVIVOR_ATLAS_PATH, SURVIVOR_SPECS, false)
	_generate_actor_atlas(PixelAtlasMap.ZOMBIE_ATLAS_PATH, ZOMBIE_SPECS, true)
	_save(_draw_shadow(), PixelAtlasMap.SHADOW_PATH)

## Builds one full actor atlas: one row per spec (palette variant), one
## column per (direction, anim, frame) slot from
## PixelAtlasMap.ACTOR_FRAME_SLOTS -- the single source of truth both this
## generator and ActorSpriteLibrary read the column layout from.
func _generate_actor_atlas(path: String, specs: Array, is_zombie: bool) -> void:
	var fs: Vector2i = PixelAtlasMap.ACTOR_FRAME_SIZE
	var columns: int = PixelAtlasMap.actor_frames_per_variant()
	var img := _new_image(fs.x * columns, fs.y * specs.size())
	for v in range(specs.size()):
		var spec: Dictionary = specs[v]
		for col in range(columns):
			var slot: Dictionary = PixelAtlasMap.ACTOR_FRAME_SLOTS[col]
			var origin := Vector2i(col * fs.x, v * fs.y)
			_draw_actor_frame(img, origin, spec, slot["direction"], slot["anim"], slot["frame"], is_zombie)
	_save(img, path)

## --- Actor skeleton -------------------------------------------------------
## Shared geometry constants (frame-local pixel coordinates) for the
## front/back skeleton; the side skeleton is narrower and shifted, see
## _draw_side_actor().

const HEAD_X := 10
const HEAD_W := 12
const HEAD_H := 11
const HEAD_TOP_BASE := 3
const TORSO_X := 7
const TORSO_W := 18
const TORSO_H := 12
const TORSO_TOP_BASE := 15
const ARM_W := 4
const ARM_H := 11
const ARM_LEFT_X := 3
const ARM_RIGHT_X := 25
const LEG_W := 4
const LEG_H := 9
const LEG_LEFT_X := 10
const LEG_RIGHT_X := 18
const LEG_TOP_BASE := 27
const SHOE_H := 3

func _walk_leg_offset(frame_index: int, left: bool) -> int:
	# 3-frame stride: frame 0 = left leg forward/raised, frame 2 = right
	# leg forward/raised, frame 1 = neutral crossing point.
	var phase: int = frame_index - 1 # -1, 0, 1
	if phase == 0:
		return 0
	var raised: bool = (phase < 0) == left
	return -2 if raised else 2

func _idle_bob(frame_index: int) -> int:
	return 0 if frame_index == 0 else -1

func _draw_actor_frame(img: Image, origin: Vector2i, spec: Dictionary, direction: StringName, anim: StringName, frame_index: int, is_zombie: bool) -> void:
	var bob: int = _idle_bob(frame_index) if anim == &"idle" else 0
	var walking: bool = anim == &"walk"
	if direction == &"side":
		_draw_side_actor(img, origin, spec, bob, walking, frame_index, is_zombie)
	else:
		_draw_front_back_actor(img, origin, spec, bob, walking, frame_index, is_zombie, direction == &"up")

func _draw_front_back_actor(img: Image, origin: Vector2i, spec: Dictionary, bob: int, walking: bool, frame_index: int, is_zombie: bool, back_view: bool) -> void:
	var hunched: bool = is_zombie and spec.get("posture", "upright") == "hunched"
	var lean: int = 1 if hunched else 0
	var outline: Color = spec.get("outline_color", PALETTE.outline)
	var head_top: int = HEAD_TOP_BASE + bob + lean
	var torso_top: int = TORSO_TOP_BASE + bob + lean
	var leg_top: int = LEG_TOP_BASE + lean

	var left_leg_off: int = _walk_leg_offset(frame_index, true) if walking else 0
	var right_leg_off: int = _walk_leg_offset(frame_index, false) if walking else 0

	_draw_leg(img, origin + Vector2i(LEG_LEFT_X, leg_top + left_leg_off), spec.bottom_color, spec.get("shoe_color", spec.bottom_color), outline)
	_draw_leg(img, origin + Vector2i(LEG_RIGHT_X, leg_top + right_leg_off), spec.bottom_color, spec.get("shoe_color", spec.bottom_color), outline)

	var arm_color: Color = spec.skin if is_zombie else spec.top_color
	var left_arm_off: int = right_leg_off / 2
	var right_arm_off: int = left_leg_off / 2
	_draw_arm(img, origin + Vector2i(ARM_LEFT_X, torso_top + 1 + left_arm_off), arm_color, outline)
	_draw_arm(img, origin + Vector2i(ARM_RIGHT_X, torso_top + 1 + right_arm_off), arm_color, outline)

	_draw_torso(img, origin, torso_top, spec, outline, is_zombie)
	_draw_head(img, origin, head_top, spec, outline, back_view, is_zombie)

func _draw_side_actor(img: Image, origin: Vector2i, spec: Dictionary, bob: int, walking: bool, frame_index: int, is_zombie: bool) -> void:
	var hunched: bool = is_zombie and spec.get("posture", "upright") == "hunched"
	var lean: int = 1 if hunched else 0
	var outline: Color = spec.get("outline_color", PALETTE.outline)
	var head_top: int = HEAD_TOP_BASE + bob + lean + 1
	var torso_top: int = TORSO_TOP_BASE + bob + lean
	var leg_top: int = LEG_TOP_BASE + lean
	var stride: int = 0
	if walking:
		stride = [-2, 0, 2][frame_index]

	# Back (trailing) leg first so the front leg overlaps it slightly.
	_draw_leg(img, origin + Vector2i(13 - stride, leg_top), spec.bottom_color, spec.get("shoe_color", spec.bottom_color), outline, 3)
	_draw_leg(img, origin + Vector2i(15 + stride, leg_top), spec.bottom_color, spec.get("shoe_color", spec.bottom_color), outline, 3)

	var arm_color: Color = spec.skin if is_zombie else spec.top_color
	var arm_swing: int = -stride
	_draw_arm(img, origin + Vector2i(18 + arm_swing / 2, torso_top + 1), arm_color, outline, 3)

	_draw_side_torso(img, origin, torso_top, spec, outline, is_zombie, hunched)
	_draw_side_head(img, origin, head_top, spec, outline, is_zombie)

func _draw_leg(img: Image, origin: Vector2i, pants: Color, shoe: Color, outline: Color, w: int = LEG_W) -> void:
	var rect := Rect2i(origin, Vector2i(w, LEG_H))
	img.fill_rect(rect, pants)
	img.fill_rect(Rect2i(origin + Vector2i(0, LEG_H - SHOE_H), Vector2i(w, SHOE_H)), shoe)
	_outline_rect(img, rect, outline)

func _draw_arm(img: Image, origin: Vector2i, color: Color, outline: Color, w: int = ARM_W) -> void:
	var rect := Rect2i(origin, Vector2i(w, ARM_H))
	img.fill_rect(rect, color)
	_outline_rect(img, rect, outline)

func _draw_torso(img: Image, origin: Vector2i, torso_top: int, spec: Dictionary, outline: Color, is_zombie: bool) -> void:
	var rect := Rect2i(origin + Vector2i(TORSO_X, torso_top), Vector2i(TORSO_W, TORSO_H))
	img.fill_rect(rect, spec.top_color)
	# Center trim line -- reads as a zipper/button placket, a cheap but
	# effective "this is a garment, not a flat block" cue.
	var accent: Color = spec.get("accent_color", spec.top_color.darkened(0.25))
	img.fill_rect(Rect2i(origin + Vector2i(TORSO_X + TORSO_W / 2 - 1, torso_top + 1), Vector2i(2, TORSO_H - 2)), accent)
	var style: String = spec.get("top_style", "plain")
	match style:
		"jacket":
			img.fill_rect(Rect2i(origin + Vector2i(TORSO_X, torso_top), Vector2i(4, 4)), accent)
			img.fill_rect(Rect2i(origin + Vector2i(TORSO_X + TORSO_W - 4, torso_top), Vector2i(4, 4)), accent)
		"coat":
			img.fill_rect(Rect2i(origin + Vector2i(TORSO_X, torso_top + TORSO_H - 2), Vector2i(TORSO_W, 4)), spec.top_color)
			_outline_rect(img, Rect2i(origin + Vector2i(TORSO_X, torso_top + TORSO_H - 2), Vector2i(TORSO_W, 4)), outline)
		"work":
			img.fill_rect(Rect2i(origin + Vector2i(TORSO_X, torso_top + TORSO_H - 4), Vector2i(TORSO_W, 2)), accent)
			img.fill_rect(Rect2i(origin + Vector2i(TORSO_X + TORSO_W / 2 - 2, torso_top + TORSO_H - 5), Vector2i(4, 3)), accent)
		"medical":
			img.fill_rect(Rect2i(origin + Vector2i(TORSO_X + TORSO_W / 2 - 3, torso_top + 3), Vector2i(6, 2)), accent)
			img.fill_rect(Rect2i(origin + Vector2i(TORSO_X + TORSO_W / 2 - 1, torso_top + 1), Vector2i(2, 6)), accent)
		_:
			pass
	if is_zombie:
		_draw_torn_notch(img, origin, torso_top, spec)
	_outline_rect(img, rect, outline)

func _draw_side_torso(img: Image, origin: Vector2i, torso_top: int, spec: Dictionary, outline: Color, is_zombie: bool, hunched: bool) -> void:
	var w := 12
	var x := 12
	var h := TORSO_H
	if hunched:
		h -= 2
		torso_top += 2
	var rect := Rect2i(origin + Vector2i(x, torso_top), Vector2i(w, h))
	img.fill_rect(rect, spec.top_color)
	var accent: Color = spec.get("accent_color", spec.top_color.darkened(0.25))
	img.fill_rect(Rect2i(origin + Vector2i(x + w - 3, torso_top + 1), Vector2i(2, h - 2)), accent)
	if is_zombie:
		_draw_torn_notch(img, origin, torso_top, spec)
	_outline_rect(img, rect, outline)

func _draw_torn_notch(img: Image, origin: Vector2i, torso_top: int, spec: Dictionary) -> void:
	# A ragged skin-colored notch breaking the clothing silhouette --
	# torn/missing fabric, never relying on skin tone alone to read zombie.
	img.fill_rect(Rect2i(origin + Vector2i(TORSO_X + 3, torso_top + TORSO_H - 5), Vector2i(4, 5)), spec.skin)
	img.set_pixel(origin.x + TORSO_X + 2, torso_top + TORSO_H - 3, PALETTE.outline)
	img.set_pixel(origin.x + TORSO_X + 8, torso_top + TORSO_H - 2, spec.skin)

func _draw_head(img: Image, origin: Vector2i, head_top: int, spec: Dictionary, outline: Color, back_view: bool, is_zombie: bool) -> void:
	var rect := Rect2i(origin + Vector2i(HEAD_X, head_top), Vector2i(HEAD_W, HEAD_H))
	img.fill_rect(rect, spec.skin)
	if is_zombie:
		img.fill_rect(Rect2i(origin + Vector2i(HEAD_X + 2, head_top + 5), Vector2i(3, 2)), PALETTE.zombie_skin_dark)
		img.fill_rect(Rect2i(origin + Vector2i(HEAD_X + HEAD_W - 5, head_top + 5), Vector2i(3, 2)), PALETTE.zombie_skin_dark)
	_outline_rect(img, rect, outline)
	_draw_hair(img, origin + Vector2i(HEAD_X, head_top), spec, back_view, is_zombie)

func _draw_side_head(img: Image, origin: Vector2i, head_top: int, spec: Dictionary, outline: Color, is_zombie: bool) -> void:
	var rect := Rect2i(origin + Vector2i(14, head_top), Vector2i(11, HEAD_H))
	img.fill_rect(rect, spec.skin)
	if is_zombie:
		img.fill_rect(Rect2i(origin + Vector2i(15, head_top + 5), Vector2i(2, 2)), PALETTE.zombie_skin_dark)
	_outline_rect(img, rect, outline)
	_draw_hair(img, origin + Vector2i(11, head_top), spec, true, is_zombie, true)

## Hair styles are silhouette-breaking, not palette swaps: each style
## occupies a different region/shape around the head block. `hair_color`
## with alpha 0 (see SURVIVOR_SPECS "bald") draws nothing.
func _draw_hair(img: Image, head_origin: Vector2i, spec: Dictionary, back_or_side: bool, is_zombie: bool, side_view: bool = false) -> void:
	var color: Color = spec.get("hair_color", PALETTE.outline)
	var style: String = spec.get("hair_style", "short")
	if color.a <= 0.01 and not is_zombie:
		return
	var w: int = HEAD_W if not side_view else 14
	match style:
		"short":
			img.fill_rect(Rect2i(head_origin + Vector2i(0, -1), Vector2i(w, 4)), color)
		"long":
			img.fill_rect(Rect2i(head_origin + Vector2i(0, -1), Vector2i(w, 4)), color)
			img.fill_rect(Rect2i(head_origin + Vector2i(-1, 2), Vector2i(2, 9)), color)
			img.fill_rect(Rect2i(head_origin + Vector2i(w - 1, 2), Vector2i(2, 9)), color)
		"bald":
			img.set_pixel(head_origin.x + w / 2, head_origin.y, Color(1, 1, 1, 0.25))
		"cap":
			img.fill_rect(Rect2i(head_origin + Vector2i(-1, -2), Vector2i(w + 2, 4)), color)
			img.fill_rect(Rect2i(head_origin + Vector2i(-1, 1), Vector2i(4, 2)), color)
			_outline_rect(img, Rect2i(head_origin + Vector2i(-1, -2), Vector2i(w + 2, 4)), PALETTE.outline)
		"hood":
			img.fill_rect(Rect2i(head_origin + Vector2i(-2, -3), Vector2i(w + 4, 6)), color)
			img.fill_rect(Rect2i(head_origin + Vector2i(-2, -3), Vector2i(3, 10)), color)
			img.fill_rect(Rect2i(head_origin + Vector2i(w - 1, -3), Vector2i(3, 10)), color)
			_outline_rect(img, Rect2i(head_origin + Vector2i(-2, -3), Vector2i(w + 4, 6)), PALETTE.outline)
		"bandana":
			img.fill_rect(Rect2i(head_origin + Vector2i(-1, -1), Vector2i(w + 2, 3)), color)
			img.fill_rect(Rect2i(head_origin + Vector2i(w - 1, -1), Vector2i(2, 6)), color)
		"buzzed":
			img.fill_rect(Rect2i(head_origin + Vector2i(0, -1), Vector2i(w, 2)), color)
		"afro":
			img.fill_rect(Rect2i(head_origin + Vector2i(-3, -4), Vector2i(w + 6, 7)), color)
			_outline_rect(img, Rect2i(head_origin + Vector2i(-3, -4), Vector2i(w + 6, 7)), PALETTE.outline)
		"patchy":
			img.fill_rect(Rect2i(head_origin + Vector2i(0, -1), Vector2i(w / 2, 3)), color)
			img.fill_rect(Rect2i(head_origin + Vector2i(w / 2 + 2, 0), Vector2i(3, 2)), color)
		"matted":
			img.fill_rect(Rect2i(head_origin + Vector2i(-1, -2), Vector2i(w + 2, 5)), color)
			img.set_pixel(head_origin.x + 2, head_origin.y + 4, PALETTE.zombie_skin_dark)
		_:
			pass

func _draw_shadow() -> Image:
	var img := _new_image(24, 12)
	for y in range(12):
		for x in range(24):
			var nx: float = (x - 12.0) / 12.0
			var ny: float = (y - 6.0) / 6.0
			if nx * nx + ny * ny <= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0.35))
	return img

# ---------------------------------------------------------------------------
# Section 1: combat / effects
# ---------------------------------------------------------------------------

func _generate_effects() -> void:
	_save(_draw_projectile(), "res://assets/pixel/effects/projectile.png")
	_save(_draw_muzzle_flash(), "res://assets/pixel/effects/muzzle_flash.png")
	_save(_draw_blood_impact(), "res://assets/pixel/effects/blood_impact.png")
	for i in range(3):
		_save(_draw_blood_decal(i), "res://assets/pixel/effects/blood_decal_%d.png" % i)
	_save(_draw_selection_marker(), "res://assets/pixel/effects/selection_marker.png")
	_save(_draw_highlight_marker(), "res://assets/pixel/effects/highlight_marker.png")

func _draw_projectile() -> Image:
	var img := _new_image(8, 4)
	img.fill_rect(Rect2i(0, 1, 8, 2), PALETTE.line_yellow)
	img.set_pixel(7, 1, PALETTE.outline)
	img.set_pixel(7, 2, PALETTE.outline)
	return img

func _draw_muzzle_flash() -> Image:
	var img := _new_image(12, 12)
	img.fill_rect(Rect2i(4, 4, 4, 4), PALETTE.line_white)
	img.fill_rect(Rect2i(2, 5, 8, 2), PALETTE.line_yellow)
	img.fill_rect(Rect2i(5, 2, 2, 8), PALETTE.line_yellow)
	return img

func _draw_blood_impact() -> Image:
	var img := _new_image(10, 10)
	var rng := _rng_for("blood_impact")
	for i in range(10):
		img.set_pixel(rng.randi_range(1, 8), rng.randi_range(1, 8), PALETTE.blood)
	img.fill_rect(Rect2i(4, 4, 3, 3), PALETTE.blood_dark)
	return img

func _draw_blood_decal(variant: int) -> Image:
	var img := _new_image(16, 16)
	var rng := _rng_for("blood_decal_%d" % variant)
	var cx := 8
	var cy := 8
	for i in range(26):
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.0, 6.0)
		var x := clampi(cx + int(cos(a) * r), 0, 15)
		var y := clampi(cy + int(sin(a) * r), 0, 15)
		img.set_pixel(x, y, PALETTE.blood if rng.randf() > 0.35 else PALETTE.blood_dark)
	img.fill_rect(Rect2i(cx - 2, cy - 2, 4, 4), PALETTE.blood_dark)
	return img

func _draw_selection_marker() -> Image:
	var img := _new_image(28, 28)
	for a in range(0, 360, 4):
		var rad := deg_to_rad(a)
		var x := int(14 + cos(rad) * 12)
		var y := int(14 + sin(rad) * 12)
		img.set_pixel(clampi(x, 0, 27), clampi(y, 0, 27), PALETTE.line_white)
	return img

func _draw_highlight_marker() -> Image:
	var img := _new_image(20, 20)
	for a in range(0, 360, 6):
		var rad := deg_to_rad(a)
		var x := int(10 + cos(rad) * 8)
		var y := int(10 + sin(rad) * 8)
		img.set_pixel(clampi(x, 0, 19), clampi(y, 0, 19), PALETTE.line_yellow)
	return img

# ---------------------------------------------------------------------------
# Section 1: UI
# ---------------------------------------------------------------------------

func _generate_ui() -> void:
	_save(_draw_icon_health(), "res://assets/pixel/ui/icon_health.png")
	_save(_draw_icon_ammo(), "res://assets/pixel/ui/icon_ammo.png")
	_save(_draw_icon_zombie(), "res://assets/pixel/ui/icon_zombie.png")
	_save(_draw_icon_kills(), "res://assets/pixel/ui/icon_kills.png")
	_save(_draw_icon_food(), "res://assets/pixel/ui/icon_food.png")
	_save(_draw_icon_water(), "res://assets/pixel/ui/icon_water.png")
	_save(_draw_icon_materials(), "res://assets/pixel/ui/icon_materials.png")
	_save(_draw_icon_medical(), "res://assets/pixel/ui/icon_medical.png")
	_save(_draw_panel_bg(), "res://assets/pixel/ui/panel_bg.png")
	_save(_draw_button(0), "res://assets/pixel/ui/button_normal.png")
	_save(_draw_button(1), "res://assets/pixel/ui/button_hover.png")
	_save(_draw_button(2), "res://assets/pixel/ui/button_pressed.png")

func _draw_icon_health() -> Image:
	var img := _new_image(16, 16)
	img.fill_rect(Rect2i(2, 6, 12, 6), PALETTE.ui_health)
	img.fill_rect(Rect2i(6, 2, 4, 12), PALETTE.ui_health)
	_outline_rect(img, Rect2i(2, 6, 12, 6), PALETTE.outline)
	_outline_rect(img, Rect2i(6, 2, 4, 12), PALETTE.outline)
	return img

func _draw_icon_ammo() -> Image:
	var img := _new_image(16, 16)
	img.fill_rect(Rect2i(6, 2, 4, 10), PALETTE.ui_ammo)
	img.fill_rect(Rect2i(5, 12, 6, 3), PALETTE.metal_dark)
	_outline_rect(img, Rect2i(6, 2, 4, 10), PALETTE.outline)
	return img

func _draw_icon_zombie() -> Image:
	var img := _new_image(16, 16)
	img.fill_rect(Rect2i(4, 4, 8, 8), PALETTE.zombie_skin)
	_outline_rect(img, Rect2i(4, 4, 8, 8), PALETTE.outline)
	img.set_pixel(6, 7, PALETTE.outline)
	img.set_pixel(9, 7, PALETTE.outline)
	return img

func _draw_icon_kills() -> Image:
	var img := _new_image(16, 16)
	for a in range(0, 360, 45):
		var rad := deg_to_rad(a)
		var x := int(8 + cos(rad) * 6)
		var y := int(8 + sin(rad) * 6)
		img.set_pixel(clampi(x, 0, 15), clampi(y, 0, 15), PALETTE.ui_ammo)
	img.fill_rect(Rect2i(6, 6, 4, 4), PALETTE.ui_health)
	return img

func _draw_icon_food() -> Image:
	var img := _new_image(16, 16)
	img.fill_rect(Rect2i(3, 5, 10, 8), PALETTE.food)
	_outline_rect(img, Rect2i(3, 5, 10, 8), PALETTE.outline)
	return img

func _draw_icon_water() -> Image:
	var img := _new_image(16, 16)
	img.fill_rect(Rect2i(5, 3, 6, 10), PALETTE.water)
	_outline_rect(img, Rect2i(5, 3, 6, 10), PALETTE.outline)
	return img

func _draw_icon_materials() -> Image:
	var img := _new_image(16, 16)
	img.fill_rect(Rect2i(3, 7, 5, 5), PALETTE.materials)
	img.fill_rect(Rect2i(8, 4, 5, 5), PALETTE.materials)
	_outline_rect(img, Rect2i(3, 7, 5, 5), PALETTE.outline)
	_outline_rect(img, Rect2i(8, 4, 5, 5), PALETTE.outline)
	return img

func _draw_icon_medical() -> Image:
	var img := _new_image(16, 16)
	img.fill_rect(Rect2i(2, 6, 12, 4), PALETTE.medical)
	img.fill_rect(Rect2i(6, 2, 4, 12), PALETTE.medical)
	_outline_rect(img, Rect2i(2, 6, 12, 4), PALETTE.outline)
	_outline_rect(img, Rect2i(6, 2, 4, 12), PALETTE.outline)
	return img

func _draw_panel_bg() -> Image:
	var img := _new_image(8, 8)
	img.fill_rect(Rect2i(0, 0, 8, 8), PALETTE.ui_panel)
	return img

func _draw_button(state: int) -> Image:
	var img := _new_image(8, 8)
	var base: Color = PALETTE.ui_panel
	if state == 1:
		base = Color(base.r + 0.06, base.g + 0.06, base.b + 0.08, base.a)
	elif state == 2:
		base = Color(base.r * 0.7, base.g * 0.7, base.b * 0.7, base.a)
	img.fill_rect(Rect2i(0, 0, 8, 8), base)
	_outline_rect(img, Rect2i(0, 0, 8, 8), PALETTE.ui_border)
	return img
