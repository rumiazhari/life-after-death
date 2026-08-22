class_name SafehouseInteriorBuilder
extends Node2D
## Settlement companion that paints the safehouse floor/perimeter TileMapLayers
## and constructs an aligned explosive-rated physical wall shell with a south
## entrance gap. It never reads or writes Settlement/StorageContainer/
## SleepSpot/GuardPost simulation state.

const TS: int = PixelAtlasMap.TILE_SIZE

@export var half_extent: float = 170.0
@export var entrance_half_width: float = 34.0

var _gatehouse_facade: BuildingFacadeVisual

func _ready() -> void:
	var tileset := PixelTilesetBuilder.get_tileset()

	var floor_layer := TileMapLayer.new()
	floor_layer.name = "FloorLayer"
	floor_layer.tile_set = tileset
	floor_layer.z_index = -8
	add_child(floor_layer)

	var wall_layer := TileMapLayer.new()
	wall_layer.name = "WallLayer"
	wall_layer.tile_set = tileset
	wall_layer.z_index = -6
	add_child(wall_layer)

	_paint_floor(floor_layer)
	_paint_walls(wall_layer)
	# The TileMap remains the authored visual language; matching explosive-
	# rated wall bodies make the safehouse a real interior rather than a
	# painted safe-radius marker. The south gap aligns with Entrance.
	var physical_half_extent := Vector2(224, 224)
	var entrance_gap := Rect2(Vector2(-48, physical_half_extent.y - 32), Vector2(96, 32))
	BuildingShellBuilder.build_perimeter_walls(
		self, physical_half_extent, load("res://assets/pixel/props/wall_concrete.png"), [entrance_gap]
	)
	_build_projected_gatehouse(tileset, physical_half_extent.y)

func _build_projected_gatehouse(tileset: TileSet, south_baseline: float) -> void:
	# The settlement is an open fortified courtyard, not a roof-toggle building.
	# Project only its inhabited entrance lodge so the courtyard remains readable.
	var gate_half_extent := Vector2(96.0, 32.0)
	var projection_height := 64.0
	var roof := TileMapLayer.new()
	roof.name = "GatehouseRoof"
	roof.tile_set = tileset
	roof.position = Vector2(0.0, south_baseline - projection_height - gate_half_extent.y)
	roof.z_index = 5
	add_child(roof)
	BuildingShellBuilder.paint_roof(roof, gate_half_extent, "D")

	_gatehouse_facade = BuildingFacadeVisual.new()
	_gatehouse_facade.name = "ProjectedGatehouseFacade"
	add_child(_gatehouse_facade)
	_gatehouse_facade.configure({
		"facade_spans": [Rect2(Vector2(-gate_half_extent.x, south_baseline), Vector2(gate_half_extent.x * 2.0, 0.0))],
		"facade_style": &"masonry_industrial",
		"archetype": &"workshop",
		"visual_storeys": 2,
		"projection_height": projection_height,
		"anchor_y": south_baseline,
		"entrance_positions": [Vector2(0.0, south_baseline - 16.0)],
		"window_positions": [Vector2(-58.0, south_baseline - 16.0), Vector2(58.0, south_baseline - 16.0)],
		"decoration_seed": 0x5AFE2026,
	})
	var sort_parent := get_tree().get_first_node_in_group("entity_container") as Node2D
	if sort_parent != null:
		_gatehouse_facade.reparent(sort_parent, true)
		_gatehouse_facade.add_to_group("projected_building_facade")

func _exit_tree() -> void:
	if is_instance_valid(_gatehouse_facade) and _gatehouse_facade.get_parent() != self and not _gatehouse_facade.is_queued_for_deletion():
		_gatehouse_facade.queue_free()

func _paint_floor(layer: TileMapLayer) -> void:
	var lo := floori(-half_extent / TS)
	var hi := floori((half_extent - 1.0) / TS)
	for gx in range(lo, hi + 1):
		for gy in range(lo, hi + 1):
			var alt: bool = (gx + gy) % 4 == 0
			PixelTilesetBuilder.paint(layer, Vector2i(gx, gy), &"safehouse_floor_alt" if alt else &"safehouse_floor")

func _paint_walls(layer: TileMapLayer) -> void:
	var lo := floori(-half_extent / TS) - 1
	var hi := floori((half_extent - 1.0) / TS) + 1
	for gx in range(lo, hi + 1):
		_paint_wall_tile(layer, Vector2i(gx, lo), hi)
		_paint_wall_tile(layer, Vector2i(gx, hi), hi)
	for gy in range(lo, hi + 1):
		_paint_wall_tile(layer, Vector2i(lo, gy), hi)
		_paint_wall_tile(layer, Vector2i(hi, gy), hi)

func _paint_wall_tile(layer: TileMapLayer, cell: Vector2i, south_row: int) -> void:
	var world_x: float = (cell.x + 0.5) * TS
	if cell.y == south_row and absf(world_x) < entrance_half_width:
		return # gap for the Entrance
	var reinforced: bool = (cell.x + cell.y) % 5 == 0
	PixelTilesetBuilder.paint(layer, cell, &"safehouse_wall_reinforced" if reinforced else &"safehouse_wall")
