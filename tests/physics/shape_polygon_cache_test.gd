extends GameTest

## `Deformation.shape_polygon` keeps its last few dented silhouettes, because each hit asks for the same one several
## times (collider, shadow, drawing) and every repaint of a wounded character asks again. A kept polygon must be the
## one a fresh computation gives, for the inputs it was made from only: another size, other dents or retuned
## deformation each get their own.

const SEED := 777


func describe() -> Dictionary:
	return {
		"name": "Kept dented silhouettes equal fresh ones",
		"description": "shape_polygon returns what a fresh computation does, hit or miss, and a change of shape, size, dents or tuning is never answered with an old polygon.",
		"tags": ["deformation", "cache"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))
	s.set_static(PhysicsConfig, "deform_radius", PhysicsConfig.deform_radius)  # restored after the test


func _impacts(rng: RandomNumberGenerator, size: Vector2, count: int) -> Array:
	var out: Array = []
	for k in count:
		var at := Vector2.from_angle(rng.randf() * TAU) * size.x * 0.5
		out.append({ "pos": at, "inward": -at.normalized(), "depth": rng.randf_range(1.0, 5.0),
			"chunk": rng.randf() < 0.3, "seed": rng.randi(), "blood": 0.0 })
	return out


func run(t: TestContext) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var wrong := 0
	var checked := 0
	for n in 80:
		var shape: String = ["circle", "square", "rect"][n % 3]
		var size := Vector2(rng.randf_range(24.0, 90.0), rng.randf_range(24.0, 90.0))
		var impacts := _impacts(rng, size, rng.randi_range(1, 12))
		var fresh := Deformation._shape_polygon(shape, size, impacts)
		for ask in 3:  # the first answer is computed, the next two come from the cache
			checked += 1
			if Deformation.shape_polygon(shape, size, impacts.duplicate(true)) != fresh:
				wrong += 1
	t.check(wrong == 0, "%d of %d answers differ from a fresh computation" % [wrong, checked])

	var size := Vector2(40.0, 40.0)
	var impacts := _impacts(rng, size, 6)
	var before := Deformation.shape_polygon("circle", size, impacts)
	impacts.append(_impacts(rng, size, 1)[0])
	t.check(Deformation.shape_polygon("circle", size, impacts) == Deformation._shape_polygon("circle", size, impacts), "one more dent is not answered with the old polygon")
	t.check(Deformation.shape_polygon("circle", size, impacts) != before, "and it is a different polygon")
	var other_size := Vector2(60.0, 60.0)
	t.check(Deformation.shape_polygon("circle", other_size, impacts) == Deformation._shape_polygon("circle", other_size, impacts), "another size is computed afresh")
	PhysicsConfig.deform_radius = 12.0
	t.check(Deformation.shape_polygon("circle", size, impacts) == Deformation._shape_polygon("circle", size, impacts), "retuned deformation is computed afresh")
