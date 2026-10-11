extends GameTest

## Every gun comes with its own magazines: each gun is built loaded with the magazine its `GunConfig` row names,
## the capacities differ gun to gun, a magazine only fits its own kind of gun, and a reload takes that magazine
## type's own time.


func describe() -> Dictionary:
	return {
		"name": "Each gun has its own magazines",
		"description": "Pistol, SMG and rifle load different capacities; a pistol won't take a rifle magazine; a rifle reload takes the rifle magazine's longer time.",
		"tags": ["item", "gun", "ammo", "magazine", "reload"],
		"timeout": 14.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	# Half-spent guns, and only rifle magazines carried: the rifle can reload, the others have nothing that fits.
	s.actor(&"gunman", &"puppet", Vector2(200, 250), { "start_slot": 6, "start_rounds": 2,
		"spare_magazine_types": [&"rifle_standard"] })


func run(t: TestContext) -> void:
	# Built loaded, each with its row's magazine, and the capacities are told apart.
	var capacities := {}
	for gun: StringName in GunConfig.guns:
		var item: GunItem = ItemRegistry.create(int(GunConfig.row(gun)["slot"]))
		var type := StringName(GunConfig.row(gun)["magazine"])
		t.expect_eq(item.rounds_loaded(), MagazineConfig.capacity_of(type), "a new %s is built full" % gun)
		t.expect_eq(item.magazine.gun, gun, "the %s's default magazine fits the %s" % [gun, gun])
		capacities[gun] = item.ammo_capacity()
	t.check(capacities.values().size() == 3 and capacities[&"pistol"] != capacities[&"smg"]
			and capacities[&"smg"] != capacities[&"rifle"] and capacities[&"pistol"] != capacities[&"rifle"],
		"the three guns hold different numbers of rounds (%s)" % capacities)

	var body := t.actor(&"gunman")
	t.expect_eq(body.ammo(6), 2, "the rifle starts with the 2 rounds asked for")
	t.expect_eq(body.ammo_capacity(6), MagazineConfig.capacity_of(&"rifle_standard"), "its capacity is the rifle magazine's")
	t.check(body.best_magazine(&"rifle") != null, "a rifle magazine is carried")
	t.check(body.best_magazine(&"pistol") == null and body.best_magazine(&"smg") == null,
		"no magazine for the pistol or the SMG is carried")
	t.check(body.can_reload(6), "the rifle can reload from it")
	t.check(not body.can_reload(3) and not body.can_reload(5), "the pistol and the SMG have nothing to reload from")

	# A reload takes the rifle magazine's own time, not the pistol's.
	var rifle_time := MagazineConfig.reload_time_of(&"rifle_standard")
	t.check(rifle_time > MagazineConfig.reload_time, "a rifle reload (%.1f s) is slower than a pistol's (%.1f s)" % [rifle_time, MagazineConfig.reload_time])
	t.puppet(&"gunman").reload()
	await t.seconds(MagazineConfig.reload_time + 0.3)
	t.check(body.is_reloading(), "past the pistol's reload time, the rifle is still reloading")
	await t.seconds(rifle_time - MagazineConfig.reload_time + 0.2)
	t.check(not body.is_reloading(), "the rifle reload has finished")
	t.expect_eq(body.ammo(6), MagazineConfig.capacity_of(&"rifle_standard"), "the rifle is full again")
	t.expect_eq(body.spare_magazines(), 1, "the half-spent rifle magazine was kept as a spare")
	t.check(body.best_magazine(&"rifle") != null and body.best_magazine(&"rifle").rounds == 2, "it still holds its 2 rounds")
