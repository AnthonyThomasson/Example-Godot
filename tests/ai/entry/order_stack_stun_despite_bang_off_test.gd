extends GameTest

## LD9 (`docs/leadership.md`): an ordered stun stack is never vetoed. Unordered, a teammate's `bang_off` on the radio (it gave the
## bang up) makes the whole stack go in quietly (E17's veto). Two invaders carrying a stun each are ordered to stack on the Terrace house's
## back door WITH a stun; a third teammate at the same door radios its claim with `bang_off` the whole time. The ordered stack still
## throws: the bang is called and a stun goes off in the kitchen before anyone goes in. (D1's one exception, the stack's own stun lost,
## is `order_stack_no_stun_goes_quiet`.)
##
## Scripted Von, down: the members' own decisions hold steady, so what they do is the order's alone. Premises: both are armed with one
## stun the way Main arms a spawn; the vetoing teammate is a puppet that radios its claim the way an AI member does.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Bang := preload("res://tests/_ai/bang_probe.gd")

const IDS := [&"a", &"b"]


func describe() -> Dictionary:
	return {
		"name": "An ordered stun stack throws despite a teammate's bang_off",
		"description": "Two invaders ordered to stack on the back door with a stun, a teammate radioing bang_off at the same door: the bang is called and a stun goes off in the kitchen before anyone goes in (LD9).",
		"tags": ["ai", "entry", "leadership", "order", "stun", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	Bang.stack(s)
	s.actor(&"mate", &"puppet", Vector2(1000, 330), { "faction": &"invader" })
	s.actor(&"lead", &"puppet", Vector2(1250, 600), { "faction": &"invader" })


func run(t: TestContext) -> void:
	if not t.require(Bang.arm(t, IDS), "both invaders carry a stun grenade (Character.item_count(7))"):
		return
	var squad := Order.raid(t, IDS, &"lead")
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	var order := Order.issue(squad, { "kind": Order.STACK, "to": [t.actor(&"a"), t.actor(&"b")], "pos": Order.BACK_NORTH, "bang": true })
	if not t.require(not order.is_empty(), "the squad posts the order (issue)"):
		return
	var claimed := func(): return IDS.all(func(id): return not Order.ordered_claims(t, t.actor(id), Entry.BACK["id"]).is_empty())
	if not t.require(await t.until(claimed, 10.0), "both claim the back door under the order (claims carrying order_id)"):
		return
	var next_veto := 0.0
	while Entry.calls(t, "going_in").is_empty() and t.time < 50.0:
		if t.time >= next_veto:
			_veto(t)
			next_veto = t.time + 1.0
		await t.frames(1)
	if not t.require(not Entry.calls(t, "going_in").is_empty(), "the point goes in"):
		return
	var went_in: float = Order.first_time(t, &"callout", func(d): return String(d.get("entry_step", "")) == "going_in")
	t.check(not Entry.calls(t, "bang").is_empty(), "the bang was called despite the teammate's bang_off")
	var booms := Probe.booms(t, &"stun")
	t.check(not booms.is_empty() and Maps.HOUSE_KITCHEN.has_point(booms[0]["data"]["position"]) and float(booms[0]["time"]) <= went_in,
		"a stun went off in the kitchen before anyone went in (bursts %s, going_in at %.2f s)" % [str(booms.map(func(e): return [snappedf(float(e["time"]), 0.01), e["data"]["position"]])), went_in])
	for id in IDS:
		var quiet := Entry.calls(t, "", id).filter(func(c): return str(c.get("order_id", "")) != "" and c.get("bang") != true)
		t.check(quiet.is_empty(), "%s's ordered claims all stayed in bang mode (%d did not)" % [id, quiet.size()])


## The teammate's claim at the back door, the bang given up: slot 3, south of the door, `bang_off`.
func _veto(t: TestContext) -> void:
	var c := t.actor(&"mate")
	EventBus.post(&"callout", {
		"speaker": c, "faction": c.faction, "position": c.global_position, "status": "", "path": "", "label": "", "target_id": 0, "point": c.global_position,
		"opening": Entry.BACK["id"], "into": "kitchen", "slot": 3, "side": -1, "entry_step": "ready", "bang": false, "bang_off": true, "stuns": 0,
	})
