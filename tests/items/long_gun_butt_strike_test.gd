extends GameTest

## F with a rifle or SMG in hand strikes with the butt: the gun swings in both hands, outward from the body, to lie nearly
## across it with the butt leading, and the blow lands from the butt, as far out as a punch with the gun's reach ever did.
## A pistol still just jabs.

const PISTOL_SLOT := 3
const SMG_SLOT := 5
const RIFLE_SLOT := 6
const Rig = preload("res://scenes/character/body/character_rig.gd")

## How far an arm bone may stretch past its length (fraction) while the gun is swung round.
const ARM_STRETCH := 0.12


func describe() -> Dictionary:
	return {
		"name": "Long guns punch with the butt",
		"description": "A rifle and an SMG swing round in both hands so the butt leads and hit a chair with it; a pistol never turns.",
		"tags": ["punch", "melee", "rifle", "smg", "pistol", "gun"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 600))
	s.switch(&"nav.rebake", false)
	var slots := { &"rifle": RIFLE_SLOT, &"smg": SMG_SLOT, &"pistol": PISTOL_SLOT }
	var y := 100.0
	for id in slots:
		s.actor(id, &"puppet", Vector2(250, y), { "start_slot": slots[id] })
		s.object(StringName("chair_%s" % id), "chair", Vector2(292, y))
		y += 150.0
	s.actor(&"free", &"puppet", Vector2(250, 540), { "start_slot": RIFLE_SLOT })


func run(t: TestContext) -> void:
	await _check_two_handed_swing(t)
	for id in [&"rifle", &"smg", &"pistol"]:
		var puppet := t.puppet(id)
		var chair: Node2D = t.object(StringName("chair_%s" % id))
		puppet.aim_at(chair.global_position)
	await t.seconds(0.4)
	var peak := {}
	for id in [&"rifle", &"smg", &"pistol"]:
		t.puppet(id).punch()
		peak[id] = 0.0
	for i in 20:
		await t.frames(1)
		for id in peak:
			var you := t.actor(id)
			peak[id] = maxf(peak[id], you.current_item().strike_swing(you.punch_amount(0)))
	for id in [&"rifle", &"smg"]:
		var you := t.actor(id)
		t.check(you.current_item().strike_ahead() > 0.0, "%s: the butt sits behind the grip" % id)
		t.check(peak[id] > 0.95, "%s: the gun swings round for the butt strike (%.2f)" % [id, peak[id]])
		var chair: Node2D = t.object(StringName("chair_%s" % id))
		var struck := func(d): return d["actor"] == id and d["body"] == chair and d["hand"] >= 0
		t.check(t.happened(&"hit_landed", struck), "%s: the butt strike lands on the chair" % id)
	t.expect_eq(t.actor(&"pistol").current_item().strike_ahead(), 0.0, "a pistol has no butt to lead with")
	t.expect_eq(peak[&"pistol"], 0.0, "a pistol never turns in the hand")


## With nothing in the way, a rifle punch swings the gun in both hands, the other hand staying a fixed grip from the
## weapon hand, until it lies nearly across the body: almost horizontal, the butt centred on the aim and a little ahead
## of the muzzle. The arms never overstretch on the way.
func _check_two_handed_swing(t: TestContext) -> void:
	var puppet := t.puppet(&"free")
	var you := t.actor(&"free")
	puppet.aim_at(Vector2(500, 540))
	await t.seconds(0.4)
	var item: GunItem = you.current_item()
	var gap := absf(item.strike_support_gap())
	t.check(gap > 0.0, "a rifle's other hand grips along the barrel (%.0f px)" % gap)
	var worst := 0.0
	var stretch := 0.0
	var tilt := 2.0
	var butt_ahead := -1000.0
	var muzzle_ahead := 1000.0
	var butt_off := 1000.0
	puppet.punch()
	for i in 40:
		await t.frames(1)
		var amount: float = you.punch_amount(0)
		var apart: Vector2 = you.hand_position(1) - you.hand_position(0)
		if amount > 0.15:
			worst = maxf(worst, absf(apart.length() - gap))
		var rig = you.rig()
		for arm in 2:
			for bone in [[Rig.SHOULDER, Rig.ELBOW, CharacterConfig.body_upper_arm], [Rig.ELBOW, Rig.HAND, CharacterConfig.body_forearm]]:
				var want: float = bone[2] * you.radius
				stretch = maxf(stretch, rig.point(bone[0][arm]).distance_to(rig.point(bone[1][arm])) / want - 1.0)
		if item.strike_swing(amount) > 0.99:
			var barrel := item.strike_direction(you.facing, amount)
			var butt: Vector2 = item.strike_end(you.facing, amount)
			var muzzle: Vector2 = barrel * (item.art_size().y - item.grip_back())
			tilt = minf(tilt, absf(barrel.dot(you.facing)))
			butt_ahead = maxf(butt_ahead, butt.dot(you.facing))
			muzzle_ahead = minf(muzzle_ahead, muzzle.dot(you.facing))
			var centre: Vector2 = you.hand_position(0) + butt
			butt_off = minf(butt_off, absf(centre.dot(you.facing.orthogonal())))
	t.check(worst < 3.0, "the other hand stays a fixed grip from the weapon hand (off by %.1f px)" % worst)
	t.check(tilt < 0.4, "the gun ends nearly across the body, not turned round (%.2f along the aim)" % tilt)
	t.check(butt_ahead > muzzle_ahead, "the butt is a little ahead of the muzzle (%.1f vs %.1f px)" % [butt_ahead, muzzle_ahead])
	t.check(butt_off < 9.0, "the butt is centred on the aim line (%.1f px off)" % butt_off)
	t.check(stretch <= ARM_STRETCH, "neither arm overstretches through the swing (%.0f%%)" % (stretch * 100.0))
