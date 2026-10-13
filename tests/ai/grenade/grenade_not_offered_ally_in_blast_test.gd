extends GameTest

## G17, the dropping rule for an ally: GRENADE is never offered when a known ally would be inside that grenade's danger zone at
## the landing spot (the option's `ally_in_blast` tag is in the tactic's `drop_tags`). One mechanism: an invader with a frag, a hostile
## behind a desk 420 px off (outside the invader's own zone, so only the ally matters; the thrower's own zone is
## `grenade_not_offered_no_safe_spot`). Scripted Von; the same scene is read twice: nobody in the way (GRENADE is offered), then an
## ally beside the hostile (dropped).

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Flank := preload("res://tests/_ai/flank_probe.gd")
const NPC_AT := Vector2(100, 250)
const HOSTILE_AT := Vector2(520, 250)
const DESK := Vector2(330, 250)
const ALLY_AT := Vector2(560, 330)  ## 100 px from the hostile, in the NPC's cone
const ALLY_PARKED := Vector2(850, 450)


func describe() -> Dictionary:
	return {
		"name": "A grenade is not offered when it would hit an ally",
		"description": "An invader with a frag and a hostile hidden behind a desk is offered GRENADE; with an ally 100 px from the hostile it is not.",
		"tags": ["ai", "grenade", "combat", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.object(&"desk", "desk", DESK)
	Flank.rules(s, [{ "pick": "combat" }, { "pick": "engage" }, { "pick": "advance" }, { "pick": "retreat" }])
	Flank.npc(s, &"n", NPC_AT, {}, &"invader", HOSTILE_AT)
	Probe.hostile(s, &"h", HOSTILE_AT, NPC_AT)
	Flank.ally(s, &"ally", ALLY_PARKED, { "aim_point": HOSTILE_AT })


func run(t: TestContext) -> void:
	var n := t.actor(&"n")
	Probe.arm(n, 0, 1)
	if not t.require(Probe.count(n, Probe.FRAG) == 1, "the invader carries a frag grenade (Character.item_count(8) = %d)" % Probe.count(n, Probe.FRAG)):
		return
	var brain := t.controller(&"n", &"current_act")
	if not t.require(await Flank.settle(t, brain), "the invader decides"):
		return
	t.check(Probe.offered(brain).has("engage") or Probe.offered(brain).has("advance"), "the tactic level is a real combat choice (%s)" % str(Probe.offered(brain)))
	if not t.require(Probe.offered(brain).has("grenade"), "with nothing in the way GRENADE is offered against the hidden hostile (offered %s)" % str(Probe.offered(brain))):
		return

	# An ally stands 100 px from the hostile, where the grenade would land.
	t.actor(&"ally").global_position = ALLY_AT
	await Flank.settle(t, brain)
	t.check(not Probe.offered(brain).has("grenade"), "an ally 100 px from the hostile is in the blast: GRENADE is dropped (offered %s)" % str(Probe.offered(brain)))
	t.check(not t.happened(&"throw"), "and nothing was thrown")
