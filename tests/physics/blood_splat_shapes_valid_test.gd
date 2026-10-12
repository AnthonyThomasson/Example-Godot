extends GameTest

## Every outline a BloodSplat draws can be triangulated (blood_splat.gd). A splat is built from random
## blobs, spikes and droplets unioned into opaque outlines, and about 1 splat in 100,000 comes out with an
## outline the engine cannot triangulate; `draw_colored_polygon` then logs "Invalid polygon data,
## triangulation failed", which failed whatever test happened to draw it (physics/hit_overload_stress,
## a few percent of runs). `BloodSplat.drawable` keeps a valid outline, swaps an invalid one for its hull
## and drops one with no area; `setup` runs every outline through it. The helper is checked on a
## self-crossing polygon (deterministic); a sweep of random splats checks the whole build.

const BloodSplat = preload("res://scenes/physics/blood/blood_splat.gd")

const SPLATS := 6000
const SEED := 20240611


func describe() -> Dictionary:
	return {
		"name": "Blood splat outlines can be drawn",
		"description": "A self-crossing outline falls back to its hull and a random sweep of splats builds only outlines the engine can triangulate.",
		"tags": ["blood", "splat", "draw"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))
	s.switch(&"nav.rebake", false)
	s.object(&"chair", "chair", Vector2(250, 150))


## The area enclosed by `poly`, whichever way it winds.
func _area(poly: PackedVector2Array) -> float:
	var twice := 0.0
	for k in poly.size():
		twice += poly[k].cross(poly[(k + 1) % poly.size()])
	return absf(twice) * 0.5


func run(t: TestContext) -> void:
	await t.frames(2)

	var square := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	t.check(BloodSplat.drawable(square) == square, "a valid outline is kept as it is")

	var bowtie := PackedVector2Array([Vector2(0, 0), Vector2(10, 10), Vector2(10, 0), Vector2(0, 10)])
	t.require(not Deformation.is_valid_polygon(bowtie), "the self-crossing outline is one the engine rejects")
	var fixed := BloodSplat.drawable(bowtie)
	t.check(Deformation.is_valid_polygon(fixed), "a self-crossing outline becomes a drawable one")
	t.check(absf(_area(fixed) - 100.0) < 0.01, "it falls back to the outline's hull")

	t.check(BloodSplat.drawable(PackedVector2Array([Vector2(0, 0), Vector2(5, 5)])).is_empty(),
		"an outline with no area is dropped")

	seed(SEED)
	var invalid := 0
	var outlines := 0
	for i in SPLATS:
		var at := Vector2(randf_range(20.0, 380.0), randf_range(20.0, 280.0))
		var direction := Vector2.from_angle(randf() * TAU) if randf() < 0.8 else Vector2.ZERO
		var splat: Node = BloodSpawner.splat(t.world, at, randf_range(1.0, 7.0), direction, randf(), [])
		for poly in splat.shapes:
			outlines += 1
			if not Deformation.is_valid_polygon(poly):
				invalid += 1
		splat.free()
		if i % 500 == 499:
			await t.frames(1)
	t.trace("outlines checked", outlines)
	t.check(outlines >= SPLATS, "splats built outlines (%d)" % outlines)
	t.check(invalid == 0, "%d of %d outlines cannot be triangulated" % [invalid, outlines])
