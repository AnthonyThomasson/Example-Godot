extends GameTest

## G17 as amended (issue #51, R7): GRENADE is offered against a hostile whose last-known spot is in a room the NPC is outside of, even
## with a line of fire: a defender barricaded in a room is grenaded, not only shot at. A householder holds the kitchen's back doorway
## from just inside it, facing out; an invader in the garden with a frag sees it through the doorway with a clear shot. It throws the
## frag into the kitchen onto it (the lob, ally and self-safety rules unchanged: it can step behind the wall out of the blast). The
## whole pipeline runs with real Von; a `require` that the invader is fighting the householder from outside the kitchen comes first.
## (`grenade_not_offered_clear_shot` stays as it is: a hostile in the open in the NPC's own room, in its line of fire, is shot.)
##
## Premises: the householder is a puppet that cannot be killed and never shoots (a defender that stands its ground in the doorway
## whatever is fired at it); the invader is armed with one frag at the start of `run`, the way Main arms a spawn.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const INVADER_AT := Vector2(980, 80)
const HOLDER_AT := Vector2(805, 190)


func describe() -> Dictionary:
	return {
		"name": "An invader frags a defender holding a doorway it has a clear shot at",
		"description": "A householder holds the kitchen's back doorway from inside, in the line of fire of an invader in the garden with a frag: GRENADE is offered and the invader throws the frag into the kitchen onto it.",
		"tags": ["ai", "grenade", "combat", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"i", &"invader", INVADER_AT, { "facing": (HOLDER_AT - INVADER_AT).normalized() })
	Probe.hostile(s, &"h", HOLDER_AT, Maps.DOOR_BACK + Vector2(200, 0))


func run(t: TestContext) -> void:
	var inv := t.actor(&"i")
	Probe.arm(inv, 0, 1)
	if not t.require(Probe.count(inv, Probe.FRAG) == 1, "the invader carries a frag grenade (Character.item_count(8) = %d)" % Probe.count(inv, Probe.FRAG)):
		return
	var brain := t.controller(&"i", &"current_act")
	var target := "t_%d" % t.actor(&"h").get_instance_id()
	if not t.require(Probe.line_clear(t, INVADER_AT, HOLDER_AT), "set-up: the invader has a clear line to the householder through the doorway"):
		return
	var seen: Array = []
	var offered := [false]
	var fighting_outside := [false]
	var watch := func() -> bool:
		var act := Probe.acts(t, &"i")
		if not seen.has(act):
			seen.append(act)
		if act.begins_with("combat/%s" % target) and not Maps.HOUSE_KITCHEN.has_point(inv.global_position):
			fighting_outside[0] = true
		if Probe.offered(brain).has("grenade"):
			offered[0] = true
		return t.happened(&"throw")
	await t.until(watch, 60.0)
	if not t.require(fighting_outside[0], "the invader fought the householder from outside the kitchen (acts %s)" % str(seen)):
		return
	t.check(offered[0], "GRENADE was offered against the householder holding the doorway (acts %s)" % str(seen))
	var throws := Probe.raw(t, &"throw", func(d): return d.get("attacker") == inv)
	if not t.check(not throws.is_empty() and throws[0]["data"].get("kind") == &"frag", "the invader threw its frag (acts %s)" % str(seen)):
		return
	t.check(not Maps.HOUSE_KITCHEN.has_point(throws[0]["data"]["position"]), "from outside the kitchen (thrown at %s)" % str((throws[0]["data"]["position"] as Vector2).round()))
	if t.check(await Probe.wait_boom(t, &"frag", 6.0), "the frag went off"):
		var at: Vector2 = Probe.booms(t, &"frag")[0]["data"]["position"]
		t.check(Maps.HOUSE_KITCHEN.has_point(at) and at.distance_to(HOLDER_AT) < 110.0, "in the kitchen, onto the householder's spot (%s, %.0f px from it)" % [str(at.round()), at.distance_to(HOLDER_AT)])
		t.check(not Probe.blast_hits(t, t.actor(&"h")).is_empty(), "and its blast caught the householder (%d blast hits on it)" % Probe.blast_hits(t, t.actor(&"h")).size())
		t.check(Probe.blast_hits(t, inv).is_empty(), "without catching the thrower in it")
