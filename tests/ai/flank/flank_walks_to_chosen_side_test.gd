extends GameTest

## Desired (B9): once a side is chosen the NPC commits. The NPC watches the target in the living room from
## the hall, scripted to flank left: it goes in through the hall door, walks round the room to the target's
## left in the target's own frame, and fires at it from there, without stalling on the way.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(150, 415)       # in the hall, looking up through the living-room door
const TARGET_POS := Vector2(230, 190)    # in the living room, facing the door
const WALK_SPEED := 150.0                # the invader preset's speed


func describe() -> Dictionary:
	return {
		"name": "The NPC walks round to the chosen flank side and fires from it",
		"description": "Scripted to flank left: the NPC goes in through the hall door, round the living room to the target's left, and lands hits from there.",
		"tags": ["ai", "flank", "behavior", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	Flank.rules(s)
	s.switch(&"nav.rebake", false)   # the NPC may shove furniture on its way; re-baking overlapping holes logs a nav sync error
	Flank.npc(s, &"npc", NPC_POS, {}, &"invader", TARGET_POS)   # held for now, see run()
	Flank.target(s, &"target", TARGET_POS, NPC_POS)


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(NPC_POS)
	var npc := t.actor(&"npc")
	var brain := t.controller(&"npc", &"current_act")
	var facing := (NPC_POS - TARGET_POS).normalized()
	var left_point := Flank.side_point(TARGET_POS, facing, "left")
	if not await Flank.settle(t, brain):
		return
	brain.max_commit_time = 6.0   # from here on a leg lasts as long as the walk needs
	npc.speed = WALK_SPEED
	t.require(await t.until(func(): return Flank.side_of_act(brain) == "left", 6.0), "the NPC adopts the left flank (%s)" % brain.current_act())
	t.require(await t.until(func(): return npc.global_position.distance_to(left_point) < 70.0, 15.0), "it reaches the left flank point (at %s, point %s)" % [npc.global_position, left_point])
	t.expect_eq(Flank.side_of(TARGET_POS, facing, npc.global_position), "left", "it stands on the target's left")
	var shots := func(): return t.events_of(&"hit", func(d): return d["attacker"] == npc).size()
	var before: int = shots.call()
	t.check(await t.until(func(): return shots.call() > before, 6.0), "it lands a hit on the target from its flank")
