extends GameTest

## LD11 and D3 (`docs/leadership.md`): the room the command menu's stack items name is the room the order goes into. The squad resolves
## a click into its doorway, side and room (`Squad.resolve`, interface 21), and the menu names what it resolves, so the label and the
## order the squad posts agree everywhere, a click exactly on the wall plane included (where neither room's side holds it).
##
## The Terrace house's living-room / kitchen doorway (a wall along x = 480): a squad built the way Main builds it over two puppet
## teammates and the human, and the menu set up with the squad's `view` and `resolve` callables, as Main sets it up. For each click the
## menu's "Stack into the <room> (quiet)" item is chosen and the request it emits is issued to the squad: the order's `into` must be the
## room the label named.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")

## Clicks by the living-room / kitchen doorway, 60 px north of its centre along the wall (off the opening: a one-sided stack).
const ON_PLANE := Vector2(480, 90)
const KITCHEN_SIDE := Vector2(500, 90)
const LIVING_SIDE := Vector2(460, 90)


func describe() -> Dictionary:
	return {
		"name": "The menu's stack label names the room the order goes into",
		"description": "For clicks by an interior doorway, on either side of the wall and exactly on its plane, the room named by the command menu's stack item is the room of the order the squad posts (LD11, D3).",
		"tags": ["ui", "hud", "leadership", "order"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.lock_interaction([&"camera", &"pause"])
	s.actor(&"t1", &"puppet", Vector2(960, 330), { "faction": &"invader" })
	s.actor(&"t2", &"puppet", Vector2(1000, 420), { "faction": &"invader" })
	s.actor(&"me", &"puppet", Vector2(1100, 500), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var t1 := t.actor(&"t1")
	var t2 := t.actor(&"t2")
	var me := t.actor(&"me")
	var squad := Order.squad(t, &"invader", [t1, t2, me], me)
	var menu := Order.command_menu(t)
	if not t.require(squad != null and menu != null, "the squad and the menu are built (%s, %s)" % [Order.SQUAD_SCRIPT, Order.COMMAND_MENU_SCRIPT]):
		return
	menu.setup({ "rooms": t.rooms, "teammates": [t1, t2], "leader": me, "view": squad.view,
		"resolve": squad.resolve if squad.has_method("resolve") else Callable() })
	var got: Array = []
	menu.order_requested.connect(func(d): got.append(d))
	for click: Vector2 in [KITCHEN_SIDE, LIVING_SIDE, ON_PLANE]:
		menu.open_at(click)
		await t.frames(1)
		var quiet := Order.item(menu, "(quiet)")
		if not t.check(not quiet.is_empty(), "a click at %s offers a quiet stack (items %s)" % [str(click), str(Order.labels(menu))]):
			menu.close()
			continue
		var label := String(quiet["label"])
		var asked := got.size()
		Order.choose(menu, label)
		await t.frames(1)
		if not t.check(got.size() == asked + 1, "choosing it at %s emits order_requested" % str(click)):
			continue
		var order := Order.issue(squad, got[asked])
		if not t.check(not order.is_empty(), "the squad posts the order for the click at %s" % str(click)):
			continue
		var into := _type_of(t, String(order.get("into", "")))
		t.expect_eq(label, "Stack into the %s (quiet)" % into, "the click at %s: the label names the room the order goes into (%s)" % [str(click), order.get("into")])


## Room `key`'s type in words ("living_room" -> "living room"), as the menu names a room.
func _type_of(t: TestContext, key: String) -> String:
	for r in t.rooms:
		if String(r["key"]) == key:
			return String(r["type"]).replace("_", " ")
	return key
