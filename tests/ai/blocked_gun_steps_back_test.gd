extends GameTest

## The AI is not written per weapon: when its gun cannot fire because the barrel is against something, it steps
## back instead. A defender with an assault rifle has a chair against its barrel (the chair's edge is between the
## aim line and the barrel's line, so the line of fire to the intruder is clear and only the rifle touches it).
## Pinned in place (speed 0) it holds fire and keeps trying to back away; free to move it steps back, the barrel
## clears and it shoots the intruder.

## The rifle in `GunConfig`: the slot the defender is given.
const RIFLE_SLOT := 6


func describe() -> Dictionary:
	return {
		"name": "An AI with a blocked rifle steps back",
		"description": "A chair against a defender's rifle barrel (clear line of fire): it holds fire and drives away from the chair, and once it can move it backs off, the barrel clears and it shoots the intruder.",
		"tags": ["ai", "gun", "rifle", "wall", "back off", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"projectile.flyover", false)
	s.set_static(GunConfig, "guns", _straight_guns())
	# Pinned to its spot (speed 0) to begin with, aimed east at the intruder along y = 250.
	s.actor(&"defender", &"defender", Vector2(300, 250), { "start_slot": RIFLE_SLOT, "speed": 0.0, "max_health": 400.0 })
	# A chair whose south edge (y = 246) is just north of the defender's aim line (y = 250) and across its barrel's
	# line (y = 244): clear to shoot past, but the barrel is against it.
	s.object(&"chair", "chair", Vector2(336, 232))
	s.actor(&"intruder", &"puppet", Vector2(750, 250), { "start_slot": 1, "faction": &"invader", "max_health": 400.0 })


func run(t: TestContext) -> void:
	var defender := t.actor(&"defender")
	var intruder := t.actor(&"intruder")
	var rounds: int = defender.ammo(RIFLE_SLOT)

	# The defender fights: it aims at the intruder and finds its barrel against the chair.
	if not t.require(await t.until(func(): return defender.weapon_blocked(), 10.0), "the rifle's barrel is against the chair"):
		return
	t.check(defender.weapon_raise() > 0.0, "the rifle is raised off the chair")

	# It cannot shoot, and its reaction is to drive away from where the barrel points.
	var backed_off := false
	var window := 3.0
	var elapsed := 0.0
	while elapsed < window:
		await t.frames(1)
		elapsed += 1.0 / float(Engine.physics_ticks_per_second)
		if defender.move_input.dot(defender.facing) < -0.5:
			backed_off = true
	t.check(backed_off, "while blocked, it steps back (drives away from its aim)")
	t.expect_eq(defender.ammo(RIFLE_SLOT), rounds, "and it fires no round meanwhile")
	t.check(intruder.health == intruder.max_health, "the intruder is untouched")

	# Free to move: it backs off, the barrel clears, and it shoots the intruder.
	defender.speed = 150.0
	t.check(await t.until(func(): return intruder.health < intruder.max_health, 14.0),
		"once it can move it clears the chair and wounds the intruder (%.0f / %.0f)" % [intruder.health, intruder.max_health])
	t.check(defender.ammo(RIFLE_SLOT) < rounds, "the rifle fired")


## Every gun dead straight, so a shot's path is the aim's alone.
func _straight_guns() -> Dictionary:
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	return straight
