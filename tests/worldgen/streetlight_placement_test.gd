extends GameTest

## R7 (ticket #61): World-Gen places streetlights along the front sidewalk of every house, about 260 px apart (each
## jittered by up to 50 px), never within 140 px of a front or exit doorway's centre nor in the strip straight out of
## one (the doorway's width plus 32 px each side, 400 px out); a lamp that would break that rule is dropped, so only a
## doorway's no-lamp zone can open a wider gap in the row. Each is a solid, anchored metal post (coverage 100,
## penetration 85: it blocks bullets) carved into the nav map. Checked for every floorplan over several seeds.
##
## It reads the lamps through (interface 1, beside `get_clutter` / `get_street`):
## - `WorldGen.get_streetlights(house) -> Array` of `{ pos, node }`: one entry per streetlight, `pos` its centre in world
##   space, `node` the placed piece (a descendant of the house, so the nav bake carves it).

const SEEDS := [1, 2, 3, 4, 5]
const ELSEWHERE := Vector2(9000, 9000)  ## Where the houses go, clear of the test arena.
## The spec's numbers (ticket #61 plan), so the test checks the plan and not the code.
const EVERY := 260.0
const JITTER := 50.0
const DOOR_CLEAR := 140.0
const STRIP_MARGIN := 32.0
const STRIP_REACH := 400.0
const MIN_GAP := EVERY - 2.0 * JITTER  ## Two neighbours, each jittered toward the other.
const MAX_GAP := EVERY + 2.0 * JITTER  ## ... and away from each other; wider only where a lamp was dropped.
const MATERIAL := "metal"
const COVERAGE := 100.0
const PENETRATION := 85.0


