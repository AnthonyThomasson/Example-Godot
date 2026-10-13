extends GameTest

## With Von scripted to choose combat, the shot-at defender's decision is broadcast on the team radio:
## a `callout` event on the EventBus carrying its speaker and decision path.


func describe() -> Dictionary:
	return {
		"name": "A combat decision posts a callout",
		"description": "Von is scripted to pick combat; the defender broadcasts a callout naming itself and its path.",
		"tags": ["ai", "callout", "eventbus", "scripted"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.von_script([{ "pick": "combat" }])
	s.switch(&"ai.callouts", true)
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"defender", &"defender", Vector2(650, 300))
	s.actor(&"attacker", &"puppet", Vector2(200, 300), { "start_slot": 3, "faction": &"invader", "max_health": 400.0 })


func run(t: TestContext) -> void:
	var gunman := t.puppet(&"attacker")
	gunman.aim_at(t.actor(&"defender"))
	await t.seconds(0.6)
	gunman.shoot()
	var combat_call := func(d): return String(d.get("path", "")).begins_with("combat") or str(d.get("path", "")).contains("combat")
	t.check(await t.until(func(): return t.happened(&"callout", combat_call), 8.0), "the defender posts a combat callout")
	var calls := t.events_of(&"callout")
	if not calls.is_empty():
		t.check(calls[0].has("speaker") and calls[0].has("position"), "the callout names its speaker and position")
