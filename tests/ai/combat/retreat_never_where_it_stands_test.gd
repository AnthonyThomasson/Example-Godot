extends GameTest

## Issue #51 R12: a RETREAT is a walk somewhere. Falling back to an ally it already stands beside, the NPC was sent to the ally's own
## spot: its walk was held short of the body, then ended at the free spot beside it, where it already stood, so the move ended the
## tick it began and the unchanged situation drew the same order again, every other frame (Invader 10, COMBAT > RETREAT x128 in one
## 10v10 match). A place to fall back to is open floor a walk away: the spot beside the ally, behind it from the threat, and never
## where the NPC stands nor on a body.
##
## Scripted Von (the loop is in what the snapshot offers, not in Von's pick): COMBAT > RETREAT > fall back to the ally. An empty arena
## (no cover, one room), an invader with an ally 40 px to its west and a defender 300 px to its east in plain view.

const START := Vector2(400, 250)
const ALLY := Vector2(360, 250)
const HOSTILE := Vector2(700, 250)
## A place within this (px) of where the NPC stands is where it stands (a stride: twice the walk's own arrival distance).
const STRIDE := 32.0
## A body's footprint (px): a place closer than this to a character stands on it.
const BODY := 32.0
## Decisions the invader may start in `WINDOW` s once it has fallen back: the walk's end, then the fight's cadence (with the loop: one
## every other frame, about 120).
const WINDOW := 4.0
const MAX_DECISIONS := 6


func describe() -> Dictionary:
	return {
		"name": "A retreat is never to where the NPC stands",
		"description": "Told to fall back to an ally it stands beside, the invader walks to a spot behind the ally once, and does not re-decide the same retreat over and over.",
		"tags": ["ai", "combat", "retreat", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.von_script([{ "pick": "combat" }, { "pick": "retreat" }, { "pick": "fall_ally_ally" }])
	s.switch(&"projectile.flyover", false)
	s.actor(&"inv", &"invader", START, { "max_health": 1000000.0, "facing": Vector2.RIGHT })  # Unkillable: the premise is the retreat, not the fight.
	s.actor(&"ally", &"puppet", ALLY, { "faction": &"invader", "max_health": 1000000.0 })
	s.actor(&"tgt", &"puppet", HOSTILE, { "faction": &"household", "max_health": 1000000.0, "aim_point": START, "facing": Vector2.LEFT })


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var brain := t.controller(&"inv", &"debug_state")
	if not t.require(await t.until(func(): return str(brain.current_act()).ends_with("/retreat/fall_ally_ally"), 10.0),
			"the invader falls back to its ally (act %s)" % brain.current_act()):
		return
	var start: int = brain.debug_state()["decisions"]
	var seen: int = start
	var wrong := {}
	var end := t.time + WINDOW
	while t.time < end:
		var n: int = brain.debug_state()["decisions"]
		if n != seen:
			seen = n
			_check_retreats(t, brain, inv, wrong)
		await t.frames(1)
	for w in wrong:
		t.check(false, "%s (%d decisions)" % [w, wrong[w]])
	var made: int = int(brain.debug_state()["decisions"]) - start
	t.trace("decisions", made)
	t.check(made <= MAX_DECISIONS, "the invader started %d decisions in %.0f s after falling back (at most %d): it re-decided the retreat over and over" % [made, WINDOW, MAX_DECISIONS])


## Every place the decision just made offered to fall back to is a walk away and open floor: each one that is not is counted in
## `wrong` (message -> decisions).
func _check_retreats(t: TestContext, brain: Node, inv: Node, wrong: Dictionary) -> void:
	var here: Vector2 = inv.global_position
	for z in brain.debug_zones():
		if str(z.get("category", "")) != "retreat":
			continue
		var p: Vector2 = z["point"]
		if p.distance_to(here) < STRIDE:
			_note(wrong, "a retreat to %s is where the invader stands" % z.get("label", ""))
		for id in [&"ally", &"tgt"]:
			if p.distance_to(t.actor(id).global_position) < BODY:
				_note(wrong, "a retreat to %s stands on %s" % [z.get("label", ""), id])


## Count one more wrong retreat spot of kind `what` in `wrong` (kind -> how many).
func _note(wrong: Dictionary, what: String) -> void:
	wrong[what] = int(wrong.get(what, 0)) + 1
