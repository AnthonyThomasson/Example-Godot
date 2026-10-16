extends GameTest

## LD9 / D4, D11 (`docs/leadership.md`): a defender ordered to stack. An ordered stack runs whatever `entry_enabled` says, and
## its approach is guarded like any walk; but for a defender's ordered walk across its own house, a room it has seen empty within
## `entry_pass_clear_time` (60 s) is clear for passing (no entry at a doorway into it), while a room it has not seen still gets one.
##
## A corridor with three rooms off its north side (A, B, C) and a den behind room A. A defender starts in the corridor (it stands in it:
## seen, with nobody in it) and is first ordered to defend room C, which it walks into. It is then ordered to stack in room A at the
## den's doorway, into the den. Its way there goes back out into the corridor (seen empty seconds ago: no entry at room C's doorway) and
## then into room A, which it has never stood in (an entry at room A's doorway, before it is in its funnel), and it then claims its slot
## at the den's doorway under the order and goes in.
##
## Scripted Von, down: the defender's own decisions hold steady, so what it does is the orders' alone. "Seen empty" is read here as the
## room the NPC stood in with nobody hostile in it (a room only glimpsed through its doorway on the way is not seen: the plan's open risk).

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Order := preload("res://tests/_ai/order_probe.gd")

const CORRIDOR := Rect2(0, 200, 900, 100)
const ROOM_A := Rect2(0, 0, 300, 200)
const ROOM_C := Rect2(600, 0, 300, 200)
const DEN := Rect2(0, -200, 300, 200)
## Room C's doorway, framed from room C (the defender comes out of it into the corridor).
const OUT_OF_C := { "id": "door_750_200", "pos": Vector2(750, 200), "width": 80.0, "out": Vector2.UP, "room": CORRIDOR, "room_key": "corridor" }
## Room A's doorway, framed from the corridor (the defender goes into room A).
const INTO_A := { "id": "door_150_200", "pos": Vector2(150, 200), "width": 80.0, "out": Vector2.DOWN, "room": ROOM_A, "room_key": "room_a" }
const ORDERED := "door_150_0"
## The leader's click: in room A, east of the den's doorway along its wall (D3: the stack forms in room A, into the den).
const CLICK := Vector2(210, 30)


func describe() -> Dictionary:
	return {
		"name": "A defender's ordered stack passes rooms it has seen empty",
		"description": "A defender ordered to stack at a far doorway walks out into a corridor it has seen empty with no entry, goes into a room it has not seen by entry, then stacks under the order (LD9, D4, D11).",
		"tags": ["ai", "entry", "leadership", "order", "guard", "defender", "scripted"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "corridor", "type": "hallway", "rect": CORRIDOR },
		{ "key": "room_a", "type": "bedroom", "rect": ROOM_A },
		{ "key": "room_b", "type": "home_office", "rect": Rect2(300, 0, 300, 200) },
		{ "key": "room_c", "type": "kitchen", "rect": ROOM_C },
		{ "key": "den", "type": "living_room", "rect": DEN },
	], [
		{ "pos": Vector2(150, 0), "width": 80.0 },
		{ "pos": Vector2(150, 200), "width": 80.0 },
		{ "pos": Vector2(450, 200), "width": 80.0 },
		{ "pos": Vector2(750, 200), "width": 80.0 },
		{ "pos": Vector2(0, 250), "width": 80.0 },
	])
	s.von_down()
	s.actor(&"d", &"defender", Vector2(600, 250), { "max_health": 1000000.0 })
	s.actor(&"lead", &"puppet", Vector2(-120, 250), { "faction": &"household" })


func run(t: TestContext) -> void:
	var d := t.actor(&"d")
	var squad := Order.squad(t, &"household", [t.actor(&"lead"), d], t.actor(&"lead"))
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	await t.seconds(0.5)
	Order.issue(squad, { "kind": Order.DEFEND, "to": [d], "room": "room_c" })
	if not t.require(await t.until(func(): return ROOM_C.grow(-30.0).has_point(d.global_position), 15.0), "the defender walks into room C on its first order (at %s)" % str(d.global_position.round())):
		return
	await t.seconds(1.0)

	var order := Order.issue(squad, { "kind": Order.STACK, "to": [d], "pos": CLICK, "bang": false })
	if not t.require(String(order.get("opening", "")) == ORDERED and String(order.get("into", "")) == "den",
			"the order is for the den's doorway, into the den (premise; %s into %s)" % [order.get("opening"), order.get("into")]):
		return
	var through := func(): return Entry.first_call_time(t, "going_in", &"d", ORDERED) < INF
	var samples := await Entry.watch(t, [&"d"], INTO_A, 100.0, through)
	var in_corridor := samples.any(func(s): return CORRIDOR.grow(-25.0).has_point(s["pos"][&"d"]))
	var in_a := samples.any(func(s): return Entry.in_room(INTO_A, s["pos"][&"d"]))
	if not t.require(in_corridor and in_a, "the defender's way went out into the corridor and into room A (premise; corridor %s, room A %s)" % [str(in_corridor), str(in_a)]):
		return
	t.check(Entry.first_call_time(t, "going_in", &"d", OUT_OF_C["id"]) == INF and Entry.calls(t, "claim", &"d").all(func(c): return String(c.get("opening", "")) != OUT_OF_C["id"]),
		"no entry at room C's doorway into the corridor, a room it has seen empty")
	Entry.check_entered(t, samples, &"d", INTO_A)
	var ordered_go := Entry.first_call_time(t, "going_in", &"d", ORDERED)
	t.check(not Order.ordered_claims(t, d, ORDERED).is_empty(), "it claims its slot at the den's doorway under the order")
	t.check(ordered_go < INF and ordered_go > Entry.first_call_time(t, "in", &"d", INTO_A["id"]), "and goes into the den after room A (at %.2f s)" % ordered_go)
