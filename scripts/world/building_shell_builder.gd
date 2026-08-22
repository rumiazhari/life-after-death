class_name BuildingShellBuilder
extends RefCounted
## Shared renderer used by both generated runtime buildings and retained
## authored fixtures to paint walls, partitions, floors, roofs and functional
## physical furniture without duplicating construction code.
##
## All positions are LOCAL to the building root. Deterministic: no
## randomness at all (a fixed building's wall run is fixed, full stop).

const TS := 32

## Paints a rectangular perimeter wall (given by its outer half-extents)
## out of 32x32 StaticBody2D+Sprite2D segments using `wall_texture`,
## skipping any cell whose center falls inside one of `gaps` (each a
## Rect2 in the same local space -- typically a door or window footprint,
## which supplies its own collision).
static func build_perimeter_walls(parent: Node2D, half_extent: Vector2, wall_texture: Texture2D, gaps: Array[Rect2] = []) -> void:
	var min_x: int = int(round((-half_extent.x) / TS))
	var max_x: int = int(round((half_extent.x) / TS)) - 1
	var min_y: int = int(round((-half_extent.y) / TS))
	var max_y: int = int(round((half_extent.y) / TS)) - 1
	for gx in range(min_x, max_x + 1):
		_maybe_wall(parent, Vector2(gx * TS + TS * 0.5, min_y * TS + TS * 0.5), wall_texture, gaps)
		_maybe_wall(parent, Vector2(gx * TS + TS * 0.5, max_y * TS + TS * 0.5), wall_texture, gaps)
	# Top/bottom runs already created all four corners. Excluding them from
	# the vertical run prevents overlapping wall bodies and duplicate stable
	# destruction IDs at each corner.
	for gy in range(min_y + 1, max_y):
		_maybe_wall(parent, Vector2(min_x * TS + TS * 0.5, gy * TS + TS * 0.5), wall_texture, gaps)
		_maybe_wall(parent, Vector2(max_x * TS + TS * 0.5, gy * TS + TS * 0.5), wall_texture, gaps)

## Builds the outside wall ring for a union of tile-aligned room rectangles.
## Shared edges are deliberately omitted here and are created later as normal
## partitions, which gives an annex its real interior doorway instead of a
## cosmetic second roof attached to a sealed rectangle.
static func build_compound_perimeter_walls(parent: Node2D, rects: Array, wall_texture: Texture2D, gaps: Array[Rect2] = []) -> void:
	var occupied := _occupied_cells(rects)
	for cell_variant in occupied:
		var cell: Vector2i = cell_variant
		if not occupied.has(cell + Vector2i.LEFT) or not occupied.has(cell + Vector2i.RIGHT) or not occupied.has(cell + Vector2i.UP) or not occupied.has(cell + Vector2i.DOWN):
			_maybe_wall(parent, Vector2(cell.x * TS + TS * 0.5, cell.y * TS + TS * 0.5), wall_texture, gaps)

static func _occupied_cells(rects: Array) -> Dictionary:
	var occupied: Dictionary = {}
	for rect_variant in rects:
		var rect: Rect2 = rect_variant
		var min_x := floori(rect.position.x / TS)
		var max_x := ceili(rect.end.x / TS) - 1
		var min_y := floori(rect.position.y / TS)
		var max_y := ceili(rect.end.y / TS) - 1
		for x in range(min_x, max_x + 1):
			for y in range(min_y, max_y + 1):
				occupied[Vector2i(x, y)] = true
	return occupied

## Same idea for a straight interior partition run between two local
## points (must be axis-aligned), used for room-dividing walls.
static func build_partition(parent: Node2D, from: Vector2, to: Vector2, wall_texture: Texture2D, gaps: Array[Rect2] = []) -> void:
	if is_equal_approx(from.y, to.y):
		var x: float = minf(from.x, to.x)
		var end_x: float = maxf(from.x, to.x)
		while x < end_x:
			_maybe_wall(parent, Vector2(x + TS * 0.5, from.y), wall_texture, gaps)
			x += TS
	else:
		var y: float = minf(from.y, to.y)
		var end_y: float = maxf(from.y, to.y)
		while y < end_y:
			_maybe_wall(parent, Vector2(from.x, y + TS * 0.5), wall_texture, gaps)
			y += TS

