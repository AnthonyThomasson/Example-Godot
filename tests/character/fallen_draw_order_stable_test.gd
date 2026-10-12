extends GameTest

## A falling body's parts keep their draw order (character_visuals.gd, `_stack`). A pair of parts only
## swaps over or under each other once their heights differ by more than STACK_BAND; while they sit within
## the band of one another, the order they were drawn in holds, so a limb lying across the trunk does not
## flicker. Shoots a one-hit target and, every frame of its fall, checks that no pair swapped while both
## were within the band. Reads the last drawn order (`_fallen_order`) and the parts' heights; draws nothing.


func describe() -> Dictionary:
	return {
		"name": "Falling body keeps its draw order",
		"description": "A shot target falls; no two of its parts swap draw order while their heights are within the stacking band.",
		"tags": ["draw", "ragdoll", "flicker"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"projectile.flyover", false)
	s.switch(&"physics.blood", false)
	s.actor(&"shooter", &"puppet", Vector2(200, 250), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(560, 250), { "max_health": 1.0 })
	s.camera_follow([&"target"])  # The camera stays on the body: one out of its view is not drawn, so its order would not change.


## The highest part of a body, by height.
func _top(parts: Array) -> float:
	var top := -INF
	for part in parts:
		top = maxf(top, part["height"])
	return top


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	shooter.aim_at(t.actor(&"target"))
	await t.seconds(0.4)
	shooter.shoot()
	if not t.require(await t.until(func(): return t.happened(&"died", func(d): return d["actor"] == &"target"), 2.0), "the target dies"):
		return

	var target: Node = t.actor(&"target")
	var visuals = target.get_node("Visuals")
	var band: float = visuals.get_script().get_script_constant_map()["STACK_BAND"]

	var prev_order: Array = []
	var prev_heights := {}
	var start_top := -INF
	var low_top := INF
	var swaps := 0
	var near_swaps := 0
	var frames_sampled := 0
	for i in 240:
		var rd = target.ragdoll
		if rd == null:
			await t.frames(1)
			continue
		var parts: Array = visuals._fallen_parts(rd)
		var heights := {}
		for part in parts:
			heights[part["key"]] = part["height"]
		var top := _top(parts)
		if start_top == -INF:
			start_top = top
		low_top = minf(low_top, top)
		var order: Array = visuals._fallen_order.duplicate()
		if not prev_order.is_empty() and order.size() == prev_order.size():
			frames_sampled += 1
			for a in order:
				for b in order:
					if prev_order.find(a) < prev_order.find(b) and order.find(a) > order.find(b):
						swaps += 1
						var was: float = absf(prev_heights[a] - prev_heights[b])
						var now: float = absf(heights[a] - heights[b])
						if was <= band and now <= band:
							near_swaps += 1
		prev_order = order
		prev_heights = heights
		await t.frames(1)

	t.trace("draw-order swaps", swaps)
	t.trace("swaps within the band", near_swaps)
	t.check(target.is_dead, "the target is dead")
	t.check(start_top > 0.0 and low_top < start_top * 0.5,
		"the body fell: highest part went from %.1f to %.1f" % [start_top, low_top])
	t.check(frames_sampled > 30, "the draw order was sampled over the fall (%d frames)" % frames_sampled)
	t.check(near_swaps == 0, "%d draw-order swaps happened while parts were within the stacking band" % near_swaps)
