extends SceneTree
## Headless one-time bake tool (Phase 3B.1). Run with:
##   godot --headless --path . --script tools/bake_district.gd
##
## Instantiates the ORIGINAL procedural DistrictBuilder, lets it fully
## construct the district exactly as it always has (tiles, buildings,
## props, roads, doors, spawn regions, scavenge points), then detaches
## that heavy construction script and packs the resulting node tree into a
## PackedScene, overwriting scenes/world/maps/UrbanDistrict01.tscn with
## real, committed, editor-editable content. Normal gameplay no longer
## runs DistrictBuilder at all -- only this offline tool does, and only
## when a deliberate map edit needs re-baking. See
## scripts/world/authored_district.gd for what the baked scene's own
## (much smaller) runtime script still does.
##
## Re-run this exact command any time district_builder.gd's layout
## constants change, then update the DistrictLayoutChecksum baseline in
## tests/test_runner.gd to match the new (still-constants-derived) hash --
## the constants remain the authored source of truth this tool bakes from.

const OUTPUT_SCENE_PATH := "res://scenes/world/maps/UrbanDistrict01.tscn"
const AUTHORED_DISTRICT_SCRIPT := "res://scripts/world/authored_district.gd"
const DISTRICT_BUILDER_SCRIPT := "res://scripts/world/district_builder.gd"

func _init() -> void:
	call_deferred("_bake")

func _bake() -> void:
	# A temporary EntityContainer-grouped node so DistrictBuilder's own
	# _build_scavenge_points() AND _build_street_props() (both of which look
	# up the "entity_container" group, matching production, for anything
	# that needs Y-sorting against actors -- scavenge points, plus the
	# abandoned/wrecked cars and the alley dumpster) have somewhere to add
	# their nodes -- moved into the district's own $DynamicEntities
	# container afterward so they're baked as part of the district scene
	# itself (see authored_district.gd for why they're reparented back into
	# the REAL EntityContainer at runtime, not left here). Deliberately NOT
	# named $ScavengePoints: it holds more than just ScavengePoint
	# instances, and a misleading container name would make the baked scene
	# harder, not easier, to read in the editor.
	var temp_entity_container := Node2D.new()
	temp_entity_container.name = "TempEntityContainer"
	temp_entity_container.add_to_group("entity_container")
	root.add_child(temp_entity_container)

	# DistrictBuilder's _ready() populates INTO pre-existing named child
	# containers ($GroundLayers, $Buildings, $StreetProps, $SpawnRegions,
	# $Boundaries) rather than creating them itself -- the original
	# UrbanDistrict01.tscn authored these as empty Node2Ds. Since that file
	# is this tool's own OUTPUT (never a stable input to load from), the
	# same empty containers are recreated here instead.
	var district := Node2D.new()
	district.name = "UrbanDistrict01"
	for container_name in ["GroundLayers", "Buildings", "StreetProps", "Navigation", "SpawnRegions", "Boundaries"]:
		var container := Node2D.new()
		container.name = container_name
		district.add_child(container)
	district.set_script(load(DISTRICT_BUILDER_SCRIPT))
	root.add_child(district)

	# Let DistrictBuilder's _ready() (which itself awaits one physics frame
	# before building the nav grid) fully resume and complete.
	for i in range(6):
		await process_frame
	await physics_frame
	await physics_frame

	var dynamic_entities_container := Node2D.new()
	dynamic_entities_container.name = "DynamicEntities"
	for child in temp_entity_container.get_children().duplicate():
		var global_pos: Vector2 = (child as Node2D).global_position
		temp_entity_container.remove_child(child)
		dynamic_entities_container.add_child(child)
		(child as Node2D).global_position = global_pos
	district.add_child(dynamic_entities_container)
	temp_entity_container.queue_free()

	# Detach the heavy runtime-construction script -- the baked scene ships
	# with the lightweight glue script instead.
	district.set_script(load(AUTHORED_DISTRICT_SCRIPT))

	_set_owner_recursive(district, district)

	var packed := PackedScene.new()
	var pack_result: int = packed.pack(district)
	if pack_result != OK:
		printerr("BAKE FAILED: pack() returned error %d" % pack_result)
		quit(1)
		return

	var save_result: int = ResourceSaver.save(packed, OUTPUT_SCENE_PATH)
	if save_result != OK:
		printerr("BAKE FAILED: ResourceSaver.save() returned error %d" % save_result)
		quit(1)
		return

	print("Baked district saved to %s (%d top-level children)" % [OUTPUT_SCENE_PATH, district.get_child_count()])
	quit(0)

## Marks every descendant as belonging to `owner_node` (required for
## PackedScene.pack() to include a procedurally-`add_child()`-ed node at
## all -- nodes with owner == null are silently excluded). Stops recursing
## into the children of an INSTANCED sub-scene (Restaurant01, Door,
## Window, ScavengePoint, ...) once it sets that instance root's own
## owner: those internal nodes are saved as part of THAT sub-scene file,
## not re-serialized into this one -- only the fact that "an instance of
## X.tscn sits here, with these property overrides" is recorded.
func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		if child.scene_file_path == "":
			_set_owner_recursive(child, owner_node)
