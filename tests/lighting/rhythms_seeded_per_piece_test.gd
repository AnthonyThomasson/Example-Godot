extends GameTest

## R10 (ticket #61): light rhythms (steady / buzz / failing / blink / shimmer / pulse) are seeded per piece. The same room, four
## TVs, four neon tubes and two lamps, is built twice, each copy in a world of its own (a SubViewport with its own World2D, so
## the copies stand at the same coordinates without touching), and each is lit with the same seed in the same frame. Over four
## seconds every light of one copy has exactly the same energy, frame by frame, as its twin in the other (two runs, same seed,
## same rhythm), and within one copy no two lights that change over time change alike (different pieces differ).
##
## It reads `WorldLighting.light(root, seed_value) -> WorldLighting` (how Main and the Testing world light a world) and its
## `lights()`. Light energy is the PointLight2D's own (0 while disabled).

const ArenaBuilder := preload("res://scenes/testing/arena_builder.gd")
const SEED := 6113
const ROOM := Rect2(0, 0, 900, 600)
const PIECES := [
	["tv", Vector2(150, 150)], ["tv", Vector2(450, 150)], ["tv", Vector2(750, 150)], ["tv", Vector2(300, 470)],
	["neon_tube", Vector2(150, 300)], ["neon_tube", Vector2(450, 300)], ["neon_tube", Vector2(750, 300)], ["neon_tube", Vector2(620, 470)],
	["lamp", Vector2(120, 520)], ["lamp", Vector2(820, 520)],
]
const FRAMES := 240
const SAME := 0.00001  ## Most a light's energy may differ from its twin's in a frame.
const CHANGES := 0.01  ## Least range of energy for a light that changes over time; and least difference between two that do.


func describe() -> Dictionary:
	return {
		"name": "Light rhythms are seeded per piece",
		"description": "Two copies of a room lit with the same seed flicker identically light for light; within a copy no two changing lights change alike.",
		"tags": ["lighting"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var first := _copy(t, "A")
	var second := _copy(t, "B")
	if not t.require(first != null and second != null, "light() returns the WorldLighting"):
		return
	var keys_a := _keys(first.lights())
	var keys_b := _keys(second.lights())
	if not t.require(keys_a.size() >= PIECES.size(), "each piece in the copy has its light (%d lights for %d pieces)" % [keys_a.size(), PIECES.size()]):
		return
	t.check(keys_a.keys() == keys_b.keys(), "the two copies have the same lights (%s / %s)" % [keys_a.keys(), keys_b.keys()])
	var traces_a := {}
	var traces_b := {}
	for key in keys_a:
		traces_a[key] = []
		traces_b[key] = []
	for _i in FRAMES:
		await t.frames(1)
		for key in keys_a:
			(traces_a[key] as Array).append(_energy(keys_a[key]))
			if keys_b.has(key):
				(traces_b[key] as Array).append(_energy(keys_b[key]))

	# Same seed, same rhythm.
	for key: String in keys_a:
		if keys_b.has(key):
			var off := _most_apart(traces_a[key], traces_b[key])
			t.check(off <= SAME, "the light at %s flickers the same in both copies (apart by up to %.4f)" % [key, off])

	# Different pieces differ.
	var changing: Array = keys_a.keys().filter(func(k: String) -> bool: return _range(traces_a[k]) >= CHANGES)
	if not t.require(changing.size() >= 2, "some of the lights have a rhythm that changes their energy (%d of %d)" % [changing.size(), keys_a.size()]):
		return
	for i in changing.size():
		for j in range(i + 1, changing.size()):
			var apart := _most_apart(traces_a[changing[i]], traces_a[changing[j]])
			t.check(apart >= CHANGES, "the lights at %s and %s keep rhythms of their own (apart by up to %.3f)" % [changing[i], changing[j], apart])


## Build one copy of the room in a world of its own under the test world, lit with `SEED`; the WorldLighting `light` returns
## (null when it returns none).
func _copy(t: TestContext, label: String) -> WorldLighting:
	var viewport := SubViewport.new()
	viewport.name = "Copy" + label
	viewport.world_2d = World2D.new()
	viewport.disable_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	t.world.add_child(viewport)
	var root := Node2D.new()
	root.name = "World"
	viewport.add_child(root)
	var arena := ArenaBuilder.build({ "rect": ROOM, "floor": "oak_planks", "walls": true, "thickness": 12.0 }, root)
	for k in PIECES.size():
		var row: Array = PIECES[k]
		ObjectFactory.spawn(WorldGen.object_definition(row[0]), arena.to_local(row[1]), arena, { "name": "%s_%d" % [row[0], k], "neon": "" })
	return WorldLighting.light(root, SEED)


## The PointLight2Ds in `lights` by a key that names the same light in either copy: its place and colour, and a count for
## lights that share them.
func _keys(lights: Array) -> Dictionary:
	var out := {}
	for l in lights:
		if not l is PointLight2D:
			continue
		var light := l as PointLight2D
		var base := "%s %s" % [light.global_position.snapped(Vector2(0.1, 0.1)), light.color.to_html()]
		var key := base
		var n := 1
		while out.has(key):
			n += 1
			key = "%s #%d" % [base, n]
		out[key] = light
	return out


## A light's energy now (0 while disabled).
func _energy(l: PointLight2D) -> float:
	return l.energy if l.enabled else 0.0


## The most two traces differ in a frame (INF when their lengths differ).
func _most_apart(a: Array, b: Array) -> float:
	if a.size() != b.size():
		return INF
	var most := 0.0
	for i in a.size():
		most = maxf(most, absf(float(a[i]) - float(b[i])))
	return most


## A trace's range (highest minus lowest).
func _range(trace: Array) -> float:
	if trace.is_empty():
		return 0.0
	var lo: float = trace[0]
	var hi: float = trace[0]
	for v: float in trace:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi - lo
