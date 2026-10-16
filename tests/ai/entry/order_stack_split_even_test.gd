extends GameTest

## LD9 / D6 (`docs/leadership.md`): a split stack's members are shared out evenly, nearer side first. The leader clicks on
## the back door's opening (a split stack, D3) for four invaders, three of them north of the door and one south of it. Each takes the
## side it reaches without crossing the doorway's view, balanced so the sides differ by at most one: two stack north and two south, the
## one from the south among the south pair. (Unordered, a stack follows its point's side, and only a member whose way there would cross the
## view splits off: three north, one south.)
##
## Scripted Von, down: the members' own decisions hold steady, so what they do is the order's alone.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")

const IDS := [&"n1", &"n2", &"n3", &"s1"]


func describe() -> Dictionary:
	return {
		"name": "A split stack is shared out evenly, nearer side first",
		"description": "Ordered to a split stack at the back door, three invaders from the north and one from the south stack two on each side, the southerner on the south (LD9, D6).",
		"tags": ["ai", "entry", "leadership", "order", "split", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"n1", &"invader", Vector2(960, 60))
	s.actor(&"n2", &"invader", Vector2(1000, 100))
	s.actor(&"n3", &"invader", Vector2(990, 20))
	s.actor(&"s1", &"invader", Vector2(985, 320))
	s.actor(&"lead", &"puppet", Vector2(1250, 600), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var squad := Order.raid(t, IDS, &"lead")
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	await t.seconds(0.3)
	var order := Order.issue(squad, { "kind": Order.STACK, "to": IDS.map(func(id): return t.actor(id)), "pos": Order.BACK_ON, "bang": false })
	if not t.require(bool(order.get("split", false)), "the click on the opening is a split stack (premise; %s)" % str(order)):
		return
	var all_stacked := func(): return IDS.all(func(id): return Order.stacked(t, id))
	if not t.require(await t.until(all_stacked, 25.0), "all four reach their slots (phases %s)" % str(IDS.map(func(id): return Order.brain(t, id).debug_entry().get("phase", "")))):
		return
	var sides := {}
	for id in IDS:
		sides[id] = Order.back_side(Order.stack_point(t, id))
	var north := IDS.filter(func(id): return sides[id] == "north").size()
	var south := IDS.filter(func(id): return sides[id] == "south").size()
	t.check(north + south == IDS.size(), "every slot is beside the door, north or south of it (%s)" % str(sides))
	t.check(absi(north - south) <= 1, "the sides differ by at most one (%d north, %d south: %s)" % [north, south, str(sides)])
	t.expect_eq(sides[&"s1"], "south", "the one from the south stacks on its nearer side, the south")
