extends GameTest

## Desired (docs/gaze-and-fire.md W1): a fight follows the hostile the NPC can see. The contact it is fighting is only a
## memory once it slips out of sight, and another hostile standing in plain view is the one to fight; while the one it is fighting
## is in view it stays with it, and with nobody else in view it keeps its memory of the first. `Behavior.update_known` is driven
## here with stand-in contacts and perception (no world).

const Behavior := preload("res://scenes/ai/behavior/behavior.gd")


## Perception with what `Behavior` asks of it on adopting a fight.
class FakePerception extends Node:
	func note_engaged() -> void:
		pass

	func under_fire() -> bool:
		return false


func describe() -> Dictionary:
	return {
		"name": "A fight retargets to a hostile in plain view",
		"description": "Behavior.update_known with two stand-in hostiles: the fight moves from a contact it has lost sight of to the one it sees, and never away from one it sees.",
		"tags": ["ai", "gaze", "combat", "unit"],
		"timeout": 5.0,
	}


func run(t: TestContext) -> void:
	var a := Node2D.new()
	var b := Node2D.new()
	var perception := FakePerception.new()
	var behavior := Behavior.new()
	behavior.setup(perception, null)
	behavior.apply_config()

	var both_seen := [_contact(a, Vector2(300, 0), true), _contact(b, Vector2(300, 200), true)]
	behavior.update_known(both_seen, 0.016)
	behavior.set_leaf({ "primitive": &"engage", "path": [], "labels": [], "params": { "point": Vector2(100, 0), "target_id": a.get_instance_id() } })
	t.expect_eq(behavior.debug_state()["engage_id"], a.get_instance_id(), "it starts out fighting A")

	behavior.update_known([_contact(a, Vector2(300, 0), true), _contact(b, Vector2(300, 200), false)], 0.016)
	t.expect_eq(behavior.debug_state()["engage_id"], a.get_instance_id(), "A in view, B not: it stays with A")
	behavior.update_known(both_seen, 0.016)
	t.expect_eq(behavior.debug_state()["engage_id"], a.get_instance_id(), "both in view: it stays with A")
	behavior.update_known([_contact(a, Vector2(300, 0), false), _contact(b, Vector2(300, 200), false)], 0.016)
	t.expect_eq(behavior.debug_state()["engage_id"], a.get_instance_id(), "neither in view: it keeps its memory of A")
	behavior.update_known([_contact(a, Vector2(300, 0), false), _contact(b, Vector2(300, 200), true)], 0.016)
	t.expect_eq(behavior.debug_state()["engage_id"], b.get_instance_id(), "A out of sight, B in view: it fights B")

	for n in [a, b, perception, behavior]:
		n.free()


## A known hostile contact the way perception hands it over.
func _contact(node: Node2D, pos: Vector2, visible_now: bool) -> Dictionary:
	return { "id": node.get_instance_id(), "node": node, "pos": pos, "hostile": true, "visible": visible_now, "age": 0.0 if visible_now else 1.0,
		"inside": true }
