extends Node2D
## Draws a destructible structure as the union of its surviving microcells,
## sampling matching regions of the source texture. Redrawn only when damage
## changes -- never per frame. The visual therefore always corresponds to the
## actual remaining collision geometry.

var _texture: Texture2D
var _grid_origin := Vector2.ZERO
var _cell_size := Vector2(8, 8)
var _cols := 4
var _rows := 4
var _alive: Array = []

func setup(texture: Texture2D, grid_origin: Vector2, cell_size: Vector2, cols: int, rows: int, alive: Array) -> void:
	_texture = texture
	_grid_origin = grid_origin
	_cell_size = cell_size
	_cols = cols
	_rows = rows
	_alive = alive.duplicate()
	queue_redraw()

func set_cells(alive: Array) -> void:
	_alive = alive.duplicate()
	queue_redraw()

func _draw() -> void:
	if _texture == null:
		return
	var tex_size := _texture.get_size()
	for row in range(_rows):
		for col in range(_cols):
			if not _alive[row * _cols + col]:
				continue
			var dst := Rect2(_grid_origin + Vector2(col, row) * _cell_size, _cell_size)
			# Sample the proportional region of the source texture so chips
			# expose texture detail instead of flat color.
			var src_pos := Vector2(col * tex_size.x / _cols, row * tex_size.y / _rows)
			var src_size := tex_size / Vector2(_cols, _rows)
			draw_texture_rect_region(_texture, Rect2(dst.position - dst.size * 0.5, dst.size),
				Rect2(src_pos, src_size))
	# Dark exposed-core outline where cells are missing.
	draw_rect(Rect2(_grid_origin - _cell_size * 0.5, Vector2(_cols, _rows) * _cell_size), Color(0, 0, 0, 0.12), false, 1.0)
