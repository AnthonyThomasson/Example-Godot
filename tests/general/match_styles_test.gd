extends GameTest

## R2 and R3's arming (ticket #61): Main arms a match's crew from the match seed (`_arm_characters`, as `match_setup_test` drives
## it, on a Main that never enters the tree), and the styles come with the arms:
## - R2: every invader, the human invader too, wears one police unit (`Character.style` `zenitex` or `trauma`), the same for every
##   invader of a match; the unit is drawn from the seed (re-arming with the same seed gives the same one, and across seeds both
##   units come up). Each defender is seeded to `merc` or `borg` (both in a crew of twelve) and to a look seed of its own.
## - R3 (`LoadoutConfig.apply` hands each item the wielder's weapon style): an invader's gun and grenades are `police` issue; a
##   defender's are `scrap` or `pipe`, one style for all it carries, and both come up across the crew.
## - The unit's ranks (`docs/outfits.md`, styles): its first invader is the lead (`Character.rank` 2), the second the sergeant (1),
##   the rest troopers (0); a defender has no rank.
## Read through `Character.style` / `look_seed` / `rank` and each carried gun's and grenade's `Item.style`.

const MainScript := preload("res://scenes/main.gd")
const DEFENDERS := 12
const INVADERS := 4
const SEED := 61
## Seeds the unit is drawn for (both units must come up).
const UNIT_SEEDS := 24
const UNITS := [&"zenitex", &"trauma"]
const DEFENDER_STYLES := [&"merc", &"borg"]
const DEFENDER_WEAPONS := [&"scrap", &"pipe"]
const INVADER_WEAPON := &"police"
## Both sides carry a gun and a grenade of each kind, so every kind of item is checked.
const DEFENDER_LOADOUT := { "weapon": &"pistol", "stuns": 1, "frags": 1 }
const INVADER_LOADOUT := { "weapon": &"rifle", "stuns": 1, "frags": 1 }
## The invaders' ranks in the order they are armed: the lead, the sergeant, then troopers (the human last).
const INVADER_RANKS := [2, 1, 0, 0, 0]


