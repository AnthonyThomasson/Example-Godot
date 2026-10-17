extends GameTest

## S4, S5 (ticket #56, `docs/grenades.md` G13): firing one-handed. While its free hand covers its eyes (a blinded character, S1)
## the weapon hand holds any gun alone (`Character.one_handed()` true), in the `one_hand` stance: the arm out, the gun lower than a
## two-handed grip and wavering; a long gun kicks harder. A round fired one-handed leaves within the gun's `spread_deg` plus its
## `GunConfig` row's `one_hand_spread_deg` (pistol 3, SMG 6, rifle 8 degrees to start), so wider than two-handed and within that bound.
## A bang that only deafens leaves both hands on the gun. The stun's aim sway is set to 0 here so the spread alone is measured
## (the sway is G13's, `character/stunned_slow_and_sway`).

const Rig = preload("res://scenes/character/body/character_rig.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")

const GUNS := { &"pistol": 3, &"smg": 5, &"rifle": 6 }
const SHOTS := 10
const AIM := Vector2(3000, 0)
## A bound's slack (degrees): a round is aimed from the muzzle at a point 300 px out on the aim line (the zeroing), so a muzzle
## that wavers a few px turns the round a fraction of a degree.
const SLACK := 1.0
## The weapon hand held one-handed is this much lower than in its two-handed grip (body radii), and still out ahead of the body (px).
const LOWER := 0.4
const OUT := 18.0
## Held still, how far a steady two-handed weapon hand moves (px), and how much more a one-handed one wavers.
const STEADY := 0.6
const WAVER := 1.5


func describe() -> Dictionary:
	return {
		"name": "A blinded character fires one-handed, low and wide",
		"description": "Blind, the weapon hand holds the gun alone (one_handed()), out, low and wavering; a rifle kicks harder; rounds leave within spread_deg + one_hand_spread_deg, wider than two-handed; deaf-only keeps both hands on the gun.",
		"tags": ["grenade", "stun", "blind", "gun", "spread", "pistol", "smg", "rifle", "item"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 3200, 900))
	s.switch(&"nav.rebake", false)
	s.switch(&"audio.sound", false)
	s.set_static(CharacterConfig, &"stun_sway", 0.0)
	var y := 120.0
	for gun: StringName in GUNS:
		s.actor(gun, &"puppet", Vector2(150, y), { "start_slot": GUNS[gun], "max_health": 100000.0 })
		y += 200.0
	s.actor(&"deaf", &"puppet", Vector2(150, y), { "start_slot": 3, "max_health": 100000.0 })


## `c.one_handed()`, or null when the character has no such read.
func _one_handed(c: Node) -> Variant:
	if c.has_method("one_handed"):
		return bool(c.call("one_handed"))
	return null


## The weapon hand's place in `c`'s skeleton: how far ahead of the body centre along the facing (px) and how high (body radii).
func _hold(c: Node) -> Dictionary:
	var item: Item = c.current_item()
	var hand: Vector3 = c.rig().point(Rig.HAND[item.weapon_hand()])
	return { "ahead": Vector2(hand.x, hand.y).dot(c.facing), "height": hand.z / c.radius, "at": hand }


## How far (px) `c`'s weapon hand wanders over `frames` frames held still: the largest distance from where it started.
func _wander(t: TestContext, c: Node, frames: int) -> float:
	var from: Vector3 = _hold(c)["at"]
	var most := 0.0
	for i in frames:
		await t.frames(1)
		most = maxf(most, (_hold(c)["at"] as Vector3).distance_to(from))
	return most


## Fire `SHOTS` rounds from `id`, one click every 0.2 s: `{ half, sd, rounds, kick }`. `half` is half the cone the rounds left in
## (degrees: half the angle between the two outermost), `sd` the spread of their directions about their mean (degrees), `rounds`
## how many left, and `kick` how far (px) the weapon hand was thrown back by the first. Measured about the rounds' own mean
## direction, since a gun is zeroed from its muzzle, which sits off the aim line (9 px for the SMG).
func _volley(t: TestContext, id: StringName) -> Dictionary:
	var c := t.actor(id)
	var seen := {}
	var angles: Array = []
	var kick := 0.0
	for k in SHOTS:
		var before: float = _hold(c)["ahead"]
		var line: Vector2 = AIM.normalized()
		t.puppet(id).shoot()
		for f in 12:
			await t.frames(1)
			if k == 0:
				kick = maxf(kick, before - float(_hold(c)["ahead"]))
			for n in t.world.get_children():
				if String(n.name).begins_with("Projectile") and n.get("ignore") == c and not seen.has(n.get_instance_id()):
					seen[n.get_instance_id()] = true
					angles.append(rad_to_deg(line.angle_to(n.get("direction"))))
	var lo := INF
	var hi := -INF
	var mean := 0.0
	for a: float in angles:
		lo = minf(lo, a)
		hi = maxf(hi, a)
		mean += a
	mean /= maxf(angles.size(), 1)
	var sd := 0.0
	for a: float in angles:
		sd += (a - mean) * (a - mean)
	sd = sqrt(sd / maxf(angles.size(), 1))
	return { "half": (hi - lo) * 0.5 if not angles.is_empty() else 0.0, "sd": sd, "rounds": angles.size(), "kick": kick }


