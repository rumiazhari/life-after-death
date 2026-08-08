class_name PixelTilesetBuilder
extends RefCounted
## Builds (once, cached for the process lifetime) the shared TileSet that
## every TileMapLayer painting the generated environment atlas draws from,
## so ArenaBuilder/Settlement never hand-roll atlas coordinates or
## duplicate TileSet construction -- they look tiles up by name through
## PixelAtlasMap.env_cell() and pass this builder's single source id to
## set_cell().

static var _cached: TileSet = null

static func get_tileset() -> TileSet:
	if _cached:
		return _cached
	var texture: Texture2D = load(PixelAtlasMap.ENV_ATLAS_PATH)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(PixelAtlasMap.TILE_SIZE, PixelAtlasMap.TILE_SIZE)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(PixelAtlasMap.TILE_SIZE, PixelAtlasMap.TILE_SIZE)
	var cells: Vector2i = PixelAtlasMap.env_atlas_size_in_cells()
	for x in range(cells.x):
		for y in range(cells.y):
			source.create_tile(Vector2i(x, y))
	tile_set.add_source(source, 0)
	_cached = tile_set
	return _cached

## Always 0 -- get_tileset() only ever registers one atlas source.
static func source_id() -> int:
	return 0

static func atlas_coords(tile_name: StringName) -> Vector2i:
	return PixelAtlasMap.env_cell(tile_name)

## Convenience wrapper so callers paint by name instead of juggling
## source_id()/atlas_coords() at every call site.
static func paint(layer: TileMapLayer, cell: Vector2i, tile_name: StringName) -> void:
	layer.set_cell(cell, source_id(), atlas_coords(tile_name))
