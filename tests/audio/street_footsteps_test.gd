extends GameTest

## R6 (ticket #61): the outdoor ring round a generated house is drawn as street and sidewalk, and it registers no
## sound surface, so footsteps outside still sound like the open ground. A puppet walks out of the front door and
## down the front of the house: every step there plays the `outdoor` footstep. Then the street itself: the house
## has street and sidewalk pieces, drawn in the house, outside every room, ringing the house on all sides, under
## the walk just taken, and none of them is a sound surface.
##
## It reads the street through `WorldGen.get_street(house) -> Array` (interface 1, like `get_rooms`), of
## `{ kind, rect, node }`, one entry per piece of the ring: `kind` `street` or `sidewalk`, `rect` its world rect,
## `node` the node that draws it.

const Probe := preload("res://tests/_audio/sound_probe.gd")
const HOUSE_SEED := 4
const ENTRANCE := Vector2(600, 600)  ## Where the front door lands; the house stands north of it.
const START := ENTRANCE + Vector2(0, 30)  ## Just out of the front door.
const WALK_TO := 150.0  ## How far south of the door the walk ends (the outdoor ring is 160 px deep).
const OUT := 80.0  ## How far outside the house the ring is probed on each side and corner.


func describe() -> Dictionary:
	return {
		"name": "Footsteps on the street sound like outdoors",
		"description": "A puppet walking on the street ring outside a generated house plays the outdoor footstep; the house has street and sidewalk pieces ringing it, outside every room, registering no sound surface.",
		"tags": ["sound", "footstep", "surface", "outdoor", "street", "restyle"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.house(HOUSE_SEED, "", ENTRANCE)
	s.set_static(SoundConfig, &"category_range", Probe.EVERYWHERE)
	s.actor(&"walker", &"puppet", START)


## Whether some piece of `street` covers `p`.
func _covered(street: Array, p: Vector2) -> bool:
	return street.any(func(e: Dictionary) -> bool: return (e.get("rect", Rect2()) as Rect2).has_point(p))


func run(t: TestContext) -> void:
	var walker := t.puppet(&"walker")
	var body := t.actor(&"walker")
	walker.walk(Vector2.DOWN)
	if not t.require(await t.until(func(): return body.global_position.y > ENTRANCE.y + WALK_TO, 5.0, "the walker leaves the house"), "it walked out"):
		return
	walker.stop()
	var outside := Probe.sounds(t, &"footstep").filter(func(d): return d["position"].y > ENTRANCE.y + 20.0)
	t.check(outside.size() >= 3, "it took steps outside (%d)" % outside.size())
	t.expect_eq(Probe.profiles(outside), [&"footstep/outdoor/walk"], "every step outside sounded like the open ground")

	var house: Node2D = t.world.house
	var street := WorldGen.get_street(house)
	var kinds := street.map(func(e: Dictionary) -> String: return String(e.get("kind", "")))
	t.check(kinds.has("street"), "the ring has street (%s)" % [kinds])
	t.check(kinds.has("sidewalk"), "the ring has sidewalk (%s)" % [kinds])

	var rooms := WorldGen.get_rooms(house)
	var bounds: Rect2 = rooms[0]["rect"]
	for room: Dictionary in rooms:
		bounds = bounds.merge(room["rect"])
	for e: Dictionary in street:
		var rect: Rect2 = e.get("rect", Rect2())
		var node: Variant = e.get("node")
		t.check(node is CanvasItem and house.is_ancestor_of(node), "the %s at %s is drawn in the house" % [e.get("kind", ""), rect])
		for room: Dictionary in rooms:
			t.check(not rect.intersects((room["rect"] as Rect2).grow(-1.0)), "the %s at %s stays out of the %s" % [e.get("kind", ""), rect, room["key"]])
		t.expect_eq(SoundSurface.at(rect.get_center()), SoundSurface.OUTDOOR, "the %s at %s registers no sound surface" % [e.get("kind", ""), rect])

	# The ring goes all the way round: each side and each corner of the house, a little way out.
	var c := bounds.get_center()
	for p: Vector2 in [
		Vector2(c.x, bounds.position.y - OUT), Vector2(c.x, bounds.end.y + OUT),
		Vector2(bounds.position.x - OUT, c.y), Vector2(bounds.end.x + OUT, c.y),
		bounds.position - Vector2(OUT, OUT), Vector2(bounds.end.x + OUT, bounds.position.y - OUT),
		Vector2(bounds.position.x - OUT, bounds.end.y + OUT), bounds.end + Vector2(OUT, OUT),
	]:
		t.check(_covered(street, p), "the street ring covers %s, outside the house" % p)
	for step: Dictionary in outside:
		t.check(_covered(street, step["position"]), "the step at %s landed on the street ring" % step["position"])
