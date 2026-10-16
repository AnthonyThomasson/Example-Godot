extends GameTest

## LD2 (`docs/leadership.md`): a Von request across a pause. The `HTTPRequest` is paused with its NPC and so is its own
## timeout; the answer that arrives during the pause is read on resume and adopted then, with no failure (no hold-steady fallback,
## no transport error logged). The whole pipeline runs with the real Von server: a lone invader in the Terrace house's back garden
## decides how to search the house; the moment its first question is in flight the tree is paused for 10 s of wall time.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")

const PAUSE_WALL := 10.0


func describe() -> Dictionary:
	return {
		"name": "A Von answer across a pause is adopted on resume",
		"description": "A decision in flight when the tree is paused for 10 s of wall time is answered and adopted after the resume, with no failure (LD2).",
		"tags": ["ai", "decision", "leadership", "clock", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"a", &"invader", Vector2(1000, 190))


func run(t: TestContext) -> void:
	var b := Order.brain(t, &"a")
	if not t.require(await t.until(func(): return bool(b.debug_brain().get("pending", false)), 20.0), "the NPC asks Von a question (premise)"):
		return
	var walks := Order.decisions(b)

	await Order.pause_for(t, PAUSE_WALL)

	var answered := await t.until(func(): return not bool(b.debug_brain().get("pending", true)), 15.0)
	t.check(answered, "the question in flight is answered after the resume")
	var brain: Dictionary = b.debug_brain()
	t.check(not bool(brain.get("failed", true)), "the walk did not fail (no hold-steady fallback)")
	t.expect_eq(Order.decisions(b), walks, "the walk in flight is the one finished, not a fresh one started on resume")
	var levels: Array = brain.get("levels", [])
	t.check(not levels.is_empty() and String(levels.back().get("pick", "")) != "", "its last level has Von's pick (levels: %s)" % str(levels.map(func(l): return [l.get("node"), l.get("pick")])))
	t.check(String(b.current_act()) != "hold", "and the NPC adopted the decision (act %s)" % b.current_act())
