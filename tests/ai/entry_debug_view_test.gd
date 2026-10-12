extends GameTest

## The entry debug overlays' data (`debug_entry_view()`, what `entry_debug.gd` and `entry_team_debug.gd` draw) follows a
## pair through the kitchen's back door: the doorway, its slots and corners and each one's slot and role while stacked,
## the pie's arc still to walk and the room points unseen from outside, the team off the radio, and after the clear the
## kitchen's doorways on with the one each covers, and the kitchen among the rooms it regards as cleared. Both overlays
## are on, so a draw error fails the test.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry debug view follows the entry",
		"description": "debug_entry_view() reports the doorway, stack, pie, team and the doorways covered after the clear, with the entry overlays on.",
		"tags": ["ai", "entry", "scripted", "overlays"],
		"timeout": 70.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(960, 60), 0.4)
	Entry.npc(s, &"b", Vector2(985, 110), 0.55)
	s.show_overlays(["show_entry", "show_entry_team"])


func run(t: TestContext) -> void:
	var seen := { "stack": {}, "pie": {}, "cover": {} }
	var guard_before := {}
	var shoot_at := {}
	var done := func(): return not Entry.calls(t, "cover", &"a").is_empty() and not Entry.calls(t, "cover", &"b").is_empty()
	var end := t.time + 60.0
	while t.time < end and not done.call():
		for id in [&"a", &"b"]:
			var v: Dictionary = Entry.brain(t, id).debug_entry_view()
			if v.is_empty():
				continue  # Before the controller's first tick.
			if guard_before.is_empty():
				guard_before = v["guard"]
			var e: Dictionary = v["entry"]
			var phase := str(e.get("phase", ""))
			if seen.has(phase) and seen[phase].is_empty():
				seen[phase] = e
				shoot_at[phase] = t.time + 1.0
		for phase in shoot_at.keys():
			if t.time >= shoot_at[phase]:
				t.screenshot(phase)  # With --shots: what the overlays draw in each phase.
				shoot_at.erase(phase)
		await t.frames(1)
	if not t.require(done.call(), "the pair cleared the kitchen and covered its doorways on"):
		return
	await t.seconds(1.0)
	t.screenshot("cover")

	var stacked: Dictionary = seen["stack"]
	if t.check(not stacked.is_empty(), "a stacked view was reported"):
		t.expect_eq(String(stacked["opening"]), Entry.BACK["id"], "the view names the back door")
		t.check((stacked["door"]["pos"] as Vector2).distance_to(Entry.BACK["pos"]) < 1.0, "the doorway is at the back door")
		t.check((stacked["slots"] as Dictionary).has(1) and (stacked["slots"] as Dictionary).has(-1), "slots on both sides")
		t.expect_eq((stacked["corners"] as Array).size(), 4, "the kitchen's four corners")
		t.check((stacked["my_slot"] as Vector2) != Vector2.INF, "its own slot point")
		t.check(str(stacked["role"]) in ["point", "follower"], "a team role (%s)" % stacked["role"])
	var pie: Dictionary = seen["pie"]
	if t.check(not pie.is_empty(), "a pie view was reported"):
		t.check(not (pie["pie_queue"] as Array).is_empty(), "the pie steps still to walk")
		t.check(not (pie["unseen"] as Array).is_empty(), "the room points still unseen from outside")
		t.check(not (pie["team"] as Array).is_empty(), "the teammate off the radio")
	var covering: Array = []
	for id in [&"a", &"b"]:
		var v: Dictionary = Entry.brain(t, id).debug_entry_view()
		var e: Dictionary = v["entry"]
		if not t.check(str(e.get("phase", "")) == "cover", "%s reports covering (%s)" % [id, e.get("phase", "")]):
			continue
		var watch: Array = e["watch"].map(func(w): return w["id"])
		watch.sort()
		var expected := [Entry.KITCHEN_HALL["id"], Entry.KITCHEN_LIVING["id"]]
		expected.sort()
		t.expect_eq(watch, expected, "%s lists the kitchen's doorways on" % id)
		covering.append(str(e["covering"]))
		t.check((v["guard"]["cleared_rooms"] as Array).has(Maps.HOUSE_KITCHEN), "%s regards the kitchen as cleared" % id)
	t.check(covering.size() == 2 and covering[0] != covering[1], "each covers its own doorway (%s)" % str(covering))
	t.check(guard_before.has("ahead") and guard_before.has("rearm"), "the guard's view is reported")
