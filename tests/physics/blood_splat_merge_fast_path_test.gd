extends GameTest

## A splat unions its random blobs, spikes and droplets into opaque outlines (`BloodSplat._merge_in`). Most pairs of
## them never touch, so it skips the polygon merge for two outlines whose boxes are apart (the union would keep them
## as two anyway). This pins the outlines to the plain merge-against-every-outline build, bit for bit, over a sweep
## of seeded splats of every size, throw and energy.

const BloodSplat = preload("res://scenes/physics/blood/blood_splat.gd")

const SPLATS := 300
const SEED := 987654


## The splat as it was built before the box test.
class EveryPairSplat extends "res://scenes/physics/blood/blood_splat.gd":
	func _merge_in(poly: PackedVector2Array) -> void:
		var current := poly
		var i := 0
		while i < shapes.size():
			var merged := Geometry2D.merge_polygons(shapes[i], current)
			var outer: Array[PackedVector2Array] = []
			for m in merged:
				if not Geometry2D.is_polygon_clockwise(m):
					outer.append(m)
			if outer.size() == 1:
				current = outer[0]
				shapes.remove_at(i)
				i = 0
			else:
				i += 1
		shapes.append(current)


func describe() -> Dictionary:
	return {
		"name": "The splat merge skips only unions that would change nothing",
		"description": "BloodSplat builds the same outlines with its box test as when it merges every outline against every other.",
		"tags": ["blood", "splat"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))
	s.switch(&"nav.rebake", false)
	s.object(&"chair", "chair", Vector2(250, 150))


func run(t: TestContext) -> void:
	await t.frames(2)
	var differing := 0
	var outlines := 0
	for i in SPLATS:
		var rng := RandomNumberGenerator.new()
		rng.seed = SEED + i
		var at := Vector2(rng.randf_range(20.0, 380.0), rng.randf_range(20.0, 280.0))
		var size := rng.randf_range(1.0, 7.0)
		var direction := Vector2.from_angle(rng.randf() * TAU) if rng.randf() < 0.8 else Vector2.ZERO
		var energy := rng.randf()
		seed(SEED + i)
		var fast := _splat(t, BloodSplat, at, size, direction, energy)
		seed(SEED + i)
		var full := _splat(t, EveryPairSplat, at, size, direction, energy)
		outlines += fast.shapes.size()
		if fast.shapes != full.shapes:
			differing += 1
		fast.free()
		full.free()
	t.check(outlines >= SPLATS, "splats built outlines (%d)" % outlines)
	t.check(differing == 0, "%d of %d splats differ from the every-outline merge" % [differing, SPLATS])


func _splat(t: TestContext, script: Script, at: Vector2, size: float, direction: Vector2, energy: float) -> Node:
	var node := Node2D.new()
	node.script = script
	t.world.add_child(node)
	node.global_position = at
	node.call(&"setup", size, direction, energy, [])
	return node
