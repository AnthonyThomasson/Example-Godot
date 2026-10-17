extends GameTest

## A falling body's trunk keeps its outline (character_visuals.gd, `_trunk_outline`). The outline is the
## union of the hulls of neighbouring cross-sections; seen edge-on those hulls touch only along a line and
## the union can come apart, leaving the torso as one small slice for a single frame as the body lands.
## Shoots several targets so a few real ragdolls land, and checks that no trunk's outline area dips below half
## of both its neighbouring frames' areas. Reads the outline; draws nothing.

const TARGETS := 4
## Frames sampled at most after the last target is down: the landing and settling. Sampling stops early once every
## body has come to rest (its outline cannot change any more), but not before MIN_FRAMES, which keeps well over
## 100 sampled frames per target.
const FRAMES := 300
const MIN_FRAMES := 110
## A frame's outline area counts as collapsed below this share of both neighbours'.
const COLLAPSE := 0.5


func describe() -> Dictionary:
	return {
		"name": "Falling body keeps its trunk outline",
		"description": "Several shot targets fall; no trunk's outline shrinks to a fraction of its size for a single frame.",
		"tags": ["draw", "ragdoll", "flicker"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"projectile.flyover", false)
	s.switch(&"physics.blood", false)
	s.actor(&"shooter", &"puppet", Vector2(200, 250), { "start_slot": 3 })
	for i in TARGETS:
		s.actor(StringName("target%d" % i), &"puppet", Vector2(560, 90.0 + 105.0 * i), { "max_health": 1.0 })


## The area of the trunk outline of `target`, seen from above (0 before it has fallen).
func _outline_area(target: Node) -> float:
	var rd = target.ragdoll
	if rd == null:
		return 0.0
	var visuals = target.get_node("Visuals")
	var outline: PackedVector2Array = visuals._trunk_outline(rd)
	return visuals._area(outline)


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	for i in TARGETS:
		var id := StringName("target%d" % i)
		shooter.aim_at(t.actor(id))
		await t.seconds(0.4)
		shooter.shoot()
		if not t.require(await t.until(func(): return t.happened(&"died", func(d): return d["actor"] == id), 2.0), "%s dies" % id):
			return

	var series := {}
	for i in TARGETS:
		series[i] = []
	var at_rest := func() -> bool:
		for i in TARGETS:
			var rd = t.actor(StringName("target%d" % i)).ragdoll
			if rd == null or not rd.is_settled():
				return false
		return true
	for frame in FRAMES:
		for i in TARGETS:
			(series[i] as Array).append(_outline_area(t.actor(StringName("target%d" % i))))
		await t.frames(1)
		if frame >= MIN_FRAMES and at_rest.call():
			break

	var collapses := []
	var sampled := 0
	for i in TARGETS:
		var areas: Array = series[i]
		for f in range(1, areas.size() - 1):
			if areas[f - 1] <= 0.0 or areas[f] <= 0.0 or areas[f + 1] <= 0.0:
				continue
			sampled += 1
			if areas[f] < COLLAPSE * minf(areas[f - 1], areas[f + 1]):
				collapses.append("target%d frame %d: %.0f -> %.0f -> %.0f" % [i, f, areas[f - 1], areas[f], areas[f + 1]])
	t.trace("trunk outline frames sampled", sampled)
	t.trace("collapsed frames", collapses.size())
	t.check(sampled > TARGETS * 100, "the trunk outline was sampled over the falls (%d frames)" % sampled)
	t.check(collapses.is_empty(), "%d trunk outlines collapsed for a frame: %s" % [collapses.size(), "; ".join(collapses.slice(0, 4))])
