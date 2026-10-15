extends GameTest

## G2 / G3: a grenade aimed at a spot just behind low cover comes to rest behind it. A lob touches down short of its aim and skids the
## rest of the way, so a sofa standing between the touchdown and the aim would stop the skid and kick the grenade back toward the
## thrower; the throw is lobbed farther instead, over the sofa, to touch down past it, and rolls on a little past the aim (as a throw
## aimed past `max_range` does, up to 100 px). A sofa (coverage 45, stood on end across the lane) 50 px in front of the aim point: the
## grenade ends on the far side of it, within that roll of the aim.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const FROM := Vector2(100, 150)
const SOFA := Vector2(430, 150)    ## stood on end: 50 px deep along the lane, 120 px across it
const SOFA_FAR_FACE := 455.0       ## its face away from the thrower
const AIM := Vector2(480, 150)     ## 25 px past that face, 380 px from the thrower: in range
const ROLL_ON := 100.0             ## how far past its aim a lob that touches down beyond it may roll (G2)


func describe() -> Dictionary:
	return {
		"name": "A grenade aimed behind a sofa comes to rest behind it",
		"description": "Thrown at a point just past a sofa standing across the lane, a stun grenade is lobbed over it and comes to rest on its far side, a roll past the aim, instead of skidding into it and bouncing back.",
		"tags": ["grenade", "lob", "cover", "item"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 300))
	s.switch(&"nav.rebake", false)
	s.object(&"sofa", "sofa", SOFA, { "rotated": true })
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 1, 0)
	if not t.require(Probe.count(thrower, Probe.STUN) == 1, "the thrower carries a stun grenade (Character.item_count(7) = %d)" % Probe.count(thrower, Probe.STUN)):
		return
	await Probe.throw_at(t, &"thrower", Probe.STUN, AIM)
	if not t.require(await Probe.wait_rest(t, 4.0), "the grenade comes to rest"):
		return
	var rest := Probe.rest_point(t)
	t.check(rest.x > SOFA_FAR_FACE, "it came to rest on the far side of the sofa (x %.0f, the far face at %.0f)" % [rest.x, SOFA_FAR_FACE])
	t.check(rest.distance_to(AIM) < ROLL_ON, "within a roll of the aim point (%.0f px off)" % rest.distance_to(AIM))
