extends GameTest

## E17 / E9 (issue #51, R10): a suspect room means a bang for every entry, not only SEARCH's. An invader with a stun is sent to search
## the living room, two doors deep through the kitchen (a plain search order, so the entry guard turns its walk through the back door
## into an entry, E9); gunfire heard in the kitchen before it sets off makes the kitchen suspect (G18). The detour's entry into the
## kitchen goes in with a bang: its claim says bang, it radios `bang` and a stun goes off in the kitchen before it goes in. The contrast,
## the same walk into an unsuspected kitchen, is `entry_guard_quiet_unsuspected_room`.
##
## Scripted Von (SEARCH > the living room: one mechanism, the guard's entry). The invader knows the house (`familiar_with_house`, as
## `entry_guard_search_room`) and carries a stun, armed the way Main arms a spawn. The gunfire is a `hit` event nobody known fired, in
## the kitchen (as tests/_ai/investigate_probe.gd posts it), first thing in `run`.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Investigate := preload("res://tests/_ai/investigate_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
## In the back garden north-east of the back door (`stun_entry_suspect_room`'s stack): the way to the living room runs through the kitchen.
const START := Vector2(960, 60)


func describe() -> Dictionary:
	return {
		"name": "A guard's entry into a suspect room goes in with a bang",
		"description": "Sent to search the living room with gunfire heard in the kitchen, the invader's walk through the back door stops as an entry, and a stun goes off in the kitchen before it goes in.",
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
	Investigate.gunfire(Maps.KITCHEN_CENTRE)
	var went_in := func(): return Entry.first_call_time(t, "going_in", &"inv", Entry.BACK["id"]) < INF
	await t.until(went_in, 50.0)
	if not t.require(Entry.first_call_time(t, "claim", &"inv", Entry.BACK["id"]) < INF, "the invader stacked at the back door (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	t.check(Entry.asked(t, "room_living_room") and not Entry.asked(t, "enter") and not Entry.asked(t, "stun_entry"),
		"the order was a plain search of the living room, not ENTER or STUN ENTRY (picks %s)" % str(t.von_requests().map(func(r): return r["pick"])))
	var going := Entry.first_call_time(t, "going_in", &"inv", Entry.BACK["id"])
	var claims := Entry.calls(t, "claim", &"inv").filter(func(c): return String(c.get("opening", "")) == Entry.BACK["id"])
	t.check(not claims.is_empty() and claims[0].get("bang") == true, "its claim on the back door said bang (%s)" % str(claims.map(func(c): return c.get("bang"))))
	var called := Entry.first_call_time(t, "bang", &"inv", Entry.BACK["id"])
	t.check(called < going, "it radioed the bang before it went in (bang at %.2f s, going_in at %.2f s)" % [called, going])
	var booms := Probe.booms(t, &"stun")
	t.check(not booms.is_empty() and Maps.HOUSE_KITCHEN.has_point(booms[0]["data"]["position"]) and float(booms[0]["time"]) <= going,
		"a stun went off in the kitchen before it went in (bursts %s, going_in at %.2f s)" % [str(booms.map(func(b): return [snappedf(float(b["time"]), 0.01), b["data"]["position"]])), going])