func run(t: TestContext) -> void:
	for id: StringName in GUNS.keys() + [&"deaf"]:
		t.puppet(id).aim_at(t.actor(id).global_position + AIM)
	await t.seconds(1.0)

	# --- Two-handed: the baseline.
	var two := {}
	var held := {}
	for gun: StringName in GUNS:
		var c := t.actor(gun)
		t.check(_one_handed(c) == false, "%s: unstunned, one_handed() is false (%s)" % [gun, str(_one_handed(c))])
		held[gun] = _hold(c)
		held[gun]["wander"] = await _wander(t, c, 30)
		two[gun] = await _volley(t, gun)
		t.check(two[gun]["rounds"] == SHOTS, "%s: two-handed, every click fired (%d)" % [gun, two[gun]["rounds"]])
		t.puppet(gun).reload()
	await t.seconds(3.0)

	# --- Blind: one hand over the eyes, the gun in the other. Deaf only: both on the gun.
	for gun: StringName in GUNS:
		if not t.require(Probe.stun(t.actor(gun), 8.0, 8.0), "Character.take_stun(blind, deaf) exists"):
			return
	Probe.stun(t.actor(&"deaf"), 0.0, 6.0)
	await t.seconds(0.8)
	t.check(_one_handed(t.actor(&"deaf")) == false, "deaf only, the gun stays in both hands (one_handed() %s)" % str(_one_handed(t.actor(&"deaf"))))
	for gun: StringName in GUNS:
		var c := t.actor(gun)
		var row: Dictionary = GunConfig.guns[gun]
		var extra := float(row.get("one_hand_spread_deg", -1.0))
		var spread := float(row.get("spread_deg", 0.0))
		t.check(_one_handed(c) == true, "%s: blinded, the gun is held in one hand (one_handed() %s)" % [gun, str(_one_handed(c))])
		t.check(extra > 0.0, "%s: GunConfig has its one_hand_spread_deg (%s)" % [gun, str(row.get("one_hand_spread_deg"))])
		var now := _hold(c)
		t.check(float(now["height"]) <= float(held[gun]["height"]) - LOWER, "%s: the gun is held low (the weapon hand %.1f body radii up, two-handed %.1f)" % [gun, now["height"], held[gun]["height"]])
		t.check(float(now["ahead"]) >= OUT, "%s: the arm is out ahead (%.0f px)" % [gun, now["ahead"]])
		var wander := await _wander(t, c, 30)
		t.check(float(held[gun]["wander"]) <= STEADY, "%s: (two-handed, the hand held steady: %.1f px)" % [gun, held[gun]["wander"]])
		t.check(wander >= WAVER, "%s: one-handed, the gun wavers (%.1f px in half a second, %.1f two-handed)" % [gun, wander, held[gun]["wander"]])
		var one := await _volley(t, gun)
		t.check(one["rounds"] == SHOTS, "%s: one-handed, every click fired (%d)" % [gun, one["rounds"]])
		t.check(one["half"] <= spread + maxf(extra, 0.0) + SLACK, "%s: the rounds left within spread_deg + one_hand_spread_deg (a cone %.1f degrees either way, bound %.1f)" % [gun, one["half"], spread + maxf(extra, 0.0)])
		t.check(extra > 0.0 and one["half"] >= two[gun]["half"] + extra * 0.25 and one["sd"] > two[gun]["sd"], "%s: one-handed the rounds spread wider (a cone %.2f degrees either way, sd %.2f; two-handed %.2f, %.2f)" % [gun, one["half"], one["sd"], two[gun]["half"], two[gun]["sd"]])
		if gun == &"rifle":
			t.check(one["kick"] >= two[gun]["kick"] * 1.25 and one["kick"] > 0.5, "the rifle kicks harder one-handed (the hand thrown back %.1f px, two-handed %.1f)" % [one["kick"], two[gun]["kick"]])
