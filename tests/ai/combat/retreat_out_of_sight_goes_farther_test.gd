extends GameTest

## Issue #51 R12: a RETREAT takes the NPC out of sight of every threat when it stands in sight of one, else farther from them. Already
## out of sight, it was offered every other spot out of sight too, nearer the threat included, and in a fight it walked from one to the
## next and back every half second. Out of sight of where the shots came from, no place nearer them is a retreat.
##
## Scripted Von (one mechanism: what RETREAT offers). The bare Terrace house, an invader in the hall; one `hit` event nobody known fired,
## from the north-east (from the living room, through the hall's north wall), lands beside it. The threat the NPC retreats from is
## where the shots came from, `investigate_distance` (300 px) out along the shot: in the living room, behind the wall from the hall.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const AT := Vector2(300, 440)
const FROM := Vector2(0.5, -0.866)
const LANDED := Vector2(310, 430)
const REACH := 300.0
## Slack (px) for the few px the invader may have moved between the snapshot and the read.
const SLACK := 8.0


func describe() -> Dictionary:
	return {
		"name": "A retreat from out of sight goes farther",
		"description": "Shot at from the living room through the hall's wall, the invader in the hall is out of sight of the shots; no spot nearer them is offered as a retreat.",
		"tags": ["ai", "combat", "retreat", "scripted"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([{ "pick": "retreat" }])
	s.actor(&"inv", &"invader", AT, { "max_health": 1000000.0, "facing": Vector2.LEFT })  # Unkillable, facing away: the shooter stays unseen.


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var brain := t.controller(&"inv", &"debug_state")
	EventBus.post(&"hit", { "position": LANDED, "direction": -FROM, "damage": 10.0, "attacker": null, "victim": null })
	if not t.require(await t.until(func(): return str(brain.current_act()).begins_with("combat/"), 5.0),
			"the invader fights back after the shot (act %s)" % brain.current_act()):
		return
	var here: Vector2 = inv.global_position
	var threat := here + FROM * REACH
	var space: PhysicsDirectSpaceState2D = (inv as Node2D).get_world_2d().direct_space_state
	if not t.require(_blocked(space, threat, here, inv), "the invader is out of sight of where the shots came from (%s)" % str(threat.round())):
		return
	var retreats: Array = brain.debug_zones().filter(func(z): return str(z.get("category", "")) == "retreat")
	t.check(not retreats.is_empty(), "RETREAT offers somewhere to go (offered %s)" % str(retreats.map(func(z): return z["label"])))
	for z in retreats:
		var p: Vector2 = z["point"]
		t.check(p.distance_to(threat) > here.distance_to(threat) - SLACK,
			"a retreat to %s at %s is nearer the shots (%.0f px) than where the invader stands (%.0f px)" % [z["label"], str(p.round()),
			p.distance_to(threat), here.distance_to(threat)])


## Whether a wall or solid piece stands between `a` and `b` (the invader's own body left out).
func _blocked(space: PhysicsDirectSpaceState2D, a: Vector2, b: Vector2, inv: Node) -> bool:
	var q := PhysicsRayQueryParameters2D.create(a, b, PhysicsLayers.SOLID, [inv.get_rid()])
	return not space.intersect_ray(q).is_empty()