func describe() -> Dictionary:
	return {
		"name": "Streetlights line the front, clear of the doorways",
		"description": "For every floorplan and several seeds: streetlights stand along the front sidewalk about 260 px apart, none within 140 px of a front or exit doorway nor in the strip out of one; each is a solid anchored metal post (coverage 100, penetration 85) carved into the nav map.",
		"tags": ["worldgen", "house", "street", "streetlight", "restyle"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


## The bounds of the house's rooms (world space).
func _bounds(rooms: Array) -> Rect2:
	var bounds: Rect2 = rooms[0]["rect"]
	for room in rooms:
		bounds = bounds.merge(room["rect"])
	return bounds


## The way out of the house through exterior doorway `door` (the edge of its one room it lies on).
func _outward(door: Dictionary, rect: Rect2) -> Vector2:
	var p: Vector2 = door["pos"]
	if absf(p.y - rect.end.y) < 1.0:
		return Vector2.DOWN
	if absf(p.y - rect.position.y) < 1.0:
		return Vector2.UP
	return Vector2.RIGHT if absf(p.x - rect.end.x) < 1.0 else Vector2.LEFT


## The strip straight out of exterior doorway `door`: its width plus the margin each side, `STRIP_REACH` px out.
func _strip(door: Dictionary, out: Vector2) -> Rect2:
	var p: Vector2 = door["pos"]
	var half: float = door["width"] * 0.5 + STRIP_MARGIN
	var across := Vector2(out.y, out.x).abs()
	var a := p - across * half
	var b := p + across * half + out * STRIP_REACH
	return Rect2(a, Vector2.ZERO).expand(b)


## The x-intervals of `band` (the front sidewalk) where the doorways' rules forbid a lamp: [[from, to], …].
func _forbidden(zones: Array, band: Rect2) -> Array:
	var out: Array = []
	for zone: Dictionary in zones:
		var strip: Rect2 = zone["strip"]
		if strip.intersects(band):
			out.append([strip.position.x, strip.end.x])
		var c: Vector2 = zone["pos"]
		var dy := maxf(0.0, maxf(band.position.y - c.y, c.y - band.end.y))
		if dy < DOOR_CLEAR:
			var dx := sqrt(DOOR_CLEAR * DOOR_CLEAR - dy * dy)
			out.append([c.x - dx, c.x + dx])
	return out


## Whether a forbidden interval of `forbidden` lies (partly) between `a` and `b`, which would have dropped a lamp there.
func _explained(forbidden: Array, a: float, b: float) -> bool:
	return forbidden.any(func(f: Array) -> bool: return f[1] > a and f[0] < b)


## Whether some hole of `holes` holds `p`.
func _carved(holes: Array, p: Vector2) -> bool:
	return holes.any(func(hole: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, hole))


func _check_house(t: TestContext, plan: String, house_seed: int, tally: Array) -> void:
	var label := "%s seed %d" % [plan, house_seed]
	var house := WorldGen.generate(house_seed, plan, ELSEWHERE, t.world)
	await t.frames(1)
	var rooms := WorldGen.get_rooms(house)
	var bounds := _bounds(rooms)
	var rect_of := {}
	for room in rooms:
		rect_of[room["key"]] = room["rect"]

	# The front sidewalk: the sidewalk piece of the street along the house's south side.
	var band := Rect2()
	for piece: Dictionary in WorldGen.get_street(house):
		var r: Rect2 = piece["rect"]
		if piece["kind"] == "sidewalk" and r.position.y >= bounds.end.y - 1.0:
			band = r
	if not t.check(band.has_area(), "%s: the street has a front sidewalk" % label):
		house.queue_free()
		return

	var zones: Array = []
	for door: Dictionary in WorldGen.get_openings(house):
		if door["front"] or door["exit"]:
			zones.append({ "pos": door["pos"], "strip": _strip(door, _outward(door, rect_of[door["rooms"][0]])) })
	var forbidden := _forbidden(zones, band)

	var lamps := WorldGen.get_streetlights(house)
	tally[0] += lamps.size()
	t.check(lamps.size() >= 1, "%s: streetlights stand along the front" % label)
	var holes := NavBuilder.furniture_holes(house)
	var xs: Array = []
	for lamp: Dictionary in lamps:
		var p: Vector2 = lamp["pos"]
		var node := lamp["node"] as Node2D
		xs.append(p.x)
		var at := "%s: the streetlight at %s" % [label, p.round()]
		t.check(band.grow(1.0).has_point(p), "%s stands on the front sidewalk %s" % [at, band])
		for zone: Dictionary in zones:
			var c: Vector2 = zone["pos"]
			t.check(p.distance_to(c) >= DOOR_CLEAR, "%s is %.0f px from the doorway at %s (at least %.0f)" % [at, p.distance_to(c), c, DOOR_CLEAR])
			t.check(not (zone["strip"] as Rect2).has_point(p), "%s is in the strip out of the doorway at %s" % [at, c])
		if not t.check(node != null and house.is_ancestor_of(node), "%s is a piece placed in the house" % at):
			continue
		t.check(node.global_position.distance_to(p) < 1.0, "%s: its node stands at its pos" % at)
		t.check(node is RigidBody2D and (node as RigidBody2D).freeze, "%s is anchored (frozen)" % at)
		t.check(node is CollisionObject2D and (node as CollisionObject2D).collision_layer & PhysicsLayers.SOLID != 0, "%s is solid (on PhysicsLayers.SOLID)" % at)
		var surface: Dictionary = node.get_surface()
		t.check(surface["material"] == MATERIAL and is_equal_approx(surface["coverage"], COVERAGE) and is_equal_approx(surface["penetration"], PENETRATION),
			"%s is a metal post (material %s, coverage %s, penetration %s)" % [at, surface["material"], surface["coverage"], surface["penetration"]])
		t.check(_carved(holes, p), "%s is carved into the nav map (NavBuilder.furniture_holes)" % at)

	# Spacing along the row: neighbours MIN_GAP..MAX_GAP apart, and the row runs the length of the front; a wider gap
	# (or a longer bare end) only where a doorway's rule dropped a lamp.
	xs.sort()
	for i in range(1, xs.size()):
		var gap: float = xs[i] - xs[i - 1]
		t.check(gap >= MIN_GAP, "%s: streetlights at x %.0f and %.0f are %.0f px apart (at least %.0f)" % [label, xs[i - 1], xs[i], gap, MIN_GAP])
		t.check(gap <= MAX_GAP or _explained(forbidden, xs[i - 1], xs[i]),
			"%s: a %.0f px gap between the streetlights at x %.0f and %.0f with no doorway in it (at most %.0f)" % [label, gap, xs[i - 1], xs[i], MAX_GAP])
	if not xs.is_empty():
		var west: float = xs[0] - band.position.x
		var east: float = band.end.x - xs[xs.size() - 1]
		t.check(west <= MAX_GAP or _explained(forbidden, band.position.x, xs[0]), "%s: the first streetlight is %.0f px from the west end of the front with no doorway between" % [label, west])
		t.check(east <= MAX_GAP or _explained(forbidden, xs[xs.size() - 1], band.end.x), "%s: the last streetlight is %.0f px from the east end of the front with no doorway between" % [label, east])
	house.queue_free()
	await t.frames(1)


func run(t: TestContext) -> void:
	var tally := [0]
	for plan in HouseDefinitions.get_all():
		for house_seed in SEEDS:
			await _check_house(t, plan, house_seed, tally)
	t.check(tally[0] > 0, "streetlights were placed (%d over every plan and seed)" % tally[0])