static func _maybe_wall(parent: Node2D, center: Vector2, wall_texture: Texture2D, gaps: Array[Rect2]) -> void:
	for gap in gaps:
		# Shrink by half a pixel before the containment test: Rect2.has_point
		# includes its left/top EDGES, so a gap rect anchored at
		# center-(16,16) would otherwise ALSO carve a perpendicular wall
		# run whose cells sit exactly on that edge (grid/annex partition
		# lines are offset 16px from the perimeter lattice), punching an
		# open flank the door slab cannot seal.
		if gap.grow(-0.5).has_point(center):
			return
	var body := StaticBody2D.new()
	body.position = center
	body.collision_layer = 1 | 32 # World | Vision
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(TS, TS)
	var collider := CollisionShape2D.new()
	collider.name = "CollisionShape2D" # stable name -- unnamed runtime nodes get "@Class@N" names
	collider.shape = shape
	body.add_child(collider)
	var sprite := Sprite2D.new()
	sprite.texture = wall_texture
	body.add_child(sprite)
	var damage := EnvironmentDamageComponent.new()
	damage.name = "EnvironmentDamageComponent"
	damage.object_id = _derived_object_id(parent, center, &"wall")
	damage.minimum_damage_class = EnvironmentDamage.DamageClass.EXPLOSIVE
	damage.max_durability = 120.0
	damage.affected_size = Vector2(TS, TS)
	damage.destroy_target = body
	body.add_child(damage)
	parent.add_child(body)

## Rooftop fixtures stamped on top of each roof material, keyed by that
## material's letter. In a top-down game the roof is most of what you
## actually look at, so a bare colour slab reads as a placeholder; a water
## tank and ducting is what makes a warehouse look like a warehouse.
## Assigned per material rather than per building so a roof's fixtures
## always match its zone (A residential, B downtown, C civic, D industrial)
## with no extra per-building data to keep in sync.
const ROOF_FIXTURES := {
	"A": [&"roof_vent", &"roof_pipe"],
	"B": [&"roof_sign", &"roof_vent"],
	"C": [&"roof_duct", &"roof_vent"],
	"D": [&"roof_tank", &"roof_duct", &"roof_vent"],
}

## Paints a 9-slice roof (center/edge/corner) across a building's own
## footprint onto a TileMapLayer, in one of the 4 shared roof material
## variants from the environment atlas -- the same tiles/technique
## DistrictBuilder uses for the non-enterable background building shells,
## so a real building's roof matches the district's visual language --
## then stamps that material's rooftop fixtures over it (see
## _paint_roof_fixtures).
static func paint_roof(layer: TileMapLayer, half_extent: Vector2, letter: String) -> void:
	var col_lo := int(floor((-half_extent.x) / TS))
	var col_hi := int(floor((half_extent.x - 1.0) / TS))
	var row_lo := int(floor((-half_extent.y) / TS))
	var row_hi := int(floor((half_extent.y - 1.0) / TS))
	for gx in range(col_lo, col_hi + 1):
		for gy in range(row_lo, row_hi + 1):
			var is_left: bool = gx == col_lo
			var is_right: bool = gx == col_hi
			var is_top: bool = gy == row_lo
			var is_bottom: bool = gy == row_hi
			var part: String
			if is_top and is_left:
				part = "corner_tl"
			elif is_top and is_right:
				part = "corner_tr"
			elif is_bottom and is_left:
				part = "corner_bl"
			elif is_bottom and is_right:
				part = "corner_br"
			elif is_top:
				part = "edge_top"
			elif is_bottom:
				part = "edge_bottom"
			elif is_left:
				part = "edge_left"
			elif is_right:
				part = "edge_right"
			else:
				part = "center"
			PixelTilesetBuilder.paint(layer, Vector2i(gx, gy), StringName("roof%s_%s" % [letter, part]))
	_paint_rect_ridge(layer, Rect2i(Vector2i(col_lo, row_lo), Vector2i(col_hi - col_lo + 1, row_hi - row_lo + 1)), letter)
	_paint_roof_fixtures(layer, letter, col_lo, col_hi, row_lo, row_hi)

