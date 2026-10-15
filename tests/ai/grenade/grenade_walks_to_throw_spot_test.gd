extends GameTest

## G17's throw spots: GRENADE is also offered when the hostile is out of range from where the NPC stands, if a reachable throw
## spot exists; the `throw` primitive walks there first, then throws. The case the matches showed most (the target 450 to 700 px off across a
## doorway into the next room): an invader with a frag in the Terrace house's kitchen, by its east wall, sees a householder holding the living
## room through the doorway between them, about 650 px away: out of range from where the invader stands (550 px, the throw range), so GRENADE
## (a defender in a room the invader is outside of) is not offered from there; it is offered through a throw spot nearer the doorway: the
## invader walks there, throws the frag into the living room onto the householder from within range, and the blast catches it.
##
## The whole pipeline runs with real Von. `require`s come first: the invader fought the householder from the kitchen, and its first COMBAT
## decision against it was made from out of throw range (so the offer, if any, was through a throw spot, not R7's in place).
##
## Premises: the householder is a puppet that cannot be killed and never shoots (a defender that holds the room whatever is fired at it); the
## invader is armed with one frag at the start of `run`, the way Main arms a spawn.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Spot := preload("res://tests/_ai/throw_spot_probe.gd")
const INVADER_AT := Vector2(790, 120)
const HOLDER_AT := Vector2(140, 150)


func describe() -> Dictionary:
	return {
		"name": "An invader walks to a throw spot to frag a defender out of range",
		"description": "A householder holds the living room 650 px from an invader with a frag in the kitchen, in sight through the doorway: GRENADE is offered through a throw spot, the invader walks there and frags the householder from within range.",
		"tags": ["ai", "grenade", "combat", "throw_spot", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"i", &"invader", INVADER_AT, { "facing": (HOLDER_AT - INVADER_AT).normalized() })
	Probe.hostile(s, &"h", HOLDER_AT, Maps.DOOR_LIVING_KITCHEN)


func run(t: TestContext) -> void:
	var inv := t.actor(&"i")
	Probe.arm(inv, 0, 1)
	if not t.require(Probe.count(inv, Probe.FRAG) == 1, "the invader carries a frag grenade (item_count(8) = %d)" % Probe.count(inv, Probe.FRAG)):
		return
	if not t.require(Probe.line_clear(t, INVADER_AT, HOLDER_AT), "set-up: the invader sees the householder through the doorway"):
		return
	var brain := t.controller(&"i", &"debug_zones")
	var target := "combat/t_%d" % t.actor(&"h").get_instance_id()
	var state := {}
	var walks: Array = []
	var acts: Array = []
	var from_kitchen := [false]
	var watch := func() -> bool:
		Spot.note(t, brain, inv, state, walks)
		var act := Probe.acts(t, &"i")
		if not acts.has(act):
			acts.append(act)
		if act.begins_with(target) and Maps.HOUSE_KITCHEN.has_point(inv.global_position):
			from_kitchen[0] = true
		return t.happened(&"throw", func(d): return d.get("attacker") == inv)
	await t.until(watch, 60.0)
	if not t.require(from_kitchen[0], "the invader fought the householder from the kitchen (acts %s)" % str(acts)):
		return
	var fights: Array = walks.filter(func(w): return not w["combat"].is_empty())
	if not t.require(not fights.is_empty() and (fights[0]["pos"] as Vector2).distance_to(HOLDER_AT) > Spot.THROW_RANGE,
			"set-up: its first COMBAT decision was made from out of throw range (walks %s)" % str(Spot.describe(walks))):
		return
	t.check(fights[0]["combat"].has("grenade"), "GRENADE was offered from out of range, through a throw spot (offered %s; walks %s)" % [str(fights[0]["combat"]), str(Spot.describe(walks))])
	var throws := Probe.raw(t, &"throw", func(d): return d.get("attacker") == inv)
	if not t.check(not throws.is_empty() and throws[0]["data"].get("kind") == &"frag", "the invader threw its frag (acts %s)" % str(acts)):
		return
	var at: Vector2 = throws[0]["data"]["position"]
	t.check(at.distance_to(HOLDER_AT) <= Spot.THROW_RANGE, "from within throw range of the householder (%.0f px)" % at.distance_to(HOLDER_AT))
	t.check(at.distance_to(fights[0]["pos"]) >= 50.0, "after walking to a throw spot (thrown at %s, it decided at %s)" % [str(at.round()), str((fights[0]["pos"] as Vector2).round())])
	t.check(not Maps.HOUSE_LIVING.has_point(at), "from outside the living room")
	if t.check(await Probe.wait_boom(t, &"frag", 6.0), "the frag went off"):
		var boom: Vector2 = Probe.booms(t, &"frag")[0]["data"]["position"]
		t.check(Maps.HOUSE_LIVING.has_point(boom) and boom.distance_to(HOLDER_AT) < 110.0, "in the living room onto the householder's spot (%s, %.0f px from it)" % [str(boom.round()), boom.distance_to(HOLDER_AT)])
		t.check(not Probe.blast_hits(t, t.actor(&"h")).is_empty(), "and its blast caught the householder")
		t.check(Probe.blast_hits(t, inv).is_empty(), "without catching the thrower")
