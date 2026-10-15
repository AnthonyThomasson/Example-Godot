extends GameTest

## G16 with G17: the evade reflex takes priority over every primitive but one moment, the NPC's own grenade in the wind-up. That grenade
## cannot be called back and leaves the hand at most a wind-up (0.3 s) later toward where it is aimed; turning away to run meanwhile would
## throw it the wrong way. So a thrower in its wind-up when a grenade lands beside it throws first, onto its spot, and runs the moment it has
## let go. One mechanism, scripted Von (COMBAT > GRENADE): an invader with a stun winds up a throw at a household puppet hidden behind a desk;
## as the wind-up begins, a teammate's stun comes down beside it, in its view from the moment it is let go (a premise: let go by the
## teammate, a puppet off to the side). The invader's stun bursts on the puppet, and the invader then runs from the teammate's stun.
##
## Premises: the puppets cannot be killed and never shoot; the teammate's stun is let go by the item's own release (`ThrownGrenade.spawn`)
## at the start of the invader's wind-up; the invader is armed at the start of `run`, the way Main arms a spawn.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const I_AT := Vector2(100, 150)
const H_AT := Vector2(500, 150)
const MATE_AT := Vector2(40, 270)  ## Out of the zone of a stun on the puppet (an ally there would drop the throw).
## Where the teammate's stun is let go from and comes down: in front of the invader, in its view from the moment it leaves the hand, and
## beside it, inside its flash zone.
const MATE_RELEASE := Vector2(180, 70)
const MATE_AIM := Vector2(160, 110)


func describe() -> Dictionary:
	return {
		"name": "A thrower in its wind-up throws first, then evades",
		"description": "A teammate's stun lands beside an invader that is winding up a throw: the invader's stun still goes onto its spot, and only then does it run.",
		"tags": ["ai", "grenade", "evade", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([{ "key": "hall", "type": "living_room", "rect": Rect2(0, 0, 900, 300) }], [{ "pos": Vector2(880, 0), "width": 60.0 }])
	s.object(&"desk", "desk", Vector2(330, 150))
	s.von_script([{ "pick": "combat" }, { "pick": "grenade" }, { "pick": "engage" }, { "pick": "advance" }, { "pick": "retreat" }])
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"i", &"invader", I_AT, { "facing": Vector2.RIGHT })
	s.actor(&"mate", &"puppet", MATE_AT, { "faction": &"invader", "max_health": 1000000.0 })
	Probe.hostile(s, &"h", H_AT, I_AT)


func run(t: TestContext) -> void:
	var inv := t.actor(&"i")
	Probe.arm(inv, 1, 0)
	if not t.require(Probe.count(inv, Probe.STUN) == 1, "the invader carries a stun (item_count(7) = %d)" % Probe.count(inv, Probe.STUN)):
		return
	var winding := func() -> bool:
		var item = inv.current_item()
		return item != null and item.hand_stance(0) == &"throw"
	if not t.require(await t.until(winding, 8.0), "the invader winds up a throw (acts %s)" % Probe.acts(t, &"i")):
		return
	var mate := t.actor(&"mate")
	ThrownGrenade.spawn(&"stun", MATE_RELEASE, MATE_AIM, mate, mate.world_root())
	var mine := func(d): return d.get("attacker") == inv
	if not t.require(await t.until(func(): return t.happened(&"throw", mine), 1.0), "the invader's stun left its hand"):
		return
	var brain := t.controller(&"i", &"debug_state")
	var ran := await t.until(func(): return not (brain.debug_state().get("evade", {}) as Dictionary).is_empty(), 1.0)
	t.check(ran, "then it runs from the teammate's stun (acts %s)" % Probe.acts(t, &"i"))
	if not t.require(await t.until(func(): return Probe.booms(t, &"stun").size() >= 2, 4.0), "both stuns went off"):
		return
	var bursts: Array = Probe.booms(t, &"stun").map(func(e): return e["data"]["position"])
	var on_spot: Array = bursts.filter(func(p): return (p as Vector2).distance_to(H_AT) < 110.0)
	t.check(not on_spot.is_empty(), "its stun went off on the puppet's spot (bursts %s)" % str(bursts))
