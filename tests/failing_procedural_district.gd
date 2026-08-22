extends ProceduralDistrict
## Runtime failure fixture: the production district still owns generation and
## signal delivery, while only its generator factory is replaced with the
## deterministic retry probe.

const RETRY_PROBE_SCRIPT: GDScript = preload("res://tests/procedural_retry_probe.gd")

func _create_generator() -> ProceduralCityGenerator:
	var generator = RETRY_PROBE_SCRIPT.new()
	generator.forced_validation_failures = ProceduralCityGenerator.MAX_GENERATION_ATTEMPTS
	return generator

func _report_generation_error(_error: String) -> void:
	# The failure itself is the expected test input; assertions inspect the
	# retained/signal diagnostics without polluting the editor debugger.
	pass
