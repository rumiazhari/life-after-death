class_name DistrictBuilder
extends Node2D
## Builds the ONE fixed, authored urban district (Phase 3B, fully
## re-authored as a designed city in Phase 3C). Every street, block,
## building, and prop position below is a literal authored coordinate --
## there is no chance-based skip, no random block grid, and the only RNG
## touched anywhere in this file is _visual_rng for pure tile-variant noise
## (which asphalt/sidewalk/grass cell gets which of several equally-valid
## texture variants) that never affects position, collision, or which prop
## exists. Running this twice produces the identical world -- see
## scripts/world/district_layout_checksum.gd and tests/test_runner.gd's
## fixed-map tests, which assert exactly that.
##
## THE CITY (see docs/urban_map_design.md for the annotated map):
## a 5x5 street grid -- two 192px arterials crossing at the origin (Grand
## Avenue east-west, Market Street north-south), four 128px secondary
## streets (Ash/Kiln east-west, Civic/Foundry north-south), and a 128px
## ring road on all four sides -- carving the district into SIXTEEN named
## city blocks. Every block is authored as a whole: its ground surface, its
## sidewalk frontage, the row of buildings that fills it, its mid-block
## alley or yard, and its street furniture. Blocks are zoned -- safehouse
## compound, two residential quarters, a civic square, a four-block
## downtown core, a public park, a market plaza, and an industrial east
## side -- so the district reads as a place, not as scattered boxes on a
## field.
##
## ArenaBuilder (scripts/world/arena_builder.gd) is preserved unused by
## Main.tscn as an optional random-layout test/performance scene -- see
## docs/urban_map_design.md "Why the main map is now fixed and authored."

const TS: int = PixelAtlasMap.TILE_SIZE
const WORLD_LAYER := 1

@export var arena_half_size: Vector2 = Vector2(1400, 1400)
@export var boundary_thickness: float = 40.0

var _ground_layer: TileMapLayer
var _roads_layer: TileMapLayer
var _sidewalks_layer: TileMapLayer
var _markings_layer: TileMapLayer
var _visual_rng := RandomNumberGenerator.new()
## Cell -> true for every tile covered by a ROADS rect, filled once by
## _index_road_cells() and read by the sidewalk/marking/prop passes so
## "is this cell street?" is one dictionary probe instead of a rect scan.
var _road_cells: Dictionary = {}

# --- Prop texture paths -------------------------------------------------
# Paths, not preload()ed Texture2D handles, because DistrictLayoutChecksum
# stringifies these very arrays: a Texture2D stringifies to a per-run
# object id, which would make the "did the map change?" checksum differ on
# every single run and detect nothing.
const TEX_BENCH := "res://assets/pixel/props/bench.png"
const TEX_CAR_SEDAN := "res://assets/pixel/props/car_sedan.png"
const TEX_CAR_WRECK := "res://assets/pixel/props/car_wreck.png"
const TEX_CHAIR := "res://assets/pixel/props/chair.png"
const TEX_CONE := "res://assets/pixel/props/cone.png"
const TEX_CRATE := "res://assets/pixel/props/crate.png"
const TEX_DEBRIS := "res://assets/pixel/props/debris_small.png"
const TEX_DRAIN := "res://assets/pixel/props/drain_cover.png"
const TEX_DUMPSTER := "res://assets/pixel/props/dumpster.png"
const TEX_HYDRANT := "res://assets/pixel/props/hydrant.png"
const TEX_PALLET := "res://assets/pixel/props/pallet.png"
const TEX_PLANTER := "res://assets/pixel/props/planter.png"
const TEX_ROAD_BARRIER := "res://assets/pixel/props/road_barrier.png"
const TEX_SANDBAGS := "res://assets/pixel/props/sandbags.png"
const TEX_STREET_LAMP := "res://assets/pixel/props/street_lamp.png"
const TEX_STREET_SIGN := "res://assets/pixel/props/street_sign.png"
const TEX_TABLE := "res://assets/pixel/props/table.png"
const TEX_TRASH_BAG := "res://assets/pixel/props/trash_bag.png"
const TEX_TREE := "res://assets/pixel/props/tree.png"
const TEX_UTILITY_BOX := "res://assets/pixel/props/utility_box.png"

# --- The street grid ----------------------------------------------------
## Every street the district has. `size.x > size.y` means an east-west
## street, otherwise north-south -- the same world-space convention
## ArenaBuilder's road strips used. Widths and centers are all multiples of
## 32 so every carriageway edge lands exactly on a tile boundary and the
## curb/sidewalk ring around each block paints without a ragged half-tile
## seam anywhere in the district.
const ROADS := [
	# East-west
	{"name": "North Ring Road", "center": Vector2(0, -1280), "size": Vector2(2800, 128)},
	{"name": "Ash Street", "center": Vector2(0, -672), "size": Vector2(2800, 128)},
	{"name": "Grand Avenue", "center": Vector2(0, 0), "size": Vector2(2800, 192)},
	{"name": "Kiln Street", "center": Vector2(0, 672), "size": Vector2(2800, 128)},
	{"name": "South Ring Road", "center": Vector2(0, 1280), "size": Vector2(2800, 128)},
	# North-south
	{"name": "West Ring Road", "center": Vector2(-1280, 0), "size": Vector2(128, 2800)},
	{"name": "Civic Street", "center": Vector2(-672, 0), "size": Vector2(128, 2800)},
	{"name": "Market Street", "center": Vector2(0, 0), "size": Vector2(192, 2800)},
	{"name": "Foundry Street", "center": Vector2(672, 0), "size": Vector2(128, 2800)},
	{"name": "East Ring Road", "center": Vector2(1280, 0), "size": Vector2(128, 2800)},
]

# --- The sixteen city blocks -------------------------------------------
## One entry per block the street grid encloses. `rect` is the WHOLE block
## (street edge to street edge); its outer 64px (BLOCK_SIDEWALK_DEPTH, two
## tiles) is automatically the curb+sidewalk frontage, and the inset
## remainder -- `buildable_rect()` -- is what the block's buildings, yards
## and alleys sit inside. `surface` is the ground the block is paved with:
## &"concrete" (default city ground), &"grass" (the park), &"dirt" (yards),
## &"cracked_ground" (the derelict lot), or &"plaza", which paves the whole
## interior in sidewalk instead of leaving bare ground.
const BLOCK_SIDEWALK_DEPTH := 64.0
const BLOCKS := [
	{"name": "Safehouse Compound", "rect": Rect2(-1216, -1216, 480, 480), "surface": &"dirt"},
	{"name": "Ash Row", "rect": Rect2(-608, -1216, 512, 480), "surface": &"concrete"},
	{"name": "Ash Terrace", "rect": Rect2(96, -1216, 512, 480), "surface": &"concrete"},
	{"name": "Foundry Works", "rect": Rect2(736, -1216, 480, 480), "surface": &"concrete"},
	{"name": "Civic Square", "rect": Rect2(-1216, -608, 480, 512), "surface": &"concrete"},
	{"name": "Market Block NW", "rect": Rect2(-608, -608, 512, 512), "surface": &"concrete"},
	{"name": "Market Block NE", "rect": Rect2(96, -608, 512, 512), "surface": &"concrete"},
	{"name": "Depot Yard", "rect": Rect2(736, -608, 480, 512), "surface": &"concrete"},
	{"name": "Willow Green", "rect": Rect2(-1216, 96, 480, 512), "surface": &"grass"},
	{"name": "Market Block SW", "rect": Rect2(-608, 96, 512, 512), "surface": &"concrete"},
	{"name": "Market Plaza", "rect": Rect2(96, 96, 512, 512), "surface": &"plaza"},
	{"name": "Storage Yard", "rect": Rect2(736, 96, 480, 512), "surface": &"concrete"},
	{"name": "Kiln Row", "rect": Rect2(-1216, 736, 480, 480), "surface": &"concrete"},
	{"name": "South Row", "rect": Rect2(-608, 736, 512, 480), "surface": &"concrete"},
	# Dirt, not cracked_ground: cracked concrete is nearly the same value as
	# the concrete around it, so the block read as "another paved lot" from
	# the camera's height instead of as a cleared, rubble-strewn one.
	{"name": "Derelict Lot", "rect": Rect2(96, 736, 512, 480), "surface": &"dirt"},
	{"name": "South Works", "rect": Rect2(736, 736, 480, 480), "surface": &"concrete"},
]

