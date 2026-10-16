extends GameTest

## LD8 / D8 (`docs/leadership.md`): a member defending a room and a live grenade. The evade reflex runs as it does anywhere
## and may take it out of the room; once the grenade has burst, the member walks back in and holds ("never leaves the room" is a rule
## on its fight options, not on the reflex). A defender ordered to defend the box room (a room 140 px square off a corridor) sees a frag
## thrown in through the doorway: the whole room is in its danger zone, so it runs out into the corridor; after the burst it goes back
## into the box room and holds there on its order.
##
## Scripted Von (the first option offered; the order level asks nothing). Premises: the thrower is an invader puppet that cannot be
## killed (the scripted world event), armed with one frag the way Main arms a spawn; hostility on trespass is off, so the defender does
## not fight the thrower for trespassing, and once it has thrown the thrower walks off out of the defender's line from the box room (the
## reflex and the return are what is watched, not a fight).

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")

const D_AT := Vector2(260, 110)
const THROWER_AT := Vector2(290, 275)
const LANDING := Vector2(290, 120)
## Where the thrower walks off to once its frag is away: east along the corridor, out of every line from inside the box room.
const AWAY := Vector2(520, 285)


func describe() -> Dictionary:
	return {
		"name": "A defender driven out by a frag walks back into its room",
		"description": "Ordered to defend the box room, a defender runs out from a frag thrown in; after the burst it walks back in and holds on its order (LD8, D8).",
		"tags": ["ai", "combat", "leadership", "order", "defend", "grenade", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.box_room(s)
	s.von_script([])
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"d", &"defender", D_AT, { "max_health": 1000000.0 })
	s.actor(&"lead", &"puppet", Vector2(560, 280), { "faction": &"household", "max_health": 1000000.0 })
	s.actor(&"thrower", &"puppet", THROWER_AT, { "faction": &"invader", "max_health": 1000000.0, "aim_point": LANDING })


func run(t: TestContext) -> void:
	var d := t.actor(&"d")
	var b := Order.brain(t, &"d")
	var squad := Order.squad(t, &"household", [t.actor(&"lead"), d], t.actor(&"lead"))
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	Order.issue(squad, { "kind": Order.DEFEND, "to": [d], "room": "box_room" })
	if not t.require(await t.until(func(): return Order.on_order(b) and Order.primitive(b) == "defend", 5.0), "the defender takes the order (act %s)" % b.current_act()):
		return
	await t.seconds(3.0)
	if not t.require(Maps.BOX_ROOM.has_point(d.global_position), "it holds inside the box room (premise; at %s)" % str(d.global_position.round())):
		return

	Probe.arm(t.actor(&"thrower"), 0, 1)
	await Probe.throw_at(t, &"thrower", Probe.FRAG, LANDING)
	# Premise: once the frag is away the thrower walks off east along the corridor, out of the defender's line from inside the box room.
	# The fragments striking round the defender are an attack by the thrower (`hostile_on_attack`), and a hostile left standing in its
	# line from its post would be fought from inside the room (LD8): the hold watched here is the order's, not that fight.
	await t.until(func(): return not Probe.live(t).is_empty(), 2.0)
	t.puppet(&"thrower").walk_to(AWAY)
	var left := false
	while Probe.booms(t, &"frag").is_empty() and t.time < 30.0:
		left = left or not Maps.BOX_ROOM.has_point(d.global_position)
		await t.frames(1)
	if not t.require(not Probe.booms(t, &"frag").is_empty(), "the frag went off"):
		return
	if not t.require(left, "the frag drove the defender out of the box room (premise: it was in the danger zone; it stayed at %s)" % str(d.global_position.round())):
		return
	t.check(not d.is_dead, "it survived the burst")

	var back := await t.until(func(): return Maps.BOX_ROOM.has_point(d.global_position) and Order.on_order(b), 15.0)
	t.check(back, "after the burst it walks back into the box room on its order (at %s, act %s)" % [str(d.global_position.round()), b.current_act()])
	if back:
		await t.seconds(2.0)
		t.check(Maps.BOX_ROOM.has_point(d.global_position) and Order.primitive(b) == "defend", "and holds there (at %s, %s)" % [str(d.global_position.round()), Order.primitive(b)])
