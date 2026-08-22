extends ProceduralCityGenerator
## Test double that deterministically rejects the first N validation calls so
## the production generator's retry and exhausted-failure contracts can be
## exercised without relying on a naturally invalid city seed.

var forced_validation_failures: int = 0
var validation_calls: int = 0

func validate(city: Dictionary) -> Array[String]:
	validation_calls += 1
	if validation_calls <= forced_validation_failures:
		return ["forced validation failure %d" % validation_calls]
	return super.validate(city)
