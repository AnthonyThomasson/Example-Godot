extends GameTest

## A character spawns carrying one random gun: `ItemRegistry.random_gun_slot` draws from a seeded generator (so a house seed
## reproduces the loadouts and every gun comes up), and `Character.set_loadout` leaves it with bare hands, fists, the key and
## just that gun, holding it, with only that gun's spare magazines.

const GUN_SLOTS := [3, 5, 6]


func describe() -> Dictionary:
	return {
		"name": "Spawning with one random gun",
		"description": "Seeded draws reproduce and cover all three guns; a character given a loadout carries exactly that gun, holds it, and has its own spares.",
		"tags": ["item", "gun", "loadout", "random", "seed"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.actor(&"newcomer", &"puppet", Vector2(200, 250))


func run(t: TestContext) -> void:
	# Seeded draws: the same seed gives the same guns, and over many draws every gun comes up.
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 12345
	b.seed = 12345
	var seen := {}
	var same := true
	for i in 60:
		var slot := ItemRegistry.random_gun_slot(a)
		same = same and slot == ItemRegistry.random_gun_slot(b)
		seen[slot] = true
		t.check(slot in GUN_SLOTS, "draw %d is a gun's slot (got %d)" % [i, slot])
	t.check(same, "the same seed draws the same guns")
	t.expect_eq(seen.size(), GUN_SLOTS.size(), "every gun comes up in 60 draws (%s)" % [seen.keys()])

	# The loadout: bare hands, fists, the key and the one gun; its own spares.
	var body := t.actor(&"newcomer")
	for slot in GUN_SLOTS:
		body.set_loadout(ItemRegistry.loadout_for(slot), slot, ItemRegistry.spares_for(slot))
		var gun: StringName = GunConfig.gun_in_slot(slot)
		for plain in [1, 2, 4]:
			t.check(body.has_item(plain), "slot %d: carries slot %d" % [slot, plain])
		for other in GUN_SLOTS:
			t.expect_eq(body.has_item(other), other == slot, "slot %d: carries only its own gun (slot %d)" % [slot, other])
		t.expect_eq(body.current_slot(), slot, "slot %d: holds it" % slot)
		t.expect_eq(body.gun_slot(), slot, "slot %d: it is the gun it fights with" % slot)
		t.expect_eq(body.ammo(), MagazineConfig.capacity_of(StringName(GunConfig.row(gun)["magazine"])), "slot %d: it is loaded full" % slot)
		t.expect_eq(body.spare_magazines(), int(GunConfig.row(gun)["spare_magazines"]), "slot %d: carries its spares" % slot)
		t.check(body.best_magazine(gun) != null, "slot %d: they are for its gun" % slot)
		for other_gun: StringName in GunConfig.guns:
			if other_gun != gun:
				t.check(body.best_magazine(other_gun) == null, "slot %d: no spares for the %s" % [slot, other_gun])
