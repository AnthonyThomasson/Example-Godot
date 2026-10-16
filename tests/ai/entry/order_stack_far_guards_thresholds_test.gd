extends GameTest

## LD9 / D4 (`docs/leadership.md`): a stack ordered from across the house guards each threshold it passes. An unordered
## entry's approach meets the guard only for doorway views (`_guard_approach`), not for thresholds. An invader standing in the Terrace house's
## living room is ordered to stack in the hall at the kitchen–hall doorway, into the kitchen; its way there goes through the
## hall–living doorway into the hall, a room nobody has cleared. It goes into the hall by tactical entry first (a detour: `going_in`
## for that doorway before it is ever in its funnel, no pause in it), then the ordered entry restarts afresh and it claims its slot at
## the kitchen doorway under the order and goes in.
##
## Scripted Von, down: the member's own decisions hold steady, so what it does is the order's alone (the guard's detour asks Von
## nothing). The order comes from the squad, as the leader's menu sends it.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")

## The hall–living doorway framed from the living room (the side the invader comes from), into the hall.
const INTO_HALL := { "id": "door_150_360", "pos": Maps.DOOR_HALL_LIVING, "width": 80.0, "out": Vector2.UP, "room": Maps.HOUSE_HALL, "room_key": "hall" }
## The ordered doorway: the kitchen–hall doorway, stacked on from the hall.
const ORDERED := "door_690_360"
## The leader's click: in the hall, east of the kitchen doorway along its wall (D3: the stack forms in the hall, into the kitchen).
const CLICK := Vector2(760, 395)


func describe() -> Dictionary:
	return {
		"name": "A stack ordered across the house enters the rooms on its way",
		"description": "An invader in the living room ordered to stack at the kitchen's hall doorway goes into the hall by entry first, then claims its ordered slot and goes in (LD9, D4).",
		"tags": ["ai", "entry", "leadership", "order", "guard", "scripted"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"a", &"invader", Vector2(70, 290), { "max_health": 1000000.0 })
	s.actor(&"lead", &"puppet", Vector2(-200, 600), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var squad := Order.raid(t, [&"a"], &"lead")
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	await t.seconds(0.3)
	var order := Order.issue(squad, { "kind": Order.STACK, "to": [t.actor(&"a")], "pos": CLICK, "bang": false })
	if not t.require(not order.is_empty(), "the squad posts the order (issue)"):
		return
	if not t.require(String(order.get("opening", "")) == ORDERED and String(order.get("into", "")) == "kitchen",
			"the order is for the kitchen–hall doorway, into the kitchen (premise; %s into %s)" % [order.get("opening"), order.get("into")]):
		return
	var a := t.actor(&"a")
	var in_ordered := func(): return Entry.first_call_time(t, "going_in", &"a", ORDERED) < INF
	var samples := await Entry.watch(t, [&"a"], INTO_HALL, 100.0, in_ordered)
	var first_hall := INF
	for s in samples:
		if Maps.HOUSE_HALL.has_point(s["pos"][&"a"]) and Entry.outward(INTO_HALL, s["pos"][&"a"]) < -Entry.INSIDE_DEPTH:
			first_hall = s["t"]
			break
	if not t.require(first_hall < INF, "the invader went into the hall on its way (premise: its route goes through the hall–living doorway)"):
		return
	Entry.check_entered(t, samples, &"a", INTO_HALL)
	t.check(not Order.ordered_claims(t, a, ORDERED).is_empty(), "after the detour it claims its slot at the ordered doorway under the order")
	var detour_in := Entry.first_call_time(t, "in", &"a", INTO_HALL["id"])
	var ordered_go := Entry.first_call_time(t, "going_in", &"a", ORDERED)
	t.check(ordered_go < INF and ordered_go > detour_in, "and goes in through it, after the hall (in the hall at %.2f s, going in to the kitchen at %.2f s)" % [detour_in, ordered_go])
