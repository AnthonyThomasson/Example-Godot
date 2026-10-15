extends GameTest

## G3: a thrown grenade does not strike its own thrower as it leaves the hand. It leaves the throwing hand beside the body (about 16 px from
## the body's centre, `docs/grenades.md` G17), and its first px pass within body + grenade radius of that centre; standing, the body is above
## the grenade's height there, so a pixel used to decide whether a throw struck its thrower and dropped at its feet. Here a stun is let go
## (`ThrownGrenade.spawn`, the item's own release) 19 px from a standing thrower's centre, just outside its body, on a path that passes 13 px
## from it: it flies on past its thrower and comes to rest near its aim, with no bounce near the thrower.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const AT := Vector2(300, 250)
const RELEASE := Vector2(294, 268)  ## 6 px behind the thrower and 18 px to its right as it faces east.
const AIM := Vector2(400, 210)
const GRENADE_RADIUS := 3.0  ## A thrown grenade's size against what it strikes (`ThrownGrenade.radius`).


func describe() -> Dictionary:
	return {
		"name": "A thrown grenade passes its own thrower",
		"description": "A stun let go just outside a standing thrower's body, on a path grazing it, flies on past the thrower and rests near its aim.",
		"tags": ["grenade", "throw", "item"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.actor(&"thrower", &"puppet", AT, { "max_health": 100000.0, "facing": Vector2.RIGHT, "aim_point": AIM })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	await t.seconds(0.2)
	var reach: float = float(thrower.radius) + GRENADE_RADIUS
	var path := (AIM - RELEASE).normalized()
	var closest: Vector2 = Geometry2D.get_closest_point_to_segment(AT, RELEASE, AIM)
	if not t.require(thrower.posture() == &"stand" and RELEASE.distance_to(AT) > reach and closest.distance_to(AT) < reach - 2.0,
			"set-up: a standing thrower, the release just outside its body (%.1f px, body + grenade %.0f), the path grazing it (%.1f px)" % [RELEASE.distance_to(AT), reach, closest.distance_to(AT)]):
		return
	ThrownGrenade.spawn(&"stun", RELEASE, AIM, thrower, thrower.world_root())
	if not t.require(await t.until(func(): return t.happened(&"grenade", func(d): return d.get("stage") == &"rest"), 3.0), "the grenade comes to rest"):
		return
	var bounces: Array = Probe.raw(t, &"grenade")
	var first: Vector2 = bounces[0]["data"]["position"]
	t.check(first.distance_to(RELEASE) > 40.0, "its first bounce is not at the thrower (%s, %.0f px from the release along %s)" % [str(first.round()), first.distance_to(RELEASE), str(path)])
	var rest: Vector2 = bounces[bounces.size() - 1]["data"]["position"]
	t.check(rest.distance_to(AIM) <= 45.0, "it rests near its aim (%.0f px from it)" % rest.distance_to(AIM))
