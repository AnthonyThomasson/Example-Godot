extends GameTest

## H1 (`docs/hearing.md`, issue #51, R5), the scenario: a heard footstep is an INVESTIGATE lead ("footsteps heard"), like gunfire.
## A defender in the Terrace house's living room hears an invader walking about the kitchen behind the wall, out of its sight, and goes
## to see: it takes INVESTIGATE on the footsteps lead and heads for the kitchen. Real Von at every level; a `require` that it heard the
## steps (its memory, `debug_memory()["footsteps"]`) comes first, so a deaf defender reads as the missing hearing, not a Von choice.
##
## Premise: the invader is a puppet (the thing to be heard) that paces a lane in the kitchen's south-west, hidden from the living room
## by the wall between, about 150 px from the defender; unkillable, it never shoots.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const DEFENDER_AT := Vector2(400, 290)
const LANE := [Vector2(560, 250), Vector2(560, 330)]


func describe() -> Dictionary:
	return {
		"name": "A defender investigates footsteps heard in the next room",
		"description": "An invader walks about the kitchen out of sight; the defender in the living room hears the steps through the wall, takes INVESTIGATE on the footsteps lead and heads for the kitchen.",
		"tags": ["ai", "investigate", "hearing", "von"],
		"requires_von": true,
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"d", &"defender", DEFENDER_AT, { "facing": Vector2.LEFT })
	s.actor(&"inv", &"puppet", LANE[0], { "faction": &"invader", "max_health": 1000000.0 })


func run(t: TestContext) -> void:
	var walker := t.puppet(&"inv")
	var d := t.actor(&"d")
	var brain := t.controller(&"d", &"debug_memory")
	var leg := 0
	walker.walk_to(LANE[1])
	var seen: Array = []
	var footsteps_lead := func() -> bool:
		var act := str(brain.current_act())
		if not seen.has(act):
			seen.append(act)
		if not act.begins_with("investigate/"):
			return false
		var lead_id := act.get_slice("/", 1)
		for z in brain.debug_zones():
			if z["category"] == &"lead" and str(z["desc"]).contains("footsteps") and _zone_id(brain, lead_id, z):
				return true
		return false
	var end := t.time + 60.0
	var took := false
	while t.time < end and not took:
		if walker.has_arrived():
			leg = (leg + 1) % 2
			walker.walk_to(LANE[leg])
		took = footsteps_lead.call()
		await t.frames(1)
	var heard: Array = brain.debug_memory().get("footsteps", [])
	if not t.require(not heard.is_empty() or took, "the defender heard the invader's footsteps through the wall (debug_memory footsteps: %d; acts %s)" % [heard.size(), str(seen)]):
		return
	if not t.require(not seen.any(func(a): return a.begins_with("combat")) or took, "set-up: it did not come on the invader by other means first (acts %s)" % str(seen)):
		return
	t.check(took, "it took INVESTIGATE on the footsteps lead (acts %s)" % str(seen))
	if took:
		var from: Vector2 = d.global_position
		await t.seconds(2.0)
		t.check(d.global_position.distance_to(LANE[0]) < from.distance_to(LANE[0]) - 20.0 or Maps.HOUSE_KITCHEN.has_point(d.global_position), "and headed for the kitchen (from %s to %s)" % [from.round(), d.global_position.round()])


## Whether lead zone `z` is the option `lead_id` of the brain's last walk (the INVESTIGATE level offered it under that id with that desc).
func _zone_id(brain: Node, lead_id: String, z: Dictionary) -> bool:
	for l in brain.debug_state().get("decision", {}).get("levels", []):
		var offered: Dictionary = l.get("offered", {})
		if offered.has(lead_id) and str(offered[lead_id]) == str(z["desc"]):
			return true
	return false
