extends GameTest

## O10 (docs/outfits.md): what a character wears weighs it down. The outfit's total weight lowers its move speed (a full plated
## kit by about 8%) and raises the stamina its run spends. Three bodies side by side, one wearing nothing set (unweighted), one
## in plain clothes and one in the full plated kit, walk, then run, the same way for the same time.

const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
const START_X := 100.0
const LANES := { &"bare": 150.0, &"plain": 300.0, &"plated": 450.0 }
const WALK_TIME := 2.0
const RUN_TIME := 2.0


func describe() -> Dictionary:
	return {
		"name": "A heavy outfit slows the walk and tires the run",
		"description": "A bare body, one in plain clothes and one in a full plated kit walk and then run for 2 s each: the plated one covers about 8% less ground and spends more stamina running; plain clothes weigh less than the kit.",
		"tags": ["outfit", "weight", "speed", "stamina", "movement"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1600, 600))
	s.switch(&"nav.rebake", false)
	for id: StringName in LANES:
		s.actor(id, &"puppet", Vector2(START_X, LANES[id]), { "facing": Vector2.RIGHT, "aim_point": Vector2(1600, LANES[id]) })


func run(t: TestContext) -> void:
	var plated := t.actor(&"plated")
	if not OutfitProbe.require_api(t, plated):
		return
	OutfitProbe.wear(plated, OutfitProbe.PLATED_KIT)
	OutfitProbe.wear(t.actor(&"plain"), OutfitProbe.PLAIN_CLOTHES)
	for id: StringName in LANES:
		t.puppet(id).aim_at(Vector2(1600, LANES[id]))
	await t.seconds(0.3)

	var walked := await _move(t, false, WALK_TIME)
	var bare_walk: float = walked[&"bare"]
	t.check(bare_walk > 200.0, "the bare body walks more than 200 px (%.0f px in %.0f s)" % [bare_walk, WALK_TIME])
	var plated_share: float = walked[&"plated"] / bare_walk
	t.check(plated_share > 0.85 and plated_share < 0.97,
		"the full plated kit walks about 8%% slower (%.0f px against %.0f: %.0f%%)" % [walked[&"plated"], bare_walk, plated_share * 100.0])
	t.check(walked[&"plain"] > walked[&"plated"] + 5.0, "plain clothes weigh less than the kit (%.0f px against %.0f)" % [walked[&"plain"], walked[&"plated"]])
	t.check(walked[&"plain"] <= bare_walk + 0.5, "and plain clothes are no faster than nothing worn")

	for id: StringName in LANES:
		t.puppet(id).stop()
	await t.seconds(0.5)  # come to a stop (walking spends no stamina, the bar is still full)
	var stamina_before := {}
	for id: StringName in LANES:
		stamina_before[id] = t.actor(id).stamina_fraction()
	var ran := await _move(t, true, RUN_TIME)
	var spent := {}
	for id: StringName in LANES:
		spent[id] = float(stamina_before[id]) - t.actor(id).stamina_fraction()
	t.check(spent[&"bare"] > 0.05, "running spends the bare body's stamina (%.2f)" % spent[&"bare"])
	t.check(spent[&"plated"] > spent[&"bare"] * 1.05, "the plated kit spends more stamina on the same run (%.3f against %.3f)" % [spent[&"plated"], spent[&"bare"]])
	t.check(ran[&"plated"] < ran[&"bare"] * 0.97, "and runs slower too (%.0f px against %.0f)" % [ran[&"plated"], ran[&"bare"]])


## Move every body right for `duration` s (running when `running`); returns the ground each covered (px).
func _move(t: TestContext, running: bool, duration: float) -> Dictionary:
	var from := {}
	for id: StringName in LANES:
		from[id] = t.actor(id).global_position.x
		t.puppet(id).set_run(running)
		t.puppet(id).walk(Vector2.RIGHT)
	await t.seconds(duration)
	var out := {}
	for id: StringName in LANES:
		out[id] = t.actor(id).global_position.x - float(from[id])
		t.trace("%s_%s" % [id, "run" if running else "walk"], out[id])
	return out
