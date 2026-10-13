extends GameTest

## Desired: the same as defenders_stay_in_house_quiet, but with the real Von deciding and with invaders
## standing outside the house heading for its front door (as in a match, before the fight starts): no defender
## ever steps outside. Needs the Von decision server. `--seed=N` pins the layout, to sweep houses.

const House := preload("res://tests/_ai/house_probe.gd")
const SEED := 1
const DEFENDERS := 2
const INVADERS := 2
const WATCH_S := 40.0


func describe() -> Dictionary:
	return {
		"name": "Defenders stay in the house as a match starts",
		"description": "Two defenders and two invaders in a generated house, as at the start of a match, real Von deciding: no defender ever steps outside.",
		"tags": ["ai", "territory", "search", "von"],
		"requires_von": true,
		"timeout": 80.0,
		# Furniture shoved in a real match makes the nav re-baker now and then hand the engine overlapping footprints
		# (see perf/match_5v5_stress); that is a nav bug this test is not about.
		"allowed_logs": ["Navigation map synchronization error", "NavigationPolygon polygon convex partition failed", "Invalid polygon data, triangulation failed"],
	}


func configure(s: TestSetup) -> void:
	s.house(SEED)


func run(t: TestContext) -> void:
	var spawner = House.spawn(t, SEED, DEFENDERS, INVADERS)
	var left: Dictionary = await House.watch(t, spawner.combatants.slice(0, DEFENDERS), WATCH_S)
	t.check(left.is_empty(), "a defender left the house: %s" % [left])
