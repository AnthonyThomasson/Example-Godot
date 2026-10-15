extends GameTest

## Issue #51 R12 (no needless COMBAT re-decision): adopting an order is not news. The controller re-decides at once when its belief about
## hostiles changes (one spotted, lost or newly hostile, or the engaged contact crossing the house boundary: the behaviour's salient key);
## adopting an order that fights a hostile sets the engaged contact, and that alone must not read as a change of belief and start a new
## decision. One mechanism, scripted Von (COMBAT > ENGAGE > from where it stands): an invader in an arena with a household puppet in sight
## from the start, nothing else changing. Its first decision is adopted; for the next second no decision is forced by "hostile belief
## changed".
##
## Premises: the puppet cannot be killed and never shoots; the invader stands still (speed 0), so where it stands does not change.

const WATCH := 1.0


func describe() -> Dictionary:
	return {
		"name": "Adopting an order on a hostile does not force a re-decision",
		"description": "An invader adopts COMBAT > ENGAGE on a puppet in sight, nothing else changing: no decision is forced by a change of belief about hostiles in the second after.",
		"tags": ["ai", "decision", "combat", "scripted"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }, { "pick": "fire_here" }])
	s.switch(&"ai.callouts", false)
	s.actor(&"i", &"invader", Vector2(150, 250), { "speed": 0.0, "facing": Vector2.RIGHT })
	s.actor(&"h", &"puppet", Vector2(450, 250), { "faction": &"household", "max_health": 1000000.0, "facing": Vector2.LEFT,
		"aim_point": Vector2(150, 250) })


func run(t: TestContext) -> void:
	var brain := t.controller(&"i", &"debug_state")
	if not t.require(await t.until(func(): return str(brain.current_act()).begins_with("combat/"), 5.0), "the invader adopted a COMBAT order (acting: %s)" % str(brain.current_act())):
		return
	var adopted_at := t.time
	var seen := [int(brain.debug_state().get("decisions", 0))]  # In an Array: a lambda captures an int by value.
	var reasons: Array = []
	await t.until(func():
		var st: Dictionary = brain.debug_state()
		var count := int(st.get("decisions", 0))
		if count != seen[0]:
			seen[0] = count
			reasons.append("%.2fs %s" % [t.time - adopted_at, str(st.get("decision_reason", ""))])
		return t.time - adopted_at >= WATCH, WATCH + 1.0)
	t.check(not reasons.any(func(r): return str(r).ends_with("hostile belief changed")),
		"no decision was forced by a change of belief in the %.0f s after the order was adopted (decisions started: %s)" % [WATCH, str(reasons)])
