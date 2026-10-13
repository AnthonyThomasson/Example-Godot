extends GameTest

## Desired: a house defender does not leave its house to investigate gunfire out in the garden.
## Nothing in the code keeps it in: its goal says to hold its ground inside the house, the snapshot says the
## gunfire is outside the house, and Von, asked whether to investigate, judges. Needs the Von decision server.

const Probe := preload("res://tests/_ai/investigate_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A defender does not leave the house to investigate gunfire",
		"description": "Gunfire is heard in the garden beyond the front door: the defender is asked whether to investigate, and stays inside the house.",
		"tags": ["ai", "territory", "investigate", "von"],
		"requires_von": true,
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Probe.world(s, &"defender")


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	var brain := t.controller(&"npc", &"current_act")
	await t.seconds(1.0)
	Probe.gunfire(Probe.OUTSIDE)
	var left := false
	var asked := false
	var elapsed := 0.0
	while elapsed < 12.0 and not left:
		await t.seconds(0.1)
		elapsed += 0.1
		t.trace("npc_x", npc.global_position.x)
		left = npc.global_position.x < Probe.OUTSIDE_X
		asked = asked or Probe.asked_about_investigating(brain)
	t.check(asked, "Von was asked whether to investigate (it was not taken without asking)")
	t.check(not left, "the defender stayed inside the house (at %s, doing %s)" % [npc.global_position.round(), brain.debug_status()])
