extends GameTest

## Main's match-setup logic, run on a Main that never enters the tree: each side is armed with its own
## loadout (by faction), an endless run draws counts within the setup's limits and valid loadouts, and a
## setup window's per-side config is parsed into counts and loadouts.

const MainScript := preload("res://scenes/main.gd")


func describe() -> Dictionary:
	return {
		"name": "Main arms sides and randomises endless matches",
		"description": "Each faction gets its side's gun, magazine and spares; endless draws stay within the chosen counts with valid loadouts; the setup config is parsed.",
		"tags": ["setup", "match", "loadout"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.actor(&"home", &"puppet", Vector2(200, 250), { "faction": &"household" })
	s.actor(&"raider", &"puppet", Vector2(600, 250), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var main = MainScript.new()
	main.house_seed = 99
	main.defender_loadout = { "weapon": &"smg", "magazine": &"smg_extended", "spares": 3 }
	main.invader_loadout = { "weapon": &"rifle" }
	main._arm_characters([t.actor(&"home"), t.actor(&"raider")])
	var home := t.actor(&"home")
	var raider := t.actor(&"raider")
	t.expect_eq(home.current_slot(), int(GunConfig.row(&"smg")["slot"]), "the defender holds the SMG")
	t.expect_eq(home.ammo(), MagazineConfig.capacity_of(&"smg_extended"), "loaded with the extended magazine")
	t.expect_eq(home.spare_magazines(), 3, "and carries three spares")
	t.expect_eq(raider.current_slot(), int(GunConfig.row(&"rifle")["slot"]), "the invader holds the rifle")
	t.expect_eq(raider.spare_magazines(), int(GunConfig.row(&"rifle")["spare_magazines"]), "with the rifle's own spares")

	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	t.expect_eq(main._random_count(rng, 0), 0, "an empty side stays empty")
	for i in 50:
		var n: int = main._random_count(rng, 3)
		t.check(n >= 1 and n <= 3, "a drawn count is within 1..3 (%d)" % n)

	main._endless_max = { "defenders": 3, "invaders": 0 }
	main._randomize_match()
	t.check(main.defender_count >= 1 and main.defender_count <= 3, "endless defenders are within the chosen count")
	t.expect_eq(main.invader_count, 0, "endless invaders stay at zero")
	t.expect_eq(main.house_seed, 0, "endless asks for a fresh seed")
	t.expect_eq(main.defender_loadout, LoadoutConfig.normalize(main.defender_loadout), "the defender loadout is valid")
	t.expect_eq(main.invader_loadout, LoadoutConfig.normalize(main.invader_loadout), "the invader loadout is valid")

	t.expect_eq(main._side_value(4, "count", 1), 4, "a bare count is read as the count")
	t.expect_eq(main._side_value({ "count": 2 }, "count", 1), 2, "a side dict's count is read")
	t.expect_eq(main._side_loadout({ "weapon": "pistol", "spares": 1 }, {}), { "weapon": "pistol", "spares": 1 }, "a side dict's loadout keys are kept")
	t.check(not main._side_defaults(1, {}).has("spares"), "an unset spare count is left to the window's default")
	t.expect_eq(main._side_defaults(2, { "weapon": &"smg", "spares": 1 })["count"], 2, "the side defaults carry the count")
	main.free()
