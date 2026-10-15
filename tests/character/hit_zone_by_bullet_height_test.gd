extends GameTest

## O2, O3 (docs/outfits.md): where a bullet strikes a body is its height over the body's coverage: feet up to 0.08, legs up
## to 0.45, torso up to 0.85, the head above, the same fractions standing (coverage 60) and crouched (35). A head shot deals
## twice a torso shot, a leg or foot shot 0.6 of it. Nobody here wears anything (O1: no outfit set), so the zones alone
## decide. One pistol round per body, square on down its own lane at a pinned height; height 25 is the legs of a standing
## body and the torso of a crouched one.

const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
const FROM_X := 150.0
const TARGET_X := 560.0
const LANE_GAP := 70.0
const ZONES: Array[StringName] = [&"feet", &"legs", &"torso", &"head"]
## The pistol's damage at full speed, head-on, to the torso (the bullet's base 10 plus the gun's 15): the full torso damage.
const TORSO_PISTOL := 25.0


func describe() -> Dictionary:
	return {
		"name": "A bullet's height picks the zone it strikes",
		"description": "Pistol rounds at pinned heights into standing and crouched bodies: the head takes twice a torso hit, the legs and feet 0.6 of it, by height over the posture's coverage.",
		"tags": ["outfit", "zone", "damage", "projectile", "posture"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 700))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	OutfitProbe.pin_height(s)
	var i := 0
	for posture: StringName in [&"stand", &"crouch"]:
		for zone: StringName in ZONES:
			s.actor(_id(posture, zone), &"puppet", Vector2(TARGET_X, _lane(i)),
				{ "max_health": 1000.0, "facing": Vector2.LEFT, "aim_point": Vector2(0, _lane(i)) })
			i += 1


func run(t: TestContext) -> void:
	var i := 0
	for posture: StringName in [&"stand", &"crouch"]:
		for zone: StringName in ZONES:
			var body := t.actor(_id(posture, zone))
			t.puppet(_id(posture, zone)).aim_at(Vector2(0, _lane(i)))
			if posture == &"crouch":
				t.check(body.set_posture(&"crouch"), "%s takes a crouch" % body.name)
			i += 1
	await t.seconds(0.5)

	i = 0
	for posture: StringName in [&"stand", &"crouch"]:
		var heights: Dictionary = OutfitProbe.STAND if posture == &"stand" else OutfitProbe.CROUCH
		for zone: StringName in ZONES:
			OutfitProbe.fire(t, Vector2(FROM_X, _lane(i)), Vector2.RIGHT, &"pistol", heights[zone])
			i += 1
	var all_hit := func() -> bool:
		for posture: StringName in [&"stand", &"crouch"]:
			for zone: StringName in ZONES:
				if OutfitProbe.hits_on(t, t.actor(_id(posture, zone))).is_empty():
					return false
		return true
	if not t.require(await t.until(all_hit, 2.0), "every round strikes its body"):
		return
	await t.frames(2)

	for posture: StringName in [&"stand", &"crouch"]:
		var heights: Dictionary = OutfitProbe.STAND if posture == &"stand" else OutfitProbe.CROUCH
		var torso := _lost(t, posture, &"torso")
		t.expect_near(torso, TORSO_PISTOL, 2.0, "a %s body hit in the torso loses a pistol round's full torso damage, %.0f (lost %.1f)" % [posture, TORSO_PISTOL, torso])
		if torso <= 0.0:
			continue
		for zone: StringName in ZONES:
			var ratio := _lost(t, posture, zone) / torso
			t.expect_near(ratio, OutfitProbe.ZONE_DAMAGE[zone], 0.06,
				"a %s body hit at height %.0f (the %s) takes %.1fx a torso hit (took %.2fx)" % [posture, heights[zone], zone, OutfitProbe.ZONE_DAMAGE[zone], ratio])
	t.check(_lost(t, &"stand", &"legs") < _lost(t, &"crouch", &"torso") * 0.75,
		"the same height of 25 is the legs standing (%.1f lost) but the torso crouched (%.1f lost)" % [_lost(t, &"stand", &"legs"), _lost(t, &"crouch", &"torso")])


## The id of the body that stands in `posture` and is shot in `zone`.
func _id(posture: StringName, zone: StringName) -> StringName:
	return StringName("%s_%s" % [posture, zone])


## The y of shooting lane `i`.
func _lane(i: int) -> float:
	return 70.0 + LANE_GAP * i


## The health the body standing in `posture` and shot in `zone` has lost.
func _lost(t: TestContext, posture: StringName, zone: StringName) -> float:
	var body := t.actor(_id(posture, zone))
	return body.max_health - body.health