## Rasterizes the same roof vocabulary over a compound footprint.  The
## exposed-neighbor test gives L and rear-wing forms real concave/convex roof
## corners without filling the footprint's empty quadrant.
static func paint_compound_roof(layer: TileMapLayer, rects: Array, letter: String) -> void:
	var occupied := _occupied_cells(rects)
	for cell_variant in occupied:
		var cell: Vector2i = cell_variant
		var missing_left := not occupied.has(cell + Vector2i.LEFT)
		var missing_right := not occupied.has(cell + Vector2i.RIGHT)
		var missing_top := not occupied.has(cell + Vector2i.UP)
		var missing_bottom := not occupied.has(cell + Vector2i.DOWN)
		var part: String
		if missing_top and missing_left:
			part = "corner_tl"
		elif missing_top and missing_right:
			part = "corner_tr"
		elif missing_bottom and missing_left:
			part = "corner_bl"
		elif missing_bottom and missing_right:
			part = "corner_br"
		elif missing_top:
			part = "edge_top"
		elif missing_bottom:
			part = "edge_bottom"
		elif missing_left:
			part = "edge_left"
		elif missing_right:
			part = "edge_right"
		else:
			part = "center"
		PixelTilesetBuilder.paint(layer, cell, StringName("roof%s_%s" % [letter, part]))
	for rect_variant in rects:
		var rect: Rect2 = rect_variant
		var cell_rect := Rect2i(
			Vector2i(floori(rect.position.x / TS), floori(rect.position.y / TS)),
			Vector2i(ceili(rect.size.x / TS), ceili(rect.size.y / TS))
		)
		_paint_rect_ridge(layer, cell_rect, letter, occupied)

static func _paint_rect_ridge(layer: TileMapLayer, rect: Rect2i, letter: String, occupied: Dictionary = {}) -> void:
	if rect.size.x < 3 or rect.size.y < 3:
		return
	var horizontal := rect.size.x >= rect.size.y
	if horizontal:
		var row := rect.position.y + int(rect.size.y / 2)
		for x in range(rect.position.x + 1, rect.end.x - 1):
			var cell := Vector2i(x, row)
			if occupied.is_empty() or occupied.has(cell):
				PixelTilesetBuilder.paint(layer, cell, StringName("roof%s_ridge_h" % letter))
	else:
		var column := rect.position.x + int(rect.size.x / 2)
		for y in range(rect.position.y + 1, rect.end.y - 1):
			var cell := Vector2i(column, y)
			if occupied.is_empty() or occupied.has(cell):
				PixelTilesetBuilder.paint(layer, cell, StringName("roof%s_ridge_v" % letter))

## Stamps ROOF_FIXTURES onto a CHILD TileMapLayer of the roof itself, never
## onto the roof layer: the fixture tiles are drawn with transparent
## surrounds so they can sit ON a roof material, and one TileMapLayer only
## holds one tile per cell -- painting them into the roof layer would punch
## a see-through hole in the building instead. Making the fixture layer a
## child is also what keeps BuildingVisibilityController correct for free:
## hiding a building's roof node hides its fixtures with it.
##
## Fixtures land on interior cells only (never the roof's edge/corner ring),
## spread evenly across the roof and staggered between two rows, all from
## integer arithmetic on the footprint -- no randomness, so a given building
## has the same rooftop every run. Roofs smaller than 3x3 tiles have no
## interior and get none.
static func _paint_roof_fixtures(layer: TileMapLayer, letter: String, col_lo: int, col_hi: int, row_lo: int, row_hi: int) -> void:
	var fixtures: Array = ROOF_FIXTURES.get(letter, [])
	if fixtures.is_empty():
		return
	var inner_cols: int = col_hi - col_lo - 1
	var inner_rows: int = row_hi - row_lo - 1
	if inner_cols < 1 or inner_rows < 1:
		return
	var fixture_layer := TileMapLayer.new()
	fixture_layer.name = "Fixtures"
	fixture_layer.tile_set = layer.tile_set
	fixture_layer.z_index = 1 # relative to the roof layer it hangs under
	layer.add_child(fixture_layer)
	for i in range(fixtures.size()):
		var col: int = col_lo + 1 + (i * 2 + 1) * inner_cols / (2 * fixtures.size())
		var row: int = row_lo + 1 + inner_rows * (1 + i % 2) / 3
		PixelTilesetBuilder.paint(fixture_layer, Vector2i(col, clampi(row, row_lo + 1, row_hi - 1)), fixtures[i])

