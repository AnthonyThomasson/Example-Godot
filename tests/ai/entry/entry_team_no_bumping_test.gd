extends GameTest

## Issue #53: a team on a tactical entry walks round its own members. A generated house, and four invaders placed and
## armed the way Main does (spread round the outside, heading for the front entrance, the invader loadout with its stun and
## frag), decide for themselves (real Von) to stack on a doorway and go in. For the whole run (the approach, the stack, the
## bang, the crossing, the corners, the clear, and the walks after it) no invader walks into a teammate that stands still:
## it goes round it, or stops short and waits; and no two invaders that are both walking collide: one gives way to the
## other. "Walks into" is measured by `tests/_ai/bump_probe.gd` (steering toward a body it touches); two walkers pressing
## into each other head-on make a bump each way, counted as one collision (`Bump.collisions`).
##
## The premise: the house is empty (no defender), so what is judged is the team's own movement, not a firefight; nothing
## else is changed (no switch, prop or timer).

const Bump := preload("res://tests/_ai/bump_probe.gd")
const House := preload("res://tests/_ai/house_probe.gd")

const SEED := 3
const INVADERS := 4
const WATCH_S := 60.0


func describe() -> Dictionary:
	return {
		"name": "An entry team does not walk into its own members",
		"description": "Four invaders placed as in a match stack on a doorway of a generated house and go in, without one walking into a teammate, standing still or walking.",
		"tags": ["ai", "entry", "von", "navigation", "character"],
		"requires_von": true,
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED)


func run(t: TestContext) -> void:
	var spawner = House.spawn(t, SEED, 0, INVADERS)
	var loadout_rng := RandomNumberGenerator.new()
	loadout_rng.seed = SEED
	for c in spawner.combatants:
		LoadoutConfig.apply(c, { "stuns": 1, "frags": 1 }, loadout_rng)
	var team: Array = spawner.combatants
	var seen: Dictionary = await Bump.watch(t, team, WATCH_S)
	var acts := ", ".join(team.map(func(c): return "%s %s" % [c.name, TestContext.controller_of(c).current_act()]))
	var stacked := _largest_stack(t, team)
	if not t.require(stacked.size() >= 3, "three or more invaders claimed the same doorway (%s; %s)" % [str(stacked), acts]):
		return
	var bumps: Array = seen["bumps"]
	var into_still := Bump.of_kind(bumps, true)
	var into_moving := Bump.of_kind(bumps, false)
	t.trace("bumps_into_still", into_still.size())
	t.trace("bumps_into_moving", into_moving.size())
	GameLog.say("bumps: into a still teammate %s, into a walking one %s, closest %.1f px, by walker's task %s; into a walking one: %s" % [
			str(Bump.totals(into_still)), str(Bump.totals(into_moving)), seen["closest"], str(Bump.tally(bumps)), Bump.describe(into_moving)])
	var collided := Bump.collisions(bumps)
	t.check(into_still.is_empty(), "no invader walks into a teammate standing still (%d times: %s)" % [into_still.size(), Bump.describe(into_still)])
	t.check(collided.is_empty(), "no two walking invaders collide (%d collisions: %s)" % [collided.size(), Bump.describe_collisions(collided)])


## The names of the invaders in `team` that radioed a claim on the doorway most of them claimed.
func _largest_stack(t: TestContext, team: Array) -> Array:
	var by_door := {}
	for d in t.events_of(&"callout", func(c): return String(c.get("entry_step", "")) == "claim"):
		var speaker = d.get("speaker")
		if speaker == null or not is_instance_valid(speaker) or not team.has(speaker):
			continue
		var door := String(d.get("opening", ""))
		var members: Array = by_door.get(door, [])
		if not members.has(speaker.name):
			members.append(speaker.name)
		by_door[door] = members
	var best: Array = []
	for door in by_door:
		if by_door[door].size() > best.size():
			best = by_door[door]
	return best
