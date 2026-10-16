extends GameTest

## LD9 (`docs/leadership.md`): a stack order ends at `cleared_room`, and the member then acts on its own. A lone invader is
## ordered to stack quietly on the Terrace house's back door: it goes in, clears the kitchen (radioing `cleared_room`) and radios
## `order_step` `done`; from then on it decides for itself, asking Von again with no `ordered` fact and walking a path that is not the
## ORDER node's.
##
## Scripted Von (the first option offered): the member's own decisions after the order are Von's (scripted), the order's ask nothing.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A stack order ends at the cleared room",
		"description": "Ordered to stack on the back door, a lone invader clears the kitchen, radios done, and then decides for itself again: Von asked, no `ordered` fact, off the ORDER node (LD9).",
		"tags": ["ai", "entry", "leadership", "order", "scripted"],
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([])
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"a", &"invader", Vector2(990, 190))
	s.actor(&"lead", &"puppet", Vector2(1250, 600), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var a := t.actor(&"a")
	var b := Order.brain(t, &"a")
	var squad := Order.raid(t, [&"a"], &"lead")
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	await t.seconds(0.3)
	var order := Order.issue(squad, { "kind": Order.STACK, "to": [a], "pos": Order.BACK_SOUTH, "bang": false })
	if not t.require(not order.is_empty(), "the squad posts the order (issue)"):
		return
	if not t.require(await t.until(func(): return not Order.ordered_claims(t, a, Entry.BACK["id"]).is_empty(), 10.0), "the invader claims the back door under the order"):
		return
	var cleared := func(): return t.happened(&"callout", func(c): return c.get("speaker") == a and String(c.get("cleared_room", "")) == "kitchen")
	if not t.require(await t.until(cleared, 50.0), "it clears the kitchen (cleared_room radioed)"):
		return
	t.check(await t.until(func(): return not Order.progress(t, "done", a).is_empty(), 15.0), "and radios its order done")
	var asked := t.von_requests().size()
	var walks := Order.decisions(b)
	var own := func(): return Order.decisions(b) > walks and not bool(b.debug_brain().get("pending", true)) and not Order.on_order(b)
	t.check(await t.until(own, 20.0), "it then decides for itself, off the ORDER node (act %s)" % b.current_act())
	t.check(t.von_requests().size() > asked, "asking Von again")
	t.check(not Order.ordered(b), "without the `ordered` fact")
