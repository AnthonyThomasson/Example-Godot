extends GameTest

## G18 / E17, the first fallback: a stack in bang mode whose thrower has no clear lob into the room (from its hand, clear of the jamb) gives the bang up
## and goes in quietly: nothing is thrown, `bang` is never radioed, and the claims that follow say the stack is quiet. A column of wardrobes (coverage 95,
## over a lob's clearance) stands across the kitchen just inside its back door, so no point of the room's far side is in the thrower's line. Scripted Von
## (SEARCH > STUN ENTRY > the back door); both invaders carry a stun, the way Main arms a spawn.

const Bang := preload("res://tests/_ai/bang_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const COLUMN_X := 770.0


func describe() -> Dictionary:
	return {
		"name": "A stack with no clear lob into the room goes in quietly",
		"description": "Wardrobes across the kitchen just inside the back door leave the thrower no line to the room: it gives the bang up, nothing is thrown, no bang is radioed and the stack goes in.",
		"tags": ["ai", "grenade", "entry", "stun", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Bang.rules(s)
	for i in 4:
		s.object(StringName("wardrobe_%d" % i), "wardrobe", Vector2(COLUMN_X, 45.0 + 90.0 * i), { "rotated": true })
	Bang.stack(s)


func run(t: TestContext) -> void:
	if not t.require(Bang.arm(t, Bang.IDS), "both invaders carry a stun grenade (Character.item_count(7))"):
		return
	var seen := { &"a": [], &"b": [] }
	var end := t.time + 50.0
	while t.time < end and Entry.calls(t, "going_in").is_empty():
		Bang.note_acts(t, seen)
		await t.frames(1)
	if not t.require(Bang.took(seen, "stun_entry"), "the AI took STUN ENTRY (acts: %s)" % str(seen)):
		return
	var firsts := Bang.IDS.map(func(id): return Entry.calls(t, "claim", id)[0])
	t.check(firsts.all(func(c): return c.get("bang") == true), "each claimed the doorway in bang mode")
	if not t.require(not Entry.calls(t, "going_in").is_empty(), "the stack went in"):
		return
	t.check(Entry.calls(t, "bang").is_empty(), "with no bang on the radio")
	t.check(not t.happened(&"throw") and Probe.booms(t).is_empty(), "and nothing thrown")
	for id in Bang.IDS:
		var last: Dictionary = Entry.calls(t, "", id).back()
		t.check(last.get("bang") == false, "%s's latest call says the stack is quiet (bang %s)" % [id, str(last.get("bang"))])
