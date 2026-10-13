extends GameTest

## G17, the `throw` primitive: the lob is checked again when the order is adopted (the NPC decided on a snapshot of a moment ago). One that is blocked by then is
## given up before the grenade is taken in hand: nothing is thrown, nothing is radioed, the NPC keeps its grenade and re-decides. One mechanism, scripted Von that
## answers slowly (30 physics frames a level): the invader has a clear lob onto a hostile hidden behind a desk when GRENADE is offered; a wardrobe (coverage 95,
## over a lob's clearance) is put on the line while its question is in flight.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const START := Vector2(100, 150)
const HOSTILE := Vector2(520, 150)
const ASIDE := Vector2(250, 40)
const ON_THE_LINE := Vector2(250, 150)


func describe() -> Dictionary:
	return {
		"name": "A throw whose lob got blocked is given up and the NPC re-decides",
		"description": "A wardrobe is put across the invader's lob while its GRENADE decision is in flight: no grenade is thrown or radioed, the invader still carries it and Von is asked again.",
		"tags": ["ai", "grenade", "combat", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([{ "key": "hall", "type": "living_room", "rect": Rect2(0, 0, 900, 300) }], [{ "pos": Vector2(880, 0), "width": 60.0 }])
	s.object(&"desk", "desk", Vector2(330, 150))
	s.object(&"wardrobe", "wardrobe", ASIDE)
	s.von_script([{ "pick": "combat" }, { "pick": "grenade" }, { "pick": "engage" }, { "pick": "advance" }, { "pick": "retreat" }], 30)
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"i", &"invader", START, { "facing": Vector2.RIGHT })
	Probe.hostile(s, &"h", HOSTILE, START)


func run(t: TestContext) -> void:
	var inv := t.actor(&"i")
	Probe.arm(inv, 0, 1)
	if not t.require(Probe.count(inv, Probe.FRAG) == 1, "the invader carries a frag (item_count(8) = %d)" % Probe.count(inv, Probe.FRAG)):
		return
	var brain := t.controller(&"i", &"debug_state")
	if not t.require(await t.until(func(): return brain.debug_state().get("decision", {}).get("pending", false), 10.0), "the NPC asked Von (the snapshot is made)"):
		return
	var wardrobe := t.object(&"wardrobe")
	wardrobe.freeze = true  # a frozen body takes a teleport (a free one is put back by the physics step)
	await t.frames(1)
	wardrobe.global_position = ON_THE_LINE
	await t.frames(1)
	var seen: Array = []
	if not t.require(await Probe.wait_act(t, &"i", "grenade", 10.0, seen), "the AI took the GRENADE tactic (its acts: %s)" % str(seen)):
		return
	t.check(not Probe.line_clear(t, inv.global_position, HOSTILE), "set-up: a wardrobe stands across the lob now")
	var asked := t.von_requests().size()
	if not t.require(await t.until(func(): return not str(brain.current_act()).contains("grenade"), 4.0), "the throw was given up (acting: %s)" % Probe.acts(t, &"i")):
		return
	await t.seconds(1.0)
	t.check(not t.happened(&"throw"), "no grenade was thrown")
	t.check(Probe.callouts(t, &"frag_out").is_empty(), "and none radioed")
	t.expect_eq(Probe.count(inv, Probe.FRAG), 1, "the invader still carries its frag")
	t.check(t.von_requests().size() > asked, "and Von was asked again")
