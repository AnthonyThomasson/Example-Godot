extends GameTest

## G11 (and G10's 1.5 s fuse): the flash works by sight. A character with a clear line of sight to the burst within
## `flash_radius` (400 px) is flash-blinded for up to `max_blind` (5 s), scaled by distance (full inside 100 px, linearly
## less out to 400) and by how much it faces the burst (facing it x1, side-on x0.6, back to it x0.25, linear between
## those). No line of sight, no flash. The victims are stood round the grenade once it lies still, so the distance and
## the facing are known exactly.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const FROM := Vector2(60, 350)
const AIM := Vector2(450, 350)
const WALL_X := 600.0
## Seconds of slack on a blind time.
const SLACK := 0.35


func describe() -> Dictionary:
	return {
		"name": "A stun flash blinds by sight, distance and facing",
		"description": "A stun grenade lies still; victims facing it, side-on and back to it at 200 px, one at 85 px and one behind a wall are blinded for the times the formula gives, the wall one not at all. The fuse is 1.5 s.",
		"tags": ["grenade", "stun", "flash", "blind", "character"],
		"timeout": 14.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, WALL_X, 700) },
		{ "key": "east", "type": "kitchen", "rect": Rect2(WALL_X, 0, 500, 700) },
	], [{ "pos": Vector2(900, 700), "width": 80.0 }])
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100000.0 })
	# Stood in place once the grenade has landed; parked in the corner until then.
	for i in 4:
		s.actor([&"facing", &"side", &"back", &"near"][i], &"puppet", Vector2(40.0 + 40.0 * i, 640), { "max_health": 100000.0 })
	s.actor(&"walled", &"puppet", Vector2(800, 350), { "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 1, 0)
	if not t.require(Probe.count(thrower, Probe.STUN) == 1, "the thrower carries a stun grenade (Character.item_count(7) = %d)" % Probe.count(thrower, Probe.STUN)):
		return
	var clicked: float = await Probe.throw_at(t, &"thrower", Probe.STUN, AIM)
	if not t.require(await Probe.wait_rest(t, 1.4), "the grenade comes to rest before it goes off"):
		return
	var burst := Probe.rest_point(t)
	Probe.place(t, &"facing", burst + Vector2(0, -200), burst)
	Probe.place(t, &"side", burst + Vector2(0, 200), burst + Vector2(0, 200) + Vector2(100, 0))
	Probe.place(t, &"back", burst + Vector2(-200, 0), burst + Vector2(-300, 0))
	Probe.place(t, &"near", burst + Vector2(60, 60), burst)
	if not t.require(await Probe.wait_boom(t, &"stun", 1.2), "the stun grenade goes off"):
		return
	var boom: Dictionary = Probe.booms(t, &"stun")[0]
	t.check(absf(float(boom["time"]) - clicked - Probe.WINDUP - Probe.FUSE_STUN) < 0.25, "it goes off 1.5 s after release (%.2f s after the click)" % (float(boom["time"]) - clicked))
	var at: Vector2 = boom["data"]["position"]
	await t.frames(2)
	var lines := []
	for who in [&"facing", &"side", &"back", &"near"]:
		var c := t.actor(who)
		var events := Probe.stuns(t, c)
		if not t.check(not events.is_empty(), "the %s victim is stunned (a stun event)" % who):
			continue
		var got := float(events[0]["data"].get("blind", -1.0))
		var want := Probe.expected_blind(c.global_position, c.facing, at)
		lines.append("%s %.2f" % [who, got])
		t.check(absf(got - want) <= SLACK, "%s: blinded %.2f s, the formula gives %.2f (%.0f px from the burst)" % [who, got, want, c.global_position.distance_to(at)])
		t.check(Probe.blind(c), "%s is_blind() once the flash has gone" % who)
	var near_events := Probe.stuns(t, t.actor(&"near"))
	if not near_events.is_empty():
		t.check(float(near_events[0]["data"].get("blind", 0.0)) >= Probe.MAX_BLIND - 0.1, "inside 100 px, facing it, the blindness is the full 5 s")
	var blind_by := func(who: StringName) -> float:
		var e := Probe.stuns(t, t.actor(who))
		return float(e[0]["data"].get("blind", 0.0)) if not e.is_empty() else -1.0
	t.check(blind_by.call(&"facing") > blind_by.call(&"side") and blind_by.call(&"side") > blind_by.call(&"back") and blind_by.call(&"back") > 0.0,
		"facing the burst blinds longer than side-on, which blinds longer than a back turned to it (%s)" % ", ".join(lines))
	var walled := t.actor(&"walled")
	t.check(walled.global_position.distance_to(at) < Probe.FLASH_RADIUS, "the walled victim is inside the flash radius (%.0f px)" % walled.global_position.distance_to(at))
	t.check(not Probe.blind(walled), "but with a wall between it and the burst there is no flash: it is not blind")
	var walled_events := Probe.stuns(t, walled)
	t.check(walled_events.is_empty() or float(walled_events[0]["data"].get("blind", 0.0)) == 0.0, "and no blind time is recorded for it")

	# The blindness ends: a back turned lasts well under a second.
	await t.seconds(1.3)
	t.check(not Probe.blind(t.actor(&"back")), "the victim with its back turned can see again after its short blindness")
	t.check(Probe.blind(t.actor(&"facing")), "while the one that faced the burst is still blind")
