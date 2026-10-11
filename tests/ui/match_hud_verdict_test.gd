extends GameTest

## The match HUD announces the result once (`match_ended`): when a faction is eliminated, or when the
## time limit runs out; and `begin` can be called again for a fresh match.

const MatchHUD := preload("res://scenes/ui/match_hud.gd")


class Fighter extends Node:
	signal died
	var faction: StringName = &"a"
	var is_dead := false

	func kill() -> void:
		is_dead = true
		died.emit()


func describe() -> Dictionary:
	return {
		"name": "Match HUD announces the result",
		"description": "match_ended fires once when a faction is eliminated and when the time limit passes; begin() restarts it cleanly.",
		"tags": ["ui", "match", "hud"],
		"timeout": 6.0,
	}


func _fighter(t: TestContext, name: String, faction: StringName) -> Fighter:
	var f := Fighter.new()
	f.name = name
	f.faction = faction
	t.world.add_child(f)
	return f


func run(t: TestContext) -> void:
	var hud := MatchHUD.new()
	t.world.add_child(hud)
	var verdicts := []
	hud.match_ended.connect(func(v): verdicts.append(v))

	var a := _fighter(t, "Ann", &"household")
	var b := _fighter(t, "Bob", &"invader")
	var c := _fighter(t, "Cy", &"invader")
	hud.begin([a, b, c])
	b.kill()
	t.expect_eq(verdicts.size(), 0, "one invader down: the match goes on")
	c.kill()
	t.expect_eq(verdicts, ["Ann WINS"], "the last invader down: the survivor wins, once")
	a.kill()
	t.expect_eq(verdicts.size(), 1, "a later death does not announce again")

	verdicts.clear()
	var d := _fighter(t, "Dee", &"household")
	var e := _fighter(t, "Eve", &"invader")
	hud.begin([d, e], 0.5)
	await t.seconds(1.0)
	t.expect_eq(verdicts, ["TIME UP - DRAW"], "an undecided match is a draw at the time limit")
	e.kill()
	t.expect_eq(verdicts.size(), 1, "and stays decided")