## Fills a rectangle (local space, half-extent from origin) with a single
## floor tile (one of the environment atlas's floor_* names -- see
## PixelAtlasMap.ENV_TILE_NAMES) tiled as 32x32 AtlasTexture Sprite2D cells
## on a plain Node2D (not a TileMapLayer -- a handful of small interiors
## doesn't need a shared TileSet, and this keeps each building scene fully
## self-contained).
static func fill_floor(parent: Node2D, half_extent: Vector2, floor_tile_name: StringName, z_index: int = -8) -> void:
	var atlas_texture: Texture2D = load(PixelAtlasMap.ENV_ATLAS_PATH)
	var cell: Vector2i = PixelAtlasMap.env_cell(floor_tile_name)
	var min_x: int = int(round((-half_extent.x) / TS))
	var max_x: int = int(round((half_extent.x) / TS)) - 1
	var min_y: int = int(round((-half_extent.y) / TS))
	var max_y: int = int(round((half_extent.y) / TS)) - 1
	for gx in range(min_x, max_x + 1):
		for gy in range(min_y, max_y + 1):
			var sprite := Sprite2D.new()
			var region := AtlasTexture.new()
			region.atlas = atlas_texture
			region.region = Rect2(cell * TS, Vector2(TS, TS))
			sprite.texture = region
			sprite.position = Vector2(gx * TS + TS * 0.5, gy * TS + TS * 0.5)
			sprite.z_index = z_index
			parent.add_child(sprite)

## Builds one furniture-with-loot prop (visual + physical obstacle +
## searchable Interactable/LootContainer) fully configured BEFORE it ever
## enters the tree -- Godot readies children before parents, so setting a
## component's prop_id only after add_child() would race its own _ready()
## reading a stale default. Building this whole subtree first and adding
## it in one shot sidesteps that entirely.
static func add_loot_furniture(parent: Node2D, local_position: Vector2, texture: Texture2D, collision_size: Vector2, prop_id: StringName, capacity_weight: float, starting_items: Dictionary, interact_label: String = "Search", minimum_damage_class: int = EnvironmentDamage.DamageClass.SMALL_ARMS) -> void:
	var stable_id := _scoped_prop_id(parent, prop_id)
	var root := _make_physical_prop(local_position, texture, collision_size, stable_id, minimum_damage_class)
	root.name = String(stable_id).get_file() # e.g. "restaurant_01/shelf_0" -> "shelf_0", so a baked/saved scene shows a readable name instead of an auto-generated "@Node2D@N" in the editor
	var area := _make_interact_area(collision_size)
	var interactable := InteractableComponent.new()
	interactable.name = "InteractableComponent" # get_node_or_null("InteractableComponent") depends on this exact name
	interactable.interact_label = interact_label
	area.add_child(interactable)
	var loot := LootContainerComponent.new()
	loot.name = "LootContainerComponent"
	loot.prop_id = stable_id
	loot.capacity_weight = capacity_weight
	loot.starting_items = starting_items
	area.add_child(loot)
	root.add_child(area)
	parent.add_child(root)

## Same construction-before-entering-tree pattern for a salvage-only prop
## (e.g. a wrecked car, a pallet) -- no Inventory, just a one-time
## materials yield.
static func add_salvage_prop(parent: Node2D, local_position: Vector2, texture: Texture2D, collision_size: Vector2, prop_id: StringName, material_yield: int) -> void:
	var stable_id := _scoped_prop_id(parent, prop_id)
	var root := _make_physical_prop(local_position, texture, collision_size, stable_id)
	root.name = String(stable_id).get_file()
	var area := _make_interact_area(collision_size)
	var interactable := InteractableComponent.new()
	interactable.name = "InteractableComponent"
	interactable.interact_label = "Salvage"
	area.add_child(interactable)
	var salvage := SalvageableComponent.new()
	salvage.name = "SalvageableComponent"
	salvage.prop_id = stable_id
	salvage.material_yield = material_yield
	area.add_child(salvage)
	root.add_child(area)
	parent.add_child(root)