## Surfaces painted INSIDE a block that differ from the block's own -- the
## back alleys (cracked), the industrial yards (dirt), the civic lawn and
## park paths (grass/dirt). This is what stops a block interior reading as
## one flat slab of concrete between its buildings.
const SURFACE_PATCHES := [
	{"rect": Rect2(-544, -1024, 384, 96), "tile": &"cracked_ground"}, # Ash Row back alley
	{"rect": Rect2(160, -1024, 384, 96), "tile": &"cracked_ground"}, # Ash Terrace mid-block alley
	{"rect": Rect2(800, -960, 352, 160), "tile": &"dirt"}, # Foundry Works loading yard
	{"rect": Rect2(-1152, -416, 352, 96), "tile": &"grass"}, # Civic Square lawn
	{"rect": Rect2(-544, -416, 384, 128), "tile": &"cracked_ground"}, # Market Block NW service alley
	{"rect": Rect2(160, -416, 384, 96), "tile": &"cracked_ground"}, # Market Block NE service alley
	{"rect": Rect2(-1024, 160, 64, 384), "tile": &"dirt"}, # Willow Green north-south path
	{"rect": Rect2(-1152, 320, 352, 64), "tile": &"dirt"}, # Willow Green east-west path
	{"rect": Rect2(-544, 288, 384, 64), "tile": &"cracked_ground"}, # Restaurant service alley
	{"rect": Rect2(800, 352, 352, 192), "tile": &"dirt"}, # Storage Yard
	{"rect": Rect2(-1152, 928, 352, 96), "tile": &"cracked_ground"}, # Kiln Row back alley
	{"rect": Rect2(-544, 928, 384, 96), "tile": &"cracked_ground"}, # South Row back alley
	{"rect": Rect2(800, 992, 352, 32), "tile": &"dirt"}, # South Works yard strip
]

const BUILDING_SCENES := {
	"restaurant_01": "res://scenes/world/buildings/Restaurant01.tscn",
	"convenience_store_01": "res://scenes/world/buildings/ConvenienceStore01.tscn",
	"clinic_01": "res://scenes/world/buildings/Clinic01.tscn",
	"apartment_01": "res://scenes/world/buildings/Apartment01.tscn",
	"workshop_01": "res://scenes/world/buildings/Workshop01.tscn",
}
## The 5 fully-enterable authored buildings, each seated against its own
## block's buildable edge so its front door opens straight onto that
## block's sidewalk instead of into the middle of a yard:
## - restaurant_01 -> Market Block SW, front door onto Kiln Street, rear
##   service door onto the mid-block service alley.
## - convenience_store_01 -> Market Block NE, front door onto Grand Avenue.
## - clinic_01 -> Civic Square, front door onto Grand Avenue.
## - apartment_01 -> Ash Row, lobby door onto Ash Street.
## - workshop_01 -> Foundry Works, public door onto its own loading yard,
##   west loading door onto Foundry Street's sidewalk.
const BUILDING_POSITIONS := {
	"restaurant_01": Vector2(-352, 454),
	"convenience_store_01": Vector2(270, -248),
	"clinic_01": Vector2(-1052, -250),
	"apartment_01": Vector2(-352, -912),
	"workshop_01": Vector2(976, -1062),
}

## The non-enterable "shell" buildings (roof + collision, no interior) that
## do the actual city-filling: rows of them abut into continuous street
## frontage along each block's edge, leaving a deliberate mid-block alley
## or yard behind. Every half_extent is a multiple of the 32px tile so each
## roof paints flush to its own footprint. `roof` picks one of the four
## shared roof materials, assigned per zone -- A brick red (residential),
## B slate (downtown), C tan (civic), D green patina (industrial/derelict).
const SHELL_BUILDINGS := [
	# Ash Row -- terraced houses along the ring road, apartment_01 behind
	{"name": "AshRowHouseA", "position": Vector2(-448, -1088), "half_extent": Vector2(96, 64), "roof": "A"},
	{"name": "AshRowHouseB", "position": Vector2(-256, -1088), "half_extent": Vector2(96, 64), "roof": "A"},
	# Ash Terrace -- two facing rows split by a mid-block alley
	{"name": "AshTerraceNorthA", "position": Vector2(256, -1088), "half_extent": Vector2(96, 64), "roof": "A"},
	{"name": "AshTerraceNorthB", "position": Vector2(448, -1088), "half_extent": Vector2(96, 64), "roof": "A"},
	{"name": "AshTerraceSouthA", "position": Vector2(256, -864), "half_extent": Vector2(96, 64), "roof": "C"},
	{"name": "AshTerraceSouthB", "position": Vector2(448, -864), "half_extent": Vector2(96, 64), "roof": "C"},
	# Civic Square -- library across the north edge, civic hall beside the clinic
	{"name": "CivicLibrary", "position": Vector2(-976, -480), "half_extent": Vector2(176, 64), "roof": "C"},
	{"name": "CivicHall", "position": Vector2(-880, -224), "half_extent": Vector2(64, 64), "roof": "C"},
	# Market Block NW -- six downtown shopfronts, two rows of three
	{"name": "MarketShopNW1", "position": Vector2(-480, -480), "half_extent": Vector2(64, 64), "roof": "B"},
	{"name": "MarketShopNW2", "position": Vector2(-352, -480), "half_extent": Vector2(64, 64), "roof": "B"},
	{"name": "MarketShopNW3", "position": Vector2(-224, -480), "half_extent": Vector2(64, 64), "roof": "B"},
	{"name": "MarketShopSW1", "position": Vector2(-480, -224), "half_extent": Vector2(64, 64), "roof": "B"},
	{"name": "MarketShopSW2", "position": Vector2(-352, -224), "half_extent": Vector2(64, 64), "roof": "D"},
	{"name": "MarketShopSW3", "position": Vector2(-224, -224), "half_extent": Vector2(64, 64), "roof": "B"},
	# Market Block NE -- convenience_store_01 anchors the Grand Avenue corner
	{"name": "MarketShopNE1", "position": Vector2(256, -480), "half_extent": Vector2(96, 64), "roof": "B"},
	{"name": "MarketShopNE2", "position": Vector2(448, -480), "half_extent": Vector2(96, 64), "roof": "B"},
	{"name": "MarketShopSE1", "position": Vector2(480, -224), "half_extent": Vector2(64, 64), "roof": "B"},
	# Depot Yard -- offices fronting Grand Avenue, parking behind
	{"name": "DepotOfficeA", "position": Vector2(896, -224), "half_extent": Vector2(96, 64), "roof": "D"},
	{"name": "DepotOfficeB", "position": Vector2(1088, -224), "half_extent": Vector2(64, 64), "roof": "D"},
	# Market Block SW -- shops facing Grand Avenue, restaurant_01 behind them
	{"name": "KilnShopA", "position": Vector2(-448, 224), "half_extent": Vector2(96, 64), "roof": "B"},
	{"name": "KilnShopB", "position": Vector2(-256, 224), "half_extent": Vector2(96, 64), "roof": "B"},
	# Storage Yard -- one long warehouse, open yard behind it
	{"name": "StorageWarehouse", "position": Vector2(976, 256), "half_extent": Vector2(176, 96), "roof": "D"},
	# Kiln Row -- two facing rows of houses split by a back alley
	{"name": "KilnRowHouseA", "position": Vector2(-1056, 864), "half_extent": Vector2(96, 64), "roof": "A"},
	{"name": "KilnRowHouseB", "position": Vector2(-864, 864), "half_extent": Vector2(64, 64), "roof": "A"},
	{"name": "KilnRowHouseC", "position": Vector2(-1056, 1088), "half_extent": Vector2(96, 64), "roof": "A"},
	{"name": "KilnRowHouseD", "position": Vector2(-864, 1088), "half_extent": Vector2(64, 64), "roof": "A"},
	# South Row -- ditto, mixed roof materials so the two rows aren't twins
	{"name": "SouthRowHouseA", "position": Vector2(-448, 864), "half_extent": Vector2(96, 64), "roof": "A"},
	{"name": "SouthRowHouseB", "position": Vector2(-256, 864), "half_extent": Vector2(96, 64), "roof": "C"},
	{"name": "SouthRowHouseC", "position": Vector2(-448, 1088), "half_extent": Vector2(96, 64), "roof": "C"},
	{"name": "SouthRowHouseD", "position": Vector2(-256, 1088), "half_extent": Vector2(96, 64), "roof": "A"},
	# Derelict Lot -- one gutted tenement in a field of rubble
	{"name": "DerelictTenement", "position": Vector2(416, 928), "half_extent": Vector2(96, 96), "roof": "D"},
	# South Works
	{"name": "SouthWarehouse", "position": Vector2(976, 896), "half_extent": Vector2(176, 96), "roof": "D"},
]

