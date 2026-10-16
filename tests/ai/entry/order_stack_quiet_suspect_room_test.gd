extends GameTest

## LD9 (`docs/leadership.md`): the ordered mode wins over the stack's own rules. Two invaders carrying a stun each are
## ordered to stack QUIETLY on the Terrace house's back door, and the kitchen behind it is suspect (gunfire heard there), which unordered
## makes any entry by a stack with a stun a bang one (the suspect-room auto-bang, E17). Ordered quiet, the stack stays quiet: no claim in
## bang mode, no `bang` call, no stun thrown, both still carry their stun when the point goes in.
##
## Scripted Von, down (every question fails): the members' own decisions hold steady, so what they do is the order's alone (the ORDER
## node asks Von nothing). Premises: both are armed with one stun the way Main arms a spawn; the gunfire is a `hit` event nobody known
## fired, in the kitchen (as tests/_ai/investigate_probe.gd posts it); the order comes from the squad, as the leader's menu sends it.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Investigate := preload("res://tests/_ai/investigate_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Suspect := preload("res://tests/_ai/suspect_probe.gd")

const IDS := [&"a", &"b"]


func describe() -> Dictionary:
	return {
		"name": "An ordered quiet stack into a suspect room stays quiet",
		"description": "Two invaders with stuns ordered to stack quietly on the back door, the kitchen suspect (gunfire heard there): no bang mode, no bang call, no stun thrown before the point goes in (LD9).",
		"tags": ["ai", "entry", "leadership", "order", "stun", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Suspect.world(s)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"lead", &"puppet", Vector2(1250, 600), { "faction": &"invader" })


func run(t: TestContext) -> void:
	if not t.require(Suspect.arm(t), "both invaders carry a stun grenade (Character.item_count(7))"):
		return
	var squad := Order.raid(t, IDS, &"lead")
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	Investigate.gunfire(Maps.KITCHEN_CENTRE)
	await t.seconds(0.3)
	var order := Order.issue(squad, { "kind": Order.STACK, "to": [t.actor(&"a"), t.actor(&"b")], "pos": Order.BACK_NORTH, "bang": false })
	if not t.require(not order.is_empty(), "the squad posts the order (issue)"):
		return
	var claimed := func(): return IDS.all(func(id): return not Order.ordered_claims(t, t.actor(id), Entry.BACK["id"]).is_empty())
	if not t.require(await t.until(claimed, 10.0), "both claim the back door under the order (claims carrying order_id)"):
		return
	t.check(await t.until(func(): return not Entry.calls(t, "going_in").is_empty(), 45.0), "the point goes in")
	for id in IDS:
		var banged := Entry.calls(t, "", id).filter(func(c): return c.get("bang") == true)
		t.check(banged.is_empty(), "%s never claimed in bang mode (%d claims did)" % [id, banged.size()])
		t.expect_eq(Probe.count(t.actor(id), Probe.STUN), 1, "%s still carries its stun" % id)
	t.check(Entry.calls(t, "bang").is_empty(), "nobody called the bang")
	t.check(Probe.booms(t, &"stun").is_empty() and not t.happened(&"throw"), "no stun was thrown")
