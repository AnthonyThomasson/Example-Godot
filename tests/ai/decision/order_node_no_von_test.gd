extends GameTest

## LD6 (`docs/leadership.md`): the ORDER node. An arriving order forces a new decision, the entry rule `ordered → order`
## takes the walk to the ORDER node, and its one option (the order) is auto-picked: the walk that adopts an order asks Von nothing.
## Scripted Von logs every question it is asked (`t.von_requests()`); an invader in the Terrace house's back garden is ordered to
## defend the kitchen, then given a newer order to defend the living room: each order is adopted by a walk of its own, with no
## question asked from the moment the order is posted.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "An order is adopted with no Von request",
		"description": "An order forces a decision walk that goes straight to the ORDER node and auto-picks the order: no question to Von, every level auto (LD6).",
		"tags": ["ai", "decision", "leadership", "order", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([])
	s.actor(&"a", &"invader", Vector2(1000, 190))
	s.actor(&"boss", &"puppet", Vector2(1100, 330), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var a := Order.brain(t, &"a")
	var boss := t.actor(&"boss")
	if not t.require(await t.until(func(): return not t.von_requests().is_empty() and not bool(a.debug_brain().get("pending", true)), 5.0),
			"the invader has made a decision of its own first, asking Von (premise)"):
		return
	for room in ["kitchen", "living_room"]:
		var asked := t.von_requests().size()
		var walks := Order.decisions(a)
		Order.post({ "id": "order_%s" % room, "leader": boss, "faction": boss.faction, "to": [t.actor(&"a")], "kind": Order.DEFEND, "room": room })
		var took := await t.until(func(): return Order.on_order(a) and String(_order_params(a).get("room", "")) == room, 3.0)
		if not t.check(took, "the order to defend the %s is adopted (act %s, params %s)" % [room, a.current_act(), str(_order_params(a))]):
			continue
		t.check(Order.decisions(a) > walks, "by a decision walk the order forced")
		t.expect_eq(t.von_requests().size(), asked, "no question was asked of Von from the order to its adoption (%s)" % room)
		var levels := Order.levels(a)
		t.check(not levels.is_empty() and String(levels[0].get("node", "")) == "order",
			"the walk started at the ORDER node (%s)" % str(levels.map(func(l): return l.get("node"))))
		t.check(levels.all(func(l): return bool(l.get("auto", false))), "every level of it was auto-picked")


## The params of the order the NPC carries out (`debug_state()["order"]`): the order's own also while the entry guard pauses it behind a
## detour into the room on its way (an invader's walk is guarded, LD8), when `debug_state()["params"]` are the detour's.
func _order_params(b: Node) -> Dictionary:
	return b.debug_state().get("order", {}).get("params", {})
