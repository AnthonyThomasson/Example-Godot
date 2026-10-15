extends GameTest

## E17 as amended by issue #51 R17: a hostile in view ends a quiet stack's listen hold early. The stack of two with a stun at the back door takes
## the quiet ENTER (scripted Von, nothing suspected), and its point holds in its slot to listen (`Listen.LISTEN`, 3 s). A second into the hold a
## householder stands in the doorway, in the point's view (on the line from its slot through the middle of the doorway): within `ENDS` s the
## point is no longer holding in its slot to listen, long before the hold would have run out.
##
## Premises: the householder is a puppet that cannot be killed and never shoots, put in the doorway a second into the hold (a defender showing
## itself); the invaders are armed with one stun each at the start of `run`, the way Main arms a spawn.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Listen := preload("res://tests/_ai/listen_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const AFTER := 1.0
const ENDS := 0.6
## How far inside the doorway the householder stands, on the point's line through it.
const INSIDE := 70.0


func describe() -> Dictionary:
	return {
		"name": "A hostile in view ends a quiet stack's listen hold",
		"description": "A quiet stack of two with a stun is holding at the back door to listen; a second in, a householder stands in the doorway in the point's view: it stops holding in its slot at once.",
		"tags": ["ai", "grenade", "entry", "stun", "listen", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Listen.world(s)
	Probe.hostile(s, &"h", Vector2(700, 40), Maps.DOOR_BACK)


func run(t: TestContext) -> void:
	for id in Listen.IDS:
		Probe.arm(t.actor(id), 1, 0)
	if not t.require(Listen.IDS.all(func(id): return Probe.count(t.actor(id), Probe.STUN) == 1), "each invader carries a stun"):
		return
	var p := await Listen.wait_point_ready(t, 15.0)
	if not t.require(p != &"", "the stack's point got to its slot at the back door"):
		return
	await t.seconds(AFTER)
	t.check(Listen.holding(t, p), "a second after the point got to its slot it is still holding there to listen (act %s, phase %s)" % [Probe.acts(t, p), str(Entry.entry(Entry.brain(t, p)).get("phase", ""))])
	var from: Vector2 = t.actor(p).global_position
	var shown := Maps.DOOR_BACK + (Maps.DOOR_BACK - from).normalized() * INSIDE
	if not t.require(Probe.line_clear(t, from, shown), "set-up: the householder's spot is in the point's line of sight through the doorway (%s from %s)" % [str(shown.round()), str(from.round())]):
		return
	Probe.place(t, &"h", shown, from)
	var at := t.time
	var ended := await t.until(func(): return not Listen.holding(t, p), ENDS)
	t.check(ended, "with a hostile in view, it stopped holding in its slot within %.1f s (act %s, phase %s, %.2f s after it showed)" % [ENDS, Probe.acts(t, p), str(Entry.entry(Entry.brain(t, p)).get("phase", "")), t.time - at])
