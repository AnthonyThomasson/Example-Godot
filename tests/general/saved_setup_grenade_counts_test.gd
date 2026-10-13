extends GameTest

## G5: the grenade counts chosen in the setup window are saved with the rest of the setup, and an older save that does not name them keeps the
## defaults (invaders 1 stun + 1 frag, defenders none): Main lays what was saved over its defaults side by side. Runs against a scratch file on a Main
## that never enters the tree, never the real file.

const MainScript := preload("res://scenes/main.gd")
const SCRATCH := "user://settings_grenades_test.json"


func describe() -> Dictionary:
	return {
		"name": "Saved setups keep the grenade counts, and old ones the defaults",
		"description": "The stun and frag counts a side was set to come back after a reload; a save written before they existed leaves invaders at 1 + 1 and defenders at 0 + 0 while keeping what it did name.",
		"tags": ["settings", "setup", "grenade", "persistence"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})


func run(t: TestContext) -> void:
	var main = MainScript.new()
	var defaults := {
		"side": "defender", "seed": 0,
		"defenders": main._side_defaults(2, main.defender_loadout),
		"invaders": main._side_defaults(2, main.invader_loadout),
	}
	t.expect_eq([int(defaults["invaders"]["stuns"]), int(defaults["invaders"]["frags"])], [1, 1], "the invaders' defaults are 1 stun and 1 frag")
	t.expect_eq([int(defaults["defenders"]["stuns"]), int(defaults["defenders"]["frags"])], [0, 0], "the defenders' are none")

	# A save from before the grenades: it names the counts of people and guns only.
	_write({ "setup": { "side": "invader", "seed": 5, "defenders": { "count": 3, "weapon": "smg" }, "invaders": { "count": 4 } } })
	Settings.load_file()
	var merged: Dictionary = main._with_saved_setup(defaults)
	t.expect_eq(int(merged["invaders"]["count"]), 4, "what the old save names is kept (the invader count)")
	t.expect_eq(str(merged["defenders"]["weapon"]), "smg", "and the defenders' weapon")
	t.expect_eq([int(merged["invaders"]["stuns"]), int(merged["invaders"]["frags"])], [1, 1], "the invaders keep 1 stun and 1 frag")
	t.expect_eq([int(merged["defenders"]["stuns"]), int(merged["defenders"]["frags"])], [0, 0], "the defenders keep none")

	# The counts a player chose are saved with the setup and come back.
	Settings.set_setup({ "mode": "watch", "side": "defender", "seed": 9, "defenders": { "count": 2, "stuns": 3, "frags": 0 }, "invaders": { "count": 2, "stuns": 0, "frags": 2 } })
	Settings.setup = {}
	Settings.load_file()
	merged = main._with_saved_setup(defaults)
	t.expect_eq([int(merged["defenders"]["stuns"]), int(merged["defenders"]["frags"])], [3, 0], "the defenders' chosen counts come back after a reload")
	t.expect_eq([int(merged["invaders"]["stuns"]), int(merged["invaders"]["frags"])], [0, 2], "and the invaders' (a chosen 0 is not the default)")
	main.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _write(data: Dictionary) -> void:
	var f := FileAccess.open(SCRATCH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
