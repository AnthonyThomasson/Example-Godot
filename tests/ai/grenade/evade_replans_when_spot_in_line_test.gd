extends GameTest

## G16, the replan: a frag that rolls on a few px after the NPC planned its way clear, by a doorway, can bring the planned spot into the
## burst's line. The plan is made again then, however short the roll (`AgentGrenades._still_safe`), and not only once the grenade has
## moved 48 px (`REPLAN_DIST`). A defender in the living room by the kitchen's doorway is in the line of a frag that comes to rest in the
## kitchen, and plans a spot out of it; the frag then rolls on, under 48 px, to a point from which that spot is in its line (the test works
## the point out from the world: the wall rays of the burst's line, its danger zone the blast radius plus the NPC's `evade_margin`). The
## NPC plans again, to a spot out of the new line, before the burst.
##
## Scripted Von (one mechanism: the evade reflex, outside Von). Premises: the thrower is an invader puppet in the kitchen that cannot be
## killed, armed here with a frag (the test world keeps the default inventory); the roll is the resting grenade moved to the new
## point with the `grenade` rest event it posts on coming to rest (the NPC, turned away from the grenade as it runs, hears where it stopped).

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const NPC_AT := Vector2(430, 180)
const THROWER_AT := Vector2(720, 150)
const AIM := Vector2(530, 160)
## A frag's danger zone for an NPC (G16): the blast radius plus the controller's `evade_margin` (120 px).
const ZONE := Probe.BLAST_RADIUS + 120.0
## The farthest the frag ends up from the point the plan was made for (px): under `AgentGrenades.REPLAN_DIST` (48), with a px to spare
## for the plan's point as `debug_state()` gives it (whole px), so the distance alone never makes a new plan.
const MAX_ROLL := 44.0
## The farthest the frag rolls on from where it rests (px): a few strides' worth, as the roll by the doorway that this rule is for.
const REST_ROLL := 60.0


func describe() -> Dictionary:
	return {
		"name": "An evade plan is made again when a short roll puts its spot in the line",
		"description": "A frag rolls on under 48 px after a defender planned its way clear by a doorway, bringing the spot into the burst's line: the defender plans a new spot out of the line before the burst.",
		"tags": ["ai", "grenade", "evade", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([{ "pick": "hold" }])
	s.actor(&"d", &"defender", NPC_AT, { "facing": Vector2.RIGHT, "max_health": 1000000.0 })
	s.actor(&"thrower", &"puppet", THROWER_AT, { "faction": &"invader", "max_health": 1000000.0, "aim_point": AIM })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 0, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1, "the thrower carries a frag grenade (Character.item_count(8))"):
		return
	await Probe.throw_at(t, &"thrower", Probe.FRAG, AIM)
	var brain := t.controller(&"d", &"debug_grenades")
	var escape := func() -> Vector2: return brain.debug_grenades()["escape"]
	var rested := func(): return not Probe.raw(t, &"grenade", func(g): return g.get("stage") == &"rest").is_empty()
	if not t.require(await t.until(func(): return rested.call() and escape.call() != Vector2.INF, 3.0), "the frag came to rest and the defender planned a spot (escape %s)" % str(escape.call())):
		return
	# The plan settles on the resting frag: a replan due from its last bounce comes within `REPLAN_EVERY` (0.15 s), then nothing moves it.
	await t.seconds(0.3)
	var spot: Vector2 = escape.call()
	await t.seconds(0.2)
	if not t.require(escape.call() == spot and spot != Vector2.INF, "set-up: the defender's spot settled before the roll (%s, then %s)" % [str(spot), str(escape.call())]):
		return
	var grenade: Node2D = Probe.live(t)[0]
	var planned: Array = t.controller(&"d", &"debug_state").debug_state().get("evade", {}).get("point", [])
	if not t.require(planned.size() == 2, "set-up: the defender is carrying out its evade plan (%s)" % str(t.controller(&"d", &"debug_state").debug_state().get("evade"))):
		return
	var at := Vector2(planned[0], planned[1])
	var rolled := _roll_into_line(t, at, spot)
	if not t.require(rolled != Vector2.INF and rolled.distance_to(grenade.global_position) <= REST_ROLL,
			"set-up: a point within %d px of the plan's %s, and a short roll from where the frag rests (%s), puts the spot %s in the frag's line (%s)" \
			% [MAX_ROLL, str(at), str(grenade.global_position), str(spot), str(rolled)]):
		return
	grenade.global_position = rolled
	EventBus.post(&"grenade", { "position": rolled, "kind": &"frag", "stage": &"rest" })
	var moved := func(): return escape.call() != spot
	t.check(await t.until(moved, 1.0), "the defender planned again after the roll (spot still %s, frag at %s, burst %s)" % [str(spot), str(rolled), str(Probe.booms(t, &"frag"))])
	t.check(Probe.booms(t, &"frag").is_empty(), "before the burst")
	var now: Vector2 = escape.call()
	t.check(now == Vector2.INF or not _in_line(t, rolled, now), "the new spot %s is out of the frag's line from %s" % [str(now), str(rolled)])


## A point within `MAX_ROLL` px of `at` (the point the plan was made for), on the kitchen's floor, from which `spot` is in the frag's line; `Vector2.INF` when there is none.
func _roll_into_line(t: TestContext, at: Vector2, spot: Vector2) -> Vector2:
	for r in range(2, int(MAX_ROLL) + 1, 2):
		for i in 32:
			var p := at + Vector2.RIGHT.rotated(TAU * i / 32.0) * float(r)
			if Maps.HOUSE_KITCHEN.grow(-12.0).has_point(p) and _in_line(t, p, spot):
				return p
	return Vector2.INF


## Whether a frag bursting at `from` reaches `to`: within the zone, and no wall between (the bare house has no furniture; characters
## stop nothing).
func _in_line(t: TestContext, from: Vector2, to: Vector2) -> bool:
	if from.distance_to(to) > ZONE:
		return false
	var query := PhysicsRayQueryParameters2D.create(from, to, PhysicsLayers.SOLID)
	query.exclude = [t.actor(&"d").get_rid(), t.actor(&"thrower").get_rid()]
	return t.actor(&"d").get_world_2d().direct_space_state.intersect_ray(query).is_empty()
