extends GameTest

## Desired (issue #40): an NPC that reaches the point of a `move` order stands still until it is given a new one. Von
## takes a moment to answer (the first answers of a match are the slowest), and the old order must not keep the NPC walking
## meanwhile: it used to carry on in its last heading, which from a point just inside the front door is out of the house.
## Gunfire is heard just inside the front door; a defender in the hall goes to it, and the next answer is slow to come.

const Probe := preload("res://tests/_ai/investigate_probe.gd")
const LEAD := Vector2(60, 415)            # just inside the front doorway, on the hall's axis
const LATENCY := 4.0                      # seconds Von takes to answer
const STILL_SPEED := 5.0                  # px/s: standing still


func describe() -> Dictionary:
	return {
		"name": "An NPC stops when it reaches its destination",
		"description": "A defender walks to gunfire heard just inside the front door and, while Von is slow to answer, stands there instead of walking out of the house.",
		"tags": ["ai", "move", "territory", "decision", "scripted"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	Probe.world(s, &"defender")
	s.von_script([{ "pick": "investigate" }])
	s.von_latency(0.0)   # answers at once while the defender is sent; run() makes them slow once it is under way (restored after the test)


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	var brain := t.controller(&"npc", &"current_act")
	await t.seconds(0.5)
	Probe.gunfire(LEAD)
	if not t.require(await t.until(func(): return String(brain.current_act()).begins_with("investigate/lead_gunfire"), 6.0), "the defender is sent to the gunfire (%s)" % brain.current_act()):
		return
	DecisionStub.latency = LATENCY
	if not t.require(await t.until(func(): return npc.global_position.distance_to(LEAD) < 40.0, 8.0), "it walks to the gunfire (at %s)" % npc.global_position.round()):
		return
	var left := false
	var moving := false
	var elapsed := 0.0
	while elapsed < LATENCY * 0.75:       # the next answer is still on its way
		await t.seconds(0.1)
		elapsed += 0.1
		t.trace("npc_x", npc.global_position.x)
		left = left or npc.global_position.x < Probe.OUTSIDE_X
		moving = moving or (elapsed > 0.5 and npc.velocity.length() > STILL_SPEED)
	t.check(not left, "it did not walk out of the house (at %s)" % npc.global_position.round())
	t.check(not moving, "it stood still on arrival while Von was answering")