## Asphalt aprons with painted stall lines. No collision -- a parking lot
## is a surface, and the cars standing on it bring their own.
const PARKING_LOTS := [
	{"center": Vector2(976, -448), "size": Vector2(352, 192)}, # Depot Yard
	{"center": Vector2(976, 1088), "size": Vector2(352, 128)}, # South Works
]

## Repeating street furniture laid along a line at a fixed step -- the lamp
## posts and street trees that make an avenue read as an avenue. Each line
## runs along a sidewalk row (never a carriageway); any generated position
## that would land on a street or inside a building footprint is skipped by
## _prop_position_is_clear(), which is why a line may safely span a whole
## side of the district straight across its intersections.
const PROP_LINES = [
	# Grand Avenue: alternating lamps and trees down both sidewalks
	{"from": Vector2(-1088, -144), "to": Vector2(1088, -144), "step": 272.0, "texture": TEX_STREET_LAMP, "size": Vector2(8, 8)},
	{"from": Vector2(-1088, 144), "to": Vector2(1088, 144), "step": 272.0, "texture": TEX_STREET_LAMP, "size": Vector2(8, 8)},
	{"from": Vector2(-952, -144), "to": Vector2(952, -144), "step": 272.0, "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"from": Vector2(-952, 144), "to": Vector2(952, 144), "step": 272.0, "texture": TEX_TREE, "size": Vector2(20, 20)},
	# Market Street
	{"from": Vector2(-144, -1088), "to": Vector2(-144, 1088), "step": 272.0, "texture": TEX_STREET_LAMP, "size": Vector2(8, 8)},
	{"from": Vector2(144, -1088), "to": Vector2(144, 1088), "step": 272.0, "texture": TEX_STREET_LAMP, "size": Vector2(8, 8)},
	{"from": Vector2(-144, -952), "to": Vector2(-144, 952), "step": 272.0, "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"from": Vector2(144, -952), "to": Vector2(144, 952), "step": 272.0, "texture": TEX_TREE, "size": Vector2(20, 20)},
	# Ash Street and Kiln Street
	{"from": Vector2(-1120, -784), "to": Vector2(1120, -784), "step": 320.0, "texture": TEX_STREET_LAMP, "size": Vector2(8, 8)},
	{"from": Vector2(-1120, -560), "to": Vector2(1120, -560), "step": 320.0, "texture": TEX_STREET_LAMP, "size": Vector2(8, 8)},
	{"from": Vector2(-1120, 560), "to": Vector2(1120, 560), "step": 320.0, "texture": TEX_STREET_LAMP, "size": Vector2(8, 8)},
	{"from": Vector2(-1120, 784), "to": Vector2(1120, 784), "step": 320.0, "texture": TEX_STREET_LAMP, "size": Vector2(8, 8)},
	# Civic Street and Foundry Street
	{"from": Vector2(-784, -1120), "to": Vector2(-784, 1120), "step": 320.0, "texture": TEX_STREET_LAMP, "size": Vector2(8, 8)},
	{"from": Vector2(-560, -1120), "to": Vector2(-560, 1120), "step": 320.0, "texture": TEX_STREET_LAMP, "size": Vector2(8, 8)},
	{"from": Vector2(560, -1120), "to": Vector2(560, 1120), "step": 320.0, "texture": TEX_STREET_LAMP, "size": Vector2(8, 8)},
	{"from": Vector2(784, -1120), "to": Vector2(784, 1120), "step": 320.0, "texture": TEX_STREET_LAMP, "size": Vector2(8, 8)},
]

## One-off street furniture, grouped by the block it dresses. Everything
## here is a solid obstacle (it has collision); flat ground detail lives in
## DECALS instead.
const PROPS = [
	# --- Safehouse Compound: a sandbagged checkpoint across the street frontage
	{"position": Vector2(-1088, -752), "texture": TEX_SANDBAGS, "size": Vector2(32, 18)},
	{"position": Vector2(-1024, -752), "texture": TEX_SANDBAGS, "size": Vector2(32, 18)},
	{"position": Vector2(-896, -752), "texture": TEX_SANDBAGS, "size": Vector2(32, 18)},
	{"position": Vector2(-832, -752), "texture": TEX_SANDBAGS, "size": Vector2(32, 18)},
	{"position": Vector2(-1136, -752), "texture": TEX_ROAD_BARRIER, "size": Vector2(36, 16)},
	{"position": Vector2(-784, -752), "texture": TEX_ROAD_BARRIER, "size": Vector2(36, 16)},
	{"position": Vector2(-752, -1088), "texture": TEX_SANDBAGS, "size": Vector2(32, 18)},
	{"position": Vector2(-752, -1024), "texture": TEX_SANDBAGS, "size": Vector2(32, 18)},
	# --- Ash Row: front-garden trees along the terrace
	{"position": Vector2(-520, -784), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-184, -784), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-352, -1010), "texture": TEX_TRASH_BAG, "size": Vector2(12, 10)},
	{"position": Vector2(-300, -980), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	# --- Ash Terrace: mid-block alley clutter
	{"position": Vector2(200, -976), "texture": TEX_TRASH_BAG, "size": Vector2(12, 10)},
	{"position": Vector2(500, -976), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(176, -784), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(528, -784), "texture": TEX_TREE, "size": Vector2(20, 20)},
	# --- Foundry Works: the loading yard behind workshop_01
	{"position": Vector2(840, -880), "texture": TEX_PALLET, "size": Vector2(30, 18)},
	{"position": Vector2(880, -880), "texture": TEX_PALLET, "size": Vector2(30, 18)},
	{"position": Vector2(920, -880), "texture": TEX_PALLET, "size": Vector2(30, 18)},
	{"position": Vector2(1000, -880), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(1040, -880), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(1000, -840), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(1040, -840), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(1120, -880), "texture": TEX_ROAD_BARRIER, "size": Vector2(36, 16)},
	{"position": Vector2(1120, -816), "texture": TEX_CONE, "size": Vector2(10, 10)},
	# --- Civic Square: benches and planters around the lawn
	{"position": Vector2(-1104, -352), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-832, -352), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-1024, -352), "texture": TEX_BENCH, "size": Vector2(32, 12)},
	{"position": Vector2(-928, -352), "texture": TEX_BENCH, "size": Vector2(32, 12)},
	{"position": Vector2(-976, -390), "texture": TEX_PLANTER, "size": Vector2(24, 16)},
	{"position": Vector2(-976, -318), "texture": TEX_PLANTER, "size": Vector2(24, 16)},
	{"position": Vector2(-1136, -144), "texture": TEX_STREET_SIGN, "size": Vector2(6, 6)},
	{"position": Vector2(-816, -144), "texture": TEX_UTILITY_BOX, "size": Vector2(14, 18)},
	# --- Market Block NW: the downtown back alley
	{"position": Vector2(-300, -352), "texture": TEX_TRASH_BAG, "size": Vector2(12, 10)},
	{"position": Vector2(-240, -352), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(-544, -144), "texture": TEX_HYDRANT, "size": Vector2(10, 10)},
	{"position": Vector2(-176, -144), "texture": TEX_UTILITY_BOX, "size": Vector2(14, 18)},
	# --- Market Block NE
	{"position": Vector2(240, -360), "texture": TEX_TRASH_BAG, "size": Vector2(12, 10)},
	{"position": Vector2(460, -360), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(176, -144), "texture": TEX_HYDRANT, "size": Vector2(10, 10)},
	{"position": Vector2(400, -144), "texture": TEX_BENCH, "size": Vector2(32, 12)},
	# --- Depot Yard: the parking apron
	{"position": Vector2(1000, -500), "texture": TEX_CAR_SEDAN, "size": Vector2(24, 44)},
	{"position": Vector2(1080, -500), "texture": TEX_CAR_SEDAN, "size": Vector2(24, 44)},
	{"position": Vector2(816, -368), "texture": TEX_CONE, "size": Vector2(10, 10)},
	{"position": Vector2(1136, -368), "texture": TEX_ROAD_BARRIER, "size": Vector2(36, 16)},
	# --- Willow Green: the park
	{"position": Vector2(-1120, 200), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-1056, 200), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-880, 200), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-816, 200), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-1120, 264), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-816, 264), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-1120, 440), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-816, 440), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-1120, 504), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-1056, 504), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-880, 504), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-816, 504), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-1100, 300), "texture": TEX_BENCH, "size": Vector2(32, 12)},
	{"position": Vector2(-900, 300), "texture": TEX_BENCH, "size": Vector2(32, 12)},
	{"position": Vector2(-1100, 404), "texture": TEX_BENCH, "size": Vector2(32, 12)},
	{"position": Vector2(-900, 404), "texture": TEX_BENCH, "size": Vector2(32, 12)},
	{"position": Vector2(-1040, 300), "texture": TEX_PLANTER, "size": Vector2(24, 16)},
	{"position": Vector2(-944, 300), "texture": TEX_PLANTER, "size": Vector2(24, 16)},
	{"position": Vector2(-1040, 404), "texture": TEX_PLANTER, "size": Vector2(24, 16)},
	{"position": Vector2(-944, 404), "texture": TEX_PLANTER, "size": Vector2(24, 16)},
	# --- Market Block SW: restaurant_01's street patio and service alley
	{"position": Vector2(-508, 400), "texture": TEX_TABLE, "size": Vector2(32, 20)},
	{"position": Vector2(-508, 490), "texture": TEX_TABLE, "size": Vector2(32, 20)},
	{"position": Vector2(-532, 432), "texture": TEX_CHAIR, "size": Vector2(14, 16)},
	{"position": Vector2(-484, 432), "texture": TEX_CHAIR, "size": Vector2(14, 16)},
	{"position": Vector2(-532, 522), "texture": TEX_CHAIR, "size": Vector2(14, 16)},
	{"position": Vector2(-484, 522), "texture": TEX_CHAIR, "size": Vector2(14, 16)},
	{"position": Vector2(-390, 326), "texture": TEX_TRASH_BAG, "size": Vector2(12, 10)},
	{"position": Vector2(-200, 326), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(-544, 144), "texture": TEX_HYDRANT, "size": Vector2(10, 10)},
	# --- Market Plaza: the district's town square
	{"position": Vector2(352, 352), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(304, 352), "texture": TEX_PLANTER, "size": Vector2(24, 16)},
	{"position": Vector2(400, 352), "texture": TEX_PLANTER, "size": Vector2(24, 16)},
	{"position": Vector2(352, 304), "texture": TEX_PLANTER, "size": Vector2(24, 16)},
	{"position": Vector2(352, 400), "texture": TEX_PLANTER, "size": Vector2(24, 16)},
	{"position": Vector2(200, 230), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(280, 230), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(424, 230), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(504, 230), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(200, 264), "texture": TEX_PALLET, "size": Vector2(30, 18)},
	{"position": Vector2(280, 264), "texture": TEX_PALLET, "size": Vector2(30, 18)},
	{"position": Vector2(424, 264), "texture": TEX_PALLET, "size": Vector2(30, 18)},
	{"position": Vector2(504, 264), "texture": TEX_PALLET, "size": Vector2(30, 18)},
	{"position": Vector2(200, 474), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(280, 474), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(424, 474), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(504, 474), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(176, 352), "texture": TEX_BENCH, "size": Vector2(32, 12)},
	{"position": Vector2(528, 352), "texture": TEX_BENCH, "size": Vector2(32, 12)},
	{"position": Vector2(176, 176), "texture": TEX_STREET_LAMP, "size": Vector2(8, 8)},
	{"position": Vector2(528, 176), "texture": TEX_STREET_LAMP, "size": Vector2(8, 8)},
	{"position": Vector2(176, 528), "texture": TEX_STREET_LAMP, "size": Vector2(8, 8)},
	{"position": Vector2(528, 528), "texture": TEX_STREET_LAMP, "size": Vector2(8, 8)},
	{"position": Vector2(352, 168), "texture": TEX_STREET_SIGN, "size": Vector2(6, 6)},
	# --- Storage Yard
	{"position": Vector2(840, 420), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(880, 420), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(840, 460), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(880, 460), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(960, 420), "texture": TEX_PALLET, "size": Vector2(30, 18)},
	{"position": Vector2(1000, 420), "texture": TEX_PALLET, "size": Vector2(30, 18)},
	{"position": Vector2(1136, 384), "texture": TEX_ROAD_BARRIER, "size": Vector2(36, 16)},
	# --- Kiln Row / South Row: back alleys and front gardens
	{"position": Vector2(-1120, 976), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(-840, 976), "texture": TEX_TRASH_BAG, "size": Vector2(12, 10)},
	{"position": Vector2(-1136, 784), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-816, 784), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-520, 976), "texture": TEX_TRASH_BAG, "size": Vector2(12, 10)},
	{"position": Vector2(-184, 976), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(-528, 784), "texture": TEX_TREE, "size": Vector2(20, 20)},
	{"position": Vector2(-176, 784), "texture": TEX_TREE, "size": Vector2(20, 20)},
	# --- Derelict Lot
	{"position": Vector2(200, 820), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	{"position": Vector2(180, 1120), "texture": TEX_ROAD_BARRIER, "size": Vector2(36, 16)},
	{"position": Vector2(300, 1120), "texture": TEX_CONE, "size": Vector2(10, 10)},
	{"position": Vector2(528, 1088), "texture": TEX_CRATE, "size": Vector2(22, 22)},
	# --- South Works
	{"position": Vector2(840, 1088), "texture": TEX_CAR_SEDAN, "size": Vector2(24, 44)},
	{"position": Vector2(920, 1088), "texture": TEX_CAR_SEDAN, "size": Vector2(24, 44)},
	{"position": Vector2(1136, 1040), "texture": TEX_CONE, "size": Vector2(10, 10)},
	{"position": Vector2(1000, 1140), "texture": TEX_ROAD_BARRIER, "size": Vector2(36, 16)},
	# --- Cars abandoned in the carriageway (cover on the open arterials)
	{"position": Vector2(-900, 48), "texture": TEX_CAR_SEDAN, "size": Vector2(24, 44)},
	{"position": Vector2(760, -48), "texture": TEX_CAR_SEDAN, "size": Vector2(24, 44)},
	{"position": Vector2(-48, -500), "texture": TEX_CAR_SEDAN, "size": Vector2(24, 44)},
	{"position": Vector2(48, 700), "texture": TEX_CAR_SEDAN, "size": Vector2(24, 44)},
]

