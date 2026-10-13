extends GameTest

## G3: a grenade strikes a wall (it is not lobbed over one) and bounces off with energy loss, so thrown at a point
## on the far side of a wall it ends up on the thrower's side. Every bounce posts a `&"grenade"` clatter.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const WALL_X := 400.0
const FROM := Vector2(250, 250)
const AIM := Vector2(600, 250)  ## in the next room, 350 px away: in range


func describe() -> Dictionary:
	return {
		"name": "A grenade bounces off a wall",
		"description": "Thrown at a point in the next room with no doorway between, a stun grenade hits the wall, posts a bounce and ends up on the thrower's side.",
		"tags": ["grenade", "bounce", "wall", "item"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	# Two rooms with a solid wall between them (no door), one outer door far from the throw.
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 500) },
		{ "key": "east", "type": "kitchen", "rect": Rect2(400, 0, 400, 500) },
	], [{ "pos": Vector2(600, 500), "width": 80.0 }])
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 1, 0)
	if not t.require(Probe.count(thrower, Probe.STUN) == 1, "the thrower carries a stun grenade (Character.item_count(7) = %d)" % Probe.count(thrower, Probe.STUN)):
		return
	await Probe.throw_at(t, &"thrower", Probe.STUN, AIM)
	if not t.require(await t.until(func(): return t.happened(&"grenade", func(d): return d.get("stage") == &"bounce"), 3.0), "the grenade bounces (a grenade event, stage bounce)"):
		return
	var bounce: Vector2 = Probe.raw(t, &"grenade", func(d): return d.get("stage") == &"bounce")[0]["data"]["position"]
	t.check(bounce.x > WALL_X - 60.0 and bounce.x < WALL_X, "the first bounce is at the wall, on the thrower's side (x %.0f)" % bounce.x)
	if not t.require(await Probe.wait_boom(t, &"stun", 4.0), "the grenade goes off"):
		return
	var at: Vector2 = Probe.booms(t, &"stun")[0]["data"]["position"]
	t.check(at.x < WALL_X, "it ends on the thrower's side of the wall (x %.0f)" % at.x)
	t.check(at.x > FROM.x + 40.0, "having flown toward the wall first (x %.0f)" % at.x)
