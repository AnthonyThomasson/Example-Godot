extends GameTest

## LD7 and LD11 (`docs/leadership.md`): an order a member has radioed `done` is no longer one it holds. The squad's `view()` then shows
## the member with no order and its step `done`, so the command menu offers no "Cancel order" for it; a `refused` order is still held,
## shown with its step `refused` (the order markers draw it red). The squad is built the way Main builds it over two puppet teammates and
## the human leader; the members' progress is radioed straight onto the bus as an NPC radios it (`&"callout"` with `order_id` and
## `order_step`), and the menu is set up with the squad's own `view` callable, as Main sets it up.

const Order := preload("res://tests/_ai/order_probe.gd")

## In the arena's room, clear of the teammates.
const CLICK := Vector2(600, 150)


func describe() -> Dictionary:
	return {
		"name": "A done order is no longer held or cancellable",
		"description": "Once a member radios its order done, the squad's view shows it with no order (step done) and the command menu offers no Cancel order for it; a refused order is still held (LD7, LD11).",
		"tags": ["ui", "leadership", "squad", "order"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.lock_interaction([&"camera", &"pause"])
	s.actor(&"t1", &"puppet", Vector2(200, 300), { "faction": &"invader" })
	s.actor(&"t2", &"puppet", Vector2(300, 300), { "faction": &"invader" })
	s.actor(&"me", &"puppet", Vector2(700, 400), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var t1 := t.actor(&"t1")
	var t2 := t.actor(&"t2")
	var me := t.actor(&"me")
	var squad := Order.squad(t, &"invader", [t1, t2, me], me)
	if not t.require(squad != null and squad.has_method("view"), "the squad is built (%s)" % Order.SQUAD_SCRIPT):
		return
	var room := String(t.rooms[0]["key"])
	var order := Order.issue(squad, { "kind": Order.DEFEND, "to": [t1, t2], "room": room })
	if not t.require(not order.is_empty(), "set-up: the squad posted a defend order to both teammates"):
		return
	var menu := Order.command_menu(t)
	if not t.require(menu != null, "the command menu script exists (%s)" % Order.COMMAND_MENU_SCRIPT):
		return
	menu.setup({ "rooms": t.rooms, "teammates": [t1, t2], "view": squad.view, "resolve": squad.resolve, "leader": me })
	menu.open_at(CLICK)
	await t.frames(1)
	t.check(not Order.item(menu, "Cancel order").is_empty(), "set-up: with both holding the order, the menu offers Cancel order (items %s)" % str(Order.labels(menu)))
	menu.close()

	_radio(t1, order, "done")
	_radio(t2, order, "refused")
	await t.frames(1)
	var done := Order.member_view(squad, t1)
	t.check((done.get("order", {}) as Dictionary).is_empty(), "the member that radioed done holds no order in the view (%s)" % str(done.get("order")))
	t.expect_eq(String(done.get("step", "")), "done", "and its step stays done")
	var refused := Order.member_view(squad, t2)
	t.check(str((refused.get("order", {}) as Dictionary).get("id", "")) == str(order["id"]), "the member that refused still holds the order (%s)" % str(refused.get("order")))
	t.expect_eq(String(refused.get("step", "")), "refused", "with its step refused")

	t2.take_damage(t2.max_health * 2.0)  # The refused one dies: it holds nothing any more, and the menu leaves it out.
	await t.frames(1)
	menu.open_at(CLICK)
	await t.frames(1)
	t.check(Order.item(menu, "Cancel order").is_empty(), "with the only living recipient's order done, the menu offers no Cancel order (items %s)" % str(Order.labels(menu)))
	menu.close()


## Radio `member`'s progress on `order` the way an NPC does (LD7).
func _radio(member: Node, order: Dictionary, step: String) -> void:
	EventBus.post(&"callout", { "speaker": member, "faction": member.get("faction"), "position": (member as Node2D).global_position,
		"order_id": order["id"], "order_step": step })
