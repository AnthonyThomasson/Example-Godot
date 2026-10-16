extends GameTest

## LD7 (`docs/leadership.md`): progress on the radio. A member's callouts about its order carry `order_id` and
## `order_step` (`moving`, `in_position`, `done`, `refused`), and the squad keeps each member's latest step for `view()`. In the
## Terrace house: a defender ordered to defend the living room radios `in_position` once it holds there, and an invader ordered to stack
## quietly on the back door radios `done` once the kitchen is cleared; each squad's view shows its member's step.
##
## Scripted Von (the first option offered; the order level asks nothing). Premise switches: hostility on sight and on trespass are off,
## so the two sides in one house leave each other alone (each order is the mechanism under test, not a fight).

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")

## A click outside the back door, south of the opening (D3: the stack forms in the back garden, south of the door, into the kitchen).
const BACK_SOUTH := Vector2(870, 250)


func describe() -> Dictionary:
	return {
		"name": "Order progress is radioed and reaches the squad's view",
		"description": "A defender ordered to defend a room radios in_position, an invader ordered to stack radios done at the cleared room; each callout carries the order's id, and Squad.view() shows each member's latest step (LD7).",
		"tags": ["ai", "decision", "leadership", "order", "entry", "scripted"],
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([])
	s.switch(&"ai.hostile_on_sight", false)
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"d", &"defender", Vector2(420, 415))
	s.actor(&"home_lead", &"puppet", Vector2(700, 430), { "faction": &"household" })
	s.actor(&"a", &"invader", Vector2(1000, 190))
	s.actor(&"raid_lead", &"puppet", Vector2(1150, 450), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var d := t.actor(&"d")
	var a := t.actor(&"a")
	var home := Order.squad(t, &"household", [t.actor(&"home_lead"), d], t.actor(&"home_lead"))
	var raid := Order.squad(t, &"invader", [t.actor(&"raid_lead"), a], t.actor(&"raid_lead"))
	if not t.require(home != null and raid != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	await t.seconds(0.5)
	var defend := Order.issue(home, { "kind": Order.DEFEND, "to": [d], "room": "living_room" })
	var stack := Order.issue(raid, { "kind": Order.STACK, "to": [a], "pos": BACK_SOUTH, "bang": false })
	if not t.require(not defend.is_empty() and not stack.is_empty(), "both squads post their orders (issue)"):
		return

	var held := await t.until(func(): return not Order.progress(t, "in_position", d).is_empty(), 25.0)
	t.check(held, "the defender radios in_position once it holds the living room")
	if held:
		var said: Dictionary = Order.progress(t, "in_position", d)[0]
		t.expect_eq(str(said.get("order_id", "")), str(defend.get("id", "?")), "the callout names the order it is about")
		t.check(Maps.HOUSE_LIVING.has_point(d.global_position), "and it is in the living room when it says so (%s)" % str(d.global_position.round()))
		await t.frames(2)
		t.expect_eq(String(Order.member_view(home, d).get("step", "")), "in_position", "the squad's view shows the defender's step")

	var done := await t.until(func(): return not Order.progress(t, "done", a).is_empty(), 50.0)
	t.check(done, "the invader radios done for its stack order")
	if done:
		var said: Dictionary = Order.progress(t, "done", a)[0]
		t.expect_eq(str(said.get("order_id", "")), str(stack.get("id", "?")), "the callout names the order it is about")
		t.check(t.happened(&"callout", func(c): return c.get("speaker") == a and String(c.get("cleared_room", "")) == "kitchen"), "after it radioed the kitchen cleared")
		await t.frames(2)
		t.expect_eq(String(Order.member_view(raid, a).get("step", "")), "done", "the squad's view shows the invader's step")
