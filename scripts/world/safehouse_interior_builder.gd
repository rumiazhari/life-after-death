class_name SafehouseInteriorBuilder
extends Node2D
## Pure-presentation companion to Settlement: paints the safehouse's floor
## and perimeter-wall TileMapLayers procedurally (so Safehouse.tscn doesn't
## need to hand-author a TileMapLayer's binary tile data by hand) and
## leaves a gap in the south wall for the Entrance node. Never reads or
## writes Settlement/StorageContainer/SleepSpot/GuardPost state -- purely
## visual, same as ArenaBuilder for the outdoor world.

const TS: int = PixelAtlasMap.TILE_SIZE

@export var half_extent: float = 170.0
@export var entrance_half_width: float = 34.0

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
