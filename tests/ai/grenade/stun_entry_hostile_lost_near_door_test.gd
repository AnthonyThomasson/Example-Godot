extends GameTest

## G18 as amended (issue #51, R6): a room is suspect when a hostile was lost near its doorway or heading in, not only when it was seen
## going in. An invader carrying a stun, in the back garden south-east of the kitchen, sees a householder in the garden walking toward
## the back door; it passes behind a tall wardrobe standing out in the garden and is lost there, outside the room, near the doorway and
## heading for it (it then goes in and hides in the kitchen's south-east corner, out of sight of the garden). The invader's first
## decision made with it lost is STUN ENTRY into the kitchen (alone, it is its own thrower), not an investigation of where it was last
## seen or heading, nor the quiet ENTER. Real Von (whatever it does about the householder while it sees it); a `require` that the
## householder was last seen outside the kitchen, near its doorway (so this is not the "seen going in" case already built), and that
## the invader went for the kitchen by its back door, comes before the check. A lone invader, so no teammate's radio of the same
## fight is a lead of its own to weigh.
##
## Premises: the householder is a puppet (unkillable, it never shoots) on a set walk; the wardrobe is the prop that loses it: it
## blocks the sight lines from the invader's corner of the garden to the last stretch before the door, and stands clear of the
## slots south of the door, the pie and the lob through the doorway. The invader is armed with a stun at the start of `run`.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Suspect := preload("res://tests/_ai/suspect_probe.gd")
const A_AT := Vector2(972, 592)
## Stood on end (`rotated`), 45 px wide across the line of sight and clear of the hall's east wall by more than a body.
const WARDROBE_AT := Vector2(920, 435)
## The householder's walk: from the east garden to the back door, in, and along the inside of the east wall to the corner.
const WALK := [Vector2(995, 280), Vector2(870, 196), Vector2(815, 196), Vector2(805, 325)]
## Near the doorway: last seen within this many px of it.
const NEAR := 150.0


func describe() -> Dictionary:
	return {
		"name": "A stun entry into a room a hostile was lost heading into",
		"description": "An invader with a stun sees a householder walking to the kitchen's back door and loses it behind a wardrobe just outside; its next decision is STUN ENTRY into the kitchen, not an investigation or the quiet ENTER.",
		"tags": ["ai", "grenade", "entry", "stun", "von"],
		"requires_von": true,
		"timeout": 100.0,
	}


func configure(s: TestSetup) -> void:
	Suspect.world(s, A_AT, Vector2.INF, { "facing": Vector2.UP })
	s.object(&"wardrobe", "wardrobe", WARDROBE_AT, { "rotated": true })
	s.actor(&"hostile", &"puppet", WALK[0], { "faction": &"household", "max_health": 1000000.0, "facing": Vector2.LEFT, "aim_point": WALK[1] })


func run(t: TestContext) -> void:
	if not t.require(Suspect.arm(t), "the invader carries a stun grenade (Character.item_count(7))"):
		return
	var door := Entry.BACK
	var hostile := t.actor(&"hostile")
	var walker := t.puppet(&"hostile")
	var leg := [1]
	walker.walk_to(WALK[1])
	# Where each invader last saw the householder (its known contacts while visible), up to its first decision that is not a fight
	# (SEARCH or INVESTIGATE: the one made with the householder lost, which `Suspect.check_stun_entry` judges), after which a
	# sighting no longer bears on that decision.
	var last_seen := { &"a": Vector2.INF }
	var decided := { &"a": false }
	# Whether the householder ever stood among a stack member's lost contacts (`debug_memory()["lost"]`).
	var lost := [false]
	var follow := func(_now: float) -> void:
		if leg[0] < WALK.size() and walker.has_arrived():
			leg[0] += 1
			if leg[0] < WALK.size():
				walker.walk_to(WALK[leg[0]])
			else:
				walker.stop()
		for id in last_seen:
			var act := str(Entry.brain(t, id).current_act())
			if last_seen[id] != Vector2.INF and (act.begins_with("search") or act.begins_with("investigate")):
				decided[id] = true
			if decided[id]:
				continue
			for c in Entry.brain(t, id).known_contacts_for_display():
				if c.get("node") == hostile and c.get("visible", false):
					last_seen[id] = c["pos"]
			if Entry.brain(t, id).debug_memory().get("lost", []).any(func(l): return l.get("name", "") == hostile.name):
				lost[0] = true
	var result: Dictionary = await Suspect.watch(t, 80.0, follow)
	var spots: Array = last_seen.values().filter(func(p): return p != Vector2.INF)
	if not t.require(spots.size() == 1, "set-up: the invader saw the householder in the garden (last seen %s; acts %s)" % [str(last_seen), str(result["seen"])]):
		return
	var outside_near := spots.all(func(p: Vector2): return Entry.outward(door, p) > 10.0 and p.distance_to(door["pos"]) < NEAR)
	if not t.require(outside_near, "set-up: when they decided with it lost, the householder was last seen outside the kitchen, near its back door (last seen at %s)" % str(last_seen)):
		return
	if not t.require(lost[0], "set-up: the householder was among the invader's lost contacts (debug_memory lost)"):
		return
	Suspect.check_stun_entry(t, result, "a householder lost by the kitchen's back door, heading in")
