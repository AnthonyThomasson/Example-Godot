extends GameTest

## Desired (ticket #41): the stack markers put the human's place in the stack on the floor. Each slot beside the doorway
## is drawn with its number, slots held by the AI dimmer than the human's own, which is highlighted; nothing is drawn
## while the stack has no reservation. The node only observes `view()` of the human's stack.

const MARKERS_SCRIPT := "res://scenes/ui/hud/stack_markers.gd"


## A stand-in for the human's stack: whatever `view()` it is told to give.
class FakeStack extends Node:
	var current := {}

	func view() -> Dictionary:
		return current


func describe() -> Dictionary:
	return {
		"name": "Stack markers draw the slots and the human's own",
		"description": "The markers show every slot of the reserved doorway, flag the human's own, and clear when the reservation ends.",
		"tags": ["ui", "hud", "stack"],
		"timeout": 6.0,
	}


func run(t: TestContext) -> void:
	if not t.require(ResourceLoader.exists(MARKERS_SCRIPT), "the stack markers script exists"):
		return
	var markers: Node2D = (load(MARKERS_SCRIPT) as GDScript).new()
	t.world.add_child(markers)
	var stack := FakeStack.new()
	t.world.add_child(stack)
	markers.watch(stack)
	await t.frames(2)
	t.expect_eq((markers.drawn() as Array).size(), 0, "nothing is drawn without a reservation")

	stack.current = {
		"opening": "door_840_190", "door": Vector2(840, 190), "mine": 2, "step": "ready",
		"slots": [
			{ "n": 1, "point": Vector2(868, 253), "mine": false, "held": true },
			{ "n": 2, "point": Vector2(868, 287), "mine": true, "held": true },
			{ "n": 3, "point": Vector2(868, 321), "mine": false, "held": false },
		],
	}
	await t.frames(2)
	var drawn: Array = markers.drawn()
	t.expect_eq(drawn.size(), 3, "every slot of the doorway is drawn")
	var numbers := drawn.map(func(d): return int(d["n"]))
	numbers.sort()
	t.expect_eq(numbers, [1, 2, 3], "each with its number")
	var own := drawn.filter(func(d): return bool(d["mine"]))
	t.check(own.size() == 1 and int(own[0]["n"]) == 2, "only the human's own slot is highlighted")
	for d in drawn:
		if int(d["n"]) == 2:
			t.check((d["point"] as Vector2).is_equal_approx(Vector2(868, 287)), "drawn where the slot is")

	stack.current = {}
	await t.frames(2)
	t.expect_eq((markers.drawn() as Array).size(), 0, "the markers clear when the reservation ends")
