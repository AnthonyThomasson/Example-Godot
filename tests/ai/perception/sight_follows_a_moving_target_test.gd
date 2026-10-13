extends GameTest

## How closely an NPC's sense of sight follows a hostile: it sees one that steps out from behind a tall piece of furniture, and
## loses one that steps behind it, within a few physics frames; and while it keeps one in sight the position it holds is never
## more than a couple of frames behind. Von is down, so the NPC holds its post and watches.

const MAX_LAG_FRAMES := 3
const NPC_AT := Vector2(150, 250)
const OPEN_AT := Vector2(650, 100)
const HIDDEN_AT := Vector2(650, 250)


func describe() -> Dictionary:
	return {
		"name": "Sight follows a moving target",
		"description": "A hostile is seen within 3 frames of stepping into view and lost within 3 frames of stepping behind a fridge; its tracked position stays within 8 px of the real one while it walks.",
		"tags": ["ai", "vision", "scripted"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.von_down()
	s.object(&"fridge", "fridge", Vector2(400, 250))
	s.actor(&"inv", &"invader", NPC_AT, { "speed": 0.0, "facing": Vector2.RIGHT })
	s.actor(&"tgt", &"puppet", OPEN_AT, { "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var brain := t.controller(&"inv", &"known_contacts_for_display")
	var target := t.actor(&"tgt")
	if not t.require(await t.until(func(): return _sees(brain), 2.0), "the NPC sees the target in the open"):
		return

	target.global_position = HIDDEN_AT
	var lost := await _frames_until(t, func(): return not _sees(brain))
	t.check(lost <= MAX_LAG_FRAMES, "it loses a target that steps behind the fridge within %d frames (took %d)" % [MAX_LAG_FRAMES, lost])

	target.global_position = OPEN_AT
	var found := await _frames_until(t, func(): return _sees(brain))
	t.check(found <= MAX_LAG_FRAMES, "it sees a target that steps back out within %d frames (took %d)" % [MAX_LAG_FRAMES, found])

	target.global_position = Vector2(500, 100)
	await t.frames(5)
	t.puppet(&"tgt").walk(Vector2.RIGHT)
	var worst := 0.0
	for i in 90:
		await t.frames(1)
		var seen := _contact(brain)
		if not seen.is_empty():
			worst = maxf(worst, (seen["pos"] as Vector2).distance_to(target.global_position))
		t.trace("position lag", worst)
	t.check(target.global_position.x > 700.0, "the target walked across the room (x %.0f)" % target.global_position.x)
	t.check(worst <= 8.0, "the position it holds trails the target by at most 8 px (worst %.1f)" % worst)


## Physics frames until `cond` holds (one more than the limit when it never does).
func _frames_until(t: TestContext, cond: Callable) -> int:
	for frames in range(1, 11):
		await t.frames(1)
		if cond.call():
			return frames
	return 11


## The NPC's contact for the target, or {}.
func _contact(brain: Node) -> Dictionary:
	for c in brain.known_contacts_for_display():
		if str(c["name"]) == "tgt":
			return c
	return {}


## Whether the NPC sees the target on this tick.
func _sees(brain: Node) -> bool:
	var c := _contact(brain)
	return not c.is_empty() and c["visible"]
