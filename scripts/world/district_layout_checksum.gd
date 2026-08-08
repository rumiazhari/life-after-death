class_name DistrictLayoutChecksum
extends RefCounted
## Deterministic checksum over DistrictBuilder's fixed layout constants
## (roads, building positions, shell buildings, spawn regions, scavenge
## points), so an accidental edit that moves or deletes a critical
## entrance/building/spawn-region is caught by a test comparing against a
## committed expected value instead of silently drifting unnoticed.

static func compute() -> String:
	var parts: Array[String] = [
		str(DistrictBuilder.ROADS),
		str(DistrictBuilder.BUILDING_POSITIONS),
		str(DistrictBuilder.SHELL_BUILDINGS),
		str(DistrictBuilder.SPAWN_REGIONS),
		str(DistrictBuilder.SCAVENGE_POINTS),
	]
	return "|".join(parts).sha256_text()
