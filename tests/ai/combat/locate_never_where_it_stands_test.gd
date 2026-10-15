extends GameTest

## Issue #51 R12: LOCATE is a walk toward the shots. Shot at from beyond the walkable ground (past the outer edge of the ring round
## the house), the NPC was sent to a point toward the shots that the navmesh pulls back to where it already stands: the move ended
## the tick it began and the unchanged situation drew the same order again, every other frame (Invader 8, COMBAT > LOCATE x216 in a
## 10v10 match on main). LOCATE is offered only when its walk goes somewhere.
##
## Scripted Von (the loop is in what the snapshot offers, not in Von's pick): COMBAT > LOCATE when offered, else what comes first. The
## bare Terrace house and a lone invader at the west edge of the garden ring, facing the house; the shots are `hit` events nobody
## known fired, from the west, landing beside it, one a second so it stays under fire.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const AT := Vector2(-140, 250)
const SHOOTER := Vector2(-700, 250)
const LANDED := Vector2(-150, 262)
## A place within this (px) of where the NPC stands is where it stands (a stride: twice the walk's own arrival distance).
const STRIDE := 32.0
## Decisions the invader may start in `WINDOW` s under fire (with the loop: one every other frame, about 90).
const WINDOW := 3.0
const MAX_DECISIONS := 6


func describe() -> Dictionary:
	return {
		"name": "LOCATE is never to where the NPC stands",
		"description": "Shot at from beyond the edge of the walkable ground, the invader is not sent toward the shots onto the spot it stands on, and does not re-decide over and over.",
		"tags": ["ai", "combat", "locate", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([{ "pick": "locate" }])
	s.actor(&"inv", &"invader", AT, { "max_health": 1000000.0, "facing": Vector2.RIGHT })  # Unkillable, facing the house: the shooter stays unseen.


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var brain := t.controller(&"inv", &"debug_state")
	await t.seconds(0.5)
	_shot()
	if not t.require(await t.until(func(): return str(brain.current_act()).begins_with("combat/"), 5.0),
			"the invader fights back after the shot (act %s)" % brain.current_act()):
		return
	var start: int = brain.debug_state()["decisions"]
	var seen: int = start
	var wrong := 0
	var next_shot := t.time + 1.0
	var end := t.time + WINDOW
	while t.time < end:
		if t.time >= next_shot:
			next_shot += 1.0
			_shot()
		var n: int = brain.debug_state()["decisions"]
		if n != seen:
			seen = n
			for z in brain.debug_zones():
				if str(z.get("label", "")) == "toward the shots" and (z["point"] as Vector2).distance_to(inv.global_position) < STRIDE:
					wrong += 1
		await t.frames(1)
	t.check(wrong == 0, "LOCATE was offered toward a point where the invader stands, in %d decisions" % wrong)
	var made: int = int(brain.debug_state()["decisions"]) - start
	t.trace("decisions", made)
	t.check(made <= MAX_DECISIONS, "the invader started %d decisions in %.0f s under fire (at most %d): it re-decided over and over" % [made, WINDOW, MAX_DECISIONS])


## One shot at the invader nobody known fired: it lands at `LANDED`, coming from `SHOOTER`.
func _shot() -> void:
	EventBus.post(&"hit", { "position": LANDED, "direction": (LANDED - SHOOTER).normalized(), "damage": 10.0, "attacker": null, "victim": null })
