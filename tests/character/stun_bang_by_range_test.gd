extends GameTest

## G12: the bang works by range. Every character within `bang_radius` (350 px) is deafened and disoriented for up to
## `max_deaf` (6 s), scaled by distance (linearly: 6 s at the burst, nothing at 350 px); through a wall the effect is x0.4.
## Within `point_blank` (30 px) it also takes `point_blank_damage` (5). Nobody else is hurt by a stun.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const FROM := Vector2(60, 350)
const AIM := Vector2(450, 350)
const WALL_X := 600.0
const SLACK := 0.35
const VICTIMS := {
	&"d100": Vector2(0, -100), &"d200": Vector2(0, 200), &"d300": Vector2(-300, 0),
	&"d424": Vector2(-300, -300), &"point_blank": Vector2(10, 0),
}


func describe() -> Dictionary:
	return {
		"name": "A stun bang deafens by range and through walls",
		"description": "A stun grenade lies still; victims 100, 200, 300 and 424 px away are deafened for the linear fall-off (the last not at all), one behind a wall for 0.4 of that, one at 10 px also loses 5 HP.",
		"tags": ["grenade", "stun", "bang", "deaf", "character"],
		"timeout": 14.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, WALL_X, 700) },
		{ "key": "east", "type": "kitchen", "rect": Rect2(WALL_X, 0, 500, 700) },
	], [{ "pos": Vector2(900, 700), "width": 80.0 }])
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100000.0 })
	var i := 0
	for id in VICTIMS:
		s.actor(id, &"puppet", Vector2(40.0 + 40.0 * i, 660), { "max_health": 100.0 })
		i += 1
	s.actor(&"walled", &"puppet", Vector2(660, 350), { "max_health": 100.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 1, 0)
	if not t.require(Probe.count(thrower, Probe.STUN) == 1, "the thrower carries a stun grenade (Character.item_count(7) = %d)" % Probe.count(thrower, Probe.STUN)):
		return
	await Probe.throw_at(t, &"thrower", Probe.STUN, AIM)
	if not t.require(await Probe.wait_rest(t, 1.4), "the grenade comes to rest before it goes off"):
		return
	var burst := Probe.rest_point(t)
	for id in VICTIMS:
		Probe.place(t, id, burst + VICTIMS[id], burst)
	if not t.require(await Probe.wait_boom(t, &"stun", 1.2), "the stun grenade goes off"):
		return
	var at: Vector2 = Probe.booms(t, &"stun")[0]["data"]["position"]
	await t.frames(2)
	for id in VICTIMS:
		var c := t.actor(id)
		var d: float = c.global_position.distance_to(at)
		var events := Probe.stuns(t, c)
		var got := float(events[0]["data"].get("deaf", 0.0)) if not events.is_empty() else 0.0
		var want := Probe.expected_deaf(d)
		t.check(absf(got - want) <= SLACK, "%s (%.0f px): deaf for %.2f s, the fall-off gives %.2f" % [id, d, got, want])
		t.check(Probe.deaf(c) == (want > 0.0), "%s is_deaf() is %s" % [id, want > 0.0])
		if id != &"point_blank":
			t.expect_near(c.health, 100.0, 0.01, "%s takes no damage from a stun" % id)
	var pb := t.actor(&"point_blank")
	t.expect_near(100.0 - pb.health, 5.0, 0.01, "a character within 30 px also takes the 5 point-blank damage")

	var walled := t.actor(&"walled")
	var dw: float = walled.global_position.distance_to(at)
	var walled_events := Probe.stuns(t, walled)
	var through := float(walled_events[0]["data"].get("deaf", 0.0)) if not walled_events.is_empty() else 0.0
	t.check(dw < Probe.BANG_RADIUS and through > 0.0, "the bang reaches through the wall (%.0f px away, deaf %.2f s)" % [dw, through])
	t.check(absf(through - Probe.expected_deaf(dw, Probe.WALL_FACTOR)) <= SLACK, "at 0.4 of the open-air time (%.2f s, expected %.2f)" % [through, Probe.expected_deaf(dw, Probe.WALL_FACTOR)])

	# The deafness ends on schedule.
	await t.seconds(1.0)
	t.check(not Probe.deaf(t.actor(&"d300")), "the character 300 px away hears again within a second")
	t.check(Probe.deaf(t.actor(&"d100")), "the one 100 px away is still deaf")
