extends GameTest

## LD9 / D10 (`docs/leadership.md`): an unordered member that joins an ordered stack follows the order's mode and side. An
## invader that took the quiet ENTER at the Terrace house's back door on its own has claimed its slot north of the door first; then a
## teammate is ordered to stack on the same door south of it, with a stun. Unordered, the first claimer sets a stack's side and mode; with an
## ordered claim in the team, the order's do: the joiner's later claims are in bang mode and on the order's side, and it stacks south of
## the door.
##
## Scripted Von (SEARCH > ENTER > the back door: the joiner's own, quiet choice; the ordered member's order level asks nothing).
## Premises: the ordered member carries a stun the way Main arms a spawn; it starts far off in the south of the garden, so the joiner has
## claimed first.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "An unordered joiner follows the ordered stack's mode and side",
		"description": "An invader that claimed the back door quietly on the north follows a teammate's later order to stack south with a stun: its claims turn to bang mode and the order's side, and it stacks south (LD9, D10).",
		"tags": ["ai", "entry", "leadership", "order", "stun", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	s.actor(&"joiner", &"invader", Vector2(960, 60))
	s.actor(&"ordered", &"invader", Vector2(990, 600))
	s.actor(&"lead", &"puppet", Vector2(1250, 600), { "faction": &"invader" })


func run(t: TestContext) -> void:
	Probe.arm(t.actor(&"ordered"), 1, 0)
	if not t.require(Probe.count(t.actor(&"ordered"), Probe.STUN) == 1, "the ordered member carries a stun (Character.item_count(7))"):
		return
	var squad := Order.raid(t, [&"joiner", &"ordered"], &"lead")
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	var joiner := t.actor(&"joiner")
	if not t.require(await t.until(func(): return not Entry.calls(t, "claim", &"joiner").is_empty(), 6.0), "the joiner claims the back door on its own first (premise)"):
		return
	var first: Dictionary = Entry.calls(t, "claim", &"joiner")[0]
	if not t.require(first.get("bang") == false and str(first.get("order_id", "")) == "", "set-up: its own claim is quiet and unordered"):
		return
	var order := Order.issue(squad, { "kind": Order.STACK, "to": [t.actor(&"ordered")], "pos": Order.BACK_SOUTH, "bang": true })
	if not t.require(not order.is_empty(), "the squad posts the order (issue)"):
		return
	var ordered_at := await _first_ordered_claim(t)
	if not t.require(ordered_at < INF, "the ordered member claims the back door under the order"):
		return
	await t.seconds(3.0)
	var later: Array = Order.raw_calls(t, joiner).filter(func(e): return float(e["time"]) > ordered_at + 1.0)
	if not t.require(not later.is_empty(), "the joiner kept radioing its claim after the order's"):
		return
	t.check(later.all(func(e): return e["data"].get("bang") == true), "the joiner's later claims are in bang mode, the order's (%s)" % str(later.map(func(e): return e["data"].get("bang"))))
	var ordered_side = Order.ordered_claims(t, t.actor(&"ordered"), Entry.BACK["id"])[0].get("side")
	t.check(later.all(func(e): return e["data"].get("side") == ordered_side), "on the order's side (%s, the joiner's: %s)" % [str(ordered_side), str(later.map(func(e): return e["data"].get("side")))])
	t.check(await t.until(func(): return Order.stacked(t, &"joiner") and Order.back_side(joiner.global_position) == "south", 20.0),
		"the joiner stacks south of the door, the order's side (at %s)" % str(joiner.global_position.round()))


## The sim time of the ordered member's first claim carrying an order_id at the back door (waiting up to 10 s), or INF.
func _first_ordered_claim(t: TestContext) -> float:
	var who := t.actor(&"ordered")
	await t.until(func(): return not Order.ordered_claims(t, who, Entry.BACK["id"]).is_empty(), 10.0)
	return Order.first_time(t, &"callout", func(d): return d.get("speaker") == who and str(d.get("order_id", "")) != "" and String(d.get("opening", "")) == Entry.BACK["id"])
