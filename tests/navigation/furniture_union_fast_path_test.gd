extends GameTest

## The nav re-bake fuses overlapping furniture footprints into one hole each (`NavBuilder._union_outlines`). That is the
## costliest step of a re-bake (it ran a polygon merge for every pair of footprints), so it skips the merge for two
## footprints whose bounding boxes are apart: the union of such a pair is the pair, as the merge would have said. This
## pins the result to the plain every-pair merge, outline for outline, over sixteen generated houses.

const SEEDS := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]


func describe() -> Dictionary:
	return {
		"name": "The furniture union skips only merges that would change nothing",
		"description": "NavBuilder fuses furniture footprints into holes; skipping the merge for boxes that are apart gives exactly the outlines the full every-pair merge does.",
		"tags": ["bake", "furniture", "holes"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	for house_seed in SEEDS:
		var holder := Node2D.new()
		t.world.add_child(holder)
		var house := WorldGen.generate(house_seed, "", Vector2.ZERO, holder)
		await t.frames(2)
		var outlines: Array = []
		for outline in NavBuilder.furniture_holes(house):
			var local := PackedVector2Array()
			for p in outline:
				local.append(p - house.position)
			outlines.append(local)
		var fast: Array = NavBuilder._union_outlines(outlines)
		var full: Array = _union_every_pair(outlines)
		t.check(fast == full, "seed %d: %d footprints fuse into %d holes, the same as the every-pair merge" % [house_seed, outlines.size(), full.size()])
		holder.queue_free()


## The union as it was before the box test: every footprint merged against every kept one.
func _union_every_pair(outlines: Array) -> Array:
	var out: Array = []
	for outline in outlines:
		var cur: PackedVector2Array = outline
		var k := 0
		while k < out.size():
			var fused := Geometry2D.merge_polygons(cur, out[k])
			var outer: Array = fused.filter(func(poly: PackedVector2Array) -> bool: return not Geometry2D.is_polygon_clockwise(poly))
			if outer.size() == 1:
				cur = outer[0]
				out.remove_at(k)
				k = 0
			else:
				k += 1
		out.append(cur)
	return out
