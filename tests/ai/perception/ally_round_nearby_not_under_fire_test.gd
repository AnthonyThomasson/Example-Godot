extends GameTest

## An ally's round striking close by is not fire at the NPC (issue #51, found while building R11): a teammate's shot that lands within
## `hit_awareness_radius` of an NPC does not put it under fire, as it knows who fired; a round from a hostile, or from a shooter it does not
## know, landing as close does, and so does an ally's round that hits the NPC itself. Four invaders stand well apart, each held still
## (`speed` 0, so the distances hold); one `hit` event lands 80 px from each (on the fourth, on it), told apart by its attacker. Read off
## each NPC's memory (`debug_memory()["under_fire"]`). Scripted Von (one mechanism).

const AT := [Vector2(300, 250), Vector2(900, 250), Vector2(1500, 250), Vector2(2100, 250)]
const IDS := [&"near_ally", &"near_hostile", &"near_unknown", &"hit_by_ally"]


func describe() -> Dictionary:
	return {
		"name": "An ally's round striking close by is not fire at the NPC",
		"description": "A teammate's round landing 80 px from an NPC leaves it calm; a hostile's or an unknown shooter's landing as close puts it under fire, and so does an ally's round that hits it.",
		"tags": ["ai", "perception", "scripted"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 2400, 500))
	s.von_script([{ "pick": "stay" }])
	for i in IDS.size():
		s.actor(IDS[i], &"invader", AT[i], { "speed": 0.0 })
	s.actor(&"mate", &"puppet", Vector2(1200, 450), { "faction": &"invader", "max_health": 1000000.0 })
	s.actor(&"foe", &"puppet", Vector2(1800, 450), { "faction": &"household", "max_health": 1000000.0 })


func run(t: TestContext) -> void:
	await t.seconds(0.3)
	var mate := t.actor(&"mate")
	var foe := t.actor(&"foe")
	var shots := [
		{ "attacker": mate, "victim": null },
		{ "attacker": foe, "victim": null },
		{ "attacker": null, "victim": null },
		{ "attacker": mate, "victim": t.actor(&"hit_by_ally") },
	]
	for i in IDS.size():
		var at: Vector2 = AT[i] + (Vector2.ZERO if shots[i]["victim"] != null else Vector2(0, 80))
		EventBus.post(&"hit", { "position": at, "direction": Vector2.UP, "damage": 0.0, "attacker": shots[i]["attacker"], "victim": shots[i]["victim"] })
	await t.frames(3)
	var under := func(id: StringName) -> bool: return not t.controller(id, &"debug_memory").debug_memory().get("under_fire", {}).is_empty()
	t.check(not under.call(&"near_ally"), "an ally's round 80 px off does not put it under fire")
	t.check(under.call(&"near_hostile"), "a hostile's round 80 px off puts it under fire")
	t.check(under.call(&"near_unknown"), "a round from a shooter it does not know, 80 px off, puts it under fire")
	t.check(under.call(&"hit_by_ally"), "an ally's round that hits it puts it under fire")
