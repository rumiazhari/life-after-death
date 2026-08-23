extends Node
## Headless diagnostic: streams a corpus of seeds/coordinates across every
## regional profile and prints any generation/validation failure with the
## full per-road connectivity detail. Run from the project root:
##
##   godot --headless --path . res://tools/DumpCityErrors.tscn

const SEED_CORPUS: Array[int] = [0, 1, 2, 3, 7, 31, 42, 255, 1024, 8801, 65535, 20260821, 2147483646]
const COORDINATES: Array[Vector2i] = [
	Vector2i.ZERO, Vector2i(-1, -1), Vector2i(2, 1), Vector2i(-3, 4),
	Vector2i(5, -5), Vector2i(4, 0), Vector2i(0, 4),
]
## Set to true for a wide deterministic sweep (slower).
const WIDE_SWEEP := false

func _ready() -> void:
	_run()

func _run() -> void:
	var generator := ProceduralCityGenerator.new()
	var failures := 0
	var cases := 0
	var profiles_seen := {}
	var coordinates := COORDINATES
	if WIDE_SWEEP:
		coordinates = []
		for y in range(-8, 9):
			for x in range(-8, 9):
				coordinates.append(Vector2i(x, y))
	for seed_value in SEED_CORPUS:
		for coordinate in coordinates:
			cases += 1
			var city := generator.generate_streamed_chunk(seed_value, coordinate)
			profiles_seen[city.get("district_profile", "?")] = true
			if not String(city.get("generation_error", "")).is_empty():
				failures += 1
				print("SEED ", seed_value, " chunk ", coordinate, " profile=", city.get("district_profile", "?"))
				for e in city.get("validation_errors", []):
					print("   ", e)
	print("PROFILE_COVERAGE ", profiles_seen.keys())
	print("CASES ", cases)
	print("FAILURES ", failures)
	get_tree().quit(1 if failures > 0 else 0)
