extends GameTest

## LD6 (`docs/leadership.md`): an ordered NPC that is shot at fights (the entry rules `under_fire → combat` and
## `engaged → combat` come before `ordered → order`), and goes back to its order once the fight lapses. The whole pipeline runs with
## the real Von server: a defender in the Terrace house's kitchen is ordered by its squad's leader to defend the kitchen; a hostile
## steps up to the back door, fires at it and walks off out of sight.
##
## Premises: the defender and the shooter cannot be killed (the fight must lapse, not end in a death); the shooter is an invader
## puppet (the scripted world event); the order is given through the squad as Main wires the leader's command menu to it.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")

## Just outside the back door, with a line into the kitchen; and well south of it in the garden, out of every line from the kitchen.
const AT_DOOR := Vector2(900, 190)
const AWAY := Vector2(1000, 520)


func describe() -> Dictionary:
	return {
		"name": "Shot at, an ordered defender fights, then resumes its order",
		"description": "A defender ordered to defend the kitchen is shot at through the back door: it takes a combat decision, and once the shooter is gone it goes back to its order (LD6).",
		"tags": ["ai", "decision", "leadership", "order", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"d", &"defender", Maps.KITCHEN_CENTRE, { "max_health": 1000000.0 })
	s.actor(&"boss", &"puppet", Vector2(300, 415), { "faction": &"household", "max_health": 1000000.0 })
	s.actor(&"shooter", &"puppet", AWAY, { "faction": &"invader", "start_slot": 3, "max_health": 1000000.0 })


func run(t: TestContext) -> void:
	var d := t.actor(&"d")
	var b := Order.brain(t, &"d")
	var squad := Order.squad(t, &"household", [t.actor(&"boss"), d], t.actor(&"boss"))
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	Order.issue(squad, { "kind": Order.DEFEND, "to": [d], "room": "kitchen" })
	if not t.require(await t.until(func(): return Order.on_order(b), 5.0), "the defender takes the order (act %s)" % b.current_act()):
		return
	await t.seconds(3.0)

	var shooter := t.puppet(&"shooter")
	shooter.walk_to(AT_DOOR)
	await t.until(shooter.has_arrived, 6.0)
	var fought := false
	for i in 4:
		shooter.aim_at(d)
		await t.seconds(0.6)
		shooter.shoot()
		fought = fought or String(b.current_act()).begins_with("combat")
	if not fought:
		fought = await t.until(func(): return String(b.current_act()).begins_with("combat"), 5.0)
	if not t.require(fought, "shot at, the defender fights (act %s)" % b.current_act()):
		return
	shooter.walk_to(AWAY)
	shooter.aim_at(AWAY + Vector2(0, 200))
	t.check(await t.until(func(): return Order.on_order(b), 40.0), "once the fight lapses it goes back to its order (act %s)" % b.current_act())
	t.check(String(Order.params(b).get("room", "")) == "kitchen", "the same order: defend the kitchen (%s)" % str(Order.params(b)))
