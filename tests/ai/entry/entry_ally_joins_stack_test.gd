extends GameTest

## Desired (E7): an invader starts a solo entry; an ally that comes into range while it slices the pie claims the next
## slot. The point then waits for it, goes in first, and the ally follows as the second to the other side.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry ally joins a solo stack",
		"description": "A late ally claims slot 2 of a solo entry; the point waits for it and they enter as a pair.",
		"tags": ["ai", "entry", "scripted", "callout"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(930, 80), 0.4)
	# Held back: not entering and not moving until the test lets it join. A short commit keeps it re-deciding.
	Entry.npc(s, &"b", Vector2(990, 330), 0.4, { "entry_enabled": false, "max_commit_time": 0.5 }, { "speed": 0.0 })


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var pieing := func(): return String(Entry.entry(Entry.brain(t, &"a")).get("phase", "")) == "pie"
	if not t.require(await t.until(pieing, 25.0), "the first invader started slicing the pie alone (act %s)" % Entry.brain(t, &"a").current_act()):
		return
	t.check(bool(Entry.entry(Entry.brain(t, &"a")).get("solo", false)), "it began alone")
	t.actor(&"b").set("speed", 150.0)
	Entry.brain(t, &"b").set("entry_enabled", true)
	var both_in := func(): return not Entry.calls(t, "in", &"a").is_empty() and not Entry.calls(t, "in", &"b").is_empty()
	var samples := await Entry.watch(t, [&"a", &"b"], door, 50.0, func():
		var at := maxf(Entry.first_call_time(t, "in", &"a"), Entry.first_call_time(t, "in", &"b"))
		return both_in.call() and t.time - at > 3.0)
	var claims := Entry.calls(t, "claim", &"b")
	if not t.require(not claims.is_empty(), "the ally claimed a slot"):
		return
	t.expect_eq(int(claims[0].get("slot", 0)), 2, "the ally took the next slot")
	if not t.require(both_in.call(), "both went in"):
		return
	t.check(Entry.first_call_time(t, "going_in", &"a") >= Entry.first_call_time(t, "ready", &"b"), "the point waited for the ally to be ready")
	t.check(Entry.first_in_funnel(samples, &"b", door) > Entry.last_in_funnel(samples.filter(func(s): return s["t"] < Entry.first_in_funnel(samples, &"b", door)), &"a", door),
		"the ally crossed after the point was through")
	var sa := Entry.first_stop_in_room(samples, &"a", door)
	var sb := Entry.first_stop_in_room(samples, &"b", door)
	t.check(sa != Vector2.INF and sb != Vector2.INF and signf(Entry.lateral(door, sa)) != signf(Entry.lateral(door, sb)), "they took opposite sides (%s / %s)" % [sa, sb])
