extends GameTest

## A puppet beside a chair sits on it through the interaction API (interact_with "sit"): it becomes
## busy with the "Sit" label, and standing up (end_interaction) frees it again.


func describe() -> Dictionary:
	return {
		"name": "Sit on a chair and stand up",
		"description": "interact_with(chair, \"sit\") locks the character in the Sit interaction; end_interaction releases it.",
		"tags": ["interaction", "sit", "chair"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 500, 400))
	s.actor(&"sitter", &"puppet", Vector2(220, 200))
	s.object(&"chair", "chair", Vector2(258, 200))


func run(t: TestContext) -> void:
	var sitter := t.actor(&"sitter")
	var p := t.puppet(&"sitter")
	p.aim_at(t.object(&"chair"))
	await t.seconds(0.2)
	p.interact(t.object(&"chair"), "sit")
	if not t.require(await t.until(sitter.is_busy, 1.0), "sitting makes the character busy"):
		return
	t.expect_eq(sitter.interaction_label(), "Sit", "the HUD label names the interaction")
	t.check(p.failed_interactions.is_empty(), "the interaction was accepted")
	p.end_interaction()
	await t.until(func(): return not sitter.is_busy(), 1.0, "standing up frees the character")
