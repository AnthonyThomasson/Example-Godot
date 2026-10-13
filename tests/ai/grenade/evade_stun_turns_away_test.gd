extends GameTest

## G16, the last resort: an NPC that cannot get clear of a stun in the fuse it has left turns its back to it. A defender stands in the
## north-east corner of a room; a hostile invader throws a stun that lands beside it. The corner leaves no way out of the flash radius (400 px)
## in 1.5 s, so the defender faces away from the burst and is blinded for only the back-turned share (x0.25) of the time.
##
## Premise: the thrower is an invader *puppet* that cannot be killed (the scripted world event), armed here as Main arms a spawn. A premise
## check reads that the defender was still inside the flash radius when it went off.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const CORNER := Vector2(1150, 50)


func describe() -> Dictionary:
	return {
		"name": "A defender cornered by a stun turns its back to it",
		"description": "A stun lands 60 px from a defender in a corner: it cannot get 400 px clear in time, so at the bang it faces away and is blind for no more than the back-turned time (about 1.25 s of 5).",
		"tags": ["ai", "grenade", "evade", "stun", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1200, 500))
	s.actor(&"d", &"defender", CORNER, { "facing": Vector2.LEFT })
	s.actor(&"thrower", &"puppet", Vector2(800, 200), { "faction": &"invader", "max_health": 1000000.0, "aim_point": CORNER })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	var d := t.actor(&"d")
	Probe.arm(thrower, 1, 0)
	if not t.require(Probe.count(thrower, Probe.STUN) == 1, "the thrower carries a stun grenade (Character.item_count(7) = %d)" % Probe.count(thrower, Probe.STUN)):
		return
	await t.seconds(0.8)
	var puppet := t.puppet(&"thrower")
	puppet.select_slot(Probe.STUN)
	var aim: Vector2 = d.global_position + Vector2(-50, 35)
	puppet.aim_at(aim)
	await t.seconds(0.5)
	var clicked := t.time
	puppet.shoot()
	var facing_at_bang := Vector2.ZERO
	var pos_at_bang := Vector2.ZERO
	while t.time < clicked + 4.0 and Probe.booms(t, &"stun").is_empty():
		facing_at_bang = d.facing
		pos_at_bang = d.global_position
		await t.frames(1)
	if not t.require(not Probe.booms(t, &"stun").is_empty(), "the stun went off"):
		return
	var at: Vector2 = Probe.booms(t, &"stun")[0]["data"]["position"]
	await t.frames(2)
	if not t.require(pos_at_bang.distance_to(at) < Probe.FLASH_RADIUS, "set-up: the defender was still inside the flash radius when it went off (%.0f px)" % pos_at_bang.distance_to(at)):
		return
	var to_burst := (at - pos_at_bang).normalized()
	t.check(facing_at_bang.dot(to_burst) <= -0.5, "it had its back to the burst (facing dot direction to it: %.2f)" % facing_at_bang.dot(to_burst))
	var flash := Probe.stuns(t, d)
	if t.require(not flash.is_empty(), "the defender was stunned"):
		var blind := float(flash[0]["data"].get("blind", 99.0))
		var back_turned := Probe.MAX_BLIND * Probe.flash_scale(pos_at_bang.distance_to(at)) * 0.25
		t.check(blind <= back_turned + 0.35, "so it was blind for only %.2f s (a back turned gives about %.2f of the 5 s)" % [blind, back_turned])
