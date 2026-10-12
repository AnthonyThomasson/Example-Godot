extends GameTest

## Desired (E2): two invaders that decide on the same frame to enter by the same door never hold the same slot: the
## radio claim settles it (the flank side claim pattern), and they stand in different slots.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry stack slots are never claimed twice",
		"description": "Two invaders deciding on the same frame end up in different stack slots of the back door.",
		"tags": ["ai", "entry", "scripted", "callout"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	# The same cadence on purpose: they decide on the same frame, so both first reach for slot 1.
	Entry.npc(s, &"a", Vector2(960, 100), 0.4, { "entry_ready_timeout": 30.0 })
	Entry.npc(s, &"b", Vector2(960, 280), 0.4, { "entry_ready_timeout": 30.0 })


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var both_ready := func(): return not Entry.calls(t, "ready", &"a").is_empty() and not Entry.calls(t, "ready", &"b").is_empty()
	await Entry.watch(t, [&"a", &"b"], door, 25.0, both_ready)
	if not t.require(both_ready.call(), "both reached a slot (%s / %s)" % [Entry.brain(t, &"a").current_act(), Entry.brain(t, &"b").current_act()]):
		return
	var ea := Entry.entry(Entry.brain(t, &"a"))
	var eb := Entry.entry(Entry.brain(t, &"b"))
	t.check(int(ea.get("slot", 0)) > 0 and int(eb.get("slot", 0)) > 0, "both hold a slot (%s / %s)" % [ea.get("slot"), eb.get("slot")])
	t.check(int(ea.get("slot", 0)) != int(eb.get("slot", 0)), "different slots (%s / %s)" % [ea.get("slot"), eb.get("slot")])
	var pa: Vector2 = ea.get("stack_point", Vector2.INF)
	var pb: Vector2 = eb.get("stack_point", Vector2.INF)
	t.check(pa.distance_to(pb) >= 28.0, "their slots are a body apart (%.0f px)" % pa.distance_to(pb))
