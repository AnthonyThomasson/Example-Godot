extends GameTest

## Against a wall a long gun is raised standing or crouched, but lying prone it swings off to the side instead: the
## rifle (and its hands) turn well off the aim, the barrel is not shortened, and it still cannot fire. A prone
## pistol is neither blocked nor swung: its hand is pushed back by the wall like a standing one. Backing off brings
## the rifle round to the aim again.

const SIDE_MIN := 1.0  # Radians the prone weapon must be off the aim (the config's is about 1.4).


func describe() -> Dictionary:
	return {
		"name": "A prone rifle swings aside at a wall; a crouched one is raised",
		"description": "At a wall: crouched rifle raised and silent; prone rifle swung to the side, not shortened, silent; prone pistol unblocked with its hand pushed back; backing off brings the rifle round again.",
		"tags": ["gun", "wall", "prone", "crouch", "stance", "rifle", "pistol"],
		"timeout": 16.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 600))
	s.set_static(CharacterConfig, &"posture_change_time", 0.0)
	s.switch(&"nav.rebake", false)
	s.switch(&"projectile.flyover", false)
	# The west wall's face is at x = 6.
	s.actor(&"crouch_rifle", &"puppet", Vector2(30, 100), { "start_slot": 6 })
	s.actor(&"prone_rifle", &"puppet", Vector2(30, 250), { "start_slot": 6 })
	s.actor(&"prone_pistol", &"puppet", Vector2(30, 400), { "start_slot": 3 })


func run(t: TestContext) -> void:
	t.puppet(&"crouch_rifle").set_posture(&"crouch")
	t.puppet(&"prone_rifle").set_posture(&"prone")
	t.puppet(&"prone_pistol").set_posture(&"prone")
	for id in [&"crouch_rifle", &"prone_rifle", &"prone_pistol"]:
		t.puppet(id).aim_at(t.actor(id).global_position + Vector2(-1000, 0))  # West, into the wall.
	await t.seconds(1.5)

	var crouched = t.actor(&"crouch_rifle")
	t.check(crouched.weapon_blocked() and crouched.weapon_raise() > 0.95, "crouched, the rifle is raised at the wall (%.2f)" % crouched.weapon_raise())
	t.check(absf(crouched.weapon_side_turn()) < 0.01, "and it is not swung aside")

	var prone = t.actor(&"prone_rifle")
	t.check(prone.weapon_blocked(), "prone, the rifle's barrel is against the wall")
	t.check(prone.weapon_raise() < 0.05, "and it is not raised up (%.2f)" % prone.weapon_raise())
	t.check(absf(prone.weapon_side_turn()) > SIDE_MIN, "it is swung to the side (%.2f rad)" % prone.weapon_side_turn())
	var off: float = absf(angle_difference(prone.pose.weapon_angle, prone.facing.angle()))
	t.check(off > SIDE_MIN * 0.8, "the drawn weapon follows, %.2f rad off the aim" % off)
	var rounds: int = prone.ammo()
	t.check(not prone.shoot(), "it cannot fire at the wall")
	t.expect_eq(prone.ammo(), rounds, "no round is spent")

	var pistol = t.actor(&"prone_pistol")
	t.check(not pistol.weapon_blocked() and absf(pistol.weapon_side_turn()) < 0.01, "a prone pistol is not blocked or swung")
	t.check(pistol.hand_position(1).x > -24.0, "its hand is held back by the wall, not through it (%.1f px)" % pistol.hand_position(1).x)

	t.puppet(&"prone_rifle").walk_to(Vector2(200, prone.global_position.y))
	t.check(await t.until(func(): return t.puppet(&"prone_rifle").has_arrived(), 8.0), "the prone rifle crawls away from the wall")
	await t.seconds(1.0)
	t.check(not prone.weapon_blocked() and absf(prone.weapon_side_turn()) < 0.05, "clear of the wall, the rifle comes round to the aim (%.2f rad)" % prone.weapon_side_turn())
