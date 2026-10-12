extends GameTest

## Desired (E6): a teammate that claimed a slot but never reaches it does not hold the stack forever: the invader at the
## door waits `entry_ready_timeout` after it was ready, then goes in without it.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const TIMEOUT := 8.0


func describe() -> Dictionary:
	return {
		"name": "Entry ready barrier times out",
		"description": "A teammate that never arrives is given up on after the ready timeout and the point goes in.",
		"tags": ["ai", "entry", "scripted", "gap", "callout"],
		"timeout": 50.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(930, 90), 0.4, { "entry_ready_timeout": TIMEOUT })
	# Claims a slot but cannot move: it never reaches it.
	Entry.npc(s, &"b", Vector2(990, 600), 0.55, { "entry_ready_timeout": TIMEOUT }, { "speed": 0.0 })


func run(t: TestContext) -> void:
	var door := Entry.BACK
	await Entry.watch(t, [&"a", &"b"], door, 45.0, func(): return not Entry.calls(t, "going_in", &"a").is_empty())
	var ready_at := Entry.first_call_time(t, "ready", &"a")
	var going_at := Entry.first_call_time(t, "going_in", &"a")
	if not t.require(going_at < INF, "the waiting invader went in (act %s)" % Entry.brain(t, &"a").current_act()):
		return
	t.check(not Entry.calls(t, "claim", &"b").is_empty(), "the stuck teammate had claimed a slot")
	t.check(Entry.calls(t, "ready", &"b").is_empty(), "the stuck teammate never reached it")
	t.check(going_at - ready_at >= TIMEOUT - 0.2, "it waited out the timeout (%.1f s)" % (going_at - ready_at))
	t.check(going_at - ready_at <= TIMEOUT + 6.0, "and not much longer (%.1f s)" % (going_at - ready_at))
