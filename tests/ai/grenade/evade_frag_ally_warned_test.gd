extends GameTest

## G16, the radio: an ally that can neither see nor hear the grenade but is in its zone moves on a teammate's `grenade` callout.
## Two defenders in the hall of the terrace house; a hostile invader at the west end throws a frag that lands beside the first. The
## second sits on a chair at the hall's east end, about 340 px from the landing, in its line of sight and inside the frag zone (blast
## radius 250 + the 120 px evade margin), but outside `hear_grenade` (300 px) and with its back to the landing. It can only learn of the
## grenade from the call, and the reflex has to break off its interaction.
##
## Premises: the thrower is an invader *puppet* that cannot be killed (the scripted world event), armed here as Main arms a spawn; and
## the second defender is busy in an interaction (seated, started through `interact_with` at the start of `run`), which is what keeps a
## defender in place in a live house, where an idle one otherwise sets off to search a room within a third of a second. A premise check
## reads where B sat when A radioed and where the grenade really came to rest, so a different set-up is a finding.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const LANDING := Vector2(450, 415)
const A_AT := Vector2(560, 415)
const B_AT := Vector2(745, 415)  ## beside its chair, near the hall's east end
const CHAIR_AT := Vector2(780, 415)


func describe() -> Dictionary:
	return {
		"name": "A defender that cannot see the grenade runs on its ally's call",
		"description": "A frag lands by defender A; defender B, seated about 340 px away with its back turned, learns of it only from A's callout, leaves its chair and gets out of the grenade's line or radius before it goes off.",
		"tags": ["ai", "grenade", "evade", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"a", &"defender", A_AT, { "facing": Vector2.LEFT })
	s.object(&"chair", "chair", CHAIR_AT)
	s.actor(&"b", &"defender", B_AT, { "facing": Vector2.RIGHT })
	s.actor(&"thrower", &"puppet", Vector2(100, 415), { "faction": &"invader", "max_health": 1000000.0, "aim_point": Vector2(900, 415) })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	var b := t.actor(&"b")
	Probe.arm(thrower, 0, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1, "the thrower carries a frag grenade (Character.item_count(8) = %d)" % Probe.count(thrower, Probe.FRAG)):
		return
	var bb := t.controller(&"b", &"current_act")
	b.interact_with(t.object(&"chair"), "sit")
	if not t.require(await t.until(b.is_busy, 1.0), "set-up: B sits on the chair (is_busy)"):
		return
	await t.seconds(0.8)
	var puppet := t.puppet(&"thrower")
	puppet.select_slot(Probe.FRAG)
	puppet.aim_at(LANDING)
	await t.seconds(0.5)
	var clicked := t.time
	puppet.shoot()
	var sources := {}
	var escape_at := INF
	var b_path: Array = []
	while t.time < clicked + 6.0 and Probe.booms(t, &"frag").is_empty():
		b_path.append({ "t": t.time, "p": b.global_position, "busy": b.is_busy() })
		var g := Probe.grenades(bb)
		for k in g.get("known", []):
			sources[k.get("source")] = true
		if escape_at == INF and (g.get("escape", Vector2.INF) as Vector2) != Vector2.INF:
			escape_at = t.time
		await t.frames(1)
	if not t.require(not Probe.booms(t, &"frag").is_empty(), "the frag went off"):
		return
	var boom: Dictionary = Probe.booms(t, &"frag")[0]
	var at: Vector2 = boom["data"]["position"]
	var called := Probe.callouts(t, &"grenade", &"a")
	if not t.require(not called.is_empty(), "defender A radioed a grenade callout"):
		return
	var call_at: float = called[0]["time"]

	# The premise: where B sat when A radioed, it was in the grenade's line and its zone, and could not have heard it land.
	var seat: Vector2 = b.global_position
	for sample in b_path:
		if float(sample["t"]) <= call_at:
			seat = sample["p"]
	var gap := seat.distance_to(at)
	t.require(gap > Probe.HEAR_GRENADE and gap < Probe.FRAG_ZONE and not _shielded(t, at, seat),
		"set-up: B sat %.0f px from where the grenade lay, between hearing range (%.0f) and the frag zone (%.0f), with nothing shielding it" % [gap, Probe.HEAR_GRENADE, Probe.FRAG_ZONE])
	t.check(b_path.any(func(sample): return float(sample["t"]) <= call_at and bool(sample["busy"])), "(B was still seated when A radioed)")

	t.check(escape_at != INF, "B ran for an escape spot (debug_grenades().escape was set)")
	t.check(escape_at >= call_at - 0.05 and escape_at <= call_at + 0.7, "within 0.7 s of A's call, not before it (call at %.2f s, B's escape set at %.2f s)" % [call_at, escape_at])
	t.check(sources.has(&"called") and not sources.has(&"seen") and not sources.has(&"heard"), "B knew of the grenade only by the callout (sources %s)" % str(sources.keys()))
	var last: Array = b_path.filter(func(s): return float(s["t"]) >= float(boom["time"]) - 0.25)
	t.check(last.all(func(s): return Probe.safe_from_frag(t, at, s["p"])), "and it was out of the grenade's line of sight or past its radius before the burst (%.0f px away)" % b.global_position.distance_to(at))
	t.check(Probe.blast_hits(t, b).is_empty() and not b.is_dead, "taking no blast")


## G7 cover for a standing body at `p` (the height of B's surface while seated): whether a wall or a piece of furniture taller than it stands
## on the straight line from the burst (`Probe.shielded` reads a character's position, and B has left its seat by the time the test checks).
func _shielded(t: TestContext, burst: Vector2, p: Vector2) -> bool:
	var exclude: Array = []
	for body in t.world.find_children("*", "CharacterBody2D", true, false):
		exclude.append((body as CharacterBody2D).get_rid())
	var space := t.world.get_world_2d().direct_space_state
	for i in 8:
		var query := PhysicsRayQueryParameters2D.create(burst, p, PhysicsLayers.SOLID)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider: Object = hit["collider"]
		if (float(collider.get_surface().get("coverage", 100.0)) if collider.has_method("get_surface") else 100.0) > 60.0:
			return true
		exclude.append(hit["rid"])
	return false
