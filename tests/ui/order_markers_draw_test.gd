extends GameTest

## LD12 / D5 (`docs/leadership.md`): the order markers (`scenes/ui/hud/order_markers.gd`, `OrderMarkers`, drawn at
## `DrawLayers.ABOVE`), built only when the human leads. A marker on each member's order target and the selection highlight (who leads is
## the squad-leaders debug overlay's, `leader_overlay_draw_test.gd`). A decoupled observer: `watch(view_callable)` polls the squad's `view()`
## (`{ leader, members: [{ node, order, step }] }`), `set_selection(nodes)` is the menu's selection, and `drawn()` is what is shown
## (`[{ kind, point, node }]`, `kind` `order` / `selected`), which this test reads.
##
## A fake squad view (plain data) over three puppets.

const Order := preload("res://tests/_ai/order_probe.gd")

## The fake squad's view, as the markers' `view` callable returns it.
var _view := {}


func describe() -> Dictionary:
	return {
		"name": "Order markers draw each order and the selection",
		"description": "The markers mark one target per member with an order and none without, and each selected teammate; the leader is not theirs to mark (LD12, D5).",
		"tags": ["ui", "hud", "leadership", "order"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.actor(&"me", &"puppet", Vector2(150, 300), { "faction": &"invader" })
	s.actor(&"t1", &"puppet", Vector2(400, 200), { "faction": &"invader" })
	s.actor(&"t2", &"puppet", Vector2(600, 400), { "faction": &"invader" })


func run(t: TestContext) -> void:
	if not t.require(ResourceLoader.exists(Order.ORDER_MARKERS_SCRIPT), "the order markers script exists (%s)" % Order.ORDER_MARKERS_SCRIPT):
		return
	var markers: Node2D = (load(Order.ORDER_MARKERS_SCRIPT) as GDScript).new()
	t.world.add_child(markers)
	if not t.require(markers.has_method("watch") and markers.has_method("set_selection") and markers.has_method("drawn"), "it has watch, set_selection and drawn"):
		return
	t.expect_eq(markers.z_index, DrawLayers.ABOVE, "drawn above the standing world (DrawLayers.ABOVE)")
	var me := t.actor(&"me")
	var t1 := t.actor(&"t1")
	var t2 := t.actor(&"t2")
	_view = { "leader": me, "members": [
		{ "node": me, "order": {}, "step": "" },
		{ "node": t1, "order": { "id": "o1", "kind": "defend_room", "room": "kitchen", "pos": Vector2(700, 100) }, "step": "moving" },
		{ "node": t2, "order": {}, "step": "" },
	] }
	markers.watch(func(): return _view)
	await t.frames(2)
	t.check(_of(markers, "leader").is_empty(), "no marker on the leader (the squad-leaders debug overlay's)")
	var orders := _of(markers, "order")
	t.check(orders.size() == 1 and orders[0].get("node") == t1, "one order target, for the member with an order (%s)" % str(orders))
	t.check(_of(markers, "selected").is_empty(), "no selection drawn while nothing is selected")

	markers.set_selection([t2])
	await t.frames(2)
	var selected := _of(markers, "selected")
	t.check(selected.size() == 1 and (selected[0].get("point", Vector2.INF) as Vector2).distance_to(t2.global_position) < 2.0,
		"the selected teammate is highlighted where it stands (%s)" % str(selected))

	_view["members"][2]["order"] = { "id": "o2", "kind": "stack", "opening": "door_840_190", "into": "kitchen", "pos": Vector2(870, 255) }
	await t.frames(2)
	t.expect_eq(_of(markers, "order").size(), 2, "a second member's order adds a second target")

	markers.set_selection([])
	await t.frames(2)
	t.check(_of(markers, "selected").is_empty(), "clearing the selection clears its highlight")


## The drawn markers of `kind`.
func _of(markers: Node, kind: String) -> Array:
	return (markers.drawn() as Array).filter(func(d): return String(d.get("kind", "")) == kind)
