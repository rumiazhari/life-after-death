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
}

const ROOF_COLORS := {
	"A": ["roofA", "roofA_dark"],
	"B": ["roofB", "roofB_dark"],
	"C": ["roofC", "roofC_dark"],
	"D": ["roofD", "roofD_dark"],
}

const SURVIVOR_SHIRTS := [
	Color8(150, 70, 60), Color8(90, 110, 130), Color8(150, 138, 96), Color8(100, 140, 110),
]
const ZOMBIE_TINTS := [
	Color8(108, 132, 98), Color8(96, 120, 140), Color8(140, 120, 90), Color8(120, 100, 130),
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
		_draw_asphalt(img, rect, rng)
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
	elif s.begins_with("roof"):
		_draw_roof_tile(img, rect, s)
	elif s.begins_with("safehouse_"):
		_draw_safehouse_tile(img, rect, s, rng)

func _draw_asphalt(img: Image, rect: Rect2i, rng: RandomNumberGenerator) -> void:
	img.fill_rect(rect, PALETTE.asphalt_mid)
	_speckle(img, rect, PALETTE.asphalt_dark, 0.06, rng)
	_speckle(img, rect, PALETTE.asphalt_light, 0.04, rng)

func _draw_sidewalk(img: Image, rect: Rect2i, rng: RandomNumberGenerator) -> void:
	img.fill_rect(rect, PALETTE.sidewalk_light)
	for gx in range(8, 32, 8):
		img.fill_rect(_local(rect, gx, 0, 1, 32), PALETTE.sidewalk_mid)
	for gy in range(8, 32, 8):
		img.fill_rect(_local(rect, 0, gy, 32, 1), PALETTE.sidewalk_mid)
	_speckle(img, rect, PALETTE.sidewalk_mid, 0.03, rng)

func _draw_curb(img: Image, rect: Rect2i, name: String) -> void:
	img.fill_rect(rect, PALETTE.sidewalk_light)
	if name == "curb_top":
		img.fill_rect(_local(rect, 0, 0, 32, 8), PALETTE.curb)
		img.fill_rect(_local(rect, 0, 6, 32, 2), PALETTE.curb_dark)
	elif name == "curb_bottom":
		img.fill_rect(_local(rect, 0, 24, 32, 8), PALETTE.curb)
		img.fill_rect(_local(rect, 0, 24, 32, 2), PALETTE.curb_dark)
	elif name == "curb_left":
		img.fill_rect(_local(rect, 0, 0, 8, 32), PALETTE.curb)
		img.fill_rect(_local(rect, 6, 0, 2, 32), PALETTE.curb_dark)
	elif name == "curb_right":
		img.fill_rect(_local(rect, 24, 0, 8, 32), PALETTE.curb)
		img.fill_rect(_local(rect, 24, 0, 2, 32), PALETTE.curb_dark)

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
	for lx in range(2, 30, 8):
		img.fill_rect(_local(rect, lx, 2, 5, 28), PALETTE.line_white)

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

func _draw_roof_tile(img: Image, rect: Rect2i, name: String) -> void:
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

func _draw_crate() -> Image:
	var img := _new_image(24, 24)
	img.fill_rect(Rect2i(0, 0, 24, 24), PALETTE.wood)
	_outline_rect(img, Rect2i(0, 0, 24, 24), PALETTE.outline)
	img.fill_rect(Rect2i(2, 2, 20, 2), PALETTE.wood_dark)
	img.fill_rect(Rect2i(2, 20, 20, 2), PALETTE.wood_dark)
	img.fill_rect(Rect2i(2, 2, 2, 20), PALETTE.wood_dark)
	img.fill_rect(Rect2i(20, 2, 2, 20), PALETTE.wood_dark)
	img.fill_rect(Rect2i(11, 2, 2, 20), PALETTE.wood_dark)
	return img

func _draw_pallet() -> Image:
	var img := _new_image(32, 20)
	for x in range(0, 32, 6):
		img.fill_rect(Rect2i(x, 4, 4, 12), PALETTE.wood)
	img.fill_rect(Rect2i(0, 0, 32, 4), PALETTE.wood_dark)
	img.fill_rect(Rect2i(0, 16, 32, 4), PALETTE.wood_dark)
	return img

func _draw_dumpster() -> Image:
	var img := _new_image(40, 28)
	img.fill_rect(Rect2i(2, 6, 36, 22), PALETTE.metal_dark)
	_outline_rect(img, Rect2i(2, 6, 36, 22), PALETTE.outline)
	img.fill_rect(Rect2i(0, 0, 40, 8), PALETTE.metal)
	_outline_rect(img, Rect2i(0, 0, 40, 8), PALETTE.outline)
	img.fill_rect(Rect2i(4, 12, 32, 2), PALETTE.outline)
	return img

func _draw_trash_bag() -> Image:
	var img := _new_image(16, 14)
	img.fill_rect(Rect2i(2, 4, 12, 10), PALETTE.zombie_clothes)
	_outline_rect(img, Rect2i(2, 4, 12, 10), PALETTE.outline)
	img.fill_rect(Rect2i(6, 0, 4, 6), PALETTE.zombie_clothes)
	return img

func _draw_cone() -> Image:
	var img := _new_image(14, 18)
	img.fill_rect(Rect2i(1, 14, 12, 4), PALETTE.outline)
	img.fill_rect(Rect2i(4, 0, 6, 14), PALETTE.cone_orange)
	img.fill_rect(Rect2i(3, 6, 8, 2), PALETTE.line_white)
	_outline_rect(img, Rect2i(3, 0, 8, 18), PALETTE.outline)
	return img

func _draw_road_barrier() -> Image:
	var img := _new_image(36, 16)
	img.fill_rect(Rect2i(0, 0, 36, 16), PALETTE.cone_orange)
	img.fill_rect(Rect2i(0, 0, 36, 4), PALETTE.line_white)
	img.fill_rect(Rect2i(0, 12, 36, 4), PALETTE.line_white)
	_outline_rect(img, Rect2i(0, 0, 36, 16), PALETTE.outline)
	return img

func _draw_sandbags() -> Image:
	var img := _new_image(32, 16)
	for i in range(4):
		img.fill_rect(Rect2i(i * 8, 6, 8, 10), PALETTE.dirt)
		_outline_rect(img, Rect2i(i * 8, 6, 8, 10), PALETTE.outline)
	for i in range(3):
		img.fill_rect(Rect2i(4 + i * 8, 0, 8, 8), PALETTE.dirt)
		_outline_rect(img, Rect2i(4 + i * 8, 0, 8, 8), PALETTE.outline)
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
	img.fill_rect(Rect2i(2, 4, 20, 4), PALETTE.wood)
	img.fill_rect(Rect2i(2, 12, 20, 4), PALETTE.wood)
	img.fill_rect(Rect2i(2, 20, 20, 4), PALETTE.wood)
	return img

func _draw_bed() -> Image:
	var img := _new_image(28, 18)
	img.fill_rect(Rect2i(0, 0, 28, 18), PALETTE.wood_dark)
	_outline_rect(img, Rect2i(0, 0, 28, 18), PALETTE.outline)
	img.fill_rect(Rect2i(2, 2, 24, 12), PALETTE.player_shirt)
	img.fill_rect(Rect2i(2, 2, 6, 6), PALETTE.sidewalk_light)
	return img

func _draw_guard_post() -> Image:
	var img := _new_image(30, 20)
	for i in range(3):
		img.fill_rect(Rect2i(i * 10, 8, 10, 12), PALETTE.dirt)
		_outline_rect(img, Rect2i(i * 10, 8, 10, 12), PALETTE.outline)
	img.fill_rect(Rect2i(4, 0, 4, 10), PALETTE.wood)
	img.fill_rect(Rect2i(22, 0, 4, 10), PALETTE.wood)
	return img

func _draw_loot_bag() -> Image:
	var img := _new_image(18, 14)
	img.fill_rect(Rect2i(2, 4, 14, 10), PALETTE.wood_dark)
	_outline_rect(img, Rect2i(2, 4, 14, 10), PALETTE.outline)
	img.fill_rect(Rect2i(6, 0, 6, 6), PALETTE.wood_dark)
	return img

func _draw_loot_food() -> Image:
	var img := _new_image(20, 16)
	img.fill_rect(Rect2i(1, 4, 18, 12), PALETTE.food)
	_outline_rect(img, Rect2i(1, 4, 18, 12), PALETTE.outline)
	img.fill_rect(Rect2i(1, 4, 18, 3), PALETTE.wood)
	return img

func _draw_loot_water() -> Image:
	var img := _new_image(20, 16)
	img.fill_rect(Rect2i(2, 2, 16, 12), PALETTE.wood)
	_outline_rect(img, Rect2i(2, 2, 16, 12), PALETTE.outline)
	img.fill_rect(Rect2i(4, 4, 4, 8), PALETTE.water)
	img.fill_rect(Rect2i(10, 4, 4, 8), PALETTE.water)
	return img

func _draw_loot_materials() -> Image:
	var img := _new_image(20, 16)
	var rng := _rng_for("loot_materials")
	for i in range(5):
		var w := rng.randi_range(6, 10)
		var h := rng.randi_range(4, 7)
		var x := rng.randi_range(0, 20 - w)
		var y := rng.randi_range(4, 16 - h)
		img.fill_rect(Rect2i(x, y, w, h), PALETTE.materials)
		_outline_rect(img, Rect2i(x, y, w, h), PALETTE.outline)
	return img

func _draw_loot_medical() -> Image:
	var img := _new_image(20, 16)
	img.fill_rect(Rect2i(2, 2, 16, 12), PALETTE.sidewalk_light)
	_outline_rect(img, Rect2i(2, 2, 16, 12), PALETTE.outline)
	img.fill_rect(Rect2i(8, 5, 4, 6), PALETTE.medical)
	img.fill_rect(Rect2i(6, 7, 8, 2), PALETTE.medical)
	return img

# ---------------------------------------------------------------------------
# Section 1: actor atlases
# ---------------------------------------------------------------------------

func _generate_actor_atlases() -> void:
	_generate_player_atlas()
	_generate_survivor_atlas()
	_generate_zombie_atlas()
	_save(_draw_shadow(), PixelAtlasMap.SHADOW_PATH)

func _draw_humanoid(img: Image, origin: Vector2i, skin: Color, shirt: Color, pants: Color, walk_frame: bool, zombie: bool) -> void:
	var bob: int = 1 if walk_frame else 0
	var limb_color: Color = skin if zombie else shirt
	img.fill_rect(Rect2i(origin + Vector2i(11, 28 + bob), Vector2i(4, 10)), pants)
	img.fill_rect(Rect2i(origin + Vector2i(17, 28 + bob), Vector2i(4, 10)), pants)
	img.fill_rect(Rect2i(origin + Vector2i(9, 16 + bob), Vector2i(14, 14)), shirt)
	img.fill_rect(Rect2i(origin + Vector2i(6, 18 + bob), Vector2i(4, 12)), limb_color)
	img.fill_rect(Rect2i(origin + Vector2i(22, 18 + bob), Vector2i(4, 12)), limb_color)
	img.fill_rect(Rect2i(origin + Vector2i(10, 4 + bob), Vector2i(12, 12)), skin)
	_outline_rect(img, Rect2i(origin + Vector2i(9, 16 + bob), Vector2i(14, 14)), PALETTE.outline)
	_outline_rect(img, Rect2i(origin + Vector2i(10, 4 + bob), Vector2i(12, 12)), PALETTE.outline)
	_outline_rect(img, Rect2i(origin + Vector2i(11, 28 + bob), Vector2i(4, 10)), PALETTE.outline)
	_outline_rect(img, Rect2i(origin + Vector2i(17, 28 + bob), Vector2i(4, 10)), PALETTE.outline)
	if zombie:
		img.fill_rect(Rect2i(origin + Vector2i(13, 22 + bob), Vector2i(6, 4)), PALETTE.zombie_skin_dark)

func _generate_player_atlas() -> void:
	var fs: Vector2i = PixelAtlasMap.ACTOR_FRAME_SIZE
	var img := _new_image(fs.x * 2, fs.y * PixelAtlasMap.PLAYER_VARIANT_COUNT)
	_draw_humanoid(img, Vector2i(0, 0), PALETTE.player_skin, PALETTE.player_shirt, PALETTE.player_pants, false, false)
	_draw_humanoid(img, Vector2i(fs.x, 0), PALETTE.player_skin, PALETTE.player_shirt, PALETTE.player_pants, true, false)
	_save(img, PixelAtlasMap.PLAYER_ATLAS_PATH)

func _generate_survivor_atlas() -> void:
	var fs: Vector2i = PixelAtlasMap.ACTOR_FRAME_SIZE
	var img := _new_image(fs.x * 2, fs.y * PixelAtlasMap.SURVIVOR_VARIANT_COUNT)
	for v in range(PixelAtlasMap.SURVIVOR_VARIANT_COUNT):
		var shirt: Color = SURVIVOR_SHIRTS[v % SURVIVOR_SHIRTS.size()]
		_draw_humanoid(img, Vector2i(0, v * fs.y), PALETTE.survivor_skin, shirt, PALETTE.player_pants, false, false)
		_draw_humanoid(img, Vector2i(fs.x, v * fs.y), PALETTE.survivor_skin, shirt, PALETTE.player_pants, true, false)
	_save(img, PixelAtlasMap.SURVIVOR_ATLAS_PATH)

func _generate_zombie_atlas() -> void:
	var fs: Vector2i = PixelAtlasMap.ACTOR_FRAME_SIZE
	var img := _new_image(fs.x * 2, fs.y * PixelAtlasMap.ZOMBIE_VARIANT_COUNT)
	for v in range(PixelAtlasMap.ZOMBIE_VARIANT_COUNT):
		var skin: Color = ZOMBIE_TINTS[v % ZOMBIE_TINTS.size()]
		_draw_humanoid(img, Vector2i(0, v * fs.y), skin, PALETTE.zombie_clothes, PALETTE.zombie_clothes, false, true)
		_draw_humanoid(img, Vector2i(fs.x, v * fs.y), skin, PALETTE.zombie_clothes, PALETTE.zombie_clothes, true, true)
	_save(img, PixelAtlasMap.ZOMBIE_ATLAS_PATH)

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
