extends GameTest

## G18 / E17: the stun goes into the room as far as it reaches, not only to its far side. The Terrace house's front door is at the west end
## of the hall, 840 px long: its far side is beyond a stun's reach (550 px) from beside the door. An invader with a stun takes STUN ENTRY at
## the front door; it plans the throw onto the farthest point along the hall it reaches with a clear lob, radios `bang`, and the stun goes off
## in the hall, well inside it (at least `BANG_MIN_DEPTH`, 120 px, from the doorway), before it goes in; the invader, beside the wall outside,
## is not flashed.
##
## Scripted Von (SEARCH > STUN ENTRY > the front door: one mechanism, the throw's aim). The invader carries a stun, armed the way Main arms a
## spawn (a test world keeps the default inventory).

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
## How far into the room (px from the doorway) the stun must go off at least: the entry's `BANG_MIN_DEPTH`.
const MIN_DEPTH := 120.0


func describe() -> Dictionary:
	return {
		"name": "A bang into a long room goes as far as the stun reaches",
		"description": "At the front door of the 840 px hall, beyond a stun's reach end to end, the invader still throws its stun into the hall before it goes in, and is not flashed.",
		"tags": ["ai", "grenade", "entry", "stun", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([{ "pick": "search" }, { "pick": "stun_entry" }, { "pick": Entry.FRONT["id"] }])
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"a", &"invader", Maps.GARDEN)


func run(t: TestContext) -> void:
	var a := t.actor(&"a")
	Probe.arm(a, 1, 0)
	if not t.require(Probe.count(a, Probe.STUN) == 1, "the invader carries a stun grenade (Character.item_count(7))"):
		return
	var flashed := [false]
	var went_in := func():
		if Probe.blind(a):
			flashed[0] = true
		return Entry.first_call_time(t, "going_in", &"a", Entry.FRONT["id"]) < INF
	await t.until(went_in, 50.0)
	if not t.require(Entry.first_call_time(t, "claim", &"a", Entry.FRONT["id"]) < INF and Entry.asked(t, "stun_entry"),
			"the invader took STUN ENTRY at the front door (act %s)" % Entry.brain(t, &"a").current_act()):
		return
	var going := Entry.first_call_time(t, "going_in", &"a", Entry.FRONT["id"])
	var called := Entry.first_call_time(t, "bang", &"a", Entry.FRONT["id"])
	var calls := Entry.calls(t, "", &"a").map(func(c): return [c.get("entry_step"), c.get("bang"), c.get("bang_off")])
	t.check(called < going, "it radioed the bang before it went in (bang at %.2f s, going_in at %.2f s; calls %s)" % [called, going, str(calls)])
	var booms := Probe.booms(t, &"stun")
	var at: Vector2 = booms[0]["data"]["position"] if not booms.is_empty() else Vector2.INF
	t.check(not booms.is_empty() and Maps.HOUSE_HALL.has_point(at) and float(booms[0]["time"]) <= going,
		"a stun went off in the hall before it went in (at %s, %s s; going_in at %.2f s)" % [str(at), str(booms.map(func(b): return snappedf(float(b["time"]), 0.01))), going])
	t.check(at != Vector2.INF and at.distance_to(Maps.DOOR_FRONT) >= MIN_DEPTH, "well inside the hall, %.0f px from the doorway (at least %d)" % [at.distance_to(Maps.DOOR_FRONT), MIN_DEPTH])
	t.check(not flashed[0], "the invader, outside beside the wall, was not flashed")
