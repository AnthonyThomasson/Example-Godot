extends GameTest

## Every gun has its own fire rate (`GunConfig` `fire_interval`). Holding the trigger fires an automatic gun
## (SMG, rifle) at its rate and does nothing for a semi-automatic one (the pistol), which fires once per click and
## is held to its rate however fast the clicks come.

## How long each phase pulls the trigger (s).
const WINDOW := 1.0

## The guns under test: id -> [actor id, inventory slot].
const GUNS := {
	&"pistol": [&"pistol_man", 3],
	&"smg": [&"smg_man", 5],
	&"rifle": [&"rifle_man", 6],
}


func describe() -> Dictionary:
	return {
		"name": "Each gun fires at its own rate",
		"description": "Holding the trigger fires the automatic guns at their configured rate and not the pistol; mashing clicks is held to the pistol's rate.",
		"tags": ["item", "gun", "fire rate", "automatic", "ammo"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 600))
	var y := 100.0
	for gun: StringName in GUNS:
		s.actor(GUNS[gun][0], &"puppet", Vector2(100, y), { "start_slot": GUNS[gun][1] })
		y += 150.0


func run(t: TestContext) -> void:
	for gun: StringName in GUNS:
		var body := t.actor(GUNS[gun][0])
		t.puppet(GUNS[gun][0]).aim_at(body.global_position + Vector2(600, 0))
	await t.seconds(0.5)  # Facing settles; nothing is in reach of a wall.
	for gun: StringName in GUNS:
		t.check(not t.actor(GUNS[gun][0]).weapon_blocked(), "%s is clear of any wall" % gun)

	# Phase 1: the trigger is held, with no clicks. Only an automatic gun keeps firing.
	var before := _rounds(t)
	for gun: StringName in GUNS:
		t.puppet(GUNS[gun][0]).hold_fire(true)
	await t.seconds(WINDOW)
	for gun: StringName in GUNS:
		t.puppet(GUNS[gun][0]).hold_fire(false)
	var held := _spent(t, before)
	t.expect_eq(held[&"pistol"], 0, "holding the trigger fires a semi-automatic pistol not at all")
	for gun: StringName in [&"smg", &"rifle"]:
		var want := WINDOW / float(GunConfig.row(gun)["fire_interval"])
		t.check(absf(held[gun] - want) <= 2.0,
			"held, the %s fires about %.1f rounds in %.1f s (fired %d)" % [gun, want, WINDOW, held[gun]])
		t.check(t.actor(GUNS[gun][0]).is_automatic(), "the %s reports itself automatic" % gun)
	t.check(not t.actor(GUNS[&"pistol"][0]).is_automatic(), "the pistol does not")
	t.check(held[&"smg"] > held[&"rifle"], "the SMG (%d) out-fires the rifle (%d)" % [held[&"smg"], held[&"rifle"]])

	# Phase 2: a click on every frame. The pistol is held to its fire interval; an automatic gun too.
	await t.seconds(0.2)
	before = _rounds(t)
	var frames := roundi(WINDOW * float(Engine.physics_ticks_per_second))
	for i in frames:
		for gun: StringName in GUNS:
			t.puppet(GUNS[gun][0]).shoot()
		await t.frames(1)
	var mashed := _spent(t, before)
	for gun: StringName in GUNS:
		var want := WINDOW / float(GunConfig.row(gun)["fire_interval"])
		t.check(absf(mashed[gun] - want) <= 2.0,
			"mashing the %s is held to about %.1f rounds in %.1f s (fired %d)" % [gun, want, WINDOW, mashed[gun]])


## Rounds loaded in each gun, by gun id.
func _rounds(t: TestContext) -> Dictionary:
	var out := {}
	for gun: StringName in GUNS:
		out[gun] = t.actor(GUNS[gun][0]).ammo(GUNS[gun][1])
	return out


## Rounds each gun has spent since `before`.
func _spent(t: TestContext, before: Dictionary) -> Dictionary:
	var now := _rounds(t)
	var out := {}
	for gun: StringName in GUNS:
		out[gun] = before[gun] - now[gun]
	return out