## Generic physical furniture and street objects are salvageable and take
## class-filtered structural damage. Callers that do not provide an id get a
## deterministic id derived from their owning room/path and local tile.
static func add_physical_prop(parent: Node2D, local_position: Vector2, texture: Texture2D, collision_size: Vector2, prop_id: StringName = &"", material_yield: int = 1, minimum_damage_class: int = EnvironmentDamage.DamageClass.SMALL_ARMS) -> void:
	var stable_id := prop_id if prop_id != &"" else _derived_object_id(parent, local_position, &"prop")
	var root := _make_physical_prop(local_position, texture, collision_size, stable_id, minimum_damage_class)
	root.name = String(stable_id).get_file()
	var area := _make_interact_area(collision_size)
	var interactable := InteractableComponent.new()
	interactable.name = "InteractableComponent"
	interactable.interact_label = "Salvage"
	area.add_child(interactable)
	var salvage := SalvageableComponent.new()
	salvage.name = "SalvageableComponent"
	salvage.prop_id = stable_id
	salvage.material_yield = maxi(material_yield, 1)
	area.add_child(salvage)
	root.add_child(area)
	parent.add_child(root)

## Flat ground detail with NO collision body at all -- drain covers, road
## rubble, scattered debris. Deliberately not add_physical_prop() with a
## tiny shape: anything with a collider can mark a navigation cell solid,
## and a manhole cover that blocks pathfinding is worse than no manhole
## cover. `z_index` defaults above the road-marking layer (-7) and below
## every prop and actor.
static func add_decal(parent: Node2D, local_position: Vector2, texture: Texture2D, z_index: int = -6) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = local_position
	sprite.z_index = z_index
	parent.add_child(sprite)

static func _make_physical_prop(local_position: Vector2, texture: Texture2D, collision_size: Vector2, object_id: StringName = &"", minimum_damage_class: int = EnvironmentDamage.DamageClass.SMALL_ARMS) -> Node2D:
	var root := Node2D.new()
	root.position = local_position
	var sprite := Sprite2D.new()
	sprite.texture = texture
	root.add_child(sprite)
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = collision_size
	var collider := CollisionShape2D.new()
	collider.name = "CollisionShape2D"
	collider.shape = shape
	body.add_child(collider)
	var damage := EnvironmentDamageComponent.new()
	damage.name = "EnvironmentDamageComponent"
	damage.object_id = object_id
	damage.minimum_damage_class = minimum_damage_class
	damage.max_durability = maxf(18.0, collision_size.length() * 0.75)
	damage.affected_size = collision_size
	damage.destroy_target = root
	body.add_child(damage)
	root.add_child(body)
	return root

static func _derived_object_id(parent: Node, local_position: Vector2, kind: StringName) -> StringName:
	var owner_id := "world"
	if parent is Room and (parent as Room).building_id != &"":
		owner_id = String((parent as Room).building_id) + "/" + String((parent as Room).room_id)
	elif "building_id" in parent and parent.get("building_id") != &"":
		owner_id = String(parent.get("building_id"))
	elif parent.is_inside_tree():
		owner_id = String(parent.get_path()).trim_prefix("/root/").replace("/", "_")
	var px := roundi(local_position.x)
	var py := roundi(local_position.y)
	return StringName("%s/%s_%d_%d" % [owner_id, String(kind), px, py])

static func _scoped_prop_id(parent: Node, requested_id: StringName) -> StringName:
	if parent is Room and (parent as Room).building_id != &"":
		var prefix := String((parent as Room).building_id) + "/"
		if String(requested_id).begins_with(prefix):
			return requested_id
		return StringName("%s/%s" % [String((parent as Room).building_id), String(requested_id).get_file()])
	return requested_id

static func _make_interact_area(collision_size: Vector2) -> Area2D:
	var area := Area2D.new()
	area.collision_layer = 64 # Interactable
	area.collision_mask = 0
	var interact_shape := RectangleShape2D.new()
	# Generous enough that there's always a reachable standing position
	# outside the physical obstacle but inside the interact zone -- the
	## largest actor (Player, 16px collision radius) needs roughly that
	# much clearance beyond the object's own footprint on every side.
	interact_shape.size = collision_size + Vector2(56, 56)
	var interact_collider := CollisionShape2D.new()
	interact_collider.shape = interact_shape
	area.add_child(interact_collider)
	return area
