extends GameTest

## G17, a throw order whose target dies on the way: the order keeps its spot when the contact it was offered on ages out on the way, but not
## when that hostile is dead. Killed while the thrower walks to its throw spot, the target leaves what the NPC knows, the NPC decides again at
## once and no grenade is thrown onto the body. The Terrace house, bare; the premise is `grenade_throw_spot_round_wall`'s (an invader with a stun
## outside the back door sees a household puppet in the kitchen, is moved behind the kitchen's east wall while its first question is in
## flight, and that question fails), so its first decision is a GRENADE through a throw spot at the back doorway, which it walks to.
##
## Other premises: the puppet never shoots, so no shots' origin is left to throw at once it is dead; it is killed with `take_damage` the first
## frame the invader is walking to the throw spot; the invader is armed at the start of `run`, the way Main arms a spawn.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const I_AT := Vector2(960, 190)
const BEHIND := Vector2(900, 50)
const H_AT := Vector2(660, 120)


func describe() -> Dictionary:
	return {
		"name": "A throw whose target is killed on the way re-decides",
		"description": "An invader walking to its throw spot to lob a stun onto a householder decides again the moment the householder is killed, and throws nothing.",
		"tags": ["ai", "grenade", "combat", "throw_spot", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([{ "pick": "combat" }, { "pick": "grenade" }, { "pick": "stun" }, { "pick": "engage" }, { "pick": "advance" }, { "pick": "retreat" }], 30)
	s.set_static(DecisionStub, "fail", false)  # Registered so the runner restores it: `run` sets it for the in-sight question only (the premise).
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"i", &"invader", I_AT, { "facing": (H_AT - I_AT).normalized() })
	Probe.hostile(s, &"h", H_AT, Maps.DOOR_BACK)


func run(t: TestContext) -> void:
	var inv := t.actor(&"i")
	var hh := t.actor(&"h")
	Probe.arm(inv, 1, 0)
	if not t.require(Probe.count(inv, Probe.STUN) == 1, "the invader carries a stun (item_count(7) = %d)" % Probe.count(inv, Probe.STUN)):
		return
	var brain := t.controller(&"i", &"debug_zones")
	if not t.require(await t.until(func(): return brain.debug_state().get("decision", {}).get("pending", false), 10.0), "the invader asked its first question, in sight"):
		return
	DecisionStub.fail = true
	inv.global_position = BEHIND
	inv.velocity = Vector2.ZERO
	var failed := await t.until(func(): return not brain.debug_state().get("decision", {}).get("pending", false), 5.0)
	DecisionStub.fail = false
	if not t.require(failed and t.von_requests().size() == 1 and str(t.von_requests()[0]["pick"]) == "",
			"set-up: the question asked in sight failed, so no order made in sight was carried out (requests %s)" % str(t.von_requests().map(func(r): return r["pick"]))):
		return
	var walking := func() -> bool:
		return "grenade" in brain.current_act() and "walking to the throw spot" in brain.debug_status()
	if not t.require(await t.until(walking, 20.0), "set-up: the invader took GRENADE through a throw spot and walks to it (acts %s)" % Probe.acts(t, &"i")):
		return
	var decisions := int(brain.debug_state().get("decisions", 0))
	hh.take_damage(hh.max_health * 2.0)
	if not t.require(hh.is_dead, "set-up: the householder is dead"):
		return
	var redecided := await t.until(func(): return int(brain.debug_state().get("decisions", 0)) > decisions, 1.0)
	t.check(redecided, "the invader decided again once its target was dead (decisions %d -> %d; status %s)" % [decisions, int(brain.debug_state().get("decisions", 0)), brain.debug_status()])
	var thrown := func() -> bool: return t.happened(&"throw", func(d): return d.get("attacker") == inv)
	await t.until(thrown, 6.0)
	t.check(not thrown.call(), "no grenade was thrown onto the dead householder (acts %s)" % Probe.acts(t, &"i"))
	t.check("grenade" not in brain.current_act(), "the throw order was dropped (act %s)" % brain.current_act())
