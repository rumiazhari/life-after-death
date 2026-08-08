class_name BuildingShellBuilder
extends RefCounted
## Shared helper every authored building scene calls from its own _ready()
## to paint its perimeter walls, interior partitions, and floor -- exists
## so wall/floor construction is one reusable routine instead of duplicated
## per-building logic (interior layout, doors, windows, furniture, and
## room bounds still come from each building's own hand-authored child
## nodes; only the repetitive "chain of 32x32 wall segments with gaps for
## doors" and "fill this rect with floor tiles" plumbing is shared here).
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
	for gy in range(min_y, max_y + 1):
		_maybe_wall(parent, Vector2(min_x * TS + TS * 0.5, gy * TS + TS * 0.5), wall_texture, gaps)
		_maybe_wall(parent, Vector2(max_x * TS + TS * 0.5, gy * TS + TS * 0.5), wall_texture, gaps)

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
		if gap.has_point(center):
			return
	var body := StaticBody2D.new()
	body.position = center
	body.collision_layer = 1 | 32 # World | Vision
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(TS, TS)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	var sprite := Sprite2D.new()
	sprite.texture = wall_texture
	body.add_child(sprite)
	parent.add_child(body)

## Paints a 9-slice roof (center/edge/corner) across a building's own
## footprint onto a TileMapLayer, in one of the 4 shared roof material
## variants from the environment atlas -- the same tiles/technique
## DistrictBuilder uses for the non-enterable background building shells,
## so a real building's roof matches the district's visual language.
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
static func add_loot_furniture(parent: Node2D, local_position: Vector2, texture: Texture2D, collision_size: Vector2, prop_id: StringName, capacity_weight: float, starting_items: Dictionary, interact_label: String = "Search") -> void:
	var root := _make_physical_prop(local_position, texture, collision_size)
	var area := _make_interact_area(collision_size)
	var interactable := InteractableComponent.new()
	interactable.name = "InteractableComponent" # get_node_or_null("InteractableComponent") depends on this exact name
	interactable.interact_label = interact_label
	area.add_child(interactable)
	var loot := LootContainerComponent.new()
	loot.name = "LootContainerComponent"
	loot.prop_id = prop_id
	loot.capacity_weight = capacity_weight
	loot.starting_items = starting_items
	area.add_child(loot)
	root.add_child(area)
	parent.add_child(root)

## Same construction-before-entering-tree pattern for a salvage-only prop
## (e.g. a wrecked car, a pallet) -- no Inventory, just a one-time
## materials yield.
static func add_salvage_prop(parent: Node2D, local_position: Vector2, texture: Texture2D, collision_size: Vector2, prop_id: StringName, material_yield: int) -> void:
	var root := _make_physical_prop(local_position, texture, collision_size)
	var area := _make_interact_area(collision_size)
	var interactable := InteractableComponent.new()
	interactable.name = "InteractableComponent"
	interactable.interact_label = "Salvage"
	area.add_child(interactable)
	var salvage := SalvageableComponent.new()
	salvage.name = "SalvageableComponent"
	salvage.prop_id = prop_id
	salvage.material_yield = material_yield
	area.add_child(salvage)
	root.add_child(area)
	parent.add_child(root)

## A purely-physical prop (no interaction at all) -- trees, parked
## non-lootable cars, planters.
static func add_physical_prop(parent: Node2D, local_position: Vector2, texture: Texture2D, collision_size: Vector2) -> void:
	parent.add_child(_make_physical_prop(local_position, texture, collision_size))

static func _make_physical_prop(local_position: Vector2, texture: Texture2D, collision_size: Vector2) -> Node2D:
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
	collider.shape = shape
	body.add_child(collider)
	root.add_child(body)
	return root

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
