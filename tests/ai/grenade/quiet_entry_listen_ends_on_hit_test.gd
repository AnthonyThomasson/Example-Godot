extends GameTest

## E17 as amended by issue #51 R17: coming under fire ends a quiet stack's listen hold early. The stack of two with a stun at the back door takes
## the quiet ENTER (scripted Von, nothing suspected), and its point holds in its slot to listen (`Listen.LISTEN`, 3 s). A second into the hold a
## shot lands beside the point, from out in the garden (not from the kitchen, so the room does not become suspect): within `ENDS` s the point is
## no longer holding in its slot to listen, long before the hold would have run out.
##
## Premises: the shot is one `hit` event nobody known fired, landing beside the point, its direction from the garden east of it; the invaders are
## armed with one stun each at the start of `run`, the way Main arms a spawn.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Listen := preload("res://tests/_ai/listen_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const AFTER := 1.0
const ENDS := 0.6


func describe() -> Dictionary:
	return {
		"name": "A shot ends a quiet stack's listen hold",
		"description": "A quiet stack of two with a stun is holding at the back door to listen; a second in, a shot lands beside the point: it stops holding in its slot at once.",
		"tags": ["ai", "grenade", "entry", "stun", "listen", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Listen.world(s)


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
	var at: Vector2 = t.actor(p).global_position
	var landed := at + Vector2(20, -20)
	EventBus.post(&"hit", { "position": landed, "direction": Vector2.LEFT, "damage": 10.0, "attacker": null, "victim": null })
	var shot := t.time
	var ended := await t.until(func(): return not Listen.holding(t, p), ENDS)
	t.check(ended, "under fire, it stopped holding in its slot within %.1f s (act %s, phase %s, %.2f s after the shot)" % [ENDS, Probe.acts(t, p), str(Entry.entry(Entry.brain(t, p)).get("phase", "")), t.time - shot])