## Flat ground detail -- sprite only, no collision, no interaction. These
## exist purely so the asphalt and the rubble lots aren't uniform texture.
const DECALS = [
	{"position": Vector2(-620, -400), "texture": TEX_DRAIN},
	{"position": Vector2(620, 400), "texture": TEX_DRAIN},
	{"position": Vector2(-400, -620), "texture": TEX_DRAIN},
	{"position": Vector2(400, 620), "texture": TEX_DRAIN},
	{"position": Vector2(-1230, -400), "texture": TEX_DRAIN},
	{"position": Vector2(1230, 400), "texture": TEX_DRAIN},
	{"position": Vector2(200, 850), "texture": TEX_DEBRIS},
	{"position": Vector2(230, 890), "texture": TEX_DEBRIS},
	{"position": Vector2(190, 960), "texture": TEX_DEBRIS},
	{"position": Vector2(270, 1080), "texture": TEX_DEBRIS},
	{"position": Vector2(360, 1090), "texture": TEX_DEBRIS},
	{"position": Vector2(460, 1070), "texture": TEX_DEBRIS},
	{"position": Vector2(530, 880), "texture": TEX_DEBRIS},
	{"position": Vector2(540, 960), "texture": TEX_DEBRIS},
	{"position": Vector2(-460, -352), "texture": TEX_DEBRIS},
	{"position": Vector2(320, -976), "texture": TEX_DEBRIS},
	{"position": Vector2(-1000, 976), "texture": TEX_DEBRIS},
	{"position": Vector2(1080, 460), "texture": TEX_DEBRIS},
]

