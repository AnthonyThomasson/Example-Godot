extends GameTest

## E17 / G18, a late reason (issue #51, R11): a stack that took the quiet ENTER and is still outside, nobody crossing, turns its entry into
## a bang when a new reason to suspect the room comes up: here gunfire heard in the kitchen once both have claimed the back door. The
## claims turn to bang (the whole stack follows), the thrower radios `bang` and a stun goes off in the kitchen before anyone goes in.
## Scripted Von (SEARCH > ENTER > the back door: one mechanism); both invaders carry a stun, the way Main arms a spawn. The gunfire is a
## `hit` event nobody known fired, inside the kitchen (as tests/_ai/investigate_probe.gd posts it).

const Bang := preload("res://tests/_ai/bang_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Investigate := preload("res://tests/_ai/investigate_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A quiet entry turns into a bang on a late reason to suspect the room",
		"description": "Two invaders with a stun take the quiet ENTER at the back door; gunfire is heard in the kitchen while they stack: their claims turn to bang and a stun goes off in the kitchen before anyone goes in.",
		"tags": ["ai", "grenade", "entry", "stun", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Bang.stack(s)


func run(t: TestContext) -> void:
	if not t.require(Bang.arm(t, Bang.IDS), "both invaders carry a stun grenade (Character.item_count(7))"):
		return
	var claimed := func(): return Bang.IDS.all(func(id): return not Entry.calls(t, "claim", id).is_empty())
	if not t.require(await t.until(claimed, 10.0), "both claimed the back door"):
		return
	if not t.require(Bang.IDS.all(func(id): return Entry.calls(t, "", id).all(func(c): return c.get("bang") == false)), "set-up: both went for it quietly (ENTER)"):
		return
	if not t.require(Entry.calls(t, "going_in").is_empty(), "set-up: nobody had gone in when the gunfire came"):
		return
	Investigate.gunfire(Maps.KITCHEN_CENTRE)
	var heard := t.time
	await t.until(func(): return not Entry.calls(t, "going_in").is_empty(), 40.0)
	var steps := func(step: String) -> Array: return Probe.raw(t, &"callout", func(d): return String(d.get("entry_step", "")) == step)
	var went_in: float = steps.call("going_in")[0]["time"] if not steps.call("going_in").is_empty() else INF
	for id in Bang.IDS:
		var turned := Probe.raw(t, &"callout", func(d): return d.get("speaker") == t.actor(id) and String(d.get("entry_step", "")) != "" and d.get("bang") == true) \
			.filter(func(e): return float(e["time"]) >= heard)
		t.check(not turned.is_empty(), "%s's claims turned to bang after the gunfire" % id)
	var called: Array = steps.call("bang")
	t.check(not called.is_empty() and float(called[0]["time"]) < went_in, "the bang was called before anyone went in (bang at %s, going_in at %.2f s)" % [str(called.map(func(c): return snappedf(float(c["time"]), 0.01))), went_in])
	var booms := Probe.booms(t, &"stun")
	t.check(not booms.is_empty() and Maps.HOUSE_KITCHEN.has_point(booms[0]["data"]["position"]) and float(booms[0]["time"]) <= went_in,
		"a stun went off in the kitchen before anyone went in (bursts %s, going_in at %.2f s)" % [str(booms.map(func(b): return [snappedf(float(b["time"]), 0.01), b["data"]["position"]])), went_in])
