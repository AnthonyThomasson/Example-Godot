extends GameTest

## Desired: in a quiet house, with nobody to fight or chase, a defender searching its rooms never
## leaves the house. Defenders are placed as Main places them (a clear spot in a random room) in a generated house
## and left alone for a while; every defender must stay within the house's rooms (a doorway's depth of slack).
## `--seed=N` pins the layout, to sweep houses.

const House := preload("res://tests/_ai/house_probe.gd")
const SEED := 1
const DEFENDERS := 2
const WATCH_S := 45.0


func describe() -> Dictionary:
	return {
		"name": "Defenders stay in a quiet house",
		"description": "Two defenders search a generated house with nobody to fight: neither ever steps outside it.",
		"tags": ["ai", "territory", "search", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED)
	s.von_script([{ "pick": "search" }])


func run(t: TestContext) -> void:
	var spawner = House.spawn(t, SEED, DEFENDERS, 0)
	var left: Dictionary = await House.watch(t, spawner.combatants, WATCH_S)
	t.check(left.is_empty(), "a defender left the house: %s" % [left])
