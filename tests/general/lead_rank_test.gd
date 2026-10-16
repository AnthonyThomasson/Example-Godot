extends GameTest

## LD10 (`docs/leadership.md`): "Lead the team". With it on (the setup window's `lead`, Start only), the human leads, and a
## human invader is given rank 2: the first NPC invader becomes the sergeant (1) and the rest troopers (0). The style draws are unchanged
## (each character's style and look seed are the ones it gets with "Lead the team" off). With it off, the human is ranked last of the
## unit. `Settings.set_setup` saves the config's `lead` with the rest of the window's choices.
##
## Main's match-setup logic runs on a Main that never enters the tree (as `match_setup_test.gd` does): the window's config through
## `_on_setup_chosen` (which applies it and returns, out of the tree, before building a world), then `_arm_characters` over the
## combatants in Main's order (the NPCs, then the human). `Settings.path` points at a scratch file, so no developer's file is touched.

const MainScript := preload("res://scenes/main.gd")


func describe() -> Dictionary:
	return {
		"name": "A human invader who leads is given rank 2",
		"description": "With Lead the team on, the human invader is armed as the unit's lead (rank 2), the first NPC its sergeant and the rest troopers, with the same style draws; off, the human is last; the setting is saved (LD10).",
		"tags": ["setup", "match", "leadership"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	# The settings file is a scratch one, and what Main and the load write into the Settings statics is put back after the test.
	s.set_static(Settings, "path", "user://test_lead_rank_settings.json")
	s.set_static(Settings, "setup", {})
	s.set_static(Settings, "overlays", {})
	s.set_static(Settings, "debug", Settings.debug)
	s.actor(&"npc1", &"puppet", Vector2(200, 250), { "faction": &"invader" })
	s.actor(&"npc2", &"puppet", Vector2(300, 250), { "faction": &"invader" })
	s.actor(&"me", &"puppet", Vector2(600, 250), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var cast := [t.actor(&"npc1"), t.actor(&"npc2"), t.actor(&"me")]
	var off := await _armed(t, false)
	t.expect_eq(off["ranks"], [2, 1, 0], "with Lead the team off the human is ranked last (npc1, npc2, human)")
	var on := await _armed(t, true)
	t.expect_eq(on["ranks"], [1, 0, 2], "with it on the human invader is the lead (2), the first NPC the sergeant (1), the rest troopers (0)")
	t.expect_eq(on["looks"], off["looks"], "the style draws are unchanged (each character's style and look seed)")
	for c in cast:
		c.rank = 0

	Settings.set_setup({ "side": "invader", "seed": 7, "lead": true, "defenders": { "count": 1 }, "invaders": { "count": 2 } })
	t.expect_eq(Settings.setup.get("lead"), true, "Settings.set_setup keeps the config's lead")
	Settings.setup = {}
	Settings.load_file()
	t.expect_eq(Settings.setup.get("lead"), true, "and saves it to the settings file")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Keybinds.reset_all()  # load_file re-applied the (empty) bindings; leave every action on its default.


## Arm the three test characters as Main does after the window's config with `lead`: `{ ranks: [...], looks: [[style, seed], ...] }`.
func _armed(t: TestContext, lead: bool) -> Dictionary:
	var cast := [t.actor(&"npc1"), t.actor(&"npc2"), t.actor(&"me")]
	var main = MainScript.new()
	await main._on_setup_chosen({ "mode": "play", "side": "invader", "seed": 99, "lead": lead,
		"defenders": { "count": 1 }, "invaders": { "count": 2 } })
	main._player = t.actor(&"me")
	main._arm_characters(cast)
	var out := { "ranks": cast.map(func(c): return int(c.rank)), "looks": cast.map(func(c): return [String(c.style), int(c.look_seed)]) }
	main.free()
	return out
