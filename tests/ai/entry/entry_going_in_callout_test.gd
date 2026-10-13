extends GameTest

## Desired (E6): the point radios that it is going in (step `going_in`, the opening and its slot) before it crosses, and
## its teammate crosses after it, one at a time: the second steps into the doorway only after the point is through.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry point radios going in",
		"description": "The point calls going in with the opening and its slot; the second crosses only after the point is through.",
		"tags": ["ai", "entry", "scripted", "callout"],
		"timeout": 50.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(960, 60), 0.4)
	Entry.npc(s, &"b", Vector2(985, 110), 0.55)


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var both_in := func(): return not Entry.calls(t, "in", &"a").is_empty() and not Entry.calls(t, "in", &"b").is_empty()
	var samples := await Entry.watch(t, [&"a", &"b"], door, 45.0, both_in)
	var going := Entry.calls(t, "going_in")
	if not t.require(not going.is_empty(), "a going-in callout was radioed"):
		return
	var radioed: Dictionary = going[0]
	t.expect_eq(String(radioed.get("opening", "")), door["id"], "it names the opening")
	t.check(int(radioed.get("slot", 0)) >= 1, "it carries the speaker's slot (%s)" % radioed.get("slot"))
	t.check(String(radioed.get("status", "")).contains("going in"), "its status says going in (%s)" % radioed.get("status"))
	if not t.require(both_in.call(), "both went through the door"):
		return
	var point: StringName = &"a" if radioed.get("speaker") == t.actor(&"a") else &"b"
	var second: StringName = &"b" if point == &"a" else &"a"
	var going_at := Entry.first_call_time(t, "going_in", point)
	var second_in := Entry.first_in_funnel(samples, second, door)
	t.check(second_in > going_at, "the second crossed after the call (%.1f > %.1f s)" % [second_in, going_at])
	t.check(second_in > Entry.last_in_funnel(samples.filter(func(s): return s["t"] < second_in), point, door),
		"one at a time: the point was out of the doorway before the second stepped in")
