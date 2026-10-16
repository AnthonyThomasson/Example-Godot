extends GameTest

## LD9 / D3 (`docs/leadership.md`): what the leader's click on a doorway decides. The side of the wall plane clicked is the
## side the stack forms on, so the room it goes into is the other one; left or right of the opening along the wall picks the stack's
## side of the door; a click on the opening (within its half-width along the wall) is a split stack; an exterior door always goes into
## the house's room, whichever side is clicked.
##
## A lone invader in the Terrace house's back garden, straight out from the back door (on its axis: neither side is nearer), is ordered
## to stack with a click south of the opening, then north of it: its stack slot is south of the door, then north. The squad's resolution
## of four more clicks is read off the orders it posts: inside the kitchen at the back door (still into the kitchen), on either side of
## the kitchen–living doorway (into the room on the far side), and on the back door's opening (a split stack).
##
## Scripted Von, down: the member's own decisions hold steady, so what it does is the order's alone.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")

## Clicks at the kitchen–living doorway (x 480, 90 px wide at y 150), 60 px south of its centre along the wall: on the kitchen side
## (east) and on the living room side (west).
const KITCHEN_SIDE := Vector2(510, 210)
const LIVING_SIDE := Vector2(450, 210)


func describe() -> Dictionary:
	return {
		"name": "The click on a doorway picks the stack's side and room",
		"description": "A click south or north of the back door's opening stacks the member on that side; a click's side of the wall picks the room it goes into, an exterior door always into the house, and a click on the opening is a split stack (LD9, D3).",
		"tags": ["ai", "entry", "leadership", "order", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"a", &"invader", Vector2(990, 190))
	s.actor(&"lead", &"puppet", Vector2(1250, 600), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var squad := Order.raid(t, [&"a"], &"lead")
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	await t.seconds(0.3)
	for side in ["south", "north"]:
		var click := Order.BACK_SOUTH if side == "south" else Order.BACK_NORTH
		var order := Order.issue(squad, { "kind": Order.STACK, "to": [t.actor(&"a")], "pos": click, "bang": false })
		if not t.check(not order.is_empty(), "the squad posts the order for a click %s of the opening (issue)" % side):
			continue
		t.expect_eq(String(order.get("opening", "")), Entry.BACK["id"], "a click %s of the opening is on the back door" % side)
		t.expect_eq(String(order.get("into", "")), "kitchen", "and goes into the kitchen")
		t.check(not bool(order.get("split", false)), "a click beside the opening is not a split stack")
		var stood := await t.until(func(): return Order.stacked(t, &"a") and Order.back_side(t.actor(&"a").global_position) == side, 20.0)
		t.check(stood, "clicked %s of the opening, the member stacks %s of the door (stack point %s, at %s)" % [side, side,
			str(Order.stack_point(t, &"a").round()), str(t.actor(&"a").global_position.round())])
		t.check(Order.back_side(Order.stack_point(t, &"a")) == side, "its slot is %s of the door (%s)" % [side, str(Order.stack_point(t, &"a").round())])

	var inside := Order.issue(squad, { "kind": Order.STACK, "to": [t.actor(&"a")], "pos": Order.BACK_INSIDE_NORTH, "bang": false })
	t.expect_eq(String(inside.get("into", "")), "kitchen", "a click inside the kitchen at the exterior back door still goes into the kitchen")
	var from_kitchen := Order.issue(squad, { "kind": Order.STACK, "to": [t.actor(&"a")], "pos": KITCHEN_SIDE, "bang": false })
	t.expect_eq(String(from_kitchen.get("opening", "")), Entry.KITCHEN_LIVING["id"], "a click beside the kitchen–living doorway is on it")
	t.expect_eq(String(from_kitchen.get("into", "")), "living_room", "clicked on the kitchen side, the stack goes into the living room")
	var from_living := Order.issue(squad, { "kind": Order.STACK, "to": [t.actor(&"a")], "pos": LIVING_SIDE, "bang": false })
	t.expect_eq(String(from_living.get("into", "")), "kitchen", "clicked on the living room side, the stack goes into the kitchen")
	var split := Order.issue(squad, { "kind": Order.STACK, "to": [t.actor(&"a")], "pos": Order.BACK_ON, "bang": false })
	t.check(bool(split.get("split", false)), "a click on the opening is a split stack (%s)" % str(split))
	t.expect_eq(String(split.get("into", "")), "kitchen", "into the kitchen")
