extends GameTest

## A furniture hole's outline drops its vertices within `SIMPLIFY_TOLERANCE` of the line between their neighbours, nearest
## first, before the bake (`NavBuilder._simplified`). It keeps each vertex's distance where it once measured every vertex again
## after each drop (dropping one changes only its two neighbours'). This pins it to the plain loop, vertex for vertex, over
## outlines like a shot-up piece's on the 1 px grid: shallow curves, steps a pixel deep, runs of points in line.

const SEED := 4411
const OUTLINES := 300


func describe() -> Dictionary:
	return {
		"name": "A hole's outline is simplified as the plain loop does",
		"description": "NavBuilder._simplified drops the same vertices in the same order as measuring every vertex after each drop, over 300 grid-snapped outlines.",
		"tags": ["bake", "furniture", "holes"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var dropped := 0
	var differing := 0
	for n in OUTLINES:
		var centre := Vector2(rng.randf_range(-200.0, 200.0), rng.randf_range(-200.0, 200.0))
		var radius := Vector2(rng.randf_range(10.0, 60.0), rng.randf_range(10.0, 60.0))
		var count := rng.randi_range(4, 80)
		var outline := PackedVector2Array()
		for k in count:
			var p := centre + Vector2.from_angle(TAU * k / count) * radius * rng.randf_range(0.95, 1.05)
			if n % 3 == 0:
				p = p.round()  # on the map's 1 px grid, as the bake snaps them
			if outline.is_empty() or outline[outline.size() - 1] != p:
				outline.append(p)
		var fast := NavBuilder._simplified(outline)
		var plain := _plain(outline)
		dropped += outline.size() - plain.size()
		if fast != plain:
			differing += 1
	t.check(dropped > 1000, "vertices dropped over the outlines (%d)" % dropped)
	t.check(differing == 0, "%d of %d outlines simplified differently from the plain loop" % [differing, OUTLINES])


## `_simplified` as it was: every vertex measured again after each drop.
func _plain(outline: PackedVector2Array) -> PackedVector2Array:
	var points := outline.duplicate()
	while points.size() > 3:
		var drop := -1
		var nearest := NavBuilder.SIMPLIFY_TOLERANCE
		for i in points.size():
			var line_from: Vector2 = points[(i - 1 + points.size()) % points.size()]
			var line_to: Vector2 = points[(i + 1) % points.size()]
			var gap: float = points[i].distance_to(Geometry2D.get_closest_point_to_segment(points[i], line_from, line_to))
			if gap < nearest:
				nearest = gap
				drop = i
		if drop < 0:
			break
		points.remove_at(drop)
	return points
