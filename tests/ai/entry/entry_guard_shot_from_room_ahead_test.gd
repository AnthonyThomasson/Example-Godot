extends GameTest

## E9 as amended (issue #51, R10): the under-fire exemption does not cover a walk into the room the shots come from. A household shooter
## fires on the invader from the kitchen through the back door while it is ordered to rush it. Shot at from a room it is outside of, the
## invader does not walk straight in under fire: it fights from outside (E14) and goes in, if at all, only by an entry it stacked for
## (`going_in` before it stands in the kitchen). The exemption that stays (shots from anywhere else) is `entry_guard_under_fire_exempt`.
##
## Premises: the shooter is a puppet that cannot be killed (so it holds the doorway, in view, the whole test); the invader cannot be
## killed either (it takes every round the shooter fires); Von is scripted to the rush (`Entry.guard_rules`), so the order is the one a
## straight walk in would follow.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const START := Vector2(990, 190)
const SHOOTER := Vector2(620, 190)
## How long the invader is watched under fire (s).
const WATCH := 15.0


func describe() -> Dictionary:
	return {
		"name": "Entry guard holds under fire from the room ahead",
		"description": "Shot at from the kitchen through the back door while ordered to rush it, the invader fights from outside and goes in only by an entry.",
		"tags": ["ai", "entry", "guard", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.guard_rules(s, ["combat", "advance", "rush"])
	Entry.npc(s, &"inv", START, 0.4, {}, { "facing": Vector2.LEFT })
	Entry.target(s, &"shooter", SHOOTER, START, { "start_slot": 3, "faction": &"household" })


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var shooter := t.puppet(&"shooter")
	var hit_outside := [false]
	# The first moment the invader stood in the kitchen, and whether it had radioed going_in for the back door by then.
	var first_in := [INF, false]
	var end := t.time + WATCH
	while t.time < end:
		shooter.aim_at(inv)
		shooter.shoot()
		var inside := Maps.HOUSE_KITCHEN.grow(-30).has_point(inv.global_position)
		if not inside and inv.damage_taken() > 0.0:
			hit_outside[0] = true
		if inside and first_in[0] == INF:
			first_in[0] = t.time
			first_in[1] = Entry.first_call_time(t, "going_in", &"inv", Entry.BACK["id"]) <= t.time
		await t.frames(1)
	if not t.require(hit_outside[0], "the invader was under fire from the kitchen while outside it (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	t.check(Entry.first_call_time(t, "claim", &"inv", Entry.BACK["id"]) < INF, "it stacked for the back door as an entry (a claim radioed)")
	t.check(first_in[0] == INF or first_in[1], "it never walked straight into the kitchen: in, if at all, only after its going_in (first in at %.2f s)" % first_in[0])
	var from_outside := t.events_of(&"shot").filter(func(d): return d.get("attacker") == inv and not Maps.HOUSE_KITCHEN.has_point(d["position"]))
	t.check(not from_outside.is_empty(), "it fought the shooter from outside (%d shots from outside the kitchen)" % from_outside.size())
