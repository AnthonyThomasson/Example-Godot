extends GameTest

## LD8 (`docs/leadership.md`): a member ordered to defend a room fights from inside it. In a fight Von still picks the
## tactic, but only among options inside that room (engage spots, retreat spots, flank sides and advance points outside it are dropped),
## and `_hold_ground` / `Combat.peek_cover` keep it in the room against a contact outside. The whole pipeline runs with the real Von
## server, in the furnished Terrace house: a defender ordered to defend the kitchen is shot at by an intruder standing in the hall
## just outside the kitchen's doorway, the fight a defender would otherwise take into the hall (advance, flank). It fights, and never
## leaves the kitchen. (An unordered defender may go out to it: that is the contrast, not asserted, since "may" is Von's call.)
##
## Premises: the defender and the intruder cannot be killed (the fight lasts the whole window); the intruder is an invader puppet that
## fires at the defender once a second (the scripted world event); the order is given through the squad, as Main wires the leader's
## command menu to it.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")

## In the kitchen, clear of the island and off the hall doorway's axis.
const D_AT := Vector2(570, 290)
## The intruder: in the hall, just south of the kitchen–hall doorway.
const INTRUDER_AT := Vector2(700, 435)
## How long (s) the fight is watched.
const WATCH := 25.0


func describe() -> Dictionary:
	return {
		"name": "A defender ordered to hold a room fights from inside it",
		"description": "Ordered to defend the kitchen and shot at from the hall, the defender fights (a combat decision) and never leaves the kitchen in 25 s (LD8).",
		"tags": ["ai", "combat", "leadership", "order", "defend", "von"],
		"requires_von": true,
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	s.actor(&"d", &"defender", D_AT, { "max_health": 1000000.0 })
	s.actor(&"lead", &"puppet", Vector2(80, 430), { "faction": &"household", "max_health": 1000000.0 })
	s.actor(&"intruder", &"puppet", INTRUDER_AT, { "faction": &"invader", "start_slot": 3, "max_health": 1000000.0, "aim_point": Vector2(700, 0) })


func run(t: TestContext) -> void:
	var d := t.actor(&"d")
	var b := Order.brain(t, &"d")
	var squad := Order.squad(t, &"household", [t.actor(&"lead"), d], t.actor(&"lead"))
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	Order.issue(squad, { "kind": Order.DEFEND, "to": [d], "room": "kitchen" })
	if not t.require(await t.until(func(): return Order.on_order(b), 5.0), "the defender takes the order (act %s)" % b.current_act()):
		return
	await t.seconds(2.0)

	var intruder := t.puppet(&"intruder")
	var fought := false
	var outside: Array = []
	var end := t.time + WATCH
	var next_shot := t.time
	while t.time < end:
		if not Maps.HOUSE_KITCHEN.has_point(d.global_position) and outside.size() < 5:
			outside.append("%.1f s at %s (act %s)" % [t.time, str(d.global_position.round()), b.current_act()])
		fought = fought or String(b.current_act()).begins_with("combat")
		if t.time >= next_shot:
			intruder.aim_at(d)
			if t.time >= next_shot + 0.4:
				intruder.shoot()
				next_shot = t.time + 1.0
		t.trace("d_y", d.global_position.y)
		await t.frames(1)
	if not t.require(fought, "shot at, the defender fights (it never took a combat decision; act %s)" % b.current_act()):
		return
	t.check(outside.is_empty(), "the ordered defender never left the kitchen (%s)" % "; ".join(outside))
