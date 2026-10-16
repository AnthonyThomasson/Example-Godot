extends GameTest

## LD9 / D7 (`docs/leadership.md`): go when ready. An ordered stack's point crosses once every living recipient of the order
## has radioed `ready` (up to the safety cap `order_ready_cap`, 60 s from the first ordered `ready`); the `entry_ready_timeout` (6 s)
## still applies to unordered joiners only. Two invaders are ordered to stack on the Terrace house's back door: one starts beside it, the
## other far off beyond the house's north-west corner, a long walk round its north side (about 1300 px, some 8 s). The near one is ready long before the far one; the point does not go
## in until the far one has radioed `ready`, well past the 6 s an unordered stack would wait.
##
## Scripted Von, down: the members' own decisions hold steady, so what they do is the order's alone.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")

## The ready timeout an unordered stack goes on after (`entry_ready_timeout`).
const READY_TIMEOUT := 6.0


func describe() -> Dictionary:
	return {
		"name": "An ordered stack waits for every recipient",
		"description": "Ordered to stack on the back door, the near invader is ready long before the far one; the point goes in only after the far one radios ready, past the unordered 6 s timeout (LD9, D7).",
		"tags": ["ai", "entry", "leadership", "order", "scripted"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"near", &"invader", Vector2(960, 60))
	s.actor(&"far", &"invader", Vector2(-140, -140))
	s.actor(&"lead", &"puppet", Vector2(1250, 600), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var squad := Order.raid(t, [&"near", &"far"], &"lead")
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	await t.seconds(0.3)
	var order := Order.issue(squad, { "kind": Order.STACK, "to": [t.actor(&"near"), t.actor(&"far")], "pos": Order.BACK_NORTH, "bang": false })
	if not t.require(not order.is_empty(), "the squad posts the order (issue)"):
		return
	var near_ready := func(): return Entry.first_call_time(t, "ready", &"near", Entry.BACK["id"]) < INF
	if not t.require(await t.until(near_ready, 15.0), "the near invader stacks and radios ready"):
		return
	var ready_near := Entry.first_call_time(t, "ready", &"near", Entry.BACK["id"])
	var went := await t.until(func(): return not Entry.calls(t, "going_in").is_empty(), Order.ORDER_READY_CAP + 10.0)
	if not t.require(went, "the point goes in at last"):
		return
	var ready_far := Entry.first_call_time(t, "ready", &"far", Entry.BACK["id"])
	var going := Order.first_time(t, &"callout", func(d): return String(d.get("entry_step", "")) == "going_in")
	t.check(ready_far < INF, "the far invader reached the stack and radioed ready")
	t.check(going >= ready_far, "the point went in only once the far invader was ready (ready at %.2f s, going in at %.2f s)" % [ready_far, going])
	t.check(going - ready_near > READY_TIMEOUT, "waiting past the unordered ready timeout (%.1f s after the near one's ready)" % (going - ready_near))
