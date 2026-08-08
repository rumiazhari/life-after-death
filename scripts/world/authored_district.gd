class_name AuthoredDistrict
extends Node2D
## Runtime glue for the BAKED UrbanDistrict01.tscn (Phase 3B.1). The
## district's geometry -- tiles, buildings, props, roads, doors, windows,
## spawn regions, scavenge points -- is now committed, authored scene
## content (baked once by tools/bake_district.gd from
## scripts/world/district_builder.gd's fixed layout constants), not
## reconstructed from those arrays at runtime _ready() time. See
## docs/urban_map_design.md "Baked, not runtime-built" for why and how.
##
## Only the two things that genuinely cannot be serialized into the .tscn
## itself remain here:
## 1. Scavenge points and the handful of street props that need the same
##    Y-sort treatment (abandoned/wrecked cars, the alley dumpster) must be
##    direct children of the Y-sorted EntityContainer (Main.tscn) for
##    correct depth sorting against actors -- they're baked as children of
##    this node's own $DynamicEntities container (so bake_district.gd can
##    capture them as part of the district scene) and reparented into the
##    real EntityContainer exactly once, here, at load time.
## 2. UrbanNavigationService's grid is built from LIVE physics-server
##    point queries against the district's static collision, which only
##    exist once this scene is actually instanced in a running tree -- it
##    cannot be precomputed and serialized.
##
## `district_builder.gd` (the ORIGINAL procedural-construction script) is
## kept as the bake tool's own input -- it is no longer attached to any
## scene that ships in Main.tscn, only instantiated standalone by
## tools/bake_district.gd when a deliberate map change needs re-baking.

@export var arena_half_size: Vector2 = Vector2(1400, 1400)

func _ready() -> void:
	_reparent_dynamic_entities()
	# Newly-added StaticBody2D collision shapes (all baked into this scene)
	# aren't queryable by the physics server until at least one physics
	# step has run -- same requirement DistrictBuilder's own _ready() had.
	await get_tree().physics_frame
	UrbanNavigationService.build(arena_half_size)
	_register_doors_with_navigation()

func _reparent_dynamic_entities() -> void:
	var dynamic_entities_container: Node = get_node_or_null("DynamicEntities")
	if dynamic_entities_container == null:
		return
	var dynamic_world: Node = get_tree().get_first_node_in_group("entity_container")
	if dynamic_world == null:
		return
	for child in dynamic_entities_container.get_children().duplicate():
		var global_pos: Vector2 = (child as Node2D).global_position
		dynamic_entities_container.remove_child(child)
		dynamic_world.add_child(child)
		(child as Node2D).global_position = global_pos

func _register_doors_with_navigation() -> void:
	for door in get_tree().get_nodes_in_group("doors"):
		if door.door_id != &"":
			UrbanNavigationService.register_door(door.door_id, door.global_position)
			if door.is_open:
				UrbanNavigationService.mark_door_open(door.door_id)

func get_arena_size() -> Vector2:
	return arena_half_size * 2.0
