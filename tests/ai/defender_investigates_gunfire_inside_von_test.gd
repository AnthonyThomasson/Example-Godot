extends GameTest

## Control for defender_stays_in_house_von: the same defender, the same gunfire, but heard INSIDE the house
## (in the kitchen). It still investigates, so the outside case above is Von weighing where the gunfire is,
## not Von never investigating. Needs the Von decision server.

const Probe := preload("res://tests/_ai/investigate_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A defender still investigates gunfire inside the house",
		"description": "Gunfire is heard in the kitchen: the defender in the hall goes to investigate it.",
		"tags": ["ai", "territory", "investigate", "von"],
		"requires_von": true,
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Probe.world(s, &"defender")


func run(t: TestContext) -> void:
	var brain := t.controller(&"npc", &"current_act")
	await t.seconds(1.0)
	Probe.gunfire(Probe.INSIDE)
	t.check(await t.until(func(): return String(brain.current_act()).begins_with("investigate"), 12.0),
		"the defender investigates the gunfire inside the house (doing %s)" % brain.debug_status())
