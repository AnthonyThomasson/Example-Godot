extends GameTest

## Desired (B4): a side an ally stands on is its own. A teammate is already working round to the target's
## south side and the NPC can see it, so that side reads 'taken by buddy' and is dropped; the others are
## offered.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(120, 350)
const TARGET_POS := Vector2(620, 330)
const BUDDY_POS := Vector2(620, 410)     # on the target's south side, in the NPC's sight; the rear route runs south of it, clear of its line of fire


func describe() -> Dictionary:
	return {
		"name": "A flank side held by a visible ally is not offered",
		"description": "A teammate the NPC can see stands on the target's south side; that side reads 'taken by buddy' and is dropped, the other sides are offered.",
		"tags": ["ai", "flank", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s)
	Flank.rules(s)
	Flank.npc(s, &"npc", NPC_POS, {}, &"invader", TARGET_POS)
	Flank.target(s, &"target", TARGET_POS, NPC_POS)
	Flank.ally(s, &"buddy", BUDDY_POS, { "aim_point": TARGET_POS })


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(NPC_POS)
	t.puppet(&"buddy").aim_at(TARGET_POS)
	var brain := t.controller(&"npc", &"current_act")
	if not await Flank.settle(t, brain):
		return
	var zones := Flank.zones(brain)
	if not t.require(zones.has("left"), "the south side was weighed (%s)" % Flank.dump(brain)):
		return
	t.expect_eq(zones["left"]["tags"]["held_by"], "buddy", "the south side is held by buddy")
	t.check(String(zones["left"]["desc"]).contains("taken by buddy"), "its description says so (%s)" % zones["left"]["desc"])
	var sides := Flank.offered_sides(brain)
	t.check(not sides.has("left"), "the held side is not offered (%s)" % [sides])
	t.check(sides.has("right") and sides.has("rear"), "the free sides are (%s)" % [sides])