## Searchable street furniture. Y-sorted against actors, so these are built
## into the "entity_container" group's node, not $StreetProps -- see
## scripts/world/authored_district.gd.
const LOOT_PROPS = [
	{"position": Vector2(-500, -352), "texture": TEX_DUMPSTER, "size": Vector2(36, 24), "prop_id": &"street/dumpster_market_nw", "capacity": 60.0, "items": {"materials": 3}},
	{"position": Vector2(350, -360), "texture": TEX_DUMPSTER, "size": Vector2(36, 24), "prop_id": &"street/dumpster_market_ne", "capacity": 60.0, "items": {"materials": 2, "food_ration": 1}},
	{"position": Vector2(-290, 326), "texture": TEX_DUMPSTER, "size": Vector2(36, 24), "prop_id": &"street/dumpster_service_alley", "capacity": 60.0, "items": {"materials": 3, "food_ration": 2}},
	{"position": Vector2(-352, -48), "texture": TEX_CAR_SEDAN, "size": Vector2(24, 44), "prop_id": &"street/car_grand_avenue", "capacity": 80.0, "items": {"materials": 2}},
	{"position": Vector2(840, -500), "texture": TEX_CAR_SEDAN, "size": Vector2(24, 44), "prop_id": &"street/car_depot_lot", "capacity": 80.0, "items": {"materials": 2, "medical_supplies": 1}},
]

## Salvage-only wrecks (one-time materials yield, no inventory). Also
## Y-sorted, so also built into the entity container.
const SALVAGE_PROPS = [
	{"position": Vector2(500, 48), "texture": TEX_CAR_WRECK, "size": Vector2(24, 44), "prop_id": &"street/wreck_grand_avenue", "yield": 4},
	{"position": Vector2(1120, -830), "texture": TEX_CAR_WRECK, "size": Vector2(24, 44), "prop_id": &"street/wreck_foundry_yard", "yield": 4},
	{"position": Vector2(1100, 470), "texture": TEX_CAR_WRECK, "size": Vector2(24, 44), "prop_id": &"street/wreck_storage_yard", "yield": 3},
	{"position": Vector2(240, 980), "texture": TEX_CAR_WRECK, "size": Vector2(24, 44), "prop_id": &"street/wreck_derelict_lot", "yield": 5},
	{"position": Vector2(920, -500), "texture": TEX_CAR_WRECK, "size": Vector2(24, 44), "prop_id": &"street/wreck_depot_lot", "yield": 3},
]

## Fixed spawn regions -- {id, position, radius, category}. Never inside
## the safehouse, never inside a building footprint: the four map-edge
## regions sit on the ring road, the alley regions sit in the middle of an
## authored mid-block alley, and the concealed regions sit in the park, the
## storage yard and the derelict lot.
const SPAWN_REGIONS := [
	{"id": &"edge_north", "position": Vector2(0, -1280), "radius": 150.0, "category": &"map_edge"},
	{"id": &"edge_south", "position": Vector2(0, 1280), "radius": 150.0, "category": &"map_edge"},
	{"id": &"edge_east", "position": Vector2(1280, 0), "radius": 150.0, "category": &"map_edge"},
	{"id": &"edge_west", "position": Vector2(-1280, 0), "radius": 150.0, "category": &"map_edge"},
	{"id": &"edge_northeast", "position": Vector2(1280, -1280), "radius": 140.0, "category": &"map_edge"},
	{"id": &"edge_southwest", "position": Vector2(-1280, 1280), "radius": 140.0, "category": &"map_edge"},
	{"id": &"alley_downtown", "position": Vector2(-352, -352), "radius": 60.0, "category": &"alley"},
	{"id": &"alley_terrace", "position": Vector2(352, -976), "radius": 55.0, "category": &"alley"},
	{"id": &"alley_service", "position": Vector2(-400, 326), "radius": 50.0, "category": &"alley"},
	{"id": &"concealed_park", "position": Vector2(-976, 470), "radius": 90.0, "category": &"concealed"},
	{"id": &"concealed_yard", "position": Vector2(1040, 470), "radius": 70.0, "category": &"concealed"},
	{"id": &"concealed_derelict", "position": Vector2(240, 900), "radius": 80.0, "category": &"concealed"},
]

