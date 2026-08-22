class_name DistrictLayoutChecksum
extends RefCounted
## Deterministic checksum over DistrictBuilder's fixed layout constants --
## every array that decides WHERE something in the city is: the street
## grid, the block plan and its ground surfaces, the building and shell
## footprints, the parking aprons, all street furniture (one-off, lines and
## decals), the searchable/salvageable street props, the spawn regions and
## the scavenge points. An accidental edit that moves or deletes a critical
## entrance, block, or spawn region is caught by a test comparing against a
## committed expected value instead of silently drifting unnoticed.
##
## Everything hashed here stringifies deterministically (Vector2, Rect2,
## StringName, and texture PATHS -- never loaded Texture2D handles, whose
## string form is a per-run object id).

static func compute() -> String:
	var parts: Array[String] = [
		str(DistrictBuilder.ROADS),
		str(DistrictBuilder.BLOCKS),
		str(DistrictBuilder.SURFACE_PATCHES),
		str(DistrictBuilder.BUILDING_POSITIONS),
		str(DistrictBuilder.SHELL_BUILDINGS),
		str(DistrictBuilder.PARKING_LOTS),
		str(DistrictBuilder.PROP_LINES),
		str(DistrictBuilder.PROPS),
		str(DistrictBuilder.DECALS),
		str(DistrictBuilder.LOOT_PROPS),
		str(DistrictBuilder.SALVAGE_PROPS),
		str(DistrictBuilder.SPAWN_REGIONS),
		str(DistrictBuilder.SCAVENGE_POINTS),
	]
	return "|".join(parts).sha256_text()
