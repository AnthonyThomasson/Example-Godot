extends GameTest

## E9 (`docs/tactical-entry.md`): under fire, a walk goes through a doorway without an entry unless it leads into the room the shots came
## from, and that room is the one behind the doorway the shots came through, not the room they landed in. An invader in the Terrace house's
## kitchen is shot at from the living room, through the doorway between them, and steps out into the hall; still under fire, it is ordered to
## rush a householder in the kitchen. The kitchen is only where it stood when the shot landed: it walks straight back in through the hall's
## doorway, without stacking for it. (Into the room the shots came from it goes only by entry: `entry_guard_shot_from_room_ahead`.)
##
## Scripted Von (one mechanism: the guard's exemption), the rush as in `entry_guard_under_fire_exempt` (`Entry.guard_rules`). Premises: the
## householder is a puppet that never shoots and cannot be killed, and the invader cannot be killed; the shot is one `hit` event nobody known
## fired (as tests/_ai/investigate_probe.gd posts gunfire), landing beside the invader; once it has been taken in, the invader is moved into
## the hall (it "steps" there), facing the householder through the doorway.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
## Where the invader stands in the kitchen, and where the shot lands beside it: the line back runs west through the middle of the
## living room doorway (y 150) to the living room's west wall.
const IN_KITCHEN := Vector2(565, 150)
const LANDED := Vector2(575, 150)
const SHOOTER := Vector2(250, 150)
## Where it steps to in the hall: below the doorway into the kitchen.
const IN_HALL := Vector2(690, 430)
const TARGET := Vector2(700, 230)


func describe() -> Dictionary:
	return {
		"name": "Entry guard: the room a shot landed in is not the shots' room",
		"description": "Shot at in the kitchen from the living room, an invader that stepped into the hall walks straight back into the kitchen under fire, without stacking: the shots came from the living room.",
		"tags": ["ai", "entry", "guard", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.guard_rules(s, ["combat", "advance", "rush"])
	Entry.npc(s, &"inv", IN_KITCHEN, 0.4, {}, { "facing": Vector2.RIGHT })
	Entry.target(s, &"householder", TARGET, IN_HALL, { "faction": &"household" })


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var brain := Entry.brain(t, &"inv")
	EventBus.post(&"hit", { "position": LANDED, "direction": (LANDED - SHOOTER).normalized(), "damage": 10.0, "attacker": null, "victim": null })
	var taken := func(): return not (brain.debug_memory().get("shot_from", []) as Array).is_empty()
	if not t.require(await t.until(taken, 3.0), "the shot was taken in as one at the invader (act %s)" % brain.current_act()):
		return
	inv.global_position = IN_HALL
	inv.aim_point = TARGET
	var stepped := t.time
	var back_in := func(): return Maps.HOUSE_KITCHEN.grow(-30).has_point(inv.global_position)
	var under_fire := [false]  # it was under fire on the walk back in (an Array: a lambda captures a bool by value)
	var reached: bool = await t.until(func():
		under_fire[0] = under_fire[0] or (bool(brain.debug_state().get("under_fire", false)) and not back_in.call())
		return back_in.call(), 15.0)
	if not t.require(String(brain.current_act()).begins_with("combat/"), "the invader was ordered to fight the householder (act %s)" % brain.current_act()):
		return
	if not t.require(under_fire[0], "it was still under fire in the hall, on the walk back in"):
		return
	t.check(reached, "it walked back into the kitchen (at %s, act %s)" % [inv.global_position.round(), brain.current_act()])
	var claimed := Entry.first_call_time(t, "claim", &"inv", Entry.KITCHEN_HALL["id"])
	t.check(claimed == INF, "it did not stack for the hall's doorway into the kitchen: the shots came from the living room (claimed it %.2f s after stepping out)" % (claimed - stepped))
	t.check(Entry.first_call_time(t, "going_in", &"inv", Entry.KITCHEN_HALL["id"]) == INF, "it did not cross that doorway as an entry")
