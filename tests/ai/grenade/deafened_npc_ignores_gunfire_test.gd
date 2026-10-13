extends GameTest

## G15, deaf: a deafened NPC hears no gunfire, hits elsewhere or radio callouts. Two defenders in the terrace house hear a shot fired in
## the kitchen: the one that can hear goes to investigate (the control), the one deafened by a bang remembers no gunfire and does not.
## Real Von; everything else is on.
##
## Premises: the gunfire is one shot heard from the kitchen (a `hit` event with nobody known behind it, as tests/_ai/investigate_probe.gd
## posts it); the deafness is `take_stun(0, 8, ...)` on one defender, as a bang's would be (the grenade's own bang is tested elsewhere).
## No behaviour is switched off: the only characters are the two household defenders, allies of each other, so trespass hostility (a stranger in
## the house) has nobody to fall on and the shot is the only thing that can draw them.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Investigate := preload("res://tests/_ai/investigate_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A deafened NPC hears no gunfire",
		"description": "A shot is heard in the kitchen: the defender who can hear investigates it; the one deafened by a bang keeps no memory of it and does not go to it.",
		"tags": ["ai", "grenade", "stun", "deaf", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"hears", &"defender", Vector2(250, 190), { "facing": Vector2.RIGHT })
	s.actor(&"deaf", &"defender", Vector2(250, 300), { "facing": Vector2.RIGHT })


func run(t: TestContext) -> void:
	var deaf := t.actor(&"deaf")
	if not t.require(Probe.stun(deaf, 0.0, 8.0, Vector2(250, 390)), "Character.take_stun(blind, deaf, from) exists"):
		return
	await t.frames(3)
	t.require(Probe.deaf(deaf), "set-up: the defender is deaf (is_deaf)")
	var hears_brain := t.controller(&"hears", &"current_act")
	var deaf_brain := t.controller(&"deaf", &"current_act")
	await t.seconds(1.0)
	Investigate.gunfire(Maps.KITCHEN_CENTRE)
	# While it is deaf, the deaf one never takes an investigate order and never sets off for the room the shot came from. (It does go about
	# its own business meanwhile, searching the house like the other, so how far it has moved says nothing about the shot.)
	var investigated := false
	var to_kitchen := false
	var went := false
	var waited := 0
	while waited < 15 * 60 and Probe.deaf(deaf):
		if str(hears_brain.current_act()).begins_with("investigate"):
			went = true
			break
		investigated = investigated or str(deaf_brain.current_act()).begins_with("investigate")
		var target: Array = deaf_brain.debug_state().get("loco", {}).get("target", [])
		to_kitchen = to_kitchen or (target.size() == 2 and Maps.HOUSE_KITCHEN.has_point(Vector2(target[0], target[1])))
		waited += 1
		await t.frames(1)
	if not t.require(went, "the defender who can hear investigates the shot (acting: %s)" % str(hears_brain.current_act())):
		return
	t.check(not (hears_brain.debug_memory()["gunfire"] as Array).is_empty(), "and remembers it")
	t.check((deaf_brain.debug_memory()["gunfire"] as Array).is_empty(), "the deafened defender remembers no gunfire")
	t.check(not str(deaf_brain.current_act()).begins_with("investigate"), "and is not investigating it (acting: %s)" % str(deaf_brain.current_act()))
	t.check(Probe.deaf(deaf), "(it is still deaf)")
	t.check(not investigated, "it never took an investigate order while it was deaf")
	t.check(not to_kitchen, "and never set off for the kitchen, where the shot was")