func describe() -> Dictionary:
	return {
		"name": "A match's invaders share a police unit, its defenders mix merc and borg",
		"description": "Main arms a crew from the match seed: every invader (and the human) gets one unit, drawn from the seed; defenders are seeded merc or borg; every gun and grenade carries its wielder's weapon style.",
		"tags": ["style", "match", "loadout", "setup"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"nav.rebake", false)
	for i in DEFENDERS:
		s.actor(_defender(i), &"puppet", Vector2(100 + (i % 6) * 110, 100 + floori(i / 6.0) * 90), { "faction": MainScript.DEFENDER_FACTION })
	for i in INVADERS:
		s.actor(_invader(i), &"puppet", Vector2(100 + i * 110, 320), { "faction": MainScript.INVADER_FACTION })
	# The human invader: the player's own character and controller, joined to the invaders' side as Main joins it.
	s.actor(&"human", &"player", Vector2(600, 400), { "faction": MainScript.INVADER_FACTION })


func run(t: TestContext) -> void:
	var defenders: Array = []
	for i in DEFENDERS:
		defenders.append(t.actor(_defender(i)))
	var invaders: Array = []
	for i in INVADERS:
		invaders.append(t.actor(_invader(i)))
	invaders.append(t.actor(&"human"))
	var main = MainScript.new()
	main.defender_loadout = DEFENDER_LOADOUT
	main.invader_loadout = INVADER_LOADOUT

	main.house_seed = SEED
	main._arm_characters(defenders + invaders)
	var unit: StringName = invaders[0].style
	t.check(unit in UNITS, "the first invader wears a police unit, zenitex or trauma (got %s)" % [unit])
	for c: Node in invaders:
		t.expect_eq(c.style, unit, "%s wears the match's unit" % c.name)
		_check_items(t, c, [INVADER_WEAPON])
	_check_ranks(t, invaders, defenders, "armed")
	var styles := {}  # defender -> its style
	var weapons := {}  # weapon style -> true
	var seeds := {}  # look seed -> true
	for c: Node in defenders:
		var style: StringName = c.style
		styles[c] = style
		t.check(style in DEFENDER_STYLES, "%s is seeded merc or borg (got %s)" % [c.name, style])
		var weapon: Variant = _check_items(t, c, DEFENDER_WEAPONS)
		if weapon != null:
			weapons[weapon] = true
		seeds[c.look_seed] = true
	for style in DEFENDER_STYLES:
		t.check(styles.values().has(style), "a crew of %d defenders has a %s among it" % [DEFENDERS, style])
	for weapon in DEFENDER_WEAPONS:
		t.check(weapons.has(weapon), "a crew of %d defenders carries %s weapons among it" % [DEFENDERS, weapon])
	t.check(seeds.size() == DEFENDERS, "each defender has a look seed of its own (%d distinct of %d)" % [seeds.size(), DEFENDERS])

	# Drawn from the seed: the same seed arms the same way.
	main._arm_characters(defenders + invaders)
	t.expect_eq(invaders[0].style, unit, "re-armed with the same seed, the invaders wear the same unit")
	for c: Node in defenders:
		t.expect_eq(c.style, styles[c], "re-armed with the same seed, %s keeps its style" % c.name)
	_check_ranks(t, invaders, defenders, "re-armed")

	# Across seeds both units come up, one per match.
	var units := {}
	for s in range(1, UNIT_SEEDS + 1):
		main.house_seed = s
		main._arm_characters(invaders)
		var drawn: StringName = invaders[0].style
		units[drawn] = true
		for c: Node in invaders:
			if not t.check(c.style == drawn, "seed %d: %s wears the match's unit %s (got %s)" % [s, c.name, drawn, c.style]):
				break
	for u in UNITS:
		t.check(units.has(u), "across %d seeds, the invaders are %s in some match (units drawn: %s)" % [UNIT_SEEDS, u, units.keys()])
	main.free()


## Check the ranks: the invaders' (in the order they were armed) are `INVADER_RANKS`, every defender's 0; `when` names the arming.
func _check_ranks(t: TestContext, invaders: Array, defenders: Array, when: String) -> void:
	var ranks := []
	for c: Node in invaders:
		ranks.append(c.rank)
	t.expect_eq(ranks, INVADER_RANKS, "%s, the unit's first invader is its lead (rank 2), the second its sergeant (1), the rest troopers (0)" % when)
	for c: Node in defenders:
		t.expect_eq(c.rank, 0, "%s, %s (a defender) has no rank" % [when, c.name])


## Check that every gun and grenade `c` carries has a weapon style in `allowed`, one style for all of them; returns it (null when
## none could be read). Each is held in turn to be read (`select_slot`, `current_item`); the gun is held again afterwards.
func _check_items(t: TestContext, c: Node, allowed: Array) -> Variant:
	var gun: int = c.gun_slot()
	var slots := [gun, ItemRegistry.STUN_SLOT, ItemRegistry.FRAG_SLOT]
	var found: Variant = null
	for slot: int in slots:
		if not t.check(c.has_item(slot), "%s carries an item in slot %d" % [c.name, slot]):
			continue
		c.select_slot(slot)
		var item: Item = c.current_item()
		var style: StringName = item.style
		t.check(style in allowed, "%s's %s has a weapon style in %s (got %s)" % [c.name, c.item_name(), allowed, style])
		if found == null:
			found = style
		else:
			t.check(style == found, "%s's %s has the same weapon style as the rest it carries (%s, got %s)" % [c.name, c.item_name(), found, style])
	c.select_slot(gun)
	return found


func _defender(i: int) -> StringName:
	return StringName("defender_%d" % i)


func _invader(i: int) -> StringName:
	return StringName("invader_%d" % i)
