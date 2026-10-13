extends GameTest

## Control for defender_stays_in_house_von: an invader (no hold-your-ground in its goal) hears the same
## gunfire out in the garden and still investigates it. What keeps a defender in is its goal, not a rule that
## applies to every NPC. Needs the Von decision server.

const Probe := preload("res://tests/_ai/investigate_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "An invader still investigates gunfire outside the house",
		"description": "Gunfire is heard in the garden: an invader (not told to hold a house) goes to investigate it.",
		"tags": ["ai", "territory", "investigate", "von"],
		"requires_von": true,
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Probe.world(s, &"invader")


func run(t: TestContext) -> void:
	var brain := t.controller(&"npc", &"current_act")
	await t.seconds(1.0)
	Probe.gunfire(Probe.OUTSIDE)
	t.check(await t.until(func(): return String(brain.current_act()).begins_with("investigate"), 12.0),
		"the invader investigates the gunfire outside the house (doing %s)" % brain.debug_status())
