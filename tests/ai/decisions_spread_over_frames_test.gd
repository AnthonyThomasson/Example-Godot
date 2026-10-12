extends GameTest

## NPCs that want to decide on the same frame build their decision snapshots over several frames, not all in one
## (`DecisionBudget`): eight invaders spawned together all see a hostile from their first frame; at most one of them starts
## a decision each frame (a choice that is done on arrival, like firing from where it stands, is decided again on the next),
## every one of them has decided within two frames apiece (none starves), and with the limit raised to all eight they go on
## deciding together at their cadence.

const COUNT := 8
const SPREAD_FRAMES := 2 * COUNT + 4
const TARGET := Vector2(900, 60)


func describe() -> Dictionary:
	return {
		"name": "Decisions are spread over frames",
		"description": "Eight invaders spawned together start at most one decision per frame and all decide within two frames apiece; with the limit raised they keep deciding at their cadence.",
		"tags": ["ai", "decision", "scripted"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1800, 400))
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.set_static(DecisionBudget, "per_frame", 1)  # The default, pinned: the first half asserts on it.
	for i in COUNT:
		var at := Vector2(150 + i * 200, 300)
		s.actor(StringName("inv%d" % i), &"invader", at, { "speed": 0.0, "facing": (TARGET - at).normalized() })
		# A short cadence, so each re-decides a few times within the window measured below.
		s.set_props(StringName("inv%d" % i), "GoalController", { "tactic_interval": 0.4, "decide_interval": 0.4, "max_commit_time": 0.4 })
	s.actor(&"tgt", &"puppet", TARGET, { "faction": &"household", "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var brains: Array = []
	for i in COUNT:
		brains.append(t.controller(StringName("inv%d" % i), &"debug_state"))
	var decided_after: Array = []
	for frame in SPREAD_FRAMES:
		await t.frames(1)
		decided_after.append(_decided(brains))
	t.trace("decided", decided_after[SPREAD_FRAMES - 1])
	t.check(decided_after[0] <= 2, "on the first frame at most one snapshot started (%d NPCs had decided)" % decided_after[0])
	var one_at_a_time := true
	for k in range(1, SPREAD_FRAMES):
		if decided_after[k] - decided_after[k - 1] > 1:
			one_at_a_time = false
	t.check(one_at_a_time, "never more than one new decision per frame (%s)" % [decided_after])
	t.check(decided_after[SPREAD_FRAMES - 1] == COUNT, "all %d had decided within %d frames, none starved (%s)" % [COUNT, SPREAD_FRAMES, decided_after])

	DecisionBudget.per_frame = COUNT  # Every NPC may decide on one frame (the test harness restores the static afterwards).
	var asked_before: int = t.von_requests().size()
	await t.seconds(1.5)
	var asked: int = t.von_requests().size() - asked_before
	t.check(asked >= COUNT, "with the limit raised every NPC decided again within 1.5 s (%d asks)" % asked)


## How many of `brains` have finished at least one decision walk.
func _decided(brains: Array) -> int:
	var n := 0
	for b in brains:
		if not (b.debug_state().get("decision", {}).get("levels", []) as Array).is_empty():
			n += 1
	return n
