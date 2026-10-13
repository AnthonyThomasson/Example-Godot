extends GameTest

## Desired (E8): a team holding a room it has cleared keeps its doorways covered until one of them moves on, then the
## rest go too: nobody stands on alone. `a` is tuned to move on after 3 s of covering; `b` would hold for 30 s, but
## leaves its doorway soon after `a` radios that it is done.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry cover holds until the team moves",
		"description": "After clearing the kitchen the pair covers its doorways together; when one moves on, the other follows at once.",
		"tags": ["ai", "entry", "scripted", "callout"],
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(960, 60), 0.4, { "entry_cover_time": 3.0 })
	Entry.npc(s, &"b", Vector2(985, 110), 0.55, { "entry_cover_time": 30.0 })


func run(t: TestContext) -> void:
	var covering := func(): return not Entry.calls(t, "cover", &"a").is_empty() and not Entry.calls(t, "cover", &"b").is_empty()
	await Entry.watch(t, [&"a", &"b"], Entry.BACK, 60.0, covering)
	if not t.require(covering.call(), "both covered a doorway on (%s / %s)" % [Entry.brain(t, &"a").current_act(), Entry.brain(t, &"b").current_act()]):
		return
	# Both hold together until `a` is done.
	var together := 0.0
	var a_done := func(): return not Entry.calls(t, "done", &"a").is_empty()
	var end := t.time + 10.0
	var last := t.time
	while not a_done.call() and t.time < end:
		if Entry.entry(Entry.brain(t, &"a")).get("phase", "") == "cover" and Entry.entry(Entry.brain(t, &"b")).get("phase", "") == "cover":
			together += t.time - last
		last = t.time
		await t.frames(1)
	if not t.require(a_done.call(), "a moved on after its cover time (act %s)" % Entry.brain(t, &"a").current_act()):
		return
	t.check(together >= 1.5, "they covered the doorways together for a while (%.2f s)" % together)
	var a_at := Entry.first_call_time(t, "done", &"a")
	var b_left := func(): return Entry.entry(Entry.brain(t, &"b")).get("phase", "") != "cover"
	await t.until(b_left, 3.0)
	t.check(b_left.call(), "b stopped covering after a moved on")
	var b_at := Entry.first_call_time(t, "done", &"b")
	t.check(b_at < INF and b_at - a_at <= 1.5, "b moved on within 1.5 s of a (a %.2f s, b %.2f s)" % [a_at, b_at])
