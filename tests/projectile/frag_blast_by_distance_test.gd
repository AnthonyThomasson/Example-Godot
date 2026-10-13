extends GameTest

## G7: the frag blast. A hittable body with a clear line from the blast point within 250 px takes blast damage through
## `take_hit`: the full 60 (a character has 50 HP) out to 120 px, falling linearly to nothing at 250 px; nothing beyond.
## Characters and objects both. Blast hits post `&"hit"` with outcome `blast`, which is how this test tells them from the
## fragments.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const FROM := Vector2(100, 450)
const AIM := Vector2(500, 450)
## Slack on the damage formula: the body has a radius and the blast point is the grenade's rest point, not the aim point.
const SLACK := 8.0


func describe() -> Dictionary:
	return {
		"name": "A frag blast hurts by distance",
		"description": "A frag lands among a dummy 80 px away (dies), one 200 px away (hurt by the linear fall-off), one 400 px away (no blast) and a chair 160 px away (struck through take_hit).",
		"tags": ["grenade", "frag", "blast", "damage"],
		"timeout": 14.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 1000))
	s.switch(&"nav.rebake", false)
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100000.0 })
	s.actor(&"near", &"puppet", AIM + Vector2(0, -80))
	s.actor(&"mid", &"puppet", AIM + Vector2(0, 200), { "max_health": 100.0 })
	s.actor(&"far", &"puppet", AIM + Vector2(0, 400), { "max_health": 100.0 })
	s.object(&"chair", "chair", AIM + Vector2(160, 0))


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 0, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1, "the thrower carries a frag grenade (Character.item_count(8) = %d)" % Probe.count(thrower, Probe.FRAG)):
		return
	await Probe.throw_at(t, &"thrower", Probe.FRAG, AIM)
	if not t.require(await Probe.wait_boom(t, &"frag", 6.0), "the frag grenade goes off"):
		return
	var blast: Vector2 = Probe.booms(t, &"frag")[0]["data"]["position"]
	await t.seconds(0.3)

	var near := t.actor(&"near")
	var near_hits := Probe.blast_hits(t, near)
	t.check(not near_hits.is_empty(), "the dummy %.0f px from the blast takes a blast hit" % near.global_position.distance_to(blast))
	if not near_hits.is_empty():
		t.check(float(near_hits[0]["data"]["damage"]) >= Probe.BLAST_DAMAGE - SLACK, "inside the kill radius it takes the full %.0f (%.0f)" % [Probe.BLAST_DAMAGE, near_hits[0]["data"]["damage"]])
	t.check(near.is_dead, "and a character of 50 HP does not survive it")

	var mid := t.actor(&"mid")
	var d_mid: float = mid.global_position.distance_to(blast)
	var mid_hits := Probe.blast_hits(t, mid)
	if t.check(not mid_hits.is_empty(), "the dummy %.0f px from the blast takes a blast hit" % d_mid):
		var want := Probe.blast_damage(d_mid)
		t.check(absf(float(mid_hits[0]["data"]["damage"]) - want) <= SLACK, "its damage falls off linearly: %.1f, expected about %.1f" % [mid_hits[0]["data"]["damage"], want])
		t.check(float(mid_hits[0]["data"]["damage"]) < Probe.BLAST_DAMAGE - 10.0, "less than the full blast")
	t.check(mid.health < mid.max_health and not mid.is_dead, "so it is hurt, not dead (%.0f / %.0f)" % [mid.health, mid.max_health])

	var far := t.actor(&"far")
	t.check(Probe.blast_hits(t, far).is_empty(), "the dummy %.0f px from the blast, past 250 px, takes no blast (fragments may still reach it)" % far.global_position.distance_to(blast))

	var chair := t.object(&"chair")
	var chair_hits := Probe.blast_hits(t, chair)
	t.check(not chair_hits.is_empty(), "the chair %.0f px from the blast is struck through take_hit as well" % chair.global_position.distance_to(blast))
	t.check(not t.spawned("BloodSplat").is_empty(), "a body hit by the blast bleeds")
