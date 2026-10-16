extends GameTest

## LD6 and LD8 (`docs/leadership.md`): an order the NPC cannot carry out is refused, and the decision walk it starts with is its own,
## not the order's. A `defend_room` order keeps the member's fight to options inside that room (`confine_room`); one naming a room the
## NPC does not know is ended `refused` as the walk starts, and that walk is then not confined to the refused room: the defender
## fighting a hostile in its living room still has its living-room firing spots, so it engages, with no `confine_room` in the leaf.
##
## Scripted Von (COMBAT, then ENGAGE): a defender in the Terrace house's living room sees an invader puppet across the room (unkillable,
## never shoots). The order is posted straight onto the bus, as a squad posts one, naming a room key the house does not have (a squad
## never produces one: the case is the defend spot or room going missing between the order and the walk).

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const D_AT := Vector2(150, 180)
const H_AT := Vector2(360, 180)


func describe() -> Dictionary:
	return {
		"name": "A refused order leaves the walk unconfined",
		"description": "A defender given a defend order for a room it does not know radios refused, and the decision it then makes fights from its own room with no confine_room in the leaf (LD6, LD8).",
		"tags": ["ai", "decision", "leadership", "order", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }])
	s.switch(&"projectile.flyover", false)
	s.actor(&"d", &"defender", D_AT, { "facing": Vector2.RIGHT })
	s.actor(&"h", &"puppet", H_AT, { "faction": &"invader", "max_health": 1000000.0, "aim_point": D_AT, "facing": Vector2.LEFT })


func run(t: TestContext) -> void:
	var d := t.actor(&"d")
	var brain := Order.brain(t, &"d")
	var engaging := func() -> bool:
		return "engage" in brain.current_act() and not brain.debug_state().get("decision", {}).get("pending", false)
	if not t.require(await t.until(engaging, 8.0), "set-up: the defender engages the invader in its living room (act %s)" % brain.current_act()):
		return
	var walks := Order.decisions(brain)
	Order.post({ "id": "o1", "leader": t.actor(&"h"), "faction": d.faction, "to": [d], "kind": Order.DEFEND, "room": "no_such_room" })
	if not t.require(await t.until(func(): return not Order.progress(t, "refused", d).is_empty(), 3.0), "the defender refuses the order (it does not know the room)"):
		return
	var decided := func() -> bool:
		return Order.decisions(brain) > walks and not brain.debug_state().get("decision", {}).get("pending", false)
	if not t.require(await t.until(decided, 3.0), "the order forced a decision (decisions %d)" % Order.decisions(brain)):
		return
	t.check(not Order.ordered(brain), "the walk was made without `ordered`")
	t.check("combat" in brain.current_act() and "engage" in brain.current_act(), "the defender still fights from its living room: COMBAT - ENGAGE (act %s)" % brain.current_act())
	t.check(not Order.params(brain).has("confine_room"), "the leaf carries no confine_room (params %s)" % str(Order.params(brain)))
