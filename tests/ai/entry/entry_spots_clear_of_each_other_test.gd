extends GameTest

## Issue #53 (E2, E8): the spots an entry hands its members do not overlap. A stack of four lines up in the garden at the
## back door: each member's slot lies clear of its neighbours' footprints, outside the hole a body standing on the
## neighbouring slot cuts in the map the NPCs walk round bodies by (a body's radius, `NavBuilder.OBSTACLE_MARGIN` and the
## walker's own radius). After the clear, the kitchen has two doorways on (the living room's and the hall's): two members
## cover them and the spare two hold the rear, each at a spot of its own, clear of the other the same way.
##
## Read through the brain's published entry view (`debug_entry_view`: `my_slot`, `rear_spot`, `phase`). Scripted Von
## (`Entry.rules`: SEARCH > ENTER > that doorway), bare rooms, invaders that cannot die (`Entry.npc`).

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")

const IDS := [&"a", &"b", &"c", &"d"]
## Body radius (px) of every character, and the agent radius the nav maps are baked for.
const RADIUS := 14.0
## A spot is clear of a body standing on another when it lies outside that body's hole in the steering map, with a pixel or two
## for the 1 px grid the map is baked on.
const CLEAR := RADIUS + NavBuilder.OBSTACLE_MARGIN + RADIUS + 2.0


func describe() -> Dictionary:
	return {
		"name": "Entry slots and rear spots are clear of each other",
		"description": "A stack of four gets slots clear of each other's footprint, and the spare members holding the rear get a spot each.",
		"tags": ["ai", "entry", "scripted", "navigation"],
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(960, 40), 0.4)
	Entry.npc(s, &"b", Vector2(985, 100), 0.55)
	Entry.npc(s, &"c", Vector2(990, 280), 0.7)
	Entry.npc(s, &"d", Vector2(960, 340), 0.85)


func run(t: TestContext) -> void:
	var slots := {}   # id -> its slot point, read while it waits in the stack
	var rears := {}   # id -> its rear spot, read while it holds the rear
	var views := func():
		for id in IDS:
			var v: Dictionary = Entry.brain(t, id).debug_entry_view().get("entry", {})
			if v.is_empty() or String(v.get("opening", "")) != Entry.BACK["id"]:
				continue
			if v.get("phase", "") in ["approach", "stack"] and v.get("my_slot") is Vector2:
				slots[id] = v["my_slot"]
			if v.get("phase", "") == "rear" and v.get("rear_spot") is Vector2:
				rears[id] = v["rear_spot"]
		return rears.size() >= 2 and slots.size() == IDS.size()
	await t.until(views, 70.0)
	if not t.require(slots.size() >= 3, "premise: three or more of them stacked at the back door (%s)" % str(slots.keys())):
		return
	t.check(_overlaps(slots).is_empty(), "every slot lies clear of the others (%.0f px or more apart: %s)" % [CLEAR, _overlaps(slots)])
	if not t.require(rears.size() >= 2, "premise: two or more spare members held the rear (%s)" % str(rears.keys())):
		return
	t.check(_overlaps(rears).is_empty(), "each member holding the rear has a spot of its own, clear of the others (%s)" % [str(_overlaps(rears))])


## The pairs of `spots` (id -> point) nearer each other than `CLEAR`, as "a-b 12 px" strings.
func _overlaps(spots: Dictionary) -> Array:
	var out: Array = []
	var ids := spots.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var gap: float = (spots[ids[i]] as Vector2).distance_to(spots[ids[j]])
			if gap < CLEAR:
				out.append("%s-%s %.0f px" % [ids[i], ids[j], gap])
	return out