## Fixed scavenge points -- deterministic identifiers, one per zone so no
## quarter of the city is worth ignoring, positions checked against every
## street/building/shell footprint above.
const SCAVENGE_POINTS := [
	{"name": "PlazaFood", "position": Vector2(250, 460), "item_id": &"food_ration", "yield": 2, "stock": 8, "danger": 15.0},
	{"name": "ParkWater", "position": Vector2(-880, 250), "item_id": &"water_bottle", "yield": 2, "stock": 8, "danger": 15.0},
	{"name": "StorageMaterials", "position": Vector2(860, 450), "item_id": &"materials", "yield": 3, "stock": 12, "danger": 25.0},
	{"name": "DerelictFood", "position": Vector2(240, 1050), "item_id": &"food_ration", "yield": 2, "stock": 6, "danger": 35.0},
	{"name": "CivicMedical", "position": Vector2(-880, -350), "item_id": &"medical_supplies", "yield": 1, "stock": 4, "danger": 40.0},
	{"name": "FoundryMaterials", "position": Vector2(860, -870), "item_id": &"materials", "yield": 3, "stock": 10, "danger": 30.0},
	{"name": "KilnRowWater", "position": Vector2(-976, 976), "item_id": &"water_bottle", "yield": 2, "stock": 6, "danger": 20.0},
	{"name": "DowntownFood", "position": Vector2(-400, -352), "item_id": &"food_ration", "yield": 1, "stock": 5, "danger": 30.0},
]

func _ready() -> void:
	_visual_rng.seed = 0x0D157201
	_build_tile_layers()
	_index_road_cells()
	_paint_ground()
	_paint_roads()
	_paint_parking_lots()
	_paint_sidewalks()
	_paint_markings()
	_build_boundary()
	_build_shell_buildings()
	_build_real_buildings()
	_build_street_props()
	_build_scavenge_points()
	_build_spawn_regions()
	# Newly-added StaticBody2D collision shapes aren't queryable by the
	# physics server until at least one physics step has run -- wait one
	# before building the navigation grid's per-cell solidity from them.
	await get_tree().physics_frame
	UrbanNavigationService.build(arena_half_size)
	_register_doors_with_navigation()

func _register_doors_with_navigation() -> void:
	for door in get_tree().get_nodes_in_group("doors"):
		if door.door_id != &"":
			UrbanNavigationService.register_door(door.door_id, door.global_position)
			if door.is_open:
				UrbanNavigationService.mark_door_open(door.door_id)

func get_arena_size() -> Vector2:
	return arena_half_size * 2.0

## The part of a block its buildings actually occupy: the whole block minus
## the curb+sidewalk frontage ring that wraps it.
static func buildable_rect(block: Dictionary) -> Rect2:
	return (block["rect"] as Rect2).grow(-BLOCK_SIDEWALK_DEPTH)

## World-space footprint of one shell building, so overlap checks (and
## tests) don't each re-derive position +/- half_extent.
static func shell_rect(shell: Dictionary) -> Rect2:
	var half: Vector2 = shell["half_extent"]
	return Rect2((shell["position"] as Vector2) - half, half * 2.0)

static func road_rect(road: Dictionary) -> Rect2:
	var size: Vector2 = road["size"]
	return Rect2((road["center"] as Vector2) - size * 0.5, size)

## Half-extent of one of the 5 enterable buildings, read from that
## building's OWN authored HALF_EXTENT constant rather than restated here,
## so a building whose footprint changes can never silently disagree with
## the district that places it.
static func enterable_half_extent(building_id: String) -> Vector2:
	match building_id:
		"restaurant_01":
			return Restaurant01.HALF_EXTENT
		"convenience_store_01":
			return ConvenienceStore01.HALF_EXTENT
		"clinic_01":
			return Clinic01.HALF_EXTENT
		"apartment_01":
			return Apartment01.HALF_EXTENT
		"workshop_01":
			return Workshop01.HALF_EXTENT
	return Vector2.ZERO

static func enterable_rect(building_id: String) -> Rect2:
	var half: Vector2 = enterable_half_extent(building_id)
	return Rect2((BUILDING_POSITIONS[building_id] as Vector2) - half, half * 2.0)

# --- Tile layers --------------------------------------------------------

func _build_tile_layers() -> void:
	var tileset := PixelTilesetBuilder.get_tileset()
	_ground_layer = _make_layer("Ground", -10, tileset)
	_roads_layer = _make_layer("Roads", -9, tileset)
	_sidewalks_layer = _make_layer("Sidewalks", -8, tileset)
	_markings_layer = _make_layer("RoadMarkings", -7, tileset)

