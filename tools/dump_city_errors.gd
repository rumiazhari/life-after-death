extends SceneTree

func _initialize() -> void:
	call_deferred(&"_run")

func _run() -> void:
	var generator := ProceduralCityGenerator.new()
	var corpus: Array[int] = [0, 1, 2, 3, 7, 31, 42, 255, 1024, 8801, 65535, 20260821, 2147483646]
	for seed_value in corpus:
		for coordinate in [Vector2i.ZERO, Vector2i(-1, -1), Vector2i(2, 1)]:
			var city := generator.generate_streamed_chunk(seed_value, coordinate)
			if not String(city.get("generation_error", "")).is_empty():
				print("SEED ", seed_value, " chunk ", coordinate, " profile=", city.get("district_profile", "?"))
				for e in city.get("validation_errors", []):
					print("   ", e)
	quit(0)
