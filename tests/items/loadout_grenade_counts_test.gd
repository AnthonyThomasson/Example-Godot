extends GameTest

## G5 (and the registry of G1): a side's loadout carries a count of stun and frag grenades (0 to 3). `LoadoutConfig.apply`
## gives the character that many in slots 7 and 8, `normalize` keeps the counts within 0..3, the setup window carries a
## Stun and a Frag count per side, and a match's default is invaders 1 + 1, defenders 0 + 0.
## `ItemRegistry.create(slot, count)` makes the grenade items, whose `uses_left()` is the count (guns and the rest: -1).

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const MainScript := preload("res://scenes/main.gd")
const SetupMenu := preload("res://scenes/ui/menus/setup_menu.gd")

const WEAPONS := [
	{ "id": "pistol", "label": "Pistol", "magazines": [{ "id": "standard", "label": "Standard" }, { "id": "extended", "label": "Extended" }] },
	{ "id": "fists", "label": "Fists", "magazines": [] },
]


func describe() -> Dictionary:
	return {
		"name": "Loadouts carry stun and frag counts",
		"description": "ItemRegistry.create(7|8, n) counts down from n; LoadoutConfig.apply arms a character with n stuns and m frags, normalize clamps them to 0..3; the setup window round-trips a count per side; a match defaults to invaders 1+1 and defenders 0+0.",
		"tags": ["grenade", "loadout", "setup", "item"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.actor(&"armed", &"puppet", Vector2(200, 250))
	s.actor(&"plain", &"puppet", Vector2(200, 400))
	s.actor(&"home", &"puppet", Vector2(500, 150), { "faction": &"household" })
	s.actor(&"raider", &"puppet", Vector2(500, 300), { "faction": &"invader" })


func _press(t: TestContext, mode_button: String, config: Dictionary) -> Dictionary:
	var menu := SetupMenu.new()
	t.world.add_child(menu)
	menu.open(config)
	var got := []
	menu.start_requested.connect(func(c): got.append(c))
	(menu.find_child(mode_button, true, false) as Button).pressed.emit()
	menu.queue_free()
	return got[0] if not got.is_empty() else {}


func run(t: TestContext) -> void:
	# The items: a count, spent a throw at a time.
	# Untyped (Variant) on purpose: `Item` has no `uses_left` yet, and a typed call would not parse.
	var stun: Variant = ItemRegistry.create(Probe.STUN, 2)
	var frag: Variant = ItemRegistry.create(Probe.FRAG, 3)
	var pistol: Variant = ItemRegistry.create(Probe.PISTOL)
	var fists: Variant = ItemRegistry.create(ItemRegistry.FISTS_SLOT)
	if not t.require(stun != null and frag != null, "ItemRegistry.create(7, 2) and create(8, 3) make the grenade items"):
		return
	if not t.require(stun.has_method("uses_left") and pistol.has_method("uses_left"), "Item.uses_left() exists on every item"):
		return
	t.expect_eq(stun.uses_left(), 2, "the stun grenade item counts two")
	t.expect_eq(frag.uses_left(), 3, "the frag grenade item counts three")
	t.expect_eq(pistol.uses_left(), -1, "a gun is unlimited (-1)")
	t.expect_eq(fists.uses_left(), -1, "so are the fists")
	t.check(stun.has_method("is_throwable") and stun.is_throwable() and frag.is_throwable(), "a grenade is throwable")
	t.check(pistol.has_method("is_throwable") and not pistol.is_throwable(), "a gun is not")

	# apply: the counts reach the character.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var armed := t.actor(&"armed")
	LoadoutConfig.apply(armed, { "weapon": &"smg", "stuns": 2, "frags": 3 }, rng)
	t.expect_eq(Probe.count(armed, Probe.STUN), 2, "two stun grenades are carried (slot 7)")
	t.expect_eq(Probe.count(armed, Probe.FRAG), 3, "three frag grenades are carried (slot 8)")
	t.expect_eq(armed.current_slot(), int(GunConfig.row(&"smg")["slot"]), "the gun is still what is held")
	var plain := t.actor(&"plain")
	LoadoutConfig.apply(plain, { "weapon": &"pistol" }, rng)
	t.expect_eq(Probe.count(plain, Probe.STUN), 0, "a loadout that names none carries no stun grenades")
	t.expect_eq(Probe.count(plain, Probe.FRAG), 0, "and no frag grenades")

	# normalize keeps the counts in 0..3.
	var big := LoadoutConfig.normalize({ "weapon": &"pistol", "stuns": 9, "frags": 9 })
	t.expect_eq(big.get("stuns"), 3, "a stun count above three is three")
	t.expect_eq(big.get("frags"), 3, "a frag count above three is three")
	var neg := LoadoutConfig.normalize({ "weapon": &"pistol", "stuns": -4, "frags": -4 })
	t.expect_eq(neg.get("stuns"), 0, "a negative stun count is zero")
	t.expect_eq(neg.get("frags"), 0, "a negative frag count is zero")
	var loader: GDScript = LoadoutConfig
	if t.require(loader.has_method("grenade_options"), "LoadoutConfig.grenade_options() lists the grenade rows for the setup window"):
		var rows: Array = loader.call("grenade_options")
		t.expect_eq(rows.map(func(r): return r["id"]), [&"stun", &"frag"], "a stun row and a frag row, in slot order")
		t.expect_eq(rows.map(func(r): return int(r["slot"])), [Probe.STUN, Probe.FRAG], "slots 7 and 8")
		t.expect_eq(rows.map(func(r): return int(r["max"])), [3, 3], "each up to three")
	t.expect_eq(LoadoutConfig.options().size(), GunConfig.guns.size() + 1, "the gun options stay Random plus one per gun")

	# The setup window carries a Stun and a Frag count per side.
	var side := { "side": "invader", "seed": 42, "weapons": WEAPONS,
		"defenders": { "count": 2, "weapon": "fists", "stuns": 0, "frags": 1 },
		"invaders": { "count": 3, "weapon": "pistol", "magazine": "extended", "spares": 1, "stuns": 2, "frags": 3 } }
	var play := _press(t, "StartButton", side)
	t.expect_eq(play.get("invaders", {}).get("stuns"), 2, "the window reports the invaders' stun count")
	t.expect_eq(play.get("invaders", {}).get("frags"), 3, "and their frag count")
	t.expect_eq(play.get("defenders", {}).get("stuns"), 0, "the defenders' stun count")
	t.expect_eq(play.get("defenders", {}).get("frags"), 1, "and frag count")
	var kept := SetupMenu.new()
	t.world.add_child(kept)
	kept.open(side)
	var config: Dictionary = kept.current_config()
	kept.queue_free()
	t.expect_eq(config.get("invaders", {}).get("frags"), 3, "current_config() keeps the counts for the next opening")

	# A match's defaults: invaders 1 + 1, defenders 0 + 0.
	var main = MainScript.new()
	main.house_seed = 99
	main._arm_characters([t.actor(&"home"), t.actor(&"raider")])
	t.expect_eq([Probe.count(t.actor(&"raider"), Probe.STUN), Probe.count(t.actor(&"raider"), Probe.FRAG)], [1, 1], "an invader starts with one stun and one frag")
	t.expect_eq([Probe.count(t.actor(&"home"), Probe.STUN), Probe.count(t.actor(&"home"), Probe.FRAG)], [0, 0], "a defender starts with none")
	main.free()
