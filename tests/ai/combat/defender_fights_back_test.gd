extends GameTest

## A puppet shoots at the defender NPC in an arena: being attacked makes it hostile, it enters combat
## (its decision path starts with `combat`) and shoots back. Needs the Von decision server.


func describe() -> Dictionary:
	return {
		"name": "Defender fights back when shot",
		"description": "The defender ignores a stranger until fired upon, then switches to combat and returns fire. Trespass hostility and callouts off.",
		"tags": ["ai", "combat", "hostility", "von"],
		"requires_von": true,
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.hostile_on_trespass", false)  # only the attack itself should make it hostile
	s.switch(&"projectile.flyover", false)
	s.actor(&"defender", &"defender", Vector2(650, 300))
	s.actor(&"attacker", &"puppet", Vector2(200, 300), { "start_slot": 3, "faction": &"invader", "max_health": 400.0 })
	s.show_overlays(["show_actions", "show_vision"])


func run(t: TestContext) -> void:
	var gunman := t.puppet(&"attacker")
	var defender := t.actor(&"defender")
	var defender_shot := func(d): return d["attacker"] == defender
	gunman.aim_at(defender)
	await t.seconds(4.0)
	t.check(not t.happened(&"hit", defender_shot), "the defender holds fire before being attacked")
	gunman.shoot()
	t.require(await t.until(func(): return t.happened(&"hit", func(d): return d["victim"] == defender), 2.0), "the opening shot hits the defender")
	var brain := t.controller(&"defender", &"current_act")
	await t.until(func(): return String(brain.current_act()).begins_with("combat"), 20.0, "the defender switches to combat")
	await t.until(func(): return t.happened(&"hit", defender_shot), 20.0, "the defender lands a shot back")
