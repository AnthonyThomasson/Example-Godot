extends GameTest

## E17 / E9 (issue #51, R10), the contrast to `entry_guard_bang_suspect_room`: the same walk with nothing to suspect the kitchen of.
## An invader with a stun is sent to search the living room, two doors deep through the kitchen; the entry guard turns its walk through
## the back door into an entry (E9), and with no reason to think a hostile is in the kitchen it goes in quietly: its calls say quiet, no
## bang is radioed and no stun is thrown.
##
## Scripted Von (SEARCH > the living room: one mechanism, the guard's entry). The invader knows the house (`familiar_with_house`, as
## `entry_guard_search_room`) and carries a stun, armed the way Main arms a spawn.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
## In the back garden north-east of the back door (`stun_entry_suspect_room`'s stack): the way to the living room runs through the kitchen.
const START := Vector2(960, 60)


func describe() -> Dictionary:
	return {
		"name": "A guard's entry into an unsuspected room goes in quietly",
		"description": "Sent to search the living room with nothing heard or seen in the kitchen, the invader's walk through the back door stops as a quiet entry: no bang, no stun.",
		"tags": ["ai", "entry", "guard", "grenade", "stun", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.guard_rules(s, ["search", "room_living_room"])
	Entry.npc(s, &"inv", START)
	s.set_props(&"inv", "GoalController", { "familiar_with_house": true })


func run(t: TestContext) -> void:
	Probe.arm(t.actor(&"inv"), 1, 0)
	if not t.require(Probe.count(t.actor(&"inv"), Probe.STUN) == 1, "the invader carries a stun grenade (Character.item_count(7))"):
		return
	var went_in := func(): return Entry.first_call_time(t, "going_in", &"inv", Entry.BACK["id"]) < INF
	if not t.require(await t.until(went_in, 50.0), "the invader went in through the back door by entry (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	t.check(Entry.asked(t, "room_living_room") and not Entry.asked(t, "enter") and not Entry.asked(t, "stun_entry"),
		"the order was a plain search of the living room, not ENTER or STUN ENTRY (picks %s)" % str(t.von_requests().map(func(r): return r["pick"])))
	var calls := Entry.calls(t, "", &"inv").filter(func(c): return String(c.get("opening", "")) == Entry.BACK["id"])
	t.check(calls.all(func(c): return c.get("bang") == false), "its calls on the back door said quiet (%s)" % str(calls.map(func(c): return [c.get("entry_step"), c.get("bang")])))
	t.check(Entry.first_call_time(t, "bang", &"inv") == INF, "no bang was radioed")
	t.check(Probe.booms(t, &"stun").is_empty() and Probe.count(t.actor(&"inv"), Probe.STUN) == 1, "no stun was thrown")
