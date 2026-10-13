extends GameTest

## Desired (E15, the limit): a member heading for a stack that others have claimed goes to its door as part of the team. An ally
## has claimed room C's doorway on the radio, so the invader ordered to ENTER there does not leave its approach to secure the
## doors it passes: the point is not left to go in alone. It walks the corridor past rooms A and B and stacks at C's door.
## Scripted Von: SEARCH > ENTER > C's doorway. The ally is a puppet in room B that repeats its claim, as a stacked
## teammate's heartbeat does.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "A member heading for a claimed stack does not stop to secure doors",
		"description": "With an ally already stacking at room C's door, the invader ordered there walks past rooms A and B without securing them and stacks as slot 2.",
		"tags": ["ai", "entry", "guard", "scripted", "callout"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.spine(s, false)
	Entry.rules(s, Entry.SPINE_C)
	Entry.npc(s, &"inv", Vector2(60, 250))
	Entry.target(s, &"ally", Vector2(450, 100), Vector2(450, 300), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var brain := Entry.brain(t, &"inv")
	var secured := []
	var next_claim := 0.0
	var end := t.time + 50.0
	var stacked := false
	while t.time < end and not stacked:
		if t.time >= next_claim:
			next_claim = t.time + 1.0
			_claim(t)
		var e := Entry.entry(brain)
		if not e.is_empty() and e["secure"] and not secured.has(e["opening"]):
			secured.append(e["opening"])
		stacked = not e.is_empty() and e["opening"] == Entry.SPINE_C["id"] and e["phase"] in ["stack", "pie"]
		await t.frames(1)
	if not t.require(Entry.asked(t, Entry.SPINE_C["id"]), "the order was ENTER for room C's doorway (act %s)" % brain.current_act()):
		return
	t.check(stacked, "it stacked at room C's door (act %s)" % brain.current_act())
	t.check(secured.is_empty(), "it secured no doorway on the way (%s)" % str(secured))
	t.expect_eq(int(Entry.entry(brain).get("slot", 0)), 2, "it took the slot after the ally's")


## The ally radios its claim on the stack at room C's door: slot 1, on the corridor's near side.
func _claim(t: TestContext) -> void:
	var who := t.actor(&"ally")
	EventBus.post(&"callout", {
		"speaker": who, "faction": who.faction, "position": who.global_position, "status": "", "path": "", "label": "", "target_id": 0,
		"point": Vector2.ZERO, "opening": Entry.SPINE_C["id"], "slot": 1, "side": -1, "entry_step": "claim",
	})
