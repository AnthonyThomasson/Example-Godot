extends RefCounted

## Shared helpers for the tests of the player's place in an AI stack (tests/ai/stack_*_test.gd; not a test itself). The
## behaviour they assert is ticket #41 / `docs/tactical-entry.md` E16: a human invader near a doorway an AI team is
## stacking at is given the first free slot over the radio, shown on the floor, and counts in the team's barrier.
##
## A puppet stands in for the human. What Main gives the human is `PlayerStack.attach(character, rooms, openings)`
## (the `PlayerStack` script is loaded by path, so a missing script fails the test cleanly instead of a parse error).
## The stack is read only through its public `view()`; the team through the same radio callouts the NPCs hear.

const Entry := preload("res://tests/_ai/entry_probe.gd")

const STACK_SCRIPT := "res://scenes/ai/team/player_stack.gd"
## Where the human stands: beside the back door's stack, well within the stack range of the doorway.
const NEAR := Vector2(1000, 330)
## Where it stands far from every doorway (beyond the stack range).
const FAR := Vector2(1350, 750)
## How far (px) inside the room the human walks when it goes in: past the wall plane, off the door's axis.
const INSIDE_DEPTH := 90.0
const INSIDE_OFFSET := 60.0


## Declare the stand-in human: an invader puppet at `pos` (the faction Main gives a human who invades), never killed.
static func human(s: TestSetup, id: StringName, pos: Vector2, props: Dictionary = {}) -> void:
	var p := { "faction": &"invader", "max_health": 1000000.0 }
	p.merge(props, true)
	s.actor(id, &"puppet", pos, p)


## Give actor `id` the human's stack radio the way Main does, and return it (null when the feature is not there yet).
static func attach(t: TestContext, id: StringName) -> Node:
	if not ResourceLoader.exists(STACK_SCRIPT):
		return null
	var script: GDScript = load(STACK_SCRIPT)
	var openings: Array = t.world.get("openings") if t.world != null else []
	return script.attach(t.actor(id), t.rooms, openings)


## What the stack shows the human (`{}` when no slot is reserved): `opening`, `door`, `slots` (`{ n, point, mine, held }`),
## `mine` (the human's slot number) and `step` (its own radio step).
static func view(stack: Node) -> Dictionary:
	return stack.view() if stack != null else {}


## The human's reserved slot number, 0 when it has none.
static func mine(stack: Node) -> int:
	return int(view(stack).get("mine", 0))


## Where slot `n` stands in the current view, or Vector2.INF.
static func slot_point(stack: Node, n: int) -> Vector2:
	for s in view(stack).get("slots", []):
		if int(s["n"]) == n:
			return s["point"]
	return Vector2.INF


## Walk the puppet `id` through `points` in turn (straight lines); false when one is not reached within `each` s.
static func walk(t: TestContext, id: StringName, points: Array, each := 8.0) -> bool:
	var p := t.puppet(id)
	for point in points:
		p.walk_to(point)
		if not await t.until(p.has_arrived, each):
			return false
	return true


## The points a human walks to go in through `door` from its stack side: out in front of the door, the doorway, then a
## spot inside off the axis.
static func crossing(door: Dictionary) -> Array:
	var out: Vector2 = door["out"]
	var pos: Vector2 = door["pos"]
	return [pos + out * 70.0, pos, pos - out * INSIDE_DEPTH + out.orthogonal() * INSIDE_OFFSET]


## Whether actor `id` ever radioed an entry step (any) as the speaker.
static func radioed(t: TestContext, id: StringName) -> bool:
	return not Entry.calls(t, "", id).is_empty()
