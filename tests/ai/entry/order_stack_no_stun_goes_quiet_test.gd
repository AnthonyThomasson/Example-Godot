extends GameTest

## LD9 / D1 (`docs/leadership.md`): a stun stack whose stun is gone. Two invaders, each carrying a stun when the order is
## given, are ordered to stack on the Terrace house's back door WITH a stun; their stuns are then taken away before they reach the door.
## With no stun in the stack, the order's bang cannot be had: the stack goes in quietly and radios `bang_off`, as a bang given up does,
## and the order is still done at `cleared_room` (each member radios `order_step` `done`).
##
## Scripted Von, down: the members' own decisions hold steady, so what they do is the order's alone. Premises: both are armed with one
## stun the way Main arms a spawn, then re-armed with none (`LoadoutConfig.apply`, as a new loadout), standing in for a stun lost.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Bang := preload("res://tests/_ai/bang_probe.gd")

const IDS := [&"a", &"b"]


func describe() -> Dictionary:
	return {
		"name": "An ordered stun stack with no stun goes in quietly",
		"description": "Ordered to stack on the back door with a stun, two invaders whose stuns are gone go in quietly, radio bang_off, and are done at the cleared kitchen (LD9, D1).",
		"tags": ["ai", "entry", "leadership", "order", "stun", "scripted"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	Bang.stack(s)
	s.actor(&"lead", &"puppet", Vector2(1250, 600), { "faction": &"invader" })


func run(t: TestContext) -> void:
	if not t.require(Bang.arm(t, IDS), "both invaders carry a stun grenade when the order is given (Character.item_count(7))"):
		return
	var squad := Order.raid(t, IDS, &"lead")
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	var order := Order.issue(squad, { "kind": Order.STACK, "to": [t.actor(&"a"), t.actor(&"b")], "pos": Order.BACK_NORTH, "bang": true })
	if not t.require(not order.is_empty(), "the squad posts the order (issue)"):
		return
	await t.frames(2)
	for id in IDS:
		Probe.arm(t.actor(id), 0, 0)
	if not t.require(IDS.all(func(id): return Probe.count(t.actor(id), Probe.STUN) == 0), "the stuns are gone (premise)"):
		return
	var claimed := func(): return IDS.all(func(id): return not Order.ordered_claims(t, t.actor(id), Entry.BACK["id"]).is_empty())
	if not t.require(await t.until(claimed, 10.0), "both claim the back door under the order (claims carrying order_id)"):
		return

	t.check(await t.until(func(): return not Entry.calls(t, "going_in").is_empty(), 45.0), "the stack goes in")
	t.check(Probe.booms(t, &"stun").is_empty() and not t.happened(&"throw"), "no stun was thrown")
	var gave_up := IDS.filter(func(id): return Entry.calls(t, "", id).any(func(c): return c.get("bang_off") == true))
	t.check(not gave_up.is_empty(), "the stack radioed bang_off: the bang given up")
	var done := func(): return IDS.all(func(id): return not Order.progress(t, "done", t.actor(id)).is_empty())
	t.check(await t.until(done, 40.0), "the order is still done at the cleared kitchen (order_step done from %s)" % str(IDS.filter(func(id): return not Order.progress(t, "done", t.actor(id)).is_empty())))
	t.check(t.happened(&"callout", func(c): return String(c.get("cleared_room", "")) == "kitchen"), "the kitchen was radioed cleared")