func _make_layer(layer_name: String, z: int, tileset: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tileset
	layer.z_index = z
	$GroundLayers.add_child(layer)
	return layer

func _tile_min() -> Vector2i:
	return Vector2i(floori(-arena_half_size.x / TS), floori(-arena_half_size.y / TS))

func _tile_max() -> Vector2i:
	return Vector2i(floori((arena_half_size.x - 1.0) / TS), floori((arena_half_size.y - 1.0) / TS))

## Cell range covered by a world rect, as [lo, hi] inclusive tile coords.
func _cells_of(rect: Rect2) -> Array[Vector2i]:
	var bounds: Array[Vector2i] = [
		Vector2i(floori(rect.position.x / TS), floori(rect.position.y / TS)),
		Vector2i(floori((rect.end.x - 1.0) / TS), floori((rect.end.y - 1.0) / TS)),
	]
	return bounds

func _index_road_cells() -> void:
	for road in ROADS:
		var bounds := _cells_of(road_rect(road))
		for gx in range(bounds[0].x, bounds[1].x + 1):
			for gy in range(bounds[0].y, bounds[1].y + 1):
				_road_cells[Vector2i(gx, gy)] = true

func _is_road_cell(cell: Vector2i) -> bool:
	return _road_cells.has(cell)

# --- Ground -------------------------------------------------------------

## Base concrete across the whole district, then each block's own zoned
## surface, then the alley/yard/lawn patches that break those blocks up.
## Painted in that order so a later, smaller rect always wins.
func _paint_ground() -> void:
	var lo := _tile_min()
	var hi := _tile_max()
	for gx in range(lo.x, hi.x + 1):
		for gy in range(lo.y, hi.y + 1):
			PixelTilesetBuilder.paint(_ground_layer, Vector2i(gx, gy), _weathered_concrete())
	for block in BLOCKS:
		var surface: StringName = block["surface"]
		if surface == &"concrete" or surface == &"plaza":
			continue # concrete is already the base; a plaza is paved by _paint_sidewalks()
		_fill_ground(buildable_rect(block), surface)
	for patch in SURFACE_PATCHES:
		_fill_ground(patch["rect"], patch["tile"])

func _fill_ground(rect: Rect2, tile_name: StringName) -> void:
	var bounds := _cells_of(rect)
	for gx in range(bounds[0].x, bounds[1].x + 1):
		for gy in range(bounds[0].y, bounds[1].y + 1):
			PixelTilesetBuilder.paint(_ground_layer, Vector2i(gx, gy), _ground_variant(tile_name))

## Cosmetic-only variation: a small share of concrete cells are cracked and
## a small share of grass cells are worn to dirt, so no zone is a flat
## slab. Never changes what exists or where -- only which of several
## equally-walkable tiles is drawn.
func _ground_variant(tile_name: StringName) -> StringName:
	match tile_name:
		&"concrete":
			return _weathered_concrete()
		&"grass":
			return &"dirt" if _visual_rng.randf() < 0.06 else &"grass"
		&"dirt":
			return &"cracked_ground" if _visual_rng.randf() < 0.10 else &"dirt"
		&"cracked_ground":
			# There is exactly one cracked-concrete tile in the atlas, so a
			# rect painted 100% cracked reads as one obviously-repeating
			# squiggle stamped in rows. Alleys are mostly sound concrete
			# with cracks and dirt through them instead.
			var roll: float = _visual_rng.randf()
			if roll < 0.12:
				return &"dirt"
			return &"concrete" if roll < 0.55 else &"cracked_ground"
		_:
			return tile_name

func _weathered_concrete() -> StringName:
	return &"cracked_ground" if _visual_rng.randf() < 0.04 else &"concrete"

# --- Streets ------------------------------------------------------------

func _paint_roads() -> void:
	var names: Array[StringName] = [&"asphalt_0", &"asphalt_1", &"asphalt_2", &"asphalt_3"]
	for road in ROADS:
		var bounds := _cells_of(road_rect(road))
		for gx in range(bounds[0].x, bounds[1].x + 1):
			for gy in range(bounds[0].y, bounds[1].y + 1):
				var pick: StringName = names[_visual_rng.randi_range(0, names.size() - 1)]
				PixelTilesetBuilder.paint(_roads_layer, Vector2i(gx, gy), pick)

func _paint_parking_lots() -> void:
	for lot in PARKING_LOTS:
		var rect := Rect2((lot["center"] as Vector2) - (lot["size"] as Vector2) * 0.5, lot["size"])
		var bounds := _cells_of(rect)
		for gx in range(bounds[0].x, bounds[1].x + 1):
			for gy in range(bounds[0].y, bounds[1].y + 1):
				PixelTilesetBuilder.paint(_roads_layer, Vector2i(gx, gy), &"asphalt_2")
		for gx in range(bounds[0].x + 1, bounds[1].x, 3):
			for gy in range(bounds[0].y + 1, bounds[1].y):
				PixelTilesetBuilder.paint(_markings_layer, Vector2i(gx, gy), &"road_solid_v")

## One rule paints every curb and sidewalk in the district: any cell that
## is neither carriageway nor block interior is pedestrian ground, and it
## gets a curb face on whichever side(s) a street actually touches it (a
## corner curb where two do), otherwise plain sidewalk. Deriving the curb
## from the street grid instead of from each road's own extent is what
## keeps sidewalks from being painted straight across an intersection --
## the bug the old per-road sidewalk pass had wherever two roads met.
func _paint_sidewalks() -> void:
	var lo := _tile_min()
	var hi := _tile_max()
	for gx in range(lo.x, hi.x + 1):
		for gy in range(lo.y, hi.y + 1):
			var cell := Vector2i(gx, gy)
			if _is_road_cell(cell):
				continue
			if _is_block_interior_cell(cell):
				continue
			PixelTilesetBuilder.paint(_sidewalks_layer, cell, _frontage_tile(cell))
	# A plaza block is paved edge to edge rather than left as bare ground.
	for block in BLOCKS:
		if block["surface"] != &"plaza":
			continue
		var bounds := _cells_of(buildable_rect(block))
		for gx in range(bounds[0].x, bounds[1].x + 1):
			for gy in range(bounds[0].y, bounds[1].y + 1):
				PixelTilesetBuilder.paint(_sidewalks_layer, Vector2i(gx, gy), _sidewalk_variant())

func _frontage_tile(cell: Vector2i) -> StringName:
	var north := _is_road_cell(cell + Vector2i(0, -1))
	var south := _is_road_cell(cell + Vector2i(0, 1))
	var west := _is_road_cell(cell + Vector2i(-1, 0))
	var east := _is_road_cell(cell + Vector2i(1, 0))
	if north and west:
		return &"curb_corner_tl"
	if north and east:
		return &"curb_corner_tr"
	if south and west:
		return &"curb_corner_bl"
	if south and east:
		return &"curb_corner_br"
	if north:
		return &"curb_top"
	if south:
		return &"curb_bottom"
	if west:
		return &"curb_left"
	if east:
		return &"curb_right"
	return _sidewalk_variant()

func _is_block_interior_cell(cell: Vector2i) -> bool:
	var center := Vector2(cell.x * TS + TS * 0.5, cell.y * TS + TS * 0.5)
	for block in BLOCKS:
		if buildable_rect(block).has_point(center):
			return true
	return false

func _sidewalk_variant() -> StringName:
	return &"sidewalk_0" if _visual_rng.randf() < 0.5 else &"sidewalk_1"

## Centre lines down every street plus a zebra crossing on each approach to
## every one of the grid's 25 intersections. Lane markings stop at the
## intersection mouth (a centre line painted straight through a junction is
## the single most obviously-wrong thing a top-down city can do).
func _paint_markings() -> void:
	for road in ROADS:
		_paint_lane_lines(road)
	for h_road in ROADS:
		if not _is_horizontal(h_road):
			continue
		for v_road in ROADS:
			if _is_horizontal(v_road):
				continue
			_paint_crossings(h_road, v_road)

func _is_horizontal(road: Dictionary) -> bool:
	var size: Vector2 = road["size"]
	return size.x > size.y

## Dashed centre line, plus a solid lane divider either side of it on the
## two wide arterials (which are six lanes across and would otherwise read
## as an empty runway).
func _paint_lane_lines(road: Dictionary) -> void:
	var size: Vector2 = road["size"]
	var horizontal := _is_horizontal(road)
	var width: float = size.y if horizontal else size.x
	var bounds := _cells_of(road_rect(road))
	_paint_lane_line(road, 0.0, &"road_dash_h" if horizontal else &"road_dash_v", bounds)
	if width >= 192.0:
		var lane_tile: StringName = &"road_solid_h" if horizontal else &"road_solid_v"
		for offset in [-64.0, 64.0]:
			_paint_lane_line(road, offset, lane_tile, bounds)

func _paint_lane_line(road: Dictionary, offset: float, tile_name: StringName, bounds: Array[Vector2i]) -> void:
	var center: Vector2 = road["center"]
	if _is_horizontal(road):
		var row := floori((center.y + offset) / TS)
		for gx in range(bounds[0].x, bounds[1].x + 1):
			if _is_junction_cell(Vector2i(gx, row), road):
				continue
			PixelTilesetBuilder.paint(_markings_layer, Vector2i(gx, row), tile_name)
	else:
		var col := floori((center.x + offset) / TS)
		for gy in range(bounds[0].y, bounds[1].y + 1):
			if _is_junction_cell(Vector2i(col, gy), road):
				continue
			PixelTilesetBuilder.paint(_markings_layer, Vector2i(col, gy), tile_name)

## True when this cell of `road` is also covered by some OTHER road -- i.e.
## it's inside a junction, where lane markings must stop.
func _is_junction_cell(cell: Vector2i, road: Dictionary) -> bool:
	var center := Vector2(cell.x * TS + TS * 0.5, cell.y * TS + TS * 0.5)
	for other in ROADS:
		if other["name"] == road["name"]:
			continue # every street's name is unique, so this is identity
		if road_rect(other).has_point(center):
			return true
	return false

## The four zebra crossings of one intersection: each is a one-tile-deep
## band laid across a carriageway, immediately outside the junction box.
func _paint_crossings(h_road: Dictionary, v_road: Dictionary) -> void:
	var h_rect := road_rect(h_road)
	var v_rect := road_rect(v_road)
	if not h_rect.intersects(v_rect):
		return
	var junction := h_rect.intersection(v_rect)
	var bands: Array[Rect2] = [
		Rect2(junction.position.x, junction.position.y - TS, junction.size.x, TS), # north approach
		Rect2(junction.position.x, junction.end.y, junction.size.x, TS), # south approach
		Rect2(junction.position.x - TS, junction.position.y, TS, junction.size.y), # west approach
		Rect2(junction.end.x, junction.position.y, TS, junction.size.y), # east approach
	]
	for band in bands:
		var bounds := _cells_of(band)
		for gx in range(bounds[0].x, bounds[1].x + 1):
			for gy in range(bounds[0].y, bounds[1].y + 1):
				var cell := Vector2i(gx, gy)
				if not _is_road_cell(cell):
					continue
				PixelTilesetBuilder.paint(_markings_layer, cell, &"crosswalk")

# --- Boundary -----------------------------------------------------------

func _build_boundary() -> void:
	var t: float = boundary_thickness
	var s: Vector2 = arena_half_size
	var walls: Array[Dictionary] = [
		{"center": Vector2(0, -s.y - t * 0.5), "size": Vector2(s.x * 2.0 + t * 2.0, t)},
		{"center": Vector2(0, s.y + t * 0.5), "size": Vector2(s.x * 2.0 + t * 2.0, t)},
		{"center": Vector2(-s.x - t * 0.5, 0), "size": Vector2(t, s.y * 2.0 + t * 2.0)},
		{"center": Vector2(s.x + t * 0.5, 0), "size": Vector2(t, s.y * 2.0 + t * 2.0)},
	]
	for wall_data in walls:
		$Boundaries.add_child(_make_wall(wall_data["center"], wall_data["size"]))

func _make_wall(center: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "BoundaryWall"
	body.position = center
	body.collision_layer = WORLD_LAYER | 32 # World + Vision
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	var visual := ColorRect.new()
	visual.color = Color(0.14, 0.05, 0.05)
	visual.size = size
	visual.position = -size * 0.5
	body.add_child(visual)
	return body

# --- Shell (non-enterable) buildings ------------------------------------

func _build_shell_buildings() -> void:
	for spec in SHELL_BUILDINGS:
		var shell := _make_shell_building(spec["position"], spec["half_extent"], spec["roof"])
		shell.name = spec["name"]
		$Buildings.add_child(shell)

func _make_shell_building(shell_position: Vector2, half: Vector2, roof_letter: String) -> Node2D:
	var root := Node2D.new()
	root.position = shell_position
	var body := StaticBody2D.new()
	body.name = "Building"
	body.collision_layer = WORLD_LAYER | 32
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = half * 2.0
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	root.add_child(body)
	var roof := TileMapLayer.new()
	roof.name = "Roof"
	roof.tile_set = PixelTilesetBuilder.get_tileset()
	roof.z_index = 5
	root.add_child(roof)
	BuildingShellBuilder.paint_roof(roof, half, roof_letter)
	return root

# --- Real enterable buildings -------------------------------------------

func _build_real_buildings() -> void:
	for building_id in BUILDING_POSITIONS:
		var scene: PackedScene = load(BUILDING_SCENES[building_id])
		var instance: Node2D = scene.instantiate()
		instance.position = BUILDING_POSITIONS[building_id]
		$Buildings.add_child(instance)

# --- Street dressing ----------------------------------------------------

func _build_street_props() -> void:
	var dynamic_world: Node = get_tree().get_first_node_in_group("entity_container")
	var props := $StreetProps

	for line in PROP_LINES:
		_place_prop_line(props, line)
	for spec in PROPS:
		BuildingShellBuilder.add_physical_prop(props, spec["position"], load(spec["texture"]), spec["size"])
	for spec in DECALS:
		BuildingShellBuilder.add_decal(props, spec["position"], load(spec["texture"]))

	if dynamic_world == null:
		return
	for spec in LOOT_PROPS:
		BuildingShellBuilder.add_loot_furniture(
			dynamic_world, spec["position"], load(spec["texture"]), spec["size"],
			spec["prop_id"], spec["capacity"], spec["items"]
		)
	for spec in SALVAGE_PROPS:
		BuildingShellBuilder.add_salvage_prop(
			dynamic_world, spec["position"], load(spec["texture"]), spec["size"],
			spec["prop_id"], spec["yield"]
		)

## Walks one PROP_LINES entry from `from` to `to` inclusive, dropping a prop
## every `step` pixels and skipping any position that would sit in a
## carriageway or inside a building -- so a line can be authored as one
## clean sweep down a whole side of the district instead of as a dozen
## hand-clipped segments.
func _place_prop_line(parent: Node2D, line: Dictionary) -> void:
	var from: Vector2 = line["from"]
	var to: Vector2 = line["to"]
	var step: float = line["step"]
	var texture: Texture2D = load(line["texture"])
	var size: Vector2 = line["size"]
	var span: float = from.distance_to(to)
	var count: int = int(round(span / step))
	for i in range(count + 1):
		var point: Vector2 = from.lerp(to, float(i) / float(maxi(count, 1)))
		if not _prop_position_is_clear(point):
			continue
		BuildingShellBuilder.add_physical_prop(parent, point, texture, size)

func _prop_position_is_clear(point: Vector2) -> bool:
	for road in ROADS:
		if road_rect(road).has_point(point):
			return false
	for shell in SHELL_BUILDINGS:
		if shell_rect(shell).grow(16.0).has_point(point):
			return false
	for building_id in BUILDING_POSITIONS:
		if enterable_rect(building_id).grow(16.0).has_point(point):
			return false
	return true

# --- Scavenge points ----------------------------------------------------

func _build_scavenge_points() -> void:
	var dynamic_world: Node = get_tree().get_first_node_in_group("entity_container")
	if dynamic_world == null:
		return
	var scene: PackedScene = load("res://scenes/world/ScavengePoint.tscn")
	for spec in SCAVENGE_POINTS:
		var instance: Node2D = scene.instantiate()
		instance.name = spec["name"]
		instance.item_id = spec["item_id"]
		instance.yield_per_scavenge = spec["yield"]
		instance.remaining_stock = spec["stock"]
		instance.danger = spec["danger"]
		dynamic_world.add_child(instance)
		instance.global_position = spec["position"]

# --- Spawn regions ------------------------------------------------------

func _build_spawn_regions() -> void:
	for spec in SPAWN_REGIONS:
		var marker := SpawnRegion.new()
		marker.name = String(spec["id"])
		marker.region_id = spec["id"]
		marker.radius = spec["radius"]
		marker.category = spec["category"]
		marker.position = spec["position"]
		$SpawnRegions.add_child(marker)
