extends GameTest

## The setup window's three start buttons each report their mode with the chosen side and each side's
## count and loadout; a weapon without a gun hides its magazine rows.

const SetupMenu := preload("res://scenes/ui/menus/setup_menu.gd")

const WEAPONS := [
	{ "id": "pistol", "label": "Pistol", "magazines": [{ "id": "standard", "label": "Standard" }, { "id": "extended", "label": "Extended" }] },
	{ "id": "fists", "label": "Fists", "magazines": [] },
]


func describe() -> Dictionary:
	return {
		"name": "Setup window reports mode, side and loadouts",
		"description": "Start / Watch / Endless emit their mode with the chosen side, counts, weapons, magazines and spares; a gunless weapon hides the magazine rows.",
		"tags": ["setup", "ui"],
		"timeout": 5.0,
	}


func _press(t: TestContext, mode_button: String) -> Dictionary:
	var menu := SetupMenu.new()
	t.world.add_child(menu)
	menu.open({
		"side": "invader", "seed": 42,
		"defenders": { "count": 2, "weapon": "fists" },
		"invaders": { "count": 3, "weapon": "pistol", "magazine": "extended", "spares": 1 },
		"weapons": WEAPONS,
	})
	var got := []
	menu.start_requested.connect(func(c): got.append(c))
	(menu.find_child(mode_button, true, false) as Button).pressed.emit()
	menu.queue_free()
	return got[0] if not got.is_empty() else {}


func run(t: TestContext) -> void:
	var play := _press(t, "StartButton")
	t.expect_eq(play.get("mode"), "play", "Start plays")
	t.expect_eq(play.get("side"), "invader", "as the chosen side")
	t.expect_eq(play.get("seed"), 42, "the seed is passed")
	t.expect_eq(play["defenders"]["count"], 2, "defender count")
	t.expect_eq(play["defenders"]["weapon"], "fists", "defender weapon")
	t.expect_eq(play["defenders"]["magazine"], "", "a gunless weapon has no magazine")
	t.expect_eq(play["invaders"]["count"], 3, "invader count")
	t.expect_eq(play["invaders"]["weapon"], "pistol", "invader weapon")
	t.expect_eq(play["invaders"]["magazine"], "extended", "invader magazine")
	t.expect_eq(play["invaders"]["spares"], 1, "invader spares")
	t.expect_eq(_press(t, "WatchButton").get("mode"), "watch", "Watch watches")
	t.expect_eq(_press(t, "EndlessButton").get("mode"), "endless", "Endless goes endless")

	# current_config() is what the window shows right now, and reopening with it restores the same choices.
	var first := SetupMenu.new()
	t.world.add_child(first)
	first.open({ "side": "invader", "seed": 42, "defenders": { "count": 2, "weapon": "fists" },
		"invaders": { "count": 3, "weapon": "pistol", "magazine": "extended", "spares": 1 }, "weapons": WEAPONS })
	var kept: Dictionary = first.current_config()
	first.queue_free()
	t.check(not kept.has("mode"), "the remembered config carries no start mode")
	var second := SetupMenu.new()
	t.world.add_child(second)
	second.open(kept.merged({ "weapons": WEAPONS }))
	t.expect_eq(second.current_config(), kept, "reopening with a remembered config restores every choice")
	second.queue_free()

	# Without weapon choices (an older caller) the window still works and reports plain counts.
	var bare := SetupMenu.new()
	t.world.add_child(bare)
	bare.open({ "defenders": 4 })
	var got := []
	bare.start_requested.connect(func(c): got.append(c))
	(bare.find_child("StartButton", true, false) as Button).pressed.emit()
	t.expect_eq(got[0]["defenders"], { "count": 4 }, "no weapon rows without choices")
